const std = @import("std");

const utilsl = @import("utils.zig");
const chess = @import("chess.zig");
const configl = @import("config.zig");
const boardl = @import("board.zig");
const hashTablel = @import("hashTable.zig");
const magicl = @import("magic.zig");
const moveTablel = @import("moveTables.zig");
const heuristicl = @import("heuristic.zig");
const schedulerl = @import("search/scheduler.zig");
const threadingl = @import("search/threading.zig");
const benchmarkl = @import("search/benchmark.zig");
const perftl = @import("search/perft.zig");
const historyl = @import("history.zig");

const filel = @import("file.zig");
const timel = @import("time.zig");
const mainl = @import("main.zig");
const lockl = @import("lock.zig");
const stringl = @import("string.zig");
const typel = @import("type.zig");

const debug_err = chess.debug_err;

const e_engineCmd = enum(u8) { NOOP = 0, QUIT, STOP, ISREADY, GO, POSITION, UCINEWGAME, REGISTER, SETOPTION, DEBUG, UCI, PONDERHIT, PRINT, BENCHMARK };
const e_goTypes = enum(u8) { DEFAULT, PONDER, EVAL, PERFT };
const e_engineOptions = enum(u8) { THREADS = 0, USEHASHTABLE, HASHTABLESIZE, INVALID, UCI_LIMITSTRENGHT, UCI_ELO, FIXED_DEPTH, USESTATICSEARCH, CLEAR_HASH, PRINT_METRIC, HEUR_WEIGHTS_PATH, USEQUIESCENCE, USENULLPRUNE, USELATEMOVEREDUC, USEFUTILITY, USEPROBCUT, USERAZORING, USERFP, TRACKMETRICS, REPORTPROG, SAVELOGS, LOGSPATH };
pub const e_engineOptionsArgType = enum(u8) { SPIN = 0, CHECK, STRING, COMBO, BUTTON, INVALID };

pub const e_logMsgType = enum(u8) { IN, OUT, CHANNELREAD };

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

pub fn getMsgStdin(reader: *std.Io.Reader) ![configl.MAX_USER_INPUT]u8 {
    var buffer = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
    var w: std.Io.Writer = .fixed(&buffer);
    _ = try reader.streamDelimiter(&w, '\n');
    reader.toss(1);
    return buffer;
}
const INPUTCHANNEL_LEN: usize = 64;
pub const cmdResult = struct {
    cmd: [configl.MAX_USER_INPUT]u8 = undefined,
    len: usize = 0,
};
pub const inputChannel = struct {
    cmdBuffer: [][configl.MAX_USER_INPUT]u8 = undefined,
    cmdSize: []usize = undefined,
    currentIdx: usize = 0,
    nextIdx: usize = 0,
    len: usize = INPUTCHANNEL_LEN,
    l: lockl.lock = .{},

    pub fn init(alloc: std.mem.Allocator) !inputChannel {
        var ret: inputChannel = undefined;
        ret.cmdBuffer = (try alloc.alloc([configl.MAX_USER_INPUT]u8, INPUTCHANNEL_LEN));
        ret.cmdSize = (try alloc.alloc(usize, INPUTCHANNEL_LEN));
        ret.nextIdx = 0;
        ret.currentIdx = 0;
        ret.l = .{};
        return ret;
    }

    pub fn nonEmpty(p_self: *inputChannel) bool {
        p_self.l.acquireLock();
        defer p_self.l.releaseLock();
        const ret = p_self.currentIdx != p_self.nextIdx;
        return ret;
    }
    pub fn readBuffer(p_self: *inputChannel) cmdResult {
        p_self.l.acquireLock();
        defer p_self.l.releaseLock();
        p_self.currentIdx = (p_self.currentIdx + 1) % INPUTCHANNEL_LEN;
        std.debug.assert(p_self.currentIdx != p_self.nextIdx + 1);
        const ret_len = p_self.cmdSize[p_self.currentIdx];
        var ret: cmdResult = .{ .len = ret_len };
        @memcpy((ret.cmd[0..ret_len]), p_self.cmdBuffer[p_self.currentIdx][0..ret_len]);
        return ret;
    }
    pub fn putCmd(p_self: *inputChannel, cmd: []const u8) bool {
        p_self.l.acquireLock();
        defer p_self.l.releaseLock();
        p_self.nextIdx = (p_self.nextIdx + 1) % INPUTCHANNEL_LEN;
        @memcpy((p_self.cmdBuffer[p_self.nextIdx][0..cmd.len]), cmd[0..cmd.len]);
        p_self.cmdSize[p_self.nextIdx] = cmd.len;
        return true;
    }
    pub fn free(p_self: *inputChannel, alloc: std.mem.Allocator) void {
        alloc.free(p_self.cmdBuffer);
        alloc.free(p_self.cmdSize);
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
    benchmarking: bool = false,
    debugMode: bool = false,
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
    computedPlies: u64 = 0,
    nPlyCompute: usize = 0,
    l: lockl.lock = .{},
    pub fn addPlies(p_self: *engineMetrics, plies: u64) void {
        p_self.l.acquireLock();
        p_self.computedPlies += plies;
        p_self.nPlyCompute += 1;
        p_self.l.releaseLock();
    }
    pub fn addTimeToSearchingMs(p_self: *engineMetrics, timeMs: i64) void {
        p_self.l.acquireLock();
        p_self.timeSearchingUs += timeMs * std.time.us_per_ms;
        p_self.l.releaseLock();
    }
    pub fn addTimeToProcessingMs(p_self: *engineMetrics, timeMs: i64) void {
        p_self.l.acquireLock();
        p_self.timeProcessingUs += timeMs * std.time.us_per_ms;
        p_self.l.releaseLock();
    }
    pub fn addTimeToSearchingUs(p_self: *engineMetrics, timeUs: i64) void {
        p_self.l.acquireLock();
        p_self.timeSearchingUs += timeUs;
        p_self.l.releaseLock();
    }
    pub fn addTimeToProcessingUs(p_self: *engineMetrics, timeUs: i64) void {
        p_self.l.acquireLock();
        p_self.timeProcessingUs += timeUs;
        p_self.l.releaseLock();
    }

    pub fn printMetric(p_self: *const engineMetrics) void {
        const proc: f64 = @as(f64, @floatFromInt(p_self.timeProcessingUs)) / std.time.us_per_ms;
        const search: f64 = @as(f64, @floatFromInt(p_self.timeSearchingUs)) / std.time.us_per_ms;
        const avg: f64 = @as(f64, @floatFromInt(p_self.computedPlies)) / @as(f64, @floatFromInt(@max(p_self.nPlyCompute, 1)));
        std.debug.print("Time spent processing {d} ms, time spent searching {d} ms. Average computed ply {d:.2}\n", .{ proc, search, avg });
    }
};

pub const engineOptions = struct {
    nThreads: spinVarType = configl.DEFAULT_THREAD,
    useHashTable: bool = configl.DEFAULT_USEHASHTABLE,
    useQuiescence: bool = configl.DEFAULT_USEQUIESC,
    useNullPrune: bool = configl.DEFAULT_USE_NULLPRUNE,
    useLMR: bool = configl.DEFAULT_LATE_MOVE_REDUCTION,
    useRazoring: bool = configl.DEFAULT_USE_RAZORING,
    useRFP: bool = configl.DEFAULT_USE_RFP,
    useFutility: bool = configl.DEFAULT_USE_FUTILITY,
    useProbCut: bool = configl.DEFAULT_USE_PROBCUT,

    hashTableSize: spinVarType = configl.DEFAULT_HASHTABLE_SIZE, // in MB
    limitElo: bool = configl.DEFAULT_LIMIT_ELO,
    fixedDepth: bool = configl.DEFAULT_FIXED_DEPTH,
    useStaticSearch: bool = configl.DEFAULT_STATIC_SEARCH,

    engineElo: spinVarType = configl.DEFAULT_ELO,
    nOptions: u16 = 0,
    depthLevel: u16 = configl.DEFAULT_DEPTH,
    trackMetrics: bool = configl.DEFAULT_TRACKMETRICS,
    reportProgress: bool = configl.DEFAULT_REPORTPROGRESS,
    setOptions: std.ArrayList(setOptionEntry) = .empty,

    saveLogs: bool = false,
    logsPath: stringl.string = undefined,
};
pub const logging = struct {
    _logs: std.ArrayList([]u8) = undefined,
    lock: lockl.lock = .{},
    freed: bool = false,
    pub fn init(alloc: std.mem.Allocator, initialCap: usize) !logging {
        var ret: logging = .{ .freed = false, .lock = .{} };
        ret._logs = try std.ArrayList([]u8).initCapacity(alloc, initialCap);
        return ret;
    }
    pub fn free(self: *logging, alloc: std.mem.Allocator) void {
        self.lock.acquireLock();
        for (0..self._logs.items.len) |i| {
            alloc.free(self._logs.items[i]);
        }
        self._logs.deinit(alloc);
        self.freed = true;
        self.lock.releaseLock();
    }
    pub fn append(self: *logging, alloc: std.mem.Allocator, msg: []u8) !void {
        self.lock.acquireLock();
        if (self.freed) {
            self.lock.releaseLock();
            std.debug.print("[DEBUG] logging.append: appending to freed logging, early return", .{});
            return;
        }
        try self._logs.append(alloc, msg);
        self.lock.releaseLock();
    }
};

pub const engine = struct {
    state: boardl.boardState = .{},
    workingThreads: std.ArrayList(std.Thread),
    status: engineStatus = .{},
    input: inputChannel,
    searcher: *schedulerl.uciSearcher,

    alloc: std.mem.Allocator,
    uciMode: bool = false,
    id: engineIdentification = .{},
    options: engineOptions = .{},
    startSw: timel.stopWatch = .{},
    metric: engineMetrics = .{},
    logs: logging = .{},

    pub fn init(alloc: std.mem.Allocator) !engine {
        var ret: engine = undefined;
        ret.alloc = alloc;
        ret.input = try inputChannel.init(alloc);
        ret.status = .{};
        ret.id = .{};
        ret.options = .{};
        ret.options.logsPath = try .initFromSlice(alloc, "out/engine.log");
        ret.startSw = .{};
        ret.startSw.startTimeTick();
        ret.metric = .{};
        ret.workingThreads = try std.ArrayList(std.Thread).initCapacity(alloc, 2);
        ret.logs = try logging.init(alloc, 16);

        ret.options.setOptions = try std.ArrayList(setOptionEntry).initCapacity(alloc, 4);
        ret.searcher = try alloc.create(schedulerl.uciSearcher);
        ret.searcher.* = .{};
        ret.searcher.schedul = .{};

        ret.uciMode = false;
        try ret.initOptions();
        ret.state = try chess.getBoardFromFen(chess.DEFAULT_FEN);

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

        try p_self.addOption(.{ .name = "savelogs", .optionType = .SAVELOGS, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = "false" } } });
        try p_self.addOption(.{ .name = "logsPath", .optionType = .LOGSPATH, .argType = .STRING, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "engine.log" } } });

        try p_self.addOption(.{ .name = "hashS", .optionType = .HASHTABLESIZE, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = 1, .max = configl.MAX_HASHSIZE, .default = configl.DEFAULT_HASHTABLE_SIZE } } });
        try p_self.addOption(.{ .name = "useHash", .optionType = .USEHASHTABLE, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USEHASHTABLE } } });

        try p_self.addOption(.{ .name = "useQuiescence", .optionType = .USEQUIESCENCE, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USEQUIESC } } });

        try p_self.addOption(.{ .name = "useNullPruning", .optionType = .USENULLPRUNE, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USE_NULLPRUNE } } });

        try p_self.addOption(.{ .name = "useLMR ", .optionType = .USELATEMOVEREDUC, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_LATE_MOVE_REDUCTION } } });

        try p_self.addOption(.{ .name = "useFutility", .optionType = .USEFUTILITY, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USE_FUTILITY } } });

        try p_self.addOption(.{ .name = "useProbCut", .optionType = .USEPROBCUT, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USE_PROBCUT } } });

        try p_self.addOption(.{ .name = "useRazoring", .optionType = .USERAZORING, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USE_RAZORING } } });
        try p_self.addOption(.{ .name = "useRFP", .optionType = .USERFP, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_USE_RFP } } });

        try p_self.addOption(.{ .name = "UCI_LimitStrength", .optionType = .UCI_LIMITSTRENGHT, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_LIMIT_ELO } } });
        try p_self.addOption(.{ .name = "UCI_Elo", .optionType = .UCI_ELO, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = configl.MIN_ELO, .max = configl.MAX_ELO, .default = configl.DEFAULT_ELO } } });

        try p_self.addOption(.{ .name = "fixedDepth", .optionType = .FIXED_DEPTH, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_FIXED_DEPTH } } });
        try p_self.addOption(.{ .name = "useStaticSearch", .optionType = .USESTATICSEARCH, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_STATIC_SEARCH } } });

        try p_self.addOption(.{ .name = "clearHash", .optionType = .CLEAR_HASH, .argType = .BUTTON, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "" } } });

        try p_self.addOption(.{ .name = "printMetric", .optionType = .PRINT_METRIC, .argType = .BUTTON, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "" } } });

        try p_self.addOption(.{ .name = "heuristicWeightsPath", .optionType = .HEUR_WEIGHTS_PATH, .argType = .STRING, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "" } } });

        try p_self.addOption(.{ .name = "trackMetrics", .optionType = .TRACKMETRICS, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_TRACKMETRICS } } });

        try p_self.addOption(.{ .name = "reportProgress", .optionType = .REPORTPROG, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_REPORTPROGRESS } } });
    }
    pub inline fn trackMetrics(p_self: *engine) bool {
        return p_self.options.trackMetrics;
    }
    pub fn printMetrics(p_self: *engine) void {
        p_self.metric.printMetric();
        if (p_self.options.useHashTable) {
            hashTablel.printTTStats();
        }
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
        var f_reader = std.Io.File.stdin().reader(mainl.getGlobalIo(), &buffer);
        const reader = &f_reader.interface;
        while (p_self.status.running) {
            const inputBuffer = try getMsgStdin(reader);
            const msg = utilsl.trimStr(&inputBuffer);
            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG] readingThread.engine: got '{s}' ({d} bytes)\n", .{ msg, msg.len });
                std.debug.print("\n", .{});
            }

            const prevCur = p_self.input.currentIdx;
            const prevNext = p_self.input.nextIdx;
            _ = p_self.input.putCmd(msg);
            const nextCur = p_self.input.currentIdx;
            const nextNext = p_self.input.nextIdx;
            if (p_self.options.saveLogs) {
                const respmsg = try std.fmt.allocPrint(p_self.alloc, "IN: '{s}' len {d} before(cur:{d} next:{d}) after(curr{d} next:{d})\n", .{ msg, msg.len, prevCur, prevNext, nextCur, nextNext });
                defer p_self.alloc.free(respmsg);
                try p_self.appendLog(respmsg);
            }
        }
    }
    pub fn executeBuffer(p_self: *engine, cmdBuffer: []const u8) bool {
        const cmdtype = getEngineCmdType(cmdBuffer);

        if (p_self.uciMode) {
            const trimmedBuffer = utilsl.trimStr(cmdBuffer);
            const status = p_self.uci_executeCmd(cmdtype, trimmedBuffer);
            if (p_self.status.debugMode) {
                if (cmdtype != .NOOP) {
                    std.debug.print("[DEBUG] executeBuffer.engine: found command type {} status: {}\n", .{ cmdtype, status });
                }
            }
            const statMsg = std.fmt.allocPrint(p_self.alloc, "engineOp {} {} '{s}' {d}", .{ cmdtype, status, cmdBuffer, cmdBuffer.len }) catch {
                return status;
            };
            defer p_self.alloc.free(statMsg);
            p_self.respond(statMsg);
            return status;
        } else if (cmdtype == .UCI) {
            p_self.uciMode = true;
            p_self.printEngineInfo();
        }
        return true;
    }
    fn waitOnWorkingThreads(p_self: *engine) void {
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.workingThreads.items[i].join();
        }
    }
    pub fn executeQuitProcedure(p_self: *engine) bool {
        p_self.status.running = false;
        p_self.searcher.close() catch {};
        if (p_self.trackMetrics()) {
            p_self.metric.addTimeToProcessingUs(p_self.searcher.schedul._threadPool.timeSpentSearchingUs());
            p_self.printMetrics();
        }
        p_self.waitOnWorkingThreads();
        p_self.respond("its ovah");
        if (p_self.options.saveLogs) {
            p_self.saveLog() catch {};
        }
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
                return p_self.executeIsReady() catch {
                    return false;
                };
            },
            .GO => {
                if (p_self.searcher.searching) {
                    if (p_self.status.debugMode) {}
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
                return p_self.executePositionCmd(cmdBuffer);
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
                const ret = p_self.executeDebugCmd(cmdBuffer);
                if (ret) {
                    p_self.searcher.schedul._threadPool.debugMode = p_self.status.debugMode;
                }
                return ret;
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
                chess.print_boardstate(&p_self.state);
                return true;
            },
        }
        return true;
    }
    pub fn respond(self: *engine, msg: []const u8) void {
        if (self.status.debugMode) {
            std.debug.print("[DEBUG] respond.engine: sending msg: '{s}'\n", .{msg});
        }
        const respmsg = std.fmt.allocPrint(self.alloc, "{s} \n", .{msg}) catch unreachable;
        defer self.alloc.free(respmsg);

        var buffer: [configl.MAX_USER_INPUT]u8 = undefined; // Buffer for stdout
        var writer = std.Io.File.stdout().writer(mainl.getGlobalIo(), &buffer);
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
        if (self.options.saveLogs) {
            const _respmsg = std.fmt.allocPrint(self.alloc, "OUT: len {d} '{s}'\n", .{ respmsg.len, respmsg[0..@min(respmsg.len, respmsg.len - 1)] }) catch {
                return;
            };
            defer self.alloc.free(_respmsg);
            self.appendLog(_respmsg) catch {
                return;
            };
        }
    }
    pub fn respondNonFmt(self: *engine, msg: []const u8) void {
        if (self.status.debugMode) {
            std.debug.print("[DEBUG] respondNonFmt.engine: sending msg: '{s}'\n", .{msg});
        }

        var buffer: [configl.MAX_USER_INPUT]u8 = undefined; // Buffer for stdout
        var writer = std.Io.File.stdout().writer(mainl.getGlobalIo(), &buffer);
        const interface = &writer.interface;
        interface.writeAll(msg) catch |err| {
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
        if (self.options.saveLogs) {
            const _respmsg = std.fmt.allocPrint(self.alloc, "OUT: len {d} '{s}'\n", .{ msg.len, msg[0..@min(msg.len, msg.len - 1)] }) catch {
                return;
            };
            defer self.alloc.free(_respmsg);
            self.appendLog(_respmsg) catch {
                return;
            };
        }
    }

    pub fn free(p_self: *engine) void {
        p_self.input.free(p_self.alloc);
        p_self.workingThreads.deinit(p_self.alloc);
        p_self.options.setOptions.deinit(p_self.alloc);
        p_self.alloc.destroy(p_self.searcher);
        if (p_self.status.initializedInternals) {
            hashTablel.hashTable.free(p_self.alloc, p_self.status.debugMode);
            //hashTablel.zobristKeys.free(p_self.alloc);
        }
        p_self.logs.free(p_self.alloc);
        p_self.options.logsPath.free(p_self.alloc);
    }

    pub fn saveLog(self: *engine) !void {
        if (!self.options.saveLogs) {
            return;
        }
        const file = try std.Io.Dir.createFile(.cwd(), mainl.getGlobalIo(), self.options.logsPath._slice(), .{ .read = true });
        defer file.close(mainl.getGlobalIo());
        for (0..self.logs._logs.items.len) |i| {
            _ = try file.writeStreamingAll(mainl.getGlobalIo(), self.logs._logs.items[i]);
        }
    }
    pub fn appendLogTyped(p_self: *engine, log: []const u8, typed: e_logMsgType) !void {
        var logmsg: []u8 = "";
        switch (typed) {
            .IN, .OUT => {
                @panic("???");
            },
            .CHANNELREAD => {
                logmsg = try std.fmt.allocPrint(p_self.alloc, "[LOG]{d} ms => channel read {s}\n", .{ p_self.startSw.timeSinceStartMs(), log });
            },
            //.SERVING => {
            //    logmsg = try std.fmt.allocPrint(p_self.alloc, "[LOG]{d} ms => channel read {s}\n", .{ p_self.startSw.timeSinceStartMs(), log });
            //    //SERVING: {s} status {}

            //},
        }
        try p_self.logs.append(p_self.alloc, logmsg);
    }

    pub fn appendLog(p_self: *engine, log: []const u8) !void {
        const logmsg = try std.fmt.allocPrint(p_self.alloc, "[LOG]{d} ms => {s}", .{ p_self.startSw.timeSinceStartMs(), log });
        try p_self.logs.append(p_self.alloc, logmsg);
    }

    pub fn executeUciNewGameCmd(p_self: *engine) bool {
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
        const name: e_engineOptions = parseSetOptionTypeCmd(&p_self.options.setOptions, cmdBuffer);
        const entry = p_self.getOptionEntry(name);

        switch (name) {
            .THREADS => {
                p_self.options.nThreads = getSpinValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .USEHASHTABLE => {
                p_self.options.useHashTable = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .SAVELOGS => {
                p_self.options.saveLogs = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .LOGSPATH => {
                const path = getStringValFromSetOptionCmd(tokens) catch {
                    return false;
                };

                if (utilsl.contains(path, ".log", .ignoreCase)) {
                    const newP = stringl.string.initFromSlice(p_self.alloc, path) catch {
                        return false;
                    };
                    p_self.options.logsPath.free(p_self.alloc);
                    p_self.options.logsPath = newP;
                } else {
                    const newP = filel.joinPath(p_self.alloc, path, "engine.log") catch {
                        return false;
                    };
                    p_self.options.logsPath.free(p_self.alloc);
                    p_self.options.logsPath = newP;
                }
                if (p_self.status.debugMode) {
                    std.debug.print("[DEBUG] executeSetoptionCmd: new logs path '{s}' \n", .{p_self.options.logsPath._slice()});
                }
                return true;
            },

            .USEQUIESCENCE => {
                p_self.options.useQuiescence = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .USENULLPRUNE => {
                p_self.options.useNullPrune = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
            },
            .USELATEMOVEREDUC => {
                p_self.options.useLMR = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
            },

            .USEFUTILITY => {
                p_self.options.useFutility = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
            },
            .USEPROBCUT => {
                p_self.options.useProbCut = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
            },

            .USERAZORING => {
                p_self.options.useRazoring = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .USERFP => {
                p_self.options.useRFP = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },

            .HASHTABLESIZE => {
                p_self.options.hashTableSize = getSpinValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };

                return p_self.updateHash(p_self.options.hashTableSize) catch {
                    return false;
                };
            },
            .UCI_ELO => {
                const val = getSpinValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return p_self.updateElo(val);
            },
            .UCI_LIMITSTRENGHT => {
                p_self.options.limitElo = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .FIXED_DEPTH => {
                p_self.options.fixedDepth = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .USESTATICSEARCH => {
                p_self.options.useStaticSearch = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .TRACKMETRICS => {
                p_self.options.trackMetrics = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .REPORTPROG => {
                p_self.options.reportProgress = getCheckValFromSetOptionCmd(tokens, entry) catch {
                    return false;
                };
                return true;
            },

            .CLEAR_HASH => {
                return p_self.updateHash(p_self.options.hashTableSize) catch {
                    return false;
                };
            },
            .PRINT_METRIC => {
                p_self.printMetrics();
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
    fn executePositionCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        const cmdOffset = 8;
        //* position [fen <fenstring> | startpos ]  moves <move1> .... <movei>
        // ex: position fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w AHah -

        if (utilsl.contains(cmdBuffer, "startpos", .ignoreCase)) {
            p_self.state = chess.getBoardFromFen(chess.DEFAULT_FEN) catch {
                return false;
            };
            chess.applyUciMoves(&p_self.state, cmdBuffer[cmdOffset..], p_self.status.debugMode) catch {
                return false;
            };
        } else if (utilsl.contains(cmdBuffer, "fen", .ignoreCase)) {
            const fenCmdOffset = utilsl.findM(u8, cmdBuffer, "fen");
            if (fenCmdOffset == -1) {
                return false;
            }
            p_self.state = chess.getBoardFromUciFen(utilsl.stripStr(cmdBuffer[(@intCast(fenCmdOffset + 3))..]), p_self.status.debugMode) catch {
                return false;
            };
        } else {
            return false;
        }
        return true;
    }
    pub fn setFen(p_self: *engine, fen: []const u8) void {
        p_self.state = chess.getBoardFromFen(fen) catch unreachable;
    }

    fn initInternals(p_self: *engine) bool {
        p_self.status.initializedInternals = true;
        magicl._initMagic(&magicl.magicTable, p_self.status.debugMode);

        moveTablel._initTables(p_self.status.debugMode);
        //hashTablel._initZobrist(p_self.alloc, configl.SEED);
        hashTablel._initOrReallocHashTable(p_self.alloc, p_self.options.hashTableSize, p_self.status.debugMode);

        _ = p_self.updateElo(p_self.options.engineElo);
        return true;
    }
    pub fn refreshInternals(p_self: *engine) void {
        _ = p_self.updateElo(p_self.options.engineElo);
        historyl._initMoveOrdering();
        _ = p_self.updateHash(p_self.options.hashTableSize) catch {};
    }
    fn updateHeuristicWeights(p_self: *engine, path: []const u8) bool {
        heuristicl.modifyHeuristicWeight(p_self.alloc, path, p_self.status.debugMode) catch {
            return false;
        };
        return true;
    }

    fn updateHash(p_self: *engine, hashSize: spinVarType) !bool {
        if (p_self.searcher.searching) {
            p_self.searcher.interrupt = true;
            while (p_self.searcher.searching) {
                try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.WAIT_TICKRATE_NS) }, .real);
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

        return true;
    }
    pub fn executeIsReady(p_self: *engine) !bool {
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
        var goArg = parseGoCmd(&tokens);

        p_self.searcher.reset();

        if (goArg.depth == 0) {
            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG] executeGoCmd: No depth found in the cmd string using the default engine option \n", .{});
            }
            goArg.depth = p_self.options.depthLevel;
        }
        if (goArg.type == .PERFT) {
            return perftl.dispatchUciPerftCmd(p_self, goArg);
        }
        if (!p_self.searcher.schedul._threadPool.running) {
            p_self.searcher.schedul._threadPool.addThread(1) catch {
                p_self.respond("engineOp threadPoolAddThread failed crashing");
                _ = p_self.executeQuitProcedure();
                @panic(":)");
            };
            p_self.respond("engineOp incrementalLoop .ADDTHREAD");
        }

        return schedulerl.dispatchUciGoCmd(p_self, cmdBuffer, goArg);
    }
    pub fn executeBenchmarkCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        _ = cmdBuffer;
        if (p_self.searcher.searching) {
            return false;
        }
        p_self.searcher.reset();
        p_self.status.benchmarking = true;
        return benchmarkl.dispatchUciBenchmark(p_self);
    }
};

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

pub fn parseSetOptionTypeCmd(options: *std.ArrayList(setOptionEntry), cmdBuffer: []const u8) e_engineOptions {
    for (0..options.items.len) |i| {
        const entry = options.items[i];
        if (utilsl.contains(cmdBuffer, entry.name, .ignoreCase)) {
            return entry.optionType;
        }
    }
    return .INVALID;
}
pub fn getSpinValFromSetOptionCmd(tokens: std.ArrayList([]const u8), entry: setOptionEntry) !spinVarType {
    for (0..tokens.items.len) |i| {
        const token = tokens.items[i];
        if (utilsl.contains(token, "value", .ignoreCase)) {
            if (i != tokens.items.len - 1) {
                const ret = std.fmt.parseInt(spinVarType, tokens.items[i + 1], 10) catch {
                    return debug_err.valueErr;
                };

                if (!entry.info.spin.validateValue(ret)) {
                    return debug_err.valueErr;
                }
                return ret;
            }
        }
    }
    return debug_err.valueErr;
}
pub fn getCheckValFromSetOptionCmd(tokens: std.ArrayList([]const u8), entry: setOptionEntry) !bool {
    for (0..tokens.items.len) |i| {
        const token = tokens.items[i];

        if (utilsl.contains(token, "value", .ignoreCase)) {
            if (i != tokens.items.len - 1) {
                const val = tokens.items[i + 1];
                if (!entry.info.str.validateValue(val)) {
                    return debug_err.valueErr;
                }
                return utilsl.contains(val, "true", .ignoreCase);
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
    var cumulSw: timel.stopWatch = .{};
    cumulSw.startTimeTick();
    while (p_self.status.running) {
        while (p_self.input.nonEmpty() and p_self.status.running) {
            cumulSw.reset();
            cumulSw.startTimeTick();
            var sw: timel.stopWatch = .{};
            sw.startTimeTick();
            const cmd = p_self.input.readBuffer();

            if (p_self.options.saveLogs and p_self.status.running) {
                p_self.appendLogTyped(cmd.cmd[0..cmd.len], .CHANNELREAD) catch {};
            }

            const status = p_self.executeBuffer(cmd.cmd[0..cmd.len]);

            if (p_self.trackMetrics()) {
                p_self.metric.addTimeToProcessingUs(sw.timeSinceStartUs());
            }
            if (p_self.options.saveLogs and p_self.status.running) {
                const respmsg = std.fmt.allocPrint(p_self.alloc, "SERVING: {s} status {}\n", .{ cmd.cmd[0..cmd.len], status }) catch {
                    continue;
                };
                defer p_self.alloc.free(respmsg);
                p_self.appendLog(respmsg) catch {
                    continue;
                };
            }
        }
        if (cumulSw.timeSinceStartUs() > configl.DEBUG_INACTIVITY_READING_US) {
            std.debug.print("[INACTIVITY] inputThreading.engine: no activity found in the last {d}s \n", .{configl.DEBUG_INACTIVITY_READING_S});
            cumulSw.reset();
            cumulSw.startTimeTick();
        }
        if (p_self.status.running) {
            if (p_self.searcher.searching and !p_self.status.benchmarking) {
                // check things here what scheduler is doing
                schedulerl.waitingRoomOneShot(p_self) catch {};
            }
        }
        std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.WAIT_TICKRATE_NS) }, .real) catch unreachable;
    }

    if (p_self.status.debugMode) {
        std.debug.print("[DEBUG] inputThreading.engine: exiting \n", .{});
    }
}

fn entrypointReaderThreading(p_self: *engine) void {
    p_self.readingThread() catch {
        if (p_self.status.running) {
            _ = p_self.executeQuitProcedure();
        }
    };
}
fn mainThread(debugMode: bool) void {
    var eng = engine.init(mainl.getGlobalGPA()) catch unreachable;
    eng.status.running = true;

    _ = std.Thread.spawn(.{}, entrypointReaderThreading, .{&eng}) catch unreachable;
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

//pub fn main(init: std.process.Init.Minimal) anyerror!void {
//    _ = init;
//    const allocator = std.heap.page_allocator;
//    var threaded: std.Io.Threaded = .init(allocator, .{});
//    defer threaded.deinit();
//    const io = threaded.io();
//    mainl.GLOBAL_CTX.setIO(io);
//    mainl.GLOBAL_CTX.setGPA(allocator);
//    mainl.GLOBAL_CTX.isInit = true;
//    try launch_engine(false);
//}
pub fn main(init: std.process.Init) anyerror!void {
    mainl.GLOBAL_CTX.setInit(init);
    try launch_engine(false);
}
