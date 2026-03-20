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

const moveContainer = movel.moveContainer;
const IMove = movel.IMove;
const scoreType = heuristicl.scoreType;
const threadPackageArray = threadingl.threadPackageArray;
const depthCommunication = alphaBetal.depthCommunication;

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
    useLateMoveReduc: bool = configl.DEFAULT_LATE_MOVE_REDUCTION,
    useSEE: bool = configl.DEFAULT_USE_SEE,
};
pub fn getSearchFeatures(p_engine: *enginel.engine) searchFeatures {
    var ret: searchFeatures = .{};
    ret.useHash = p_engine.options.useHashTable;
    ret.useQuiescence = p_engine.options.useQuiescence;
    ret.useNullPrune = p_engine.options.useNullPrune;
    ret.useLateMoveReduc = p_engine.options.useLateMoveReduction;

    ret.useStaticSearch = p_engine.options.useStaticSearch;
    ret.fixedDepth = p_engine.options.fixedDepth;
    ret.useSEE = p_engine.options.useSEE;
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

const TIME_BUFFER_SIZE: usize = 20;
pub const timeManager = struct {
    timeBuffer: [TIME_BUFFER_SIZE]timeDecision = undefined,
    len: usize = 0,
    currentIndex: usize = 0,
    searchStartTime: i64 = 0,

    pub fn startSearchTick(p_self: *timeManager) void {
        p_self.searchStartTime = std.time.milliTimestamp();
    }
    pub fn timeSinceStartMs(p_self: *timeManager) i64 {
        return std.time.milliTimestamp() - p_self.searchStartTime;
    }
    pub fn timeSinceStartSec(p_self: *timeManager) i64 {
        return p_self.timeSinceStartMs() / std.time.ms_per_s;
    }
    pub fn reset(p_self: *timeManager) void {
        p_self.len = 0;
        p_self.currentIndex = 0;
        p_self.searchStartTime = 0;
    }
    pub fn append(p_self: *timeManager, item: timeDecision) void {
        p_self.timeBuffer[p_self.currentIndex] = item;
        p_self.len = @min(p_self.len + 1, TIME_BUFFER_SIZE);
        p_self.currentIndex = (p_self.len + 1) % TIME_BUFFER_SIZE;
    }
    pub fn avg(p_self: *timeManager) f64 {
        if (p_self.len == 0) {
            return 0.0;
        }
        var acc: f64 = 0.0;
        for (0..p_self.len) |i| {
            acc += @floatFromInt(p_self.timeBuffer[i]);
        }
        return acc / (p_self.len);
    }
    pub fn isOvertimeSearching(p_self: *timeManager, remainingMsTime: i64) bool {
        const _remainTime: f64 = @floatFromInt(remainingMsTime);
        const maxTime: i64 = @intFromFloat(_remainTime * configl.SCHEDULER_MAX_TIME_FRCT);
        return (p_self.timeSinceStartMs() > maxTime);
    }
    pub fn isOvertimeCritical(p_self: *timeManager, remainingMsTime: i64) bool {
        const _remainTime: f64 = @floatFromInt(remainingMsTime);
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
    pub fn startThreadPack(p_self: *scheduler, alloc: std.mem.Allocator) ![]alphaBetal.depthCommunication {
        threadingl.zeroThreadPackArray(p_self.p_threadPack);
        var coms = try alloc.alloc(alphaBetal.depthCommunication, p_self.p_threadPack.len);
        for (0..p_self.p_threadPack.len) |thread_id| {
            if (p_self.isDebugMode()) {
                std.debug.print("[DEBUG] startThreadPack: starting thread {d}\n", .{thread_id});
            }
            coms[thread_id] = .{ .depth = 0, .depthSet = false, .lock = false };
            p_self.p_threadPack.items(._tInfo)[thread_id].alive = true;

            p_self.p_threadPack.items(.threadHandle)[thread_id] = try std.Thread.spawn(.{}, alphaBetal.alphaBetaWaitingRoom, .{ &p_self.p_threadPack.items(.chessState)[thread_id], &p_self.p_threadPack.items(.moves)[thread_id], &p_self.p_threadPack.items(._tInfo)[thread_id], &coms[thread_id], p_self.features });
        }
        return coms;
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
    pub fn startSearch(p_self: *scheduler, depth: u16, depthComs: *[]depthCommunication) void {
        if (p_self.isDebugMode()) {
            std.debug.print("[DEBUG] startSearch: starting search at depth: {d}\n", .{depth});
        }
        std.debug.assert(depth != 0);
        p_self.timeM.startSearchTick();

        threadingl.zeroThreadPackArray(p_self.p_threadPack);
        for (0..p_self.p_threadPack.len) |i| {
            p_self.p_threadPack.items(._tInfo)[i].working = true;
            depthComs.*[i].setDepth(depth);
        }
    }
    pub fn startSearchWithLine(p_self: *scheduler, depth: u16, depthComs: *[]depthCommunication, line: *const movel.line) void {
        if (p_self.isDebugMode()) {
            std.debug.print("[DEBUG] startSearchWithLine: starting search at depth: {d}\n", .{depth});
        }
        std.debug.assert(depth != 0);
        p_self.timeM.startSearchTick();

        threadingl.zeroThreadPackArray(p_self.p_threadPack);
        for (0..p_self.p_threadPack.len) |i| {
            depthComs.*[i].setLine(line);
            p_self.p_threadPack.items(._tInfo)[i].working = true;
            depthComs.*[i].setDepth(depth);
        }
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
        if (p_self.features.useStaticSearch) {
            return p_self.staticLoop(depth);
        } else {
            return p_self.incrementalLoop(depth);
        }
    }
    pub fn extractBest(p_self: *scheduler) moveDecisionExt {
        const res = threadingl.getCombinedFromPack(p_self.p_threadPack);
        return res.currentBest.copy();
    }
    pub fn staticLoop(p_self: *scheduler, depth: u16) searchReport {
        var coms = p_self.startThreadPack(p_self.alloc) catch {
            std.debug.print("[DEBUG] staticLoop: failed to start the pack\n", .{});
            p_self.engineSet = false;
            return .{};
        };
        defer p_self.alloc.free(coms);

        p_self.searchDepth = depth;
        p_self.startSearch(depth, &coms);

        var decision: moveDecisionExt = .{};

        var countTimePrint = @divFloor(configl.INFO_TICKRATE_NS, configl.SCHEDULER_TICKRATE_NS);
        countTimePrint = @max(1, countTimePrint);
        var count: usize = 0;
        while (true) {
            std.Thread.sleep(configl.SCHEDULER_TICKRATE_NS);
            if (count % countTimePrint == 0) {
                p_self.sendUpdate();
                count = 0;
            }
            count += 1;
            const stat = p_self.getSearchStatus();

            //std.debug.print("{}\n", .{stat});

            if (stat == .INTERRUPTED) {
                p_self.handleInterrupt();
                break;
            } else if (stat == .FINISHED) {
                decision = p_self.extractBest();
                p_self.handleInterrupt();
                break;
            } else if (stat == .CONTINUE) {
                // nothing much
            }
        }

        p_self.sendPartial(&decision);
        p_self.sendFinal(&decision);
        // TODO: FIX ME: UCI style thingy here
        p_self.engineSet = false;
        const res = threadingl.getCombinedFromPack(p_self.p_threadPack);
        return .{ .move = decision.move, .timeTakenMs = p_self.timeM.timeSinceStartMs(), .searchStat = res.searchStat };
    }
    pub fn incrementalLoop(p_self: *scheduler, maxDepth: u16) searchReport {
        var coms = p_self.startThreadPack(p_self.alloc) catch {
            p_self.engineSet = false;
            return .{};
        };
        defer p_self.alloc.free(coms);

        p_self.searchDepth = 1;
        p_self.startSearch(p_self.searchDepth, &coms);

        var decision: moveDecisionExt = .{};
        var countTimePrint = @divFloor(configl.INFO_TICKRATE_NS, configl.SCHEDULER_TICKRATE_NS);
        countTimePrint = @max(1, countTimePrint);
        var count: usize = 0;

        while (p_self.searchDepth <= configl.SCHEDULER_MAX_ENDGAME_DEPTH) {
            std.Thread.sleep(configl.SCHEDULER_TICKRATE_NS);
            if (count % countTimePrint == 0) {
                if (p_self.reportProgress) {
                    p_self.sendUpdate();
                }
                count = 0;
            }
            count += 1;
            const stat = p_self.getSearchStatus();
            if (stat == .INTERRUPTED) {
                break;
            } else if (stat == .FINISHED) {
                p_self.timeM.append(.{ .time = p_self.timeM.timeSinceStartMs(), .checked = p_self.p_engine.state.isLegal(p_self.turn) });
                decision = p_self.extractBest();
                if (p_self.reportProgress) {
                    p_self.sendPartial(&decision);
                }
                if (!p_self.canExtendSearch(maxDepth, &decision)) {
                    break;
                }
                p_self.searchDepth += 1;
                p_self.startSearchWithLine(p_self.searchDepth, &coms, &decision.line);
            } else if (stat == .CONTINUE) {
                if (p_self.timeM.isOvertimeCritical(p_self.timeRemaining())) {
                    p_self.handleInterrupt();
                    if (p_self.isDebugMode()) {
                        std.debug.print("[DEBUG] waitingLoop: CRITICALY LOW TIME! Sending previous result\n", .{});
                    }
                    break;
                }
            }
        }

        p_self.sendFinal(&decision);
        p_self.handleInterrupt();
        // TODO: FIX ME: UCI style thingy here
        p_self.engineSet = false;
        const res = threadingl.getCombinedFromPack(p_self.p_threadPack);
        return .{ .move = decision.move, .timeTakenMs = p_self.timeM.timeSinceStartMs(), .searchStat = res.searchStat, .score = decision.scoring };
    }

    pub fn timeRemaining(p_self: *scheduler) i64 {
        if (p_self.turn) {
            return p_self.p_engine.searcher.config.wtime;
        }
        return p_self.p_engine.searcher.config.btime;
    }
    pub fn canExtendSearch(p_self: *scheduler, maxDepth: u16, decision: *const moveDecisionExt) bool {
        if (p_self.features.fixedDepth and p_self.searchDepth == maxDepth or (p_self.searchDepth >= configl.SCHEDULER_MAX_ENDGAME_DEPTH)) {
            return false;
        }
        if (@abs(decision.scoring) >= weightl.simpleCheckMateScore) {
            return false;
        }
        if (p_self.timeM.isOvertimeSearching(p_self.timeRemaining())) {
            return false;
        }
        const prevTime: i64 = p_self.timeM.timeSinceStartMs();
        const floatTime: f64 = @floatFromInt(p_self.timeRemaining());
        const maxTime: i64 = @intFromFloat(floatTime * configl.SCHEDULER_MAX_TIME_FRCT);
        return ((prevTime * configl.SCHEDULER_GROWTH_TIME_EST) < maxTime);
    }
    pub inline fn isDebugMode(p_self: *scheduler) bool {
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

    // FIXME:
    sched.setEngine(p_engine);

    // pre start the searching thread here
    _ = sched.entryPointSearch(searcher.config.depth);
}

pub fn main() void {
    @panic("");
}
