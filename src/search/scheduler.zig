const std = @import("std");

const enginel = @import("../engine.zig");
const movel = @import("../move.zig");
const alphaBetal = @import("alphaBeta.zig");
const threadingl = @import("threading.zig");
const heuristicl = @import("../heuristic.zig");
const hashl = @import("../hashTable.zig");
const utilsl = @import("../utils.zig");
const configl = @import("../config.zig");
const weightl = @import("../weights.zig");
const timel = @import("../time.zig");
const mainl = @import("../main.zig");
const boardl = @import("../board.zig");

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
    useRazoring: bool = configl.DEFAULT_USE_RAZORING,
    useRFP: bool = configl.DEFAULT_USE_RFP,
    reportProgress: bool = configl.DEFAULT_REPORTPROGRESS,
    useFutility: bool = configl.DEFAULT_USE_FUTILITY,
};
pub fn getSearchFeatures(p_engine: *enginel.engine) searchFeatures {
    var ret: searchFeatures = .{};
    ret.useHash = p_engine.options.useHashTable;
    ret.useQuiescence = p_engine.options.useQuiescence;
    ret.useNullPrune = p_engine.options.useNullPrune;
    ret.useLMR = p_engine.options.useLMR;
    ret.useStaticSearch = p_engine.options.useStaticSearch;
    ret.fixedDepth = p_engine.options.fixedDepth;
    ret.useRazoring = p_engine.options.useRazoring;
    ret.useRFP = p_engine.options.useRFP;
    ret.reportProgress = p_engine.options.reportProgress;
    ret.useFutility = p_engine.options.useFutility;
    return ret;
}

pub const uciSearcher = struct {
    schedul: scheduler = .{},
    searching: bool = false,
    interrupt: bool = false,
    swSinceSearch: timel.stopWatch = .{},

    pub fn reset(p_self: *uciSearcher) void {
        p_self.interrupt = false;
        p_self.searching = false;
    }
    pub fn close(self: *uciSearcher) !void {
        self.interrupt = true;
        self.searching = false;
        self.schedul._threadPool.close();
    }
};

pub fn waitingRoomOneShot(self: *enginel.engine) !void {
    const stat = self.searcher.schedul.getSearchStatus();
    if (stat == .INTERRUPTED or stat == .FINISHED) {
        const decision = self.searcher.schedul.extractBest();
        _sendFinal(self, &decision);
        self.searcher.schedul.handleInterrupt();
        self.searcher.searching = false;
        self.searcher.swSinceSearch.reset();
        self.searcher.schedul.timeM.reset();
    } else {
        // .CONTINUE
        // test for critical time use here
        if (self.searcher.schedul.timeM.isOvertimeCritical()) {
            std.debug.print("[CRITICAL] interruped due to critical time constraints\n", .{});
            self.searcher.schedul.handleInterrupt();
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
        // only used in the benchmark files
        if (!p_self._threadPool.running) {
            return .{};
        }

        const pack: threadingl.searchPackage = .{ .depth = depth, .features = p_self.features, .scheduler = p_self, .chessState = p_self.p_engine.state };

        const ret = p_self.incrementalLoop(&pack);

        if (p_self.p_engine.trackMetrics()) {
            p_self.p_engine.metric.addTimeToSearchingMs(ret.timeTakenMs);
        }
        return ret;
    }
    pub fn extractBest(p_self: *scheduler) moveDecisionExt {
        const res = p_self._threadPool.getCombinedInfo();
        return res.currentBest.copy();
    }

    pub fn incrementalLoop(p_self: *scheduler, pack: *const threadingl.searchPackage) searchReport {
        std.debug.assert(p_self._threadPool.running);

        p_self.timeM.startSearchTick();
        defer p_self.timeM.stopWatch.stop();

        p_self._threadPool.submit(pack) catch {
            p_self.p_engine.respond("engineOp threadPoolSubmit failed crashing");
            _ = p_self.p_engine.executeQuitProcedure();
            @panic(":)");
        };

        const tickrate = configl.WAIT_TICKRATE_NS;
        var decision: moveDecisionExt = .{};
        var countTimePrint = @divFloor(configl.INFO_TICKRATE_NS, tickrate);
        countTimePrint = @max(1, countTimePrint);
        var count: usize = 0;

        var stat = p_self.getSearchStatus();

        while (stat == .CONTINUE) {
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
        const res = p_self._threadPool.getCombinedInfo();
        return .{ .move = decision.move, .timeTakenMs = p_self.timeM.timeSinceStartMs(), .searchStat = res.searchStat, .score = decision.scoring };
    }

    pub inline fn isDebugMode(p_self: *const scheduler) bool {
        return p_self.p_engine.status.debugMode;
    }
};

pub fn dispatchUciGoCmd(p_engine: *enginel.engine, cmdBuffer: []const u8, config: enginel.goArgStruct) bool {
    _ = cmdBuffer;
    const pack: threadingl.searchPackage = .{ .chessState = p_engine.state, .depth = config.depth, .features = getSearchFeatures(p_engine), .scheduler = &(p_engine.searcher.schedul) };
    p_engine.searcher.schedul.timeM.startSearchTick();

    p_engine.searcher.searching = true;
    p_engine.searcher.swSinceSearch.startTimeTick();
    p_engine.searcher.schedul.setEngine(p_engine);
    if (p_engine.state.whiteToMove()) {
        p_engine.searcher.schedul.timeM.setRemainingTimeMs(config.wtime);
    } else {
        p_engine.searcher.schedul.timeM.setRemainingTimeMs(config.btime);
    }
    p_engine.searcher.schedul._threadPool.submit(&pack) catch {
        p_engine.respond("engineOp threadPoolSubmit failed crashing");
        _ = p_engine.executeQuitProcedure();
        @panic(":)");
    };

    return true;
}

pub fn _startSearch(sched: *const scheduler, p_state: *boardl.boardState, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: u16) void {
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
    var ss: alphaBetal.searchStack = .{};
    if (sched.isDebugMode()) {
        std.debug.print("[DEBUG] _startSearch: starting from depth {d} max depth {d} remaining time {d} ms\n", .{ depth, maxDepth, sched.timeM.remainingTimeMs });
    }

    _ = alphaBetal.searchEntrypoint(p_state, undefined, p_info, depth, &features, &line, &ss);
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
        _ = (alphaBetal.searchEntrypoint(p_state, undefined, p_info, depth, &features, &line, &ss));
        line.copyFromLine(&p_info.currentBest.line);
        decision = &p_info.currentBest;
        if (features.reportProgress) {
            sendPartial(sched, depth, decision, p_info);
        }
    }
    if (sched.isDebugMode()) {
        std.debug.print("debug exit status alive: {} overtime thinking: {}\n", .{ p_info.alive, canExtendSearch(&sched.timeM, depth, maxDepth, decision, &features) });
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
pub fn _sendFinal(p_self: *enginel.engine, decision: *const moveDecisionExt) void {
    var buffer = std.mem.zeroes([32]u8);
    const msg = std.fmt.bufPrint(&buffer, "bestmove {s}\n", .{decision.move.getStr()}) catch unreachable;
    p_self.respondNonFmt(msg);
}

pub fn sendUpdate(p_self: *scheduler) void {
    const res = p_self._threadPool.getInfos()[0];
    const n_nodes: i64 = @intCast(res.searchStat.n_nodeExplored);
    const timeDelta = p_self.timeM.timeSinceStartMs();

    const msg = std.fmt.allocPrint(p_self.p_engine.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d} cutoff: {d}", .{ @divFloor(n_nodes, (timeDelta + 1)) * 1000, n_nodes, res.searchStat.n_hashRetrieve, hashl.hashTable.stat.insertion, res.searchStat.n_cutoffs }) catch {
        return;
    };
    defer p_self.p_engine.alloc.free(msg);
    p_self.p_engine.respond(msg);
    return;
}
