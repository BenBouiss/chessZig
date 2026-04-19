const std = @import("std");

const enginel = @import("../engine.zig");
const movel = @import("../move.zig");
const chessl = @import("../chess.zig");
const moveGenl = @import("../move_generation.zig");
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
const threadPackageArray = threadingl.threadPackageArray;

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
    return ret;
}

pub const uciSearcher = struct {
    config: enginel.goArgStruct = .{},
    schedul: scheduler = .{},
    bestMove: moveDecisionExt = .{},
    nThreads: u32 = 1,
    endCounter: u16 = 0,
    searching: bool = false,
    interrupt: bool = false,

    pub fn reset(p_self: *uciSearcher) void {
        p_self.endCounter = 0;
        p_self.interrupt = false;
        p_self.searching = false;
        p_self.bestMove = .{};
    }
    pub fn printInfo(self: uciSearcher) void {
        std.debug.print("searcher thread: {d}\n", .{self.nThreads});
    }
};
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
pub const timeDecision = struct {
    time: i64 = 0,
    depth: u16 = 0,
    checked: bool = false,
};

// Exploration phase for an engine with d as the default depth
//
// Launch expl d - 1
//  Check time
//
// Launch expl d
//  Check time
//
//     ...
//
// Launch expl max d
//  Check time
//
// on Check time: check if _currentTime - _start is below the max time fraction allowed in config if not we return the current best sol found (ie the one for the previous exploration)
//
// if during a search the waiting thread of the scheduler notices the time being in the red, the scheduler should be allowed to interrupt the search
pub const scheduler = struct {
    p_engine: *enginel.engine = undefined,

    timeM: timeManager = .{},
    features: searchFeatures = .{},
    p_threadPack: *threadPackageArray = undefined,
    alloc: std.mem.Allocator = undefined,
    searchDepth: u16 = 0,
    engineSet: bool = false,
    turn: bool = true,
    reportProgress: bool = true,

    pub fn setEngine(p_self: *scheduler, p_engine: *enginel.engine) void {
        p_self.p_engine = p_engine;
        p_self.engineSet = true;
        p_self.alloc = p_engine.alloc;
        p_self.turn = p_engine.state.whiteToMove();
        p_self.features = getSearchFeatures(p_engine);
    }
    pub inline fn setThreadPack(p_self: *scheduler, p_pack: *threadPackageArray) void {
        p_self.p_threadPack = p_pack;
    }
    pub fn _startThreadPack(p_self: *scheduler, alloc: std.mem.Allocator, maxDepth: u16) !void {
        _ = alloc;
        threadingl.zeroThreadPackArray(p_self.p_threadPack);
        for (0..p_self.p_threadPack.len) |thread_id| {
            if (p_self.isDebugMode()) {
                std.debug.print("[DEBUG] startThreadPack: starting thread {d}\n", .{thread_id});
            }
            p_self.p_threadPack.items(._tInfo)[thread_id].alive = true;
            p_self.p_threadPack.items(._tInfo)[thread_id].working = true;

            p_self.p_threadPack.items(.threadHandle)[thread_id] = try std.Thread.spawn(.{}, _startSearch, .{ p_self, &p_self.p_threadPack.items(.chessState)[thread_id], &p_self.p_threadPack.items(._tInfo)[thread_id], p_self.features, maxDepth });
        }
    }

    pub fn sendFinal(p_self: *scheduler, decision: *moveDecisionExt) void {
        if (!p_self.engineSet) {
            @panic("engine not set");
        }

        const msg = std.fmt.allocPrint(p_self.alloc, "bestmove {s}", .{decision.move.getStr()}) catch unreachable;
        p_self.p_engine.respond(utilsl.trimStr(msg));
        defer p_self.alloc.free(msg);
    }
    pub fn sendPartial(p_self: *scheduler, decision: *moveDecisionExt) void {
        if (!p_self.engineSet) {
            @panic("engine not set");
        }

        const res = threadingl.getCombinedFromPack(p_self.p_threadPack);
        const n_nodes: i64 = @intCast(res.searchStat.n_nodeExplored);

        const final_info = std.fmt.allocPrint(p_self.alloc, "info depth {d} score cp {d} nodes {d} cutoff: {d} currmove {s} pv {f}", .{ p_self.searchDepth, decision.scoring, n_nodes, res.searchStat.n_cutoffs, utilsl.trimStr(&decision.move.getStr()), decision.line }) catch unreachable;
        defer p_self.alloc.free(final_info);
        p_self.p_engine.respond(utilsl.trimStr(final_info));
    }

    pub fn sendUpdate(p_self: *scheduler) void {
        const res = threadingl.getCombinedFromPack(p_self.p_threadPack);
        const n_nodes: i64 = @intCast(res.searchStat.n_nodeExplored);
        const timeDelta = p_self.timeM.timeSinceStartMs();

        const msg = std.fmt.allocPrint(p_self.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d} cutoff: {d}", .{ @divFloor(n_nodes, (timeDelta + 1)) * 1000, n_nodes, res.searchStat.n_hashRetrieve, hashl.hashTable.n_insertion, res.searchStat.n_cutoffs }) catch {
            return;
        };
        defer p_self.alloc.free(msg);
        p_self.p_engine.respond(msg);
        return;
    }

    pub fn getSearchStatus(p_self: *scheduler) searchStatus {
        var searcher = p_self.p_engine.searcher;
        if (searcher.interrupt) {
            return .INTERRUPTED;
        }
        searcher.endCounter = 0;
        for (0..p_self.p_threadPack.len) |i| {
            const info: threadingl.threadInfo = p_self.p_threadPack.items(._tInfo)[i];
            searcher.endCounter += @intFromBool(!info.working);
        }
        if (searcher.endCounter == p_self.p_threadPack.len) {
            return .FINISHED;
        }
        return .CONTINUE;
    }
    pub fn handleInterrupt(p_self: *scheduler) void {
        if (p_self.isDebugMode()) {
            std.debug.print("[DEBUG] handleInterrupt: interrupting\n", .{});
        }
        for (0..p_self.p_threadPack.len) |i| {
            p_self.p_threadPack.items(._tInfo)[i].alive = false;
        }
        threadingl.joinOnThreadPack(p_self.p_threadPack);
        if (p_self.isDebugMode()) {
            std.debug.print("[DEBUG] handleInterrupt: finished\n", .{});
        }
    }
    pub inline fn entryPointSearch(p_self: *scheduler, depth: u16) searchReport {
        var ret: searchReport = undefined;

        ret = p_self.incrementalLoop(depth);

        if (p_self.p_engine.trackMetrics()) {
            p_self.p_engine.metric.addTimeToSearchingMs(ret.timeTakenMs);
        }
        return ret;
    }
    pub fn extractBest(p_self: *scheduler) moveDecisionExt {
        const res = threadingl.getCombinedFromPack(p_self.p_threadPack);
        return res.currentBest.copy();
    }

    pub fn incrementalLoop(p_self: *scheduler, maxDepth: u16) searchReport {
        p_self.timeM.startSearchTick();
        defer p_self.timeM.stopWatch.stop();
        defer p_self.engineSet = false;

        p_self._startThreadPack(p_self.alloc, maxDepth) catch {
            return .{};
        };

        const tickrate = configl.WR_TICKRATE_NS;

        var decision: moveDecisionExt = .{};
        var countTimePrint = @divFloor(configl.INFO_TICKRATE_NS, tickrate);
        countTimePrint = @max(1, countTimePrint);
        var count: usize = 0;

        var stat = p_self.getSearchStatus();
        while (stat == .CONTINUE) {
            count += 1;
            if (count % countTimePrint == 0) {
                if (p_self.reportProgress) {
                    p_self.sendUpdate();
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

        p_self.sendFinal(&decision);
        p_self.handleInterrupt();
        // TODO: FIX ME: UCI style thingy here
        p_self.engineSet = false;
        const res = threadingl.getCombinedFromPack(p_self.p_threadPack);
        return .{ .move = decision.move, .timeTakenMs = p_self.timeM.timeSinceStartMs(), .searchStat = res.searchStat, .score = decision.scoring };
    }

    pub inline fn isDebugMode(p_self: *const scheduler) bool {
        return p_self.p_engine.status.debugMode;
    }
};

pub fn dispatchUciGoCmd(p_engine: *enginel.engine, cmdBuffer: []const u8) bool {
    if (p_engine.searcher.config.type == .PERFT) {
        return perftl.dispatchUciPerftCmd(p_engine);
    }
    var moveArray: moveContainer = undefined;

    if (p_engine.searcher.config.searchMoves) {
        var _moveArray = chessl.getMoveListFromStr(&p_engine.state, cmdBuffer, p_engine.alloc) catch {
            return false;
        };
        defer _moveArray.deinit(p_engine.alloc);

        moveArray = movel.arrayListMoveToMoveContainer(&_moveArray);
    } else {
        moveArray = moveGenl.generateLegalMoves(&p_engine.state);
    }

    const dispatchThread = std.Thread.spawn(.{}, dispatchUciGoThreads, .{ p_engine, moveArray }) catch {
        return false;
    };
    p_engine.workingThreads.append(p_engine.alloc, dispatchThread) catch {
        return false;
    };

    return true;
}
pub fn dispatchUciGoThreads(p_engine: *enginel.engine, moveArray: movel.moveContainer) void {
    var stopWatch: timel.stopWatch = .{};
    stopWatch.startTimeTick();
    defer stopWatch.stop();
    var searcher = &p_engine.searcher;

    const _nThread = @min(searcher.nThreads, moveArray.len);
    if (_nThread == 0) {
        std.debug.print("[PANIC] dispatchUciGoThreads: thread {d} move {d}\n", .{ searcher.nThreads, moveArray.len });
        @panic("No thread or no moves available");
    }
    if (p_engine.status.debugMode) {
        std.debug.print("[DEBUG] dispatchUciGoThreads: nthread info: searcher: {d}, movearray: {d}\n", .{ searcher.nThreads, moveArray.len });
    }

    var pack = threadingl.getThreadPackArray(p_engine.alloc, &p_engine.state, &moveArray, _nThread) catch {
        std.debug.print("[ERROR] dispatchUciGoThreads: Cant init thread pack array\n", .{});
        return;
    };
    defer threadingl.freeThreadPackArray(p_engine.alloc, &pack);

    p_engine.searcher.searching = true;
    defer p_engine.searcher.searching = false;

    var sched = &searcher.schedul;
    sched.setThreadPack(&pack);
    sched.reportProgress = true;

    // FIXME: !!!!!
    sched.setEngine(p_engine);
    if (sched.turn) {
        sched.timeM.setRemainingTimeMs(searcher.config.wtime);
    } else {
        sched.timeM.setRemainingTimeMs(searcher.config.btime);
    }

    if (p_engine.trackMetrics()) {
        p_engine.metric.addTimeToProcessingMs(stopWatch.timeSinceStartMs());
    }
    // pre start the searching thread here
    _ = sched.entryPointSearch(searcher.config.depth);
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
        std.debug.print("[DEBUG] _startSearch: starting from depth {d}\n", .{depth});
    }

    _ = alphaBetal.searchEntrypoint(p_state, undefined, p_info, depth, &features, &line);
    var decision = &p_info.currentBest;
    if (sched.reportProgress) {
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
        if (sched.reportProgress) {
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
    if (!p_self.engineSet) {
        @panic("engine not set");
    }

    const n_nodes: i64 = @intCast(p_info.searchStat.n_nodeExplored);
    const n_cut = p_info.searchStat.n_cutoffs;

    const final_info = std.fmt.allocPrint(p_self.alloc, "info depth {d} score cp {d} nodes {d} cutoff: {d} currmove {s} pv {f}", .{ depth, decision.scoring, n_nodes, n_cut, utilsl.trimStr(&decision.move.getStr()), decision.line }) catch unreachable;
    defer p_self.alloc.free(final_info);
    p_self.p_engine.respond(utilsl.trimStr(final_info));
}

pub fn main() void {
    @panic("");
}
