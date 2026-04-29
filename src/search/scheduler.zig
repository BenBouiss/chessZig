const std = @import("std");

const enginel = @import("../engine.zig");
const movel = @import("../move.zig");
const chessl = @import("../chess.zig");
const perftl = @import("perft.zig");
const alphaBetal = @import("alphaBeta.zig");
const threadingl = @import("threading.zig");
const heuristicl = @import("../heuristic.zig");
const hashl = @import("../hashTable.zig");
const utilsl = @import("../utils.zig");
const configl = @import("../config.zig");
const weightl = @import("../weights.zig");
const timel = @import("../time.zig");
const mainl = @import("../main.zig");

const moveContainer = movel.moveContainer;
const IMove = movel.IMove;
const scoreType = heuristicl.scoreType;

pub const searchStatus = enum { CONTINUE, INTERRUPTED, FINISHED };
pub const searchReport = struct {
    timeTakenMs: i64 = 0,
    searchStat: threadingl.searchStatistic = .{},
    move: IMove = .{},
    score: scoreType = 0,
};

pub const searchFeatures = struct {
    useHash: bool = configl.DEFAULT_USEHASHTABLE,
    useQuiescence: bool = configl.DEFAULT_USEQUIESC,
    useNullPrune: bool = configl.DEFAULT_USE_NULLPRUNE,
    useStaticSearch: bool = configl.DEFAULT_STATIC_SEARCH,
    fixedDepth: bool = configl.DEFAULT_FIXED_DEPTH,
    useLMR: bool = configl.DEFAULT_LATE_MOVE_REDUCTION,
    useSEE: bool = configl.DEFAULT_USE_SEE,
    useFutility: bool = configl.DEFAULT_USE_FUTILITY,
    useRazoring: bool = configl.DEFAULT_USE_RAZORING,
    searchType: configl.searchType = configl.DEFAULT_SEARCH_TYPE,
    reportProgress: bool = configl.DEFAULT_REPORTPROGRESS,
};
pub fn getSearchFeatures(p_engine: *enginel.engine) searchFeatures {
    var ret: searchFeatures = .{};
    ret.useHash = p_engine.options.useHashTable;
    ret.useQuiescence = p_engine.options.useQuiescence;
    ret.useNullPrune = p_engine.options.useNullPrune;
    ret.useLMR = p_engine.options.useLMR;

    ret.useStaticSearch = p_engine.options.useStaticSearch;
    ret.fixedDepth = p_engine.options.fixedDepth;
    ret.useSEE = p_engine.options.useSEE;
    ret.useFutility = p_engine.options.useFutility;
    ret.searchType = p_engine.options.searchType;
    ret.useRazoring = p_engine.options.useRazoring;
    ret.reportProgress = p_engine.options.reportProgress;
    return ret;
}

pub const searchingThreadContainer = struct {
    len: usize = 0,
    items: [configl.MAX_THREAD]std.Thread = undefined,
    pub fn appendThread(p_self: *searchingThreadContainer, thread: std.Thread) void {
        std.debug.assert(p_self.len < configl.MAX_THREAD);
        p_self.items[p_self.len] = thread;
        p_self.len += 1;
    }
    pub fn reset(p_self: *searchingThreadContainer) void {
        p_self.len = 0;
    }
    pub fn joinOn(self: *searchingThreadContainer) void {
        //std.debug.print("[DEBUG] searchingThreadContainer.joinOn: joining on the {d} thread(s) stored\n", .{self.len});
        for (0..self.len) |i| {
            self.items[i].join();
        }
        self.reset();
    }
};

pub const searcherPackage = struct {
    config: enginel.goArgStruct = undefined,
    state: chessl.Board_state = undefined,
};

pub const uciSearcher = struct {
    pack: searcherPackage = .{},
    schedul: scheduler = .{},
    searching: bool = false,
    interrupt: bool = false,
    threadProp: threadingl.threadP = undefined,
    searchingThread: searchingThreadContainer = .{},

    pub fn reset(p_self: *uciSearcher) void {
        p_self.interrupt = false;
        p_self.searching = false;
    }
    pub fn dispatch(self: *uciSearcher) !void {
        self.threadProp.alive = true;
        self.threadProp.status = .WAITING;
        self.threadProp._handle = try std.Thread.spawn(.{}, waitingRoom, .{self});
    }

    pub fn close(self: *uciSearcher) !void {
        //
        self.threadProp.alive = false;
        self.interrupt = true;
        self.threadProp._handle.join();
        self.schedul._threadPool.close();
        self.searchingThread.joinOn();
    }
    pub fn submit(self: *uciSearcher, p_engine: *enginel.engine, pack: searcherPackage) threadingl.threadPoolerr!void {
        //
        self.schedul.setEngine(p_engine);
        self.pack = pack;
        if (self.pack.state.whiteToMove()) {
            self.schedul.timeM.setRemainingTimeMs(self.pack.config.wtime);
        } else {
            self.schedul.timeM.setRemainingTimeMs(self.pack.config.btime);
        }
        self.threadProp.searchPing = true;
    }
};
pub fn waitingRoom(self: *uciSearcher) !void {
    //
    self.threadProp.alive = true;
    self.threadProp.status = .WAITING;
    var sw: timel.stopWatch = .{};
    sw.startTimeTick();
    const timeout = 2;
    while (self.threadProp.alive) {
        std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.WR_TICKRATE_NS) }, .real) catch {
            self.schedul.p_engine.respond("engineOp uciSearcher.waitingroom .FATAL");
            self.close() catch unreachable;
        };
        if (self.threadProp.searchPing) {
            sw.reset();
            sw.startTimeTick();
            self.threadProp.status = .WORKING;
            self.threadProp.searchPing = false;
            dispatchUciGoThreads(self);
        }

        if (sw.timeSinceStartSec() > timeout) {
            sw.reset();
            sw.startTimeTick();
            std.debug.print("[INACTIVITY] searcher.WaitingRoom: no activity in the last {d} seconds\n", .{timeout});
            self.schedul.p_engine.respond("engineOp uciSearcher.waitingroom .WAITING");
        }
    }
}
pub const moveDecisionExt = struct {
    move: IMove = .{},
    scoring: scoreType = 0,
    line: movel.line = .{},
    pub fn invertScore(p_self: *moveDecisionExt) void {
        p_self.scoring = -p_self.scoring;
    }
    pub fn isBetter(p_self: *moveDecisionExt, other: *moveDecisionExt) bool {
        return p_self.scoring > other.scoring;
    }
    pub fn copy(self: moveDecisionExt) moveDecisionExt {
        return .{ .move = self.move, .line = self.line, .scoring = self.scoring };
    }
};

pub const timeManager = struct {
    stopWatch: timel.stopWatch = .{},
    remainingTimeMs: i64 = 0,

    pub inline fn startSearchTick(p_self: *timeManager) void {
        p_self.stopWatch.startTimeTick();
    }
    pub inline fn timeSinceStartMs(p_self: *const timeManager) i64 {
        return p_self.stopWatch.timeSinceStartMs();
    }
    pub inline fn timeSinceStartSec(p_self: *const timeManager) i64 {
        return p_self.stopWatch.timeSinceStartSec();
    }
    pub fn reset(p_self: *timeManager) void {
        p_self.remainingTimeMs = 0;
        p_self.stopWatch.reset();
    }
    pub fn setRemainingTimeMs(p_self: *timeManager, timeMs: i64) void {
        p_self.remainingTimeMs = timeMs;
    }

    pub fn isOvertimeSearching(p_self: *const timeManager) bool {
        const _remainTime: f64 = @floatFromInt(p_self.remainingTimeMs);
        const maxTime: i64 = @intFromFloat(_remainTime * configl.SCHEDULER_MAX_TIME_FRCT);
        return (p_self.timeSinceStartMs() > maxTime);
    }
    pub fn isOvertimeCritical(p_self: *const timeManager) bool {
        const _remainTime: f64 = @floatFromInt(p_self.remainingTimeMs);
        const maxTime: i64 = @intFromFloat(_remainTime * configl.SCHEDULER_CRITICAL_TIME_FRCT);
        return (p_self.timeSinceStartMs() > maxTime);
    }
};

pub const scheduler = struct {
    // used for .respond() and alloc
    p_engine: *enginel.engine = undefined,
    timeM: timeManager = .{},
    features: searchFeatures = .{},
    reportProgress: bool = true,
    _threadPool: threadingl.threadPool = .{},

    pub fn setEngine(p_self: *scheduler, p_engine: *enginel.engine) void {
        p_self.p_engine = p_engine;
        p_self.features = getSearchFeatures(p_engine);
    }

    pub fn getSearchStatus(p_self: *scheduler) searchStatus {
        const searcher = p_self.p_engine.searcher;
        if (searcher.interrupt) {
            return .INTERRUPTED;
        }
        return p_self._threadPool.getSearchStatus();
    }
    pub fn handleInterrupt(p_self: *scheduler) void {
        p_self._threadPool.stop();
        p_self._threadPool.waitOnFinish();
    }
    pub fn entryPointSearch(p_self: *scheduler, depth: u16) searchReport {
        const ret = p_self.incrementalLoop(depth);

        if (p_self.p_engine.trackMetrics()) {
            p_self.p_engine.metric.addTimeToSearchingMs(ret.timeTakenMs);
        }
        return ret;
    }
    pub fn extractBest(p_self: *scheduler) moveDecisionExt {
        const res = p_self._threadPool.getCombinedInfo();
        return res.currentBest.copy();
    }

    pub fn incrementalLoop(p_self: *scheduler, maxDepth: u16) searchReport {
        p_self.timeM.startSearchTick();
        defer p_self.timeM.stopWatch.stop();

        if (!p_self._threadPool.running) {
            p_self._threadPool.addThread(1) catch unreachable;

            p_self.p_engine.respond("engineOp incrementalLoop .ADDTHREAD");
        }
        const pack: threadingl.searchPackage = .{ .depth = maxDepth, .features = p_self.features, .scheduler = p_self, .chessState = p_self.p_engine.state };

        std.debug.assert(p_self._threadPool.nThread == 1);
        std.debug.assert(p_self._threadPool.running);
        p_self._threadPool.submit(&pack) catch unreachable;

        const tickrate = configl.WR_TICKRATE_NS;
        var decision: moveDecisionExt = .{};
        var countTimePrint = @divFloor(configl.INFO_TICKRATE_NS, tickrate);
        countTimePrint = @max(1, countTimePrint);
        var count: usize = 0;

        var stat = p_self.getSearchStatus();

        var sw: timel.stopWatch = .{};
        sw.startTimeTick();
        const timeout = 2;
        while (stat == .CONTINUE) {
            if (sw.timeSinceStartSec() > timeout) {
                sw.reset();
                sw.startTimeTick();
                std.debug.print("[INACTIVITY] scheduler.incrementalLoop: no activity in the last {d} seconds\n", .{timeout});
                p_self.p_engine.respond("engineOp uciSearcher.waitingroom .WAITING");
            }
            count += 1;
            if (count % countTimePrint == 0) {
                if (p_self.features.reportProgress) {
                    sendUpdate(p_self);
                }
                count = 0;
            }
            std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(tickrate) }, .real) catch {
                break;
            };
            stat = p_self.getSearchStatus();
            if (stat == .INTERRUPTED or stat == .FINISHED) {
                decision = p_self.extractBest();
                break;
            }
        }
        if (p_self.isDebugMode()) {
            std.debug.print("[DEBUG] incrementalLoop: last status: {}\n", .{stat});
        }

        sendFinal(p_self, &decision);
        p_self.handleInterrupt();
        // TODO: FIX ME: UCI style thingy here
        const res = p_self._threadPool.getCombinedInfo();
        return .{ .move = decision.move, .timeTakenMs = p_self.timeM.timeSinceStartMs(), .searchStat = res.searchStat, .score = decision.scoring };
    }

    pub inline fn isDebugMode(p_self: *const scheduler) bool {
        return p_self.p_engine.status.debugMode;
    }
};

pub fn dispatchUciGoCmd(p_engine: *enginel.engine, cmdBuffer: []const u8, config: enginel.goArgStruct) bool {
    if (config.type == .PERFT) {
        return perftl.dispatchUciPerftCmd(p_engine, config);
    }
    _ = cmdBuffer;
    if (!p_engine.searcher.threadProp.alive) {
        p_engine.searcher.dispatch() catch {
            return false;
        };
    }
    p_engine.searcher.submit(p_engine, .{ .config = config, .state = p_engine.state.copy() }) catch {
        return false;
    };
    return true;
}
pub fn dispatchUciGoThreads(p_searcher: *uciSearcher) void {
    p_searcher.searching = true;
    defer p_searcher.searching = false;

    _ = p_searcher.schedul.entryPointSearch(p_searcher.pack.config.depth);
}
pub fn _startSearch(sched: *const scheduler, p_state: *chessl.Board_state, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: u16) void {
    // everything gets "returned" via the p_info
    // launched as single threaded
    // redundant as the thread beeing launch already sets this beforehand, however the previous init serves just to prevent very early return (ie: status == .FINISHED) when nothing happened
    p_info.working = true;
    defer p_info.working = false;
    var depth: u16 = 1;
    if (features.useStaticSearch) {
        depth = maxDepth;
    }
    var line: movel.line = .{};
    if (sched.isDebugMode()) {
        std.debug.print("[DEBUG] _startSearch: starting from depth {d} max depth {d}\n", .{ depth, maxDepth });
    }

    _ = alphaBetal.searchEntrypoint(p_state, undefined, p_info, depth, &features, &line);
    var decision = &p_info.currentBest;
    if (features.reportProgress) {
        sendPartial(sched, depth, decision, p_info);
    }

    while (p_info.alive and canExtendSearch(&sched.timeM, depth, maxDepth, decision, &features)) {
        depth += 1;
        if (sched.isDebugMode()) {
            std.debug.print("[DEBUG] _startSearch: starting line ", .{});
            line.print();
        }
        _ = (alphaBetal.searchEntrypoint(p_state, undefined, p_info, depth, &features, &line));
        line.copyFromLine(&p_info.currentBest.line);
        decision = &p_info.currentBest;
        if (features.reportProgress) {
            sendPartial(sched, depth, decision, p_info);
        }
    }
    if (sched.p_engine.options.trackMetrics) {
        sched.p_engine.metric.addPlies(depth);
    }
}

pub fn canExtendSearch(timer: *const timeManager, depth: u16, maxDepth: u16, decision: *const moveDecisionExt, p_features: *const searchFeatures) bool {
    if (p_features.fixedDepth and depth == maxDepth or (depth >= configl.SCHEDULER_MAX_ENDGAME_DEPTH)) {
        return false;
    }
    if (@abs(decision.scoring) >= weightl.simpleCheckMateScore) {
        return false;
    }
    if (timer.isOvertimeSearching()) {
        return false;
    }
    const prevTime: i64 = timer.timeSinceStartMs();
    const floatTime: f64 = @floatFromInt(timer.remainingTimeMs);
    const maxTime: i64 = @intFromFloat(floatTime * configl.SCHEDULER_MAX_TIME_FRCT);
    return ((prevTime * configl.SCHEDULER_GROWTH_TIME_EST) < maxTime);
}

pub fn sendPartial(p_self: *const scheduler, depth: u16, decision: *const moveDecisionExt, p_info: *const threadingl.threadInfo) void {
    const n_nodes: i64 = @intCast(p_info.searchStat.n_nodeExplored);
    const n_cut = p_info.searchStat.n_cutoffs;

    const final_info = std.fmt.allocPrint(p_self.p_engine.alloc, "info depth {d} score cp {d} nodes {d} cutoff: {d} currmove {s} pv {f}", .{ depth, decision.scoring, n_nodes, n_cut, utilsl.trimStr(&decision.move.getStr()), decision.line }) catch unreachable;
    defer p_self.p_engine.alloc.free(final_info);
    p_self.p_engine.respond(utilsl.trimStr(final_info));
}
pub fn sendFinal(p_self: *scheduler, decision: *moveDecisionExt) void {
    var buffer = std.mem.zeroes([32]u8);

    const msg = std.fmt.bufPrint(&buffer, "bestmove {s}\n", .{decision.move.getStr()}) catch unreachable;
    if (p_self.p_engine.status.debugMode) {
        std.debug.print("[DEBUG] sendFinal: best move: '{s}' \n", .{decision.move.getStr()});
    }
    p_self.p_engine.respondNonFmt(msg);
}

pub fn sendUpdate(p_self: *scheduler) void {
    const res = p_self._threadPool.getInfos()[0];
    const n_nodes: i64 = @intCast(res.searchStat.n_nodeExplored);
    const timeDelta = p_self.timeM.timeSinceStartMs();

    const msg = std.fmt.allocPrint(p_self.p_engine.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d} cutoff: {d}", .{ @divFloor(n_nodes, (timeDelta + 1)) * 1000, n_nodes, res.searchStat.n_hashRetrieve, hashl.hashTable.n_insertion, res.searchStat.n_cutoffs }) catch {
        return;
    };
    defer p_self.p_engine.alloc.free(msg);
    p_self.p_engine.respond(msg);
    return;
}

pub fn main() void {
    @panic("");
}
