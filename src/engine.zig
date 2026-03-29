const std = @import("std");

const utilsl = @import("utils.zig");
const chess = @import("chess.zig");
const configl = @import("config.zig");
const movel = @import("move.zig");
const hashTablel = @import("hashTable.zig");
const magicl = @import("magic.zig");
const moveTablel = @import("moveTables.zig");
const speedTestl = @import("speedTest.zig");
const heuristicl = @import("heuristic.zig");
const schedulerl = @import("search/scheduler.zig");
const threadingl = @import("search/threading.zig");
const benchmarkl = @import("search/benchmark.zig");
const filel = @import("file.zig");
const timel = @import("time.zig");

const Board_state = chess.Board_state;
const e_moveFlags = movel.e_moveFlags;
const IMove = movel.IMove;
const debug_err = chess.debug_err;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

const e_engineCmd = enum(u8) { NOOP = 0, QUIT, STOP, ISREADY, GO, POSITION, UCINEWGAME, REGISTER, SETOPTION, DEBUG, UCI, PONDERHIT, PRINT, BENCHMARK };
const e_goTypes = enum(u8) { DEFAULT, PONDER, EVAL, PERFT };
const e_engineOptions = enum(u8) { THREADS = 0, USEHASHTABLE, HASHTABLESIZE, INVALID, UCI_LIMITSTRENGHT, UCI_ELO, FIXED_DEPTH, USESTATICSEARCH, CLEAR_HASH, PRINT_METRIC, HEUR_WEIGHTS_PATH, USEQUIESCENCE, USENULLPRUNE, USELATEMOVEREDUC, USESEE, USEFUTILITY, TRACKMETRICS };
pub const e_engineOptionsArgType = enum(u8) { SPIN = 0, CHECK, STRING, COMBO, BUTTON, INVALID };

pub const goArgStruct = struct {
    searchMoves: bool = false,
    infinite: bool = false,
    type: e_goTypes = .DEFAULT,
    useBatched: bool = false,

    // all times in ms
    wtime: u32 = std.math.maxInt(u32),
    btime: u32 = std.math.maxInt(u32),
    winc: u32 = 0,
    binc: u32 = 0,

    movestogo: u32 = 0,
    movetime: u32 = 0,
    nodes: u64 = 0,
    depth: u16 = 0,
    mate: u16 = 0,
};

pub fn getMsgStdin(reader: *std.io.Reader) ![configl.MAX_USER_INPUT]u8 {
    var buffer = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
    var w: std.io.Writer = .fixed(&buffer);
    _ = try reader.streamDelimiter(&w, '\n');
    reader.toss(1);
    return buffer;
}
pub const inputChannel = struct {
    cmdBuffer: std.ArrayList([]u8),
    lock: bool = false,

    pub fn init(alloc: std.mem.Allocator) !inputChannel {
        var ret: inputChannel = undefined;
        ret.lock = false;
        ret.cmdBuffer = try std.ArrayList([]u8).initCapacity(alloc, 10);
        return ret;
    }
    fn acquireLock(p_self: *inputChannel) void {
        while (p_self.lock) {
            std.Thread.sleep(configl.ENGINE_LOCK_TICKRATE_NS);
        }
        p_self.lock = true;
    }
    inline fn releaseLock(p_self: *inputChannel) void {
        p_self.lock = false;
    }
    pub fn nonEmpty(p_self: *inputChannel) bool {
        p_self.acquireLock();
        const ret = p_self.cmdBuffer.items.len != 0;
        p_self.releaseLock();
        return ret;
    }
    pub fn readBuffer(p_self: *inputChannel) []u8 {
        // caller is responsible for the freeing of the []u8
        p_self.acquireLock();
        const ret = p_self.cmdBuffer.orderedRemove(0);
        p_self.releaseLock();
        return ret;
    }
    pub fn putCmd(p_self: *inputChannel, alloc: std.mem.Allocator, cmd: []const u8) bool {
        p_self.acquireLock();
        const _cmd = alloc.dupe(u8, cmd) catch {
            p_self.releaseLock();
            return false;
        };

        p_self.cmdBuffer.append(alloc, _cmd) catch {
            p_self.releaseLock();
            return false;
        };
        p_self.releaseLock();
        return true;
    }
    pub fn free(p_self: *inputChannel, alloc: std.mem.Allocator) void {
        p_self.acquireLock();
        for (0..p_self.cmdBuffer.items.len) |i| {
            alloc.free(p_self.cmdBuffer.items[i]);
        }
        p_self.cmdBuffer.deinit(alloc);
        p_self.releaseLock();
    }
};

const spinVarType: type = u32;
const optionInfo_spin = struct {
    min: spinVarType,
    max: spinVarType,
    default: spinVarType,

    pub fn validateValue(self: optionInfo_spin, value: spinVarType) bool {
        return (value >= self.min) and (value <= self.max);
    }
};

const optionInfo_str = struct {
    default: []const u8,
    _var: []const u8,
    pub fn validateValue(self: optionInfo_str, value: []const u8) bool {
        return utilsl.contains(self._var, value, .ignoreCase);
    }
};

const optionInfo = union { spin: optionInfo_spin, str: optionInfo_str };

pub const setOptionEntry = struct {
    name: []const u8 = undefined,
    optionType: e_engineOptions = .INVALID,
    argType: e_engineOptionsArgType = .INVALID,
    info: optionInfo = undefined,
    pub fn optionNameMsg(self: *setOptionEntry, alloc: std.mem.Allocator) ![]const u8 {
        var msg: []const u8 = undefined;
        if (self.argType == .SPIN) {
            msg = try std.fmt.allocPrint(alloc, "option name {s} type spin default {d} min {d} max {d}", .{ self.name, self.info.spin.default, self.info.spin.min, self.info.spin.max });
        } else if (self.argType == .COMBO) {
            msg = try std.fmt.allocPrint(alloc, "option name {s} type combo default {s} var {s}", .{ self.name, self.info.str.default, self.info.str._var });
        } else if (self.argType == .CHECK) {
            msg = try std.fmt.allocPrint(alloc, "option name {s} type check default {s} var {s}", .{ self.name, self.info.str.default, self.info.str._var });
        } else if (self.argType == .BUTTON) {
            msg = try std.fmt.allocPrint(alloc, "option name {s} type button ", .{self.name});
        } else if (self.argType == .STRING) {
            msg = try std.fmt.allocPrint(alloc, "option name {s} type string", .{self.name});
        }

        return msg;
    }
};

pub const engineStatus = struct {
    running: bool = false,
    // FIXME: useless for now
    // searching vvv
    searching: bool = false,
    debugMode: bool = false,
    positionProvided: bool = false,
    initializedInternals: bool = false,
};
pub const engineIdentification = struct {
    name: []const u8 = configl.NAME,
    author: []const u8 = configl.AUTHOR,
    code: []const u8 = configl.VERSION,
    setLater: bool = false,
};
pub const engineMetrics = struct {
    timeSearchingUs: i64 = 0,
    timeProcessingUs: i64 = 0,
    lock: bool = false,
    pub fn addTimeToSearchingMs(p_self: *engineMetrics, timeMs: i64) void {
        p_self.acquireLock();
        p_self.timeSearchingUs += timeMs * std.time.us_per_ms;
        p_self.releaseLock();
    }
    pub fn addTimeToProcessingMs(p_self: *engineMetrics, timeMs: i64) void {
        p_self.acquireLock();
        p_self.timeProcessingUs += timeMs * std.time.us_per_ms;
        p_self.releaseLock();
    }
    pub fn addTimeToSearchingUs(p_self: *engineMetrics, timeUs: i64) void {
        p_self.acquireLock();
        p_self.timeSearchingUs += timeUs;
        p_self.releaseLock();
    }
    pub fn addTimeToProcessingUs(p_self: *engineMetrics, timeUs: i64) void {
        p_self.acquireLock();
        p_self.timeProcessingUs += timeUs;
        p_self.releaseLock();
    }
    pub fn acquireLock(p_self: *engineMetrics) void {
        while (p_self.lock) {}
        p_self.lock = true;
    }
    pub inline fn releaseLock(p_self: *engineMetrics) void {
        p_self.lock = false;
    }
    pub fn printMetric(p_self: *const engineMetrics) void {
        const proc: f64 = @as(f64, @floatFromInt(p_self.timeProcessingUs)) / std.time.us_per_ms;
        const search: f64 = @as(f64, @floatFromInt(p_self.timeSearchingUs)) / std.time.us_per_ms;
        std.debug.print("Time spent processing {d} ms, time spent searching {d} ms\n", .{ proc, search });
    }
};

pub const engineOptions = struct {
    nThreads: spinVarType = configl.DEFAULT_THREAD,
    useHashTable: bool = configl.DEFAULT_USEHASHTABLE,
    useQuiescence: bool = configl.DEFAULT_USEQUIESC,
    useNullPrune: bool = configl.DEFAULT_USE_NULLPRUNE,
    useLMR: bool = configl.DEFAULT_LATE_MOVE_REDUCTION,
    useSEE: bool = configl.DEFAULT_USE_SEE,
    useFutility: bool = configl.DEFAULT_USE_FUTILITY,

    hashTableSize: spinVarType = configl.DEFAULT_HASHTABLE_SIZE, // in MB
    limitElo: bool = configl.DEFAULT_LIMIT_ELO,
    fixedDepth: bool = configl.DEFAULT_FIXED_DEPTH,
    useStaticSearch: bool = configl.DEFAULT_STATIC_SEARCH,

    engineElo: spinVarType = configl.DEFAULT_ELO,
    setOptions: std.ArrayList(setOptionEntry) = undefined,
    nOptions: u16 = 0,
    depthLevel: u16 = configl.DEFAULT_DEPTH,
    trackMetrics: bool = configl.DEFAULT_TRACKMETRICS,
};

pub const engine = struct {
    state: Board_state,
    workingThreads: std.ArrayList(std.Thread),
    status: engineStatus = .{},
    input: inputChannel,
    searcher: schedulerl.uciSearcher,

    alloc: std.mem.Allocator,
    uciMode: bool = false,
    id: engineIdentification = .{},
    options: engineOptions = .{},
    stopWatch: timel.stopWatch = .{},
    metric: engineMetrics = .{},

    pub fn init(alloc: std.mem.Allocator) !engine {
        var ret: engine = undefined;
        ret.alloc = alloc;
        ret.input = try inputChannel.init(alloc);
        ret.status = .{};
        ret.id = .{};
        ret.searcher = .{};
        ret.options = .{};
        ret.stopWatch = .{};
        ret.metric = .{};

        ret.workingThreads = try std.ArrayList(std.Thread).initCapacity(alloc, 2);
        ret.options.setOptions = try std.ArrayList(setOptionEntry).initCapacity(alloc, 4);

        ret.uciMode = false;
        try ret.initOptions();

        return ret;
    }

    pub fn printEngineInfo(p_self: *engine) void {
        var buffer: [1024]u8 = std.mem.zeroes([1024]u8);
        var msgId = std.fmt.bufPrint(&buffer, "id name {s}", .{p_self.id.name}) catch unreachable;
        p_self.respond(msgId);
        msgId = std.fmt.bufPrint(&buffer, "id version {s}", .{p_self.id.code}) catch unreachable;
        p_self.respond(msgId);
        msgId = std.fmt.bufPrint(&buffer, "id author {s}", .{p_self.id.author}) catch unreachable;
        p_self.respond(msgId);

        for (0..p_self.options.nOptions) |i| {
            const msg = p_self.options.setOptions.items[i].optionNameMsg(p_self.alloc) catch unreachable;
            defer p_self.alloc.free(msg);
            p_self.respond(msg);
        }
        p_self.respond("uciok");
    }
    pub fn initOptions(p_self: *engine) !void {
        try p_self.addOption(.{ .name = "threads", .optionType = .THREADS, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = 1, .max = configl.MAX_THREAD, .default = 1 } } });

        try p_self.addOption(.{ .name = "hash", .optionType = .HASHTABLESIZE, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = 1, .max = configl.MAX_HASHSIZE, .default = configl.DEFAULT_HASHTABLE_SIZE } } });
        try p_self.addOption(.{ .name = "useHash", .optionType = .USEHASHTABLE, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USEHASHTABLE } } });

        try p_self.addOption(.{ .name = "useQuiescence", .optionType = .USEQUIESCENCE, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USEQUIESC } } });

        try p_self.addOption(.{ .name = "useNullPruning", .optionType = .USENULLPRUNE, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USE_NULLPRUNE } } });
        try p_self.addOption(.{ .name = "useLMR ", .optionType = .USELATEMOVEREDUC, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_LATE_MOVE_REDUCTION } } });

        try p_self.addOption(.{ .name = "useSEE", .optionType = .USESEE, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USE_SEE } } });
        try p_self.addOption(.{ .name = "useFutility", .optionType = .USEFUTILITY, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USE_FUTILITY } } });

        try p_self.addOption(.{ .name = "UCI_LimitStrength", .optionType = .UCI_LIMITSTRENGHT, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_LIMIT_ELO } } });
        try p_self.addOption(.{ .name = "UCI_Elo", .optionType = .UCI_ELO, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = configl.MIN_ELO, .max = configl.MAX_ELO, .default = configl.DEFAULT_ELO } } });

        try p_self.addOption(.{ .name = "fixedDepth", .optionType = .FIXED_DEPTH, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_FIXED_DEPTH } } });
        try p_self.addOption(.{ .name = "useStaticSearch", .optionType = .USESTATICSEARCH, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_STATIC_SEARCH } } });

        try p_self.addOption(.{ .name = "clearHash", .optionType = .CLEAR_HASH, .argType = .BUTTON, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "" } } });

        try p_self.addOption(.{ .name = "printMetric", .optionType = .PRINT_METRIC, .argType = .BUTTON, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "" } } });

        try p_self.addOption(.{ .name = "heuristicWeightsPath", .optionType = .HEUR_WEIGHTS_PATH, .argType = .STRING, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "" } } });
        try p_self.addOption(.{ .name = "trackMetrics", .optionType = .TRACKMETRICS, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_TRACKMETRICS } } });
    }
    pub inline fn trackMetrics(p_self: *engine) bool {
        return p_self.options.trackMetrics;
    }
    pub fn addOption(p_self: *engine, opt: setOptionEntry) !void {
        try p_self.options.setOptions.append(p_self.alloc, opt);
        p_self.options.nOptions += 1;
    }
    pub fn getOptionEntry(p_self: *engine, opt: e_engineOptions) setOptionEntry {
        for (0..p_self.options.nOptions) |i| {
            const _opt = p_self.options.setOptions.items[i];
            if (opt == _opt.optionType) {
                return _opt;
            }
        }
        return .{};
    }

    pub fn readingThread(p_self: *engine) !void {
        var buffer: [configl.MAX_USER_INPUT]u8 = undefined;
        var f_reader = std.fs.File.stdin().reader(&buffer);
        const reader = &f_reader.interface;
        //_ = p_self.input.putCmd(p_self.alloc, "uci");
        while (p_self.status.running) {
            const inputBuffer = try getMsgStdin(reader);
            const msg = utilsl.trimStr(&inputBuffer);
            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG] readingThread.engine: got '{s}' ({d} bytes)\n", .{ msg, msg.len });
                std.debug.print("\n", .{});
            }

            _ = p_self.input.putCmd(p_self.alloc, &inputBuffer);
        }
    }
    pub fn executeBuffer(p_self: *engine, cmdBuffer: []const u8) void {
        const cmdtype = getEngineCmdType(cmdBuffer);

        if (p_self.uciMode) {
            const trimmedBuffer = utilsl.trimStr(cmdBuffer);
            const status = p_self.uci_executeCmd(cmdtype, trimmedBuffer);
            if (p_self.status.debugMode) {
                if (cmdtype != .NOOP) {
                    std.debug.print("[DEBUG] executeBuffer: found command type {} status: {}\n", .{ cmdtype, status });
                }
            }
        } else if (cmdtype == .UCI) {
            p_self.uciMode = true;
            p_self.printEngineInfo();
        }
    }
    fn waitOnWorkingThreads(p_self: *engine) void {
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.workingThreads.items[i].join();
        }
    }
    pub fn executeQuitProcedure(p_self: *engine) bool {
        p_self.status.running = false;
        p_self.searcher.interrupt = true;
        if (p_self.trackMetrics()) {
            p_self.metric.printMetric();
        }
        p_self.waitOnWorkingThreads();
        p_self.respond("its ovah");
        p_self.free();
        return true;
    }
    pub fn uci_executeCmd(p_self: *engine, cmd: e_engineCmd, cmdBuffer: []const u8) bool {
        switch (cmd) {
            .NOOP => {
                return true;
            },
            .QUIT => {
                return p_self.executeQuitProcedure();
            },
            .STOP => {
                p_self.searcher.interrupt = true;
                return true;
            },
            .ISREADY => {
                return p_self.executeIsReady();
            },
            .GO => {
                if (!p_self.status.positionProvided or p_self.searcher.searching) {
                    if (p_self.status.debugMode) {
                        std.debug.print("[DEBUG]uci_executeCmd: failed go cmd, position not provided or searcher still searching\n", .{});
                    }
                    return false;
                }
                if (!p_self.status.initializedInternals) {
                    _ = p_self.initInternals();
                }
                return p_self.executeGoCmd(cmdBuffer);
            },
            .POSITION => {
                if (!p_self.status.initializedInternals) {
                    _ = p_self.initInternals();
                }
                return p_self.executePositionCmd(cmdBuffer, p_self.alloc);
            },
            .UCINEWGAME => {
                return p_self.executeUciNewGameCmd();
            },
            .REGISTER => {
                return p_self.executeRegisterCmd(cmdBuffer);
            },
            .SETOPTION => {
                return p_self.executeSetOptionCmd(cmdBuffer);
            },
            .DEBUG => {
                return p_self.executeDebugCmd(cmdBuffer);
            },
            .UCI => {
                p_self.respond("ICU");
                return true;
            },
            .PONDERHIT => {
                p_self.respond("pondering ...");
                return true;
            },
            .BENCHMARK => {
                // by default single threaded will probably just use the engine options maybe
                if (!p_self.status.initializedInternals) {
                    _ = p_self.initInternals();
                }
                return p_self.executeBenchmarkCmd(cmdBuffer);
            },
            .PRINT => {
                if (p_self.status.positionProvided) {
                    chess.print_boardstate(&p_self.state);
                    return true;
                }
                return false;
            },
        }
        return true;
    }
    pub fn respond(self: engine, msg: []const u8) void {
        if (self.status.debugMode) {
            std.debug.print("[DEBUG] respond.engine: sending msg: '{s}'\n", .{msg});
        }
        const respmsg = std.fmt.allocPrint(self.alloc, "{s} \n", .{msg}) catch unreachable;
        defer self.alloc.free(respmsg);

        var buffer: [configl.MAX_USER_INPUT]u8 = undefined; // Buffer for stdout
        var writer = std.fs.File.stdout().writer(&buffer);
        const interface = &writer.interface;
        interface.writeAll(respmsg) catch |err| {
            if (self.status.debugMode) {
                std.debug.print("[DEBUG] respond.engine: caught err: {}\n", .{err});
            }
            return;
        };
        interface.flush() catch |err| {
            if (self.status.debugMode) {
                std.debug.print("[DEBUG] respond.engine: caught err: {}\n", .{err});
            }
            return;
        };
    }
    pub fn addCommand(p_self: *engine, alloc: std.mem.Allocator, cmd: []const u8) bool {
        _ = p_self.input.putCmd(alloc, cmd);
        return true;
    }
    pub fn sendKill(p_self: *engine) void {
        p_self.status.running = false;
        p_self.searcher.interrupt = true;
        p_self.respond("its ovah");
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.workingThreads.items[i].join();
        }
    }
    pub fn free(p_self: *engine) void {
        p_self.input.free(p_self.alloc);
        p_self.workingThreads.deinit(p_self.alloc);
        p_self.options.setOptions.deinit(p_self.alloc);
        hashTablel.hashTable.free(p_self.alloc);
    }

    pub fn executeUciNewGameCmd(p_self: *engine) bool {
        p_self.status.positionProvided = false;
        p_self.refreshInternals();
        return true;
    }
    pub fn executeDebugCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        if (utilsl.contains(cmdBuffer, "on", .ignoreCase)) {
            p_self.status.debugMode = true;
            return true;
        } else if (utilsl.contains(cmdBuffer, "off", .ignoreCase)) {
            p_self.status.debugMode = false;
            return true;
        }
        return false;
    }
    pub fn executeRegisterCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        //
        var tokens = utilsl.split(u8, p_self.alloc, cmdBuffer, ' ') catch {
            return false;
        };
        defer tokens.deinit(p_self.alloc);
        var tokenIndex: u32 = 1;
        while (tokenIndex != tokens.items.len) {
            if (utilsl.contains(tokens.items[tokenIndex], "later", .ignoreCase)) {
                p_self.id.setLater = true;
                return true;
            }
            if (utilsl.contains(tokens.items[tokenIndex], "name", .ignoreCase)) {
                if ((tokenIndex != tokens.items.len) and !utilsl.contains(tokens.items[tokenIndex + 1], "code", .ignoreCase)) {
                    p_self.setName(tokens.items[tokenIndex + 1]);
                }
            } else if (utilsl.contains(tokens.items[tokenIndex], "code", .ignoreCase)) {
                if ((tokenIndex != tokens.items.len) and !utilsl.contains(tokens.items[tokenIndex + 1], "name", .ignoreCase)) {
                    p_self.setCode(tokens.items[tokenIndex + 1]);
                }
            }
            tokenIndex += 2;
        }
        return true;
    }
    pub fn executeSetOptionCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        // format: setoption name <id> [value <x>]
        var tokens = utilsl.split(u8, p_self.alloc, cmdBuffer, ' ') catch {
            return false;
        };
        defer tokens.deinit(p_self.alloc);
        if (tokens.items.len < 2) {
            return false;
        }
        const name: e_engineOptions = parseSetOptionTypeCmd(cmdBuffer);
        const entry = p_self.getOptionEntry(name);

        switch (name) {
            .THREADS => {
                const val = getSpinValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.spin.validateValue(val)) {
                    return false;
                }
                p_self.options.nThreads = val;
                return true;
            },
            .USEHASHTABLE => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.useHashTable = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },

            .USEQUIESCENCE => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.useQuiescence = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },
            .USENULLPRUNE => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.useNullPrune = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },
            .USELATEMOVEREDUC => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.useLMR = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },
            .USESEE => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.useSEE = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },
            .USEFUTILITY => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.useFutility = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },

            .HASHTABLESIZE => {
                const val = getSpinValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.spin.validateValue(val)) {
                    return false;
                }
                return p_self.updateHash(val);
            },
            .UCI_ELO => {
                const val = getSpinValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.spin.validateValue(val)) {
                    return false;
                }
                return p_self.updateElo(val);
            },
            .UCI_LIMITSTRENGHT => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.limitElo = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },
            .FIXED_DEPTH => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.fixedDepth = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },
            .USESTATICSEARCH => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.useStaticSearch = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },
            .TRACKMETRICS => {
                const val = getCheckValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!entry.info.str.validateValue(val)) {
                    return false;
                }
                p_self.options.trackMetrics = utilsl.contains(val, "true", .ignoreCase);
                return true;
            },

            .CLEAR_HASH => {
                return p_self.updateHash(p_self.options.hashTableSize);
            },
            .PRINT_METRIC => {
                p_self.metric.printMetric();
                return true;
            },
            .HEUR_WEIGHTS_PATH => {
                const path = getStringValFromSetOptionCmd(tokens) catch {
                    return false;
                };
                if (!filel.fileExists(path)) {
                    return false;
                }
                return p_self.updateHeuristicWeights(path);
            },
            .INVALID => {
                return false;
            },
        }

        return true;
    }

    fn setName(p_self: *engine, name: []const u8) void {
        p_self.id.name = name;
    }
    fn setCode(p_self: *engine, code: []const u8) void {
        p_self.id.code = code;
    }
    fn executePositionCmd(p_self: *engine, cmdBuffer: []const u8, alloc: std.mem.Allocator) bool {
        const cmdOffset = 8;
        //* position [fen <fenstring> | startpos ]  moves <move1> .... <movei>
        // ex: position fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w AHah -
        if (utilsl.contains(cmdBuffer, "startpos", .ignoreCase)) {
            p_self.state = chess.getBoardFromFen(p_self.alloc, chess.DEFAULT_FEN) catch {
                return false;
            };
            chess.applyUciMoves(&p_self.state, cmdBuffer[cmdOffset..], alloc, p_self.status.debugMode) catch {
                return false;
            };
        } else if (utilsl.contains(cmdBuffer, "fen", .ignoreCase)) {
            const fenCmdOffset = utilsl.findM(u8, cmdBuffer, "fen");
            if (fenCmdOffset == -1) {
                return false;
            }
            p_self.state = chess.getBoardFromUciFen(utilsl.stripStr(cmdBuffer[(@intCast(fenCmdOffset + 3))..]), alloc, p_self.status.debugMode) catch {
                return false;
            };
        } else {
            return false;
        }
        p_self.status.positionProvided = true;
        return true;
    }
    pub fn setFen(p_self: *engine, fen: []const u8) void {
        p_self.state = chess.getBoardFromFen(p_self.alloc, fen) catch unreachable;
    }

    fn initInternals(p_self: *engine) bool {
        p_self.status.initializedInternals = true;
        magicl._initMagic(&magicl.magicTable, p_self.status.debugMode);

        moveTablel._initTables(p_self.status.debugMode);
        hashTablel._initZobrist(p_self.alloc, configl.SEED);
        hashTablel._initOrReallocHashTable(p_self.alloc, p_self.options.hashTableSize, p_self.status.debugMode);

        _ = p_self.updateElo(p_self.options.engineElo);
        return true;
    }
    fn refreshInternals(p_self: *engine) void {
        _ = p_self.updateElo(p_self.options.engineElo);
        heuristicl._initMoveOrdering();
    }
    fn updateHeuristicWeights(p_self: *engine, path: []const u8) bool {
        heuristicl.modifyHeuristicWeight(p_self.alloc, path, p_self.status.debugMode) catch {
            return false;
        };
        return true;
    }
    fn updateHash(p_self: *engine, hashSize: spinVarType) bool {
        if (p_self.searcher.searching) {
            p_self.searcher.interrupt = true;
            while (p_self.searcher.searching) {
                std.Thread.sleep(configl.WAIT_TICKRATE_NS);
            }
        }

        p_self.options.hashTableSize = hashSize;
        hashTablel._initOrReallocHashTable(p_self.alloc, p_self.options.hashTableSize, p_self.status.debugMode);
        return true;
    }
    fn updateElo(p_self: *engine, elo: spinVarType) bool {
        p_self.options.engineElo = elo;
        const _elo: f32 = @floatFromInt(elo);
        const delta: f32 = (_elo - configl.MIN_ELO) / (configl.MAX_ELO - configl.MIN_ELO);
        const proj = configl.MIN_DEPTH + (configl.MAX_DEPTH - configl.MIN_DEPTH) * delta;
        p_self.options.depthLevel = @intFromFloat(proj);
        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] updateElo: New updates depth {d} from elo {d}\n", .{ p_self.options.depthLevel, elo });
        }

        return true;
    }
    pub fn executeIsReady(p_self: *engine) bool {
        while (p_self.searcher.searching) {
            std.Thread.sleep(configl.WAIT_TICKRATE_NS);
        }
        if (!p_self.status.initializedInternals) {
            _ = p_self.initInternals();
        }
        p_self.respond("readyok");
        return true;
    }
    pub fn executeGoCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        var tokens = utilsl.split(u8, p_self.alloc, cmdBuffer, ' ') catch {
            return false;
        };
        defer tokens.deinit(p_self.alloc);
        const goArg = parseGoCmd(&tokens);

        p_self.searcher.reset();
        p_self.searcher.config = goArg;
        p_self.searcher.nThreads = p_self.options.nThreads;
        p_self.status.positionProvided = false;
        if (p_self.searcher.config.depth == 0) {
            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG] dispatchUciGoThreads: No depth found in the cmd string using the default engine option \n", .{});
            }
            p_self.searcher.config.depth = p_self.options.depthLevel;
        }
        return schedulerl.dispatchUciGoCmd(p_self, cmdBuffer);
    }
    pub fn executeBenchmarkCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        _ = cmdBuffer;
        if (p_self.searcher.searching) {
            return false;
        }
        p_self.searcher.reset();
        return benchmarkl.dispatchUciBenchmark(p_self);
        //@panic("speedtest missing");
    }
};
pub fn getLastMoveFromUci(p_board: *Board_state, cmdBuffer: []const u8, alloc: std.mem.Allocator) !IMove {
    var moveArray = try chess.getMoveListFromStr(p_board, cmdBuffer, alloc);
    defer moveArray.deinit(alloc);
    const n = moveArray.items.len;
    if (n == 0) {
        return debug_err.fenErr;
    }
    var retMove = moveArray.items[n - 1];
    chess.fillMoveFromState(p_board, &retMove);
    if (retMove.isEnpassant()) {
        if (p_board.whiteToMove()) {
            retMove.setCapture(.nBlackPawn);
        } else {
            retMove.setCapture(.nWhitePawn);
        }
    }
    return retMove;
}

fn parseGoCmd(tokens: *std.ArrayList([]const u8)) goArgStruct {
    var goArgs: goArgStruct = .{};
    var tokenIndex: u32 = 1;
    while (tokenIndex < tokens.items.len) {
        const arg = tokens.items[tokenIndex];
        if (utilsl.contains(arg, "searchmoves", .ignoreCase)) {
            goArgs.searchMoves = true;
            tokenIndex -= 1;
        } else if (utilsl.contains(arg, "eval", .ignoreCase)) {
            goArgs.type = .EVAL;
            tokenIndex -= 1;
        } else if (utilsl.contains(arg, "perft", .ignoreCase)) {
            goArgs.type = .PERFT;
            tokenIndex -= 1;
        } else if (utilsl.contains(arg, "batched", .ignoreCase)) {
            goArgs.useBatched = true;
            tokenIndex -= 1;
        } else if (utilsl.contains(arg, "ponder", .ignoreCase)) {
            goArgs.type = .PONDER;
            tokenIndex -= 1;
        } else if (utilsl.contains(arg, "wtime", .ignoreCase)) {
            goArgs.wtime = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch {
                tokenIndex += 1;
                continue;
            };
        } else if (utilsl.contains(arg, "btime", .ignoreCase)) {
            goArgs.btime = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch {
                tokenIndex += 1;
                continue;
            };
        } else if (utilsl.contains(arg, "winc", .ignoreCase)) {
            goArgs.winc = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch {
                tokenIndex += 1;
                continue;
            };
        } else if (utilsl.contains(arg, "binc", .ignoreCase)) {
            goArgs.binc = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch {
                tokenIndex += 1;
                continue;
            };
        } else if (utilsl.contains(arg, "movestogo", .ignoreCase)) {
            goArgs.movestogo = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch {
                tokenIndex += 1;
                continue;
            };
        } else if (utilsl.contains(arg, "depth", .ignoreCase)) {
            goArgs.depth = std.fmt.parseInt(u16, tokens.items[tokenIndex + 1], 10) catch {
                tokenIndex += 1;
                continue;
            };
        } else if (utilsl.contains(arg, "nodes", .ignoreCase)) {
            goArgs.nodes = std.fmt.parseInt(u64, tokens.items[tokenIndex + 1], 10) catch {
                tokenIndex += 1;
                continue;
            };
        } else if (utilsl.contains(arg, "mate", .ignoreCase)) {
            goArgs.mate = std.fmt.parseInt(u16, tokens.items[tokenIndex + 1], 10) catch {
                tokenIndex += 1;
                continue;
            };
        } else if (utilsl.contains(arg, "movetime", .ignoreCase)) {
            goArgs.movetime = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch {
                tokenIndex += 1;
                continue;
            };
            goArgs.wtime = goArgs.movetime;
            goArgs.btime = goArgs.movetime;
        } else if (utilsl.contains(arg, "infinite", .ignoreCase)) {
            goArgs.infinite = true;
        } else {
            tokenIndex -= 1;
        }
        tokenIndex += 2;
    }

    return goArgs;
}

pub fn parseSetOptionTypeCmd(cmdBuffer: []const u8) e_engineOptions {
    if (utilsl.contains(cmdBuffer, " threads", .ignoreCase)) {
        return .THREADS;
    } else if (utilsl.contains(cmdBuffer, " hash", .ignoreCase)) {
        return .HASHTABLESIZE;
    } else if (utilsl.contains(cmdBuffer, " usehash", .ignoreCase)) {
        return .USEHASHTABLE;
    } else if (utilsl.contains(cmdBuffer, " uci_limitstrength", .ignoreCase)) {
        return .UCI_LIMITSTRENGHT;
    } else if (utilsl.contains(cmdBuffer, " uci_elo", .ignoreCase)) {
        return .UCI_ELO;
    } else if (utilsl.contains(cmdBuffer, " fixeddepth", .ignoreCase)) {
        return .FIXED_DEPTH;
    } else if (utilsl.contains(cmdBuffer, " usestaticsearch", .ignoreCase)) {
        return .USESTATICSEARCH;
    } else if (utilsl.contains(cmdBuffer, " trackmetrics", .ignoreCase)) {
        return .TRACKMETRICS;
    } else if (utilsl.contains(cmdBuffer, " clearhash", .ignoreCase)) {
        return .CLEAR_HASH;
    } else if (utilsl.contains(cmdBuffer, " printmetric", .ignoreCase)) {
        return .PRINT_METRIC;
    } else if (utilsl.contains(cmdBuffer, " heuristicWeightsPath", .ignoreCase)) {
        return .HEUR_WEIGHTS_PATH;
    } else if (utilsl.contains(cmdBuffer, " useQuiescence", .ignoreCase)) {
        return .USEQUIESCENCE;
    } else if (utilsl.contains(cmdBuffer, " useNullPruning", .ignoreCase)) {
        return .USENULLPRUNE;
    } else if (utilsl.contains(cmdBuffer, " useLMR", .ignoreCase)) {
        return .USELATEMOVEREDUC;
    } else if (utilsl.contains(cmdBuffer, " useSEE", .ignoreCase)) {
        return .USESEE;
    } else if (utilsl.contains(cmdBuffer, " useFutility", .ignoreCase)) {
        return .USEFUTILITY;
    }

    return .INVALID;
}
pub fn getSpinValFromSetOptionCmd(tokens: std.ArrayList([]const u8)) !spinVarType {
    for (0..tokens.items.len) |i| {
        const token = tokens.items[i];
        if (utilsl.contains(token, "value", .ignoreCase)) {
            if (i != tokens.items.len - 1) {
                const ret = std.fmt.parseInt(spinVarType, tokens.items[i + 1], 10) catch {
                    return debug_err.valueErr;
                };
                return ret;
            }
        }
    }
    return debug_err.valueErr;
}
pub fn getCheckValFromSetOptionCmd(tokens: std.ArrayList([]const u8)) ![]const u8 {
    for (0..tokens.items.len) |i| {
        const token = tokens.items[i];

        if (utilsl.contains(token, "value", .ignoreCase)) {
            if (i != tokens.items.len - 1) {
                return tokens.items[i + 1];
            }
        }
    }
    return debug_err.valueErr;
}
pub fn getStringValFromSetOptionCmd(tokens: std.ArrayList([]const u8)) ![]const u8 {
    for (0..tokens.items.len) |i| {
        const token = tokens.items[i];

        if (utilsl.contains(token, "value", .ignoreCase)) {
            if (i != tokens.items.len - 1) {
                return tokens.items[i + 1];
            }
        }
    }
    return debug_err.valueErr;
}

fn inputThreading(p_self: *engine) void {
    var cumulTime: u64 = 0;
    while (p_self.status.running) {
        while (p_self.input.cmdBuffer.items.len != 0 and p_self.status.running) {
            p_self.stopWatch.startTimeTick();
            const cmdBuffer = p_self.input.readBuffer();
            defer p_self.alloc.free(cmdBuffer);
            p_self.executeBuffer(cmdBuffer);
            cumulTime = 0;
            if (p_self.trackMetrics()) {
                p_self.metric.addTimeToProcessingUs(p_self.stopWatch.timeSinceStartUs());
            }
            p_self.stopWatch.stop();
        }
        if (cumulTime > configl.DEBUG_INACTIVITY_READING_NS) {
            std.debug.print("[INACTIVITY] inputThreading.engine: no activity found in the last {d}s \n", .{configl.DEBUG_INACTIVITY_READING_S});
            cumulTime = 0;
        }
        std.Thread.sleep(configl.ENGINE_SERVING_TICKRATE_NS);
        cumulTime += configl.ENGINE_SERVING_TICKRATE_NS;
    }
}

fn entrypointReaderThreading(p_self: *engine) void {
    p_self.readingThread() catch unreachable;
}
fn mainThread(debugMode: bool) void {
    var eng = engine.init(GLOBAL_ALLOC) catch unreachable;
    eng.status.running = true;

    _ = std.Thread.spawn(.{}, entrypointReaderThreading, .{&eng}) catch unreachable;
    //eng.workingThreads.append(eng.alloc, inputThread) catch unreachable;
    eng.status.debugMode = debugMode;
    inputThreading(&eng);
}

fn getEngineCmdType(cmd: []const u8) e_engineCmd {
    if (utilsl.contains(cmd, "isready", .ignoreCase)) {
        return .ISREADY;
    } else if (utilsl.contains(cmd, "go", .ignoreCase)) {
        return .GO;
    } else if (utilsl.contains(cmd, "position", .ignoreCase)) {
        return .POSITION;
    } else if (utilsl.contains(cmd, "ucinewgame", .ignoreCase)) {
        return .UCINEWGAME;
    } else if (utilsl.contains(cmd, "register", .ignoreCase)) {
        return .REGISTER;
    } else if (utilsl.contains(cmd, "setoption", .ignoreCase)) {
        return .SETOPTION;
    } else if (utilsl.contains(cmd, "debug", .ignoreCase)) {
        return .DEBUG;
    } else if (utilsl.contains(cmd, "uci", .ignoreCase)) {
        return .UCI;
    } else if (utilsl.contains(cmd, "stop", .ignoreCase)) {
        return .STOP;
    } else if (utilsl.contains(cmd, "quit", .ignoreCase)) {
        return .QUIT;
    } else if (utilsl.contains(cmd, "ponderhit", .ignoreCase)) {
        return .PONDERHIT;
    } else if (utilsl.contains(cmd, "print", .ignoreCase)) {
        return .PRINT;
    } else if (utilsl.contains(cmd, "benchmark", .ignoreCase)) {
        return .BENCHMARK;
    }
    return .NOOP;
}
pub fn launch_engine(debugMode: bool) !void {
    mainThread(debugMode);
    return;
}

pub fn main() anyerror!void {
    try launch_engine(false);
}
