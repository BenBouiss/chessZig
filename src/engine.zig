const std = @import("std");

const utilsl = @import("utils.zig");
const chess = @import("chess.zig");
const configl = @import("config.zig");
const boardl = @import("board.zig");
const hashTablel = @import("hashTable.zig");
const magicl = @import("magic.zig");
const heuristicl = @import("heuristic.zig");
const schedulerl = @import("scheduler.zig");
const perftl = @import("perft.zig");
const historyl = @import("history.zig");
const nnuel = @import("nnue.zig");
const weightl = @import("weights.zig");
const ucil = @import("uci.zig");
const typel = @import("type.zig");

const build_options = @import("build_options");

const filel = @import("file.zig");
const timel = @import("time.zig");
const mainl = @import("main.zig");
const lockl = @import("lock.zig");
const stringl = @import("string.zig");

const debug_err = chess.debug_err;

const e_engineCmd = enum(u8) { NOOP = 0, QUIT, STOP, ISREADY, GO, POSITION, UCINEWGAME, REGISTER, SETOPTION, DEBUG, UCI, PONDERHIT, PRINT, BENCHMARK, PRINTPARAMS };
const e_goTypes = enum(u8) { DEFAULT, PONDER, EVAL, PERFT };
const e_engineOptions = enum(u8) { THREADS = 0, HASHTABLESIZE, INVALID, UCI_ELO, FIXED_DEPTH, USESTATICSEARCH, CLEAR_HASH, PRINT_METRIC, TRACKMETRICS, REPORTPROG, SAVELOGS, LOGSPATH };
pub const e_engineOptionsArgType = enum(u8) { SPIN = 0, CHECK, STRING, COMBO, BUTTON, INVALID };

pub const e_logMsgType = enum(u8) { IN, OUT, CHANNELREAD };

pub const goArgStruct = struct {
    searchMoves: bool = false,
    infinite: bool = false,
    type: e_goTypes = .DEFAULT,
    useBatched: bool = false,

    // all times in ms
    wtime: i64 = std.math.maxInt(i64),
    btime: i64 = std.math.maxInt(i64),
    winc: i64 = 0,
    binc: i64 = 0,

    movestogo: u64 = 0,
    movetime: i64 = 0,
    nodes: u64 = 0,
    depth: typel.depthT = 0,
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
    pub fn initP(alloc: std.mem.Allocator) !*inputChannel {
        const ret = try alloc.create(inputChannel);
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
        return p_self.currentIdx != p_self.nextIdx;
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
    pub fn putCmd(p_self: *inputChannel, cmd: []const u8) void {
        p_self.l.acquireLock();
        defer p_self.l.releaseLock();
        p_self.nextIdx = (p_self.nextIdx + 1) % INPUTCHANNEL_LEN;
        @memcpy((p_self.cmdBuffer[p_self.nextIdx][0..cmd.len]), cmd[0..cmd.len]);
        p_self.cmdSize[p_self.nextIdx] = cmd.len;
    }
    pub fn free(p_self: *inputChannel, alloc: std.mem.Allocator) void {
        alloc.free(p_self.cmdBuffer);
        alloc.free(p_self.cmdSize);
    }
};

const spinVarType: type = i32;
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

pub const optionInfo = union { spin: optionInfo_spin, str: optionInfo_str };

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
    debugMode: bool = false,
    initializedInternals: bool = false,
};
pub const engineIdentification = struct {
    name: []const u8 = configl.NAME,
    author: []const u8 = configl.AUTHOR,
    code: []const u8 = configl.VERSION,
};
pub const engineMetrics = struct {
    timeSearchingUs: i64 = 0,
    timeProcessingUs: i64 = 0,
    computedPlies: i64 = 0,
    nPlyCompute: usize = 0,
    l: lockl.lock = .{},
    pub fn addPlies(p_self: *engineMetrics, plies: typel.depthT) void {
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
        const proc: i64 = @divFloor(p_self.timeProcessingUs, std.time.us_per_ms);
        const search: i64 = @divFloor(p_self.timeSearchingUs, std.time.us_per_ms);
        const avg: f64 = @as(f64, @floatFromInt(p_self.computedPlies)) / @as(f64, @floatFromInt(@max(p_self.nPlyCompute, 1)));
        std.log.info("Time spent processing {d} ms, time spent searching {d} ms. Average computed ply {d:.2}", .{ proc, search, avg });
    }
};

pub const engineOptions = struct {
    searchF: schedulerl.searchFeatures = .{},
    nThreads: spinVarType = configl.DEFAULT_THREAD,
    nOptions: u16 = 0,
    trackMetrics: bool = configl.DEFAULT_TRACKMETRICS,
    hashTableSize: spinVarType = configl.DEFAULT_HASHTABLE_SIZE, // in MB
    setOptions: std.ArrayList(setOptionEntry) = .empty,
};
pub const logging = struct {
    _logs: std.ArrayList([]u8) = .empty,
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

    workingThreads: std.ArrayList(std.Thread) = .empty,
    status: engineStatus = .{},
    scheduler: schedulerl.scheduler = .{},

    alloc: std.mem.Allocator,
    //uciMode: bool = false,
    id: engineIdentification = .{},
    options: engineOptions = .{},
    startSw: timel.stopWatch = .{},
    metric: engineMetrics = .{},
    logs: logging = .{},

    saveLogs: bool = false,
    logsPath: stringl.string = undefined,

    pub fn init(alloc: std.mem.Allocator) !engine {
        var ret: engine = undefined;
        ret.alloc = alloc;
        ret.status = .{};
        ret.id = .{};
        ret.options = .{};
        ret.logsPath = try .initFromSlice(alloc, "out/engine.log");
        ret.startSw = .init(true);
        ret.metric = .{};
        ret.workingThreads = try std.ArrayList(std.Thread).initCapacity(alloc, 2);
        ret.logs = try logging.init(alloc, 16);

        ret.options.setOptions = try std.ArrayList(setOptionEntry).initCapacity(alloc, 4);
        ret.scheduler = .{};
        //ret.uciMode = false;
        try ret.initInternals();
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
        if (build_options.useTune) {
            for (0..weightl.tunerOpts.items.len) |i| {
                const msg = weightl.tunerOpts.items[i].opt.optionNameMsg(p_self.alloc) catch unreachable;
                defer p_self.alloc.free(msg);
                p_self.respond(msg);
            }
        }
        p_self.respond("uciok");
    }
    pub fn initOptions(p_self: *engine) !void {
        try p_self.addOption(.{ .name = "threads", .optionType = .THREADS, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = 1, .max = configl.MAX_THREAD, .default = configl.DEFAULT_THREAD } } });

        try p_self.addOption(.{ .name = "savelogs", .optionType = .SAVELOGS, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = "false" } } });

        try p_self.addOption(.{ .name = "logsPath", .optionType = .LOGSPATH, .argType = .STRING, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "engine.log" } } });

        try p_self.addOption(.{ .name = "hash", .optionType = .HASHTABLESIZE, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = 1, .max = configl.MAX_HASHSIZE, .default = configl.DEFAULT_HASHTABLE_SIZE } } });

        try p_self.addOption(.{ .name = "UCI_Elo", .optionType = .UCI_ELO, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = configl.MIN_ELO, .max = configl.MAX_ELO, .default = configl.DEFAULT_ELO } } });

        try p_self.addOption(.{ .name = "fixedDepth", .optionType = .FIXED_DEPTH, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_FIXED_DEPTH } } });
        try p_self.addOption(.{ .name = "useStaticSearch", .optionType = .USESTATICSEARCH, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_STATIC_SEARCH } } });

        try p_self.addOption(.{ .name = "clearHash", .optionType = .CLEAR_HASH, .argType = .BUTTON, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "" } } });

        try p_self.addOption(.{ .name = "printMetric", .optionType = .PRINT_METRIC, .argType = .BUTTON, .info = optionInfo{ .str = optionInfo_str{ ._var = "", .default = "" } } });

        try p_self.addOption(.{ .name = "trackMetrics", .optionType = .TRACKMETRICS, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_TRACKMETRICS } } });

        try p_self.addOption(.{ .name = "reportProgress", .optionType = .REPORTPROG, .argType = .CHECK, .info = optionInfo{ .str = optionInfo_str{ ._var = "false true", .default = configl._DEFAULT_REPORTPROGRESS } } });
        if (build_options.useTune) {
            try weightl.appendAll();
        }
    }
    pub inline fn trackMetrics(p_self: *engine) bool {
        return p_self.options.trackMetrics;
    }
    pub inline fn printMetrics(p_self: *engine) void {
        p_self.metric.timeSearchingUs = p_self.scheduler._threadPool.timeSpentSearchingUs();
        p_self.metric.computedPlies = p_self.scheduler._threadPool.computedPlies;
        p_self.metric.nPlyCompute = p_self.scheduler._threadPool.nPlyCompute;
        p_self.metric.printMetric();
        hashTablel.printTTStats();
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

    fn waitOnWorkingThreads(p_self: *engine) void {
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.workingThreads.items[i].join();
        }
    }
    pub fn executeQuitProcedure(p_self: *engine) bool {
        p_self.status.running = false;
        p_self.scheduler.close();
        if (p_self.trackMetrics()) {
            p_self.printMetrics();
        }
        p_self.waitOnWorkingThreads();
        p_self.respond("its ovah");
        if (p_self.saveLogs) {
            p_self.saveLog() catch {};
        }
        p_self.free(p_self.alloc);
        return true;
    }

    pub fn respond(self: *engine, msg: []const u8) void {
        var msgBuffer: [configl.MAX_USER_INPUT]u8 = @splat(0); // Buffer for stdout
        const respmsg = std.fmt.bufPrint(&msgBuffer, "{s} \n", .{msg}) catch unreachable;

        std.Io.File.stdout().writeStreamingAll(mainl.getGlobalIo(), respmsg) catch |err| {
            if (self.status.debugMode) {
                std.debug.print("[DEBUG] respond.engine: caught err: {}\n", .{err});
            }
            return;
        };

        if (self.saveLogs) {
            const _respmsg = std.fmt.allocPrint(self.alloc, "OUT: len {d} '{s}'\n", .{ respmsg.len, respmsg[0..@min(respmsg.len, respmsg.len - 1)] }) catch {
                return;
            };
            defer self.alloc.free(_respmsg);
            self.appendLog(self.alloc, _respmsg) catch {
                return;
            };
        }
    }

    pub fn free(p_self: *engine, alloc: std.mem.Allocator) void {
        p_self.workingThreads.deinit(alloc);
        p_self.options.setOptions.deinit(alloc);
        if (p_self.status.initializedInternals) {
            hashTablel.hashTable.free(alloc, p_self.status.debugMode);
            //hashTablel.zobristKeys.free(p_self.alloc);
        }
        p_self.logs.free(alloc);
        p_self.logsPath.free(alloc);
        weightl.tunerOpts.deinit(alloc);
    }

    pub fn saveLog(self: *engine) !void {
        if (!self.saveLogs) {
            return;
        }
        const file = try std.Io.Dir.createFile(.cwd(), mainl.getGlobalIo(), self.logsPath._slice(), .{ .read = true });
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
        }
        try p_self.logs.append(p_self.alloc, logmsg);
    }

    pub fn appendLog(p_self: *engine, alloc: std.mem.Allocator, log: []const u8) !void {
        const logmsg = try std.fmt.allocPrint(alloc, "[LOG]{d} ms => {s}", .{ p_self.startSw.timeSinceStartMs(), log });
        try p_self.logs.append(alloc, logmsg);
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
        _ = p_self;
        _ = cmdBuffer;
        return true;
    }
    pub fn executeSetOptionCmd(p_self: *engine, alloc: std.mem.Allocator, cmdBuffer: []const u8) bool {
        // format: setoption name <id> [value <x>]
        var tokens = utilsl.split(u8, alloc, cmdBuffer, ' ') catch {
            return false;
        };
        defer tokens.deinit(alloc);
        if (tokens.items.len < 2) {
            return false;
        }
        const name: e_engineOptions = parseSetOptionTypeCmd(&p_self.options.setOptions, tokens.items[2]);
        const entry = p_self.getOptionEntry(name);

        switch (name) {
            .THREADS => {
                p_self.options.nThreads = getSpinValFromSetOptionCmd(&tokens, entry) catch {
                    return false;
                };
                return true;
            },

            .SAVELOGS => {
                p_self.saveLogs = getCheckValFromSetOptionCmd(&tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .LOGSPATH => {
                const path = getValueSlice(&tokens) catch {
                    return false;
                };

                if (utilsl.contains(path, ".log", .ignoreCase)) {
                    const newP = stringl.string.initFromSlice(alloc, path) catch {
                        return false;
                    };
                    p_self.logsPath.free(alloc);
                    p_self.logsPath = newP;
                } else {
                    const newP = filel.joinPath(alloc, path, "engine.log") catch {
                        return false;
                    };
                    p_self.logsPath.free(alloc);
                    p_self.logsPath = newP;
                }
                if (p_self.status.debugMode) {
                    std.debug.print("[DEBUG] executeSetoptionCmd: new logs path '{s}' \n", .{p_self.logsPath._slice()});
                }
                return true;
            },

            .HASHTABLESIZE => {
                p_self.options.hashTableSize = getSpinValFromSetOptionCmd(&tokens, entry) catch {
                    return false;
                };

                return p_self.updateHash(p_self.options.hashTableSize) catch {
                    return false;
                };
            },
            .UCI_ELO => {
                return true;
            },

            .FIXED_DEPTH => {
                p_self.options.searchF.fixedDepth = getCheckValFromSetOptionCmd(&tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .USESTATICSEARCH => {
                p_self.options.searchF.useStaticSearch = getCheckValFromSetOptionCmd(&tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .TRACKMETRICS => {
                p_self.options.trackMetrics = getCheckValFromSetOptionCmd(&tokens, entry) catch {
                    return false;
                };
                return true;
            },
            .REPORTPROG => {
                p_self.options.searchF.reportProgress = getCheckValFromSetOptionCmd(&tokens, entry) catch {
                    return false;
                };
                return true;
            },

            .CLEAR_HASH => {
                if (hashTablel.hashTable.initialized) {
                    hashTablel.hashTable.zero();
                }
                return true;
            },
            .PRINT_METRIC => {
                p_self.printMetrics();
                return true;
            },

            .INVALID => {
                for (0..weightl.tunerOpts.items.len) |i| {
                    const opt = weightl.tunerOpts.items[i];
                    if (utilsl.contains(cmdBuffer, opt.opt.name, .ignoreCase)) {
                        const val = getSpinValFromSetOptionCmd(&tokens, opt.opt) catch {
                            return false;
                        };
                        opt.addr.* = val;
                        return true;
                    }
                }
                return false;
            },
        }

        return false;
    }

    pub fn executePositionCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        const cmdOffset = 8;
        //* position [fen <fenstring> | startpos ]  moves <move1> .... <movei>
        // ex: position fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w AHah -
        var gen = utilsl.splitGenerator(u8).init(cmdBuffer, ' ');
        const modifier = gen.get(1) orelse return false;

        if (utilsl.startsWith(modifier, "startpos", .ignoreCase)) {
            p_self.state = chess.getBoardFromFen(chess.DEFAULT_FEN) catch {
                return false;
            };
            chess.applyUciMoves(&p_self.state, cmdBuffer[cmdOffset..], p_self.status.debugMode) catch {
                return false;
            };
        } else if (utilsl.startsWith(modifier, "fen", .ignoreCase)) {
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

    fn initInternals(p_self: *engine) !void {
        p_self.status.initializedInternals = true;
        try p_self.initOptions();
        magicl._initMagic(&magicl.magicTable, p_self.status.debugMode);
        p_self.refreshInternals();
        if (!nnuel.nnueNet.inited and comptime configl.USE_NNUE) {
            nnuel.nnueNet = try .init(p_self.alloc, configl.NET_PATH);
        }
    }
    pub fn refreshInternals(p_self: *engine) void {
        historyl._initMoveOrdering();
        _ = p_self.updateHash(p_self.options.hashTableSize) catch {};
    }

    fn updateHash(p_self: *engine, hashSize: spinVarType) !bool {
        p_self.options.hashTableSize = hashSize;
        hashTablel._initOrReallocHashTable(p_self.alloc, @intCast(p_self.options.hashTableSize), p_self.status.debugMode);
        return true;
    }

    pub fn executeIsReady(p_self: *engine) !bool {
        if (!p_self.status.initializedInternals) {
            try p_self.initInternals();
        }
        p_self.respond("readyok");
        return true;
    }
    pub fn interruptSearch(p_self: *engine) void {
        p_self.scheduler.handleInterrupt();
    }
    pub fn executeGoCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        const goArg = parseGoCmd(cmdBuffer);

        p_self.scheduler.reset();
        if (goArg.type == .PERFT) {
            return perftl.dispatchUciPerftCmd(p_self, goArg);
        }
        if (!p_self.scheduler._threadPool.running) {
            p_self.scheduler._threadPool.addThread(1) catch {
                p_self.respond("engineOp threadPoolAddThread failed crashing");
                _ = p_self.executeQuitProcedure();
                @panic(":)");
            };
            p_self.respond("engineOp incrementalLoop .ADDTHREAD");
        }

        return schedulerl.dispatchUciGoCmd(p_self, goArg);
    }
    pub fn executeBenchmarkCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        _ = cmdBuffer;
        p_self.scheduler.reset();
        return dispatchUciBenchmark(p_self, p_self.alloc);
    }
};
//https://github.com/maksimKorzh/chess_programming/
pub const benchmarkEntries = [_][]const u8{
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 ",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1 ",
    "rnbqkb1r/pp1p1pPp/8/2p1pP2/1P1P4/3P3P/P1P1P3/RNBQKBNR w KQkq e6 0 1",
    "r2q1rk1/ppp2ppp/2n1bn2/2b1p3/3pP3/3P1NPP/PPP1NPB1/R1BQ1RK1 b - - 0 9 ",
    "4R1K1/8/8/8/8/8/3R1k2/8 b - - 0 0 ", // double rook situation
};

pub fn dispatchUciBenchmark(p_engine: *engine, alloc: std.mem.Allocator) bool {
    // executes the benchmark steps

    const dispatchThread = std.Thread.spawn(.{}, dispatchUciBenchmarkThreads, .{ p_engine, alloc }) catch {
        return false;
    };
    p_engine.workingThreads.append(alloc, dispatchThread) catch {
        return false;
    };
    return true;
}
pub fn dispatchUciBenchmarkThreads(p_engine: *engine, alloc: std.mem.Allocator) void {
    var results: std.ArrayList(schedulerl.searchReport) = std.ArrayList(schedulerl.searchReport).initCapacity(alloc, 4) catch {
        return;
    };
    defer results.deinit(alloc);
    const benchmarkDepth: u16 = 8;

    var sched = &p_engine.scheduler;
    if (!sched._threadPool.running) {
        sched._threadPool.addThread(1) catch unreachable;
    }
    std.debug.print("============ Benchmark evaluation ============\n", .{});
    var features: schedulerl.searchFeatures = p_engine.options.searchF;
    features.fixedDepth = true;
    features.reportProgress = true;
    for (0..benchmarkEntries.len) |i| {
        p_engine.refreshInternals();
        const fen = benchmarkEntries[i];
        p_engine.state = chess.getBoardFromFen(fen) catch {
            continue;
        };
        const res = sched.entryPointSearch(p_engine.state, benchmarkDepth, features);
        results.append(alloc, res) catch unreachable;
    }
    printResults(&benchmarkEntries, &results);
    std.debug.print("============ Benchmark perft ============\nComing soon\n", .{});
}
pub fn printResults(fens: []const []const u8, reports: *const std.ArrayList(schedulerl.searchReport)) void {
    for (0..fens.len) |i| {
        const curr: schedulerl.searchReport = reports.items[i];
        const _time: u64 = @intCast(curr.timeTakenMs);
        const nps = 1000 * @divFloor(curr.searchStat.n_nodeExplored, _time + 1);
        const cuttoffF: f64 = 100 * @as(f64, @floatFromInt(curr.searchStat.n_cutoffs)) / @as(f64, @floatFromInt(curr.searchStat.n_nodeExplored));
        std.debug.print("{s} nps: {d} nodes: {d} cutoff {d} cutoff {d:4.1}% move {s} cp {d} retrieved: {d}\n", .{ fens[i], nps, curr.searchStat.n_nodeExplored, curr.searchStat.n_cutoffs, cuttoffF, curr.move.getStr(), curr.score, curr.searchStat.n_hashRetrieve });
    }
}

fn parseGoCmd(cmd: []const u8) goArgStruct {
    var goArgs: goArgStruct = .{};
    var gen = utilsl.splitGenerator(u8).init(cmd, ' ');
    while (gen.next()) |arg| {
        if (utilsl.startsWith(arg, "searchmoves", .ignoreCase)) {
            goArgs.searchMoves = true;
        } else if (utilsl.startsWith(arg, "eval", .ignoreCase)) {
            goArgs.type = .EVAL;
        } else if (utilsl.startsWith(arg, "perft", .ignoreCase)) {
            goArgs.type = .PERFT;
        } else if (utilsl.startsWith(arg, "batched", .ignoreCase)) {
            goArgs.useBatched = true;
        } else if (utilsl.startsWith(arg, "ponder", .ignoreCase)) {
            goArgs.type = .PONDER;
        } else if (utilsl.startsWith(arg, "wtime", .ignoreCase)) {
            if (gen.next()) |val| {
                goArgs.wtime = std.fmt.parseInt(i64, val, 10) catch {
                    gen.rewind();
                    continue;
                };
            }
        } else if (utilsl.startsWith(arg, "btime", .ignoreCase)) {
            if (gen.next()) |val| {
                goArgs.btime = std.fmt.parseInt(i64, val, 10) catch {
                    gen.rewind();
                    continue;
                };
            }
        } else if (utilsl.startsWith(arg, "winc", .ignoreCase)) {
            if (gen.next()) |val| {
                goArgs.winc = std.fmt.parseInt(i64, val, 10) catch {
                    gen.rewind();
                    continue;
                };
            }
        } else if (utilsl.startsWith(arg, "binc", .ignoreCase)) {
            if (gen.next()) |val| {
                goArgs.binc = std.fmt.parseInt(i64, val, 10) catch {
                    gen.rewind();
                    continue;
                };
            }
        } else if (utilsl.startsWith(arg, "movestogo", .ignoreCase)) {
            if (gen.next()) |val| {
                goArgs.movestogo = std.fmt.parseInt(u64, val, 10) catch {
                    gen.rewind();
                    continue;
                };
            }
        } else if (utilsl.startsWith(arg, "depth", .ignoreCase)) {
            if (gen.next()) |val| {
                goArgs.depth = std.fmt.parseInt(typel.depthT, val, 10) catch {
                    gen.rewind();
                    continue;
                };
            }
        } else if (utilsl.startsWith(arg, "nodes", .ignoreCase)) {
            if (gen.next()) |val| {
                goArgs.nodes = std.fmt.parseInt(u64, val, 10) catch {
                    gen.rewind();
                    continue;
                };
            }
        } else if (utilsl.startsWith(arg, "mate", .ignoreCase)) {
            if (gen.next()) |val| {
                goArgs.mate = std.fmt.parseInt(u16, val, 10) catch {
                    gen.rewind();
                    continue;
                };
            }
        } else if (utilsl.startsWith(arg, "movetime", .ignoreCase)) {
            if (gen.next()) |val| {
                goArgs.movetime = std.fmt.parseInt(i64, val, 10) catch {
                    gen.rewind();
                    continue;
                };
            }
            goArgs.wtime = goArgs.movetime;
            goArgs.btime = goArgs.movetime;
        } else if (utilsl.startsWith(arg, "infinite", .ignoreCase)) {
            goArgs.infinite = true;
        }
    }

    return goArgs;
}

pub fn parseSetOptionTypeCmd(options: *std.ArrayList(setOptionEntry), cmdBuffer: []const u8) e_engineOptions {
    for (0..options.items.len) |i| {
        const entry = options.items[i];
        if (utilsl.startsWith(cmdBuffer, entry.name, .ignoreCase)) {
            return entry.optionType;
        }
    }
    return .INVALID;
}
pub fn getValueSlice(tokens: *std.ArrayList([]const u8)) ![]const u8 {
    for (0..tokens.items.len) |i| {
        const token = tokens.items[i];
        if (utilsl.startsWith(token, "value", .ignoreCase)) {
            if (i != tokens.items.len - 1) {
                return tokens.items[i + 1];
            } else {
                return debug_err.valueErr;
            }
        }
    }
    return debug_err.valueErr;
}
pub fn getSpinValFromSetOptionCmd(tokens: *std.ArrayList([]const u8), entry: setOptionEntry) !spinVarType {
    const s = try getValueSlice(tokens);
    const ret = std.fmt.parseInt(spinVarType, s, 10) catch {
        return debug_err.valueErr;
    };
    if (!entry.info.spin.validateValue(ret)) {
        return debug_err.valueErr;
    }
    return ret;
}

pub fn getCheckValFromSetOptionCmd(tokens: *std.ArrayList([]const u8), entry: setOptionEntry) !bool {
    const s = try getValueSlice(tokens);
    if (!entry.info.str.validateValue(s)) {
        return debug_err.valueErr;
    }
    return utilsl.contains(s, "true", .ignoreCase);
}

pub fn getEngineCmdType(cmd: []const u8) e_engineCmd {
    if (utilsl.startsWith(cmd, "isready", .ignoreCase)) {
        return .ISREADY;
    } else if (utilsl.startsWith(cmd, "go", .ignoreCase)) {
        return .GO;
    } else if (utilsl.startsWith(cmd, "position", .ignoreCase)) {
        return .POSITION;
    } else if (utilsl.startsWith(cmd, "ucinewgame", .ignoreCase)) {
        return .UCINEWGAME;
    } else if (utilsl.startsWith(cmd, "register", .ignoreCase)) {
        return .REGISTER;
    } else if (utilsl.startsWith(cmd, "setoption", .ignoreCase)) {
        return .SETOPTION;
    } else if (utilsl.startsWith(cmd, "debug", .ignoreCase)) {
        return .DEBUG;
    } else if (utilsl.startsWith(cmd, "uci", .ignoreCase)) {
        return .UCI;
    } else if (utilsl.startsWith(cmd, "stop", .ignoreCase)) {
        return .STOP;
    } else if (utilsl.startsWith(cmd, "quit", .ignoreCase)) {
        return .QUIT;
    } else if (utilsl.startsWith(cmd, "ponderhit", .ignoreCase)) {
        return .PONDERHIT;
    } else if (utilsl.startsWith(cmd, "printparams", .ignoreCase)) {
        return .PRINTPARAMS;
    } else if (utilsl.startsWith(cmd, "print", .ignoreCase)) {
        return .PRINT;
    } else if (utilsl.startsWith(cmd, "benchmark", .ignoreCase)) {
        return .BENCHMARK;
    }
    return .NOOP;
}
pub fn launch_engine() !void {
    try ucil.launchUci(mainl.getGlobalGPA());
}

pub fn main(init: std.process.Init) anyerror!void {
    mainl.GLOBAL_CTX.setInit(init);
    try launch_engine();
}
