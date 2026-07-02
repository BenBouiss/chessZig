const std = @import("std");

const enginel = @import("../engine.zig");
const movel = @import("../move.zig");
const alphaBetal = @import("alphaBeta.zig");
const threadingl = @import("threading.zig");
const hashl = @import("../hashTable.zig");
const utilsl = @import("../utils.zig");
const configl = @import("../config.zig");
const weightl = @import("../weights.zig");
const timel = @import("../time.zig");
const mainl = @import("../main.zig");
const boardl = @import("../board.zig");
const typel = @import("../type.zig");
const chessl = @import("../chess.zig");
const moveGenl = @import("../move_generation.zig");
const heuristicl = @import("../heuristic.zig");

const IMove = movel.IMove;
const scoreType = typel.scoreType;

pub const searchStatus = enum { CONTINUE, INTERRUPTED, FINISHED };

pub const searchReport = struct {
    timeTakenMs: i64 = 0,
    searchStat: threadingl.searchStatistic = .{},
    move: IMove = .{},
    score: scoreType = 0,
};

pub const searchFeatures = struct {
    useHash: bool = configl.DEFAULT_USEHASHTABLE,
    useNullPrune: bool = configl.DEFAULT_USE_NULLPRUNE,
    useStaticSearch: bool = configl.DEFAULT_STATIC_SEARCH,
    fixedDepth: bool = configl.DEFAULT_FIXED_DEPTH,
    useLMR: bool = configl.DEFAULT_LATE_MOVE_REDUCTION,
    useRazoring: bool = configl.DEFAULT_USE_RAZORING,
    useRFP: bool = configl.DEFAULT_USE_RFP,
    reportProgress: bool = configl.DEFAULT_REPORTPROGRESS,
    useFutility: bool = configl.DEFAULT_USE_FUTILITY,
    useProbCut: bool = configl.DEFAULT_USE_PROBCUT,
    useIIR: bool = configl.DEFAULT_USE_IIR,
    useAspiration: bool = configl.DEFAULT_USE_ASPIRATION,
};

pub const uciSearcher = struct {
    schedul: scheduler = .{},
    interrupt: bool = false,

    pub fn reset(p_self: *uciSearcher) void {
        p_self.interrupt = false;
        p_self.schedul.reset();
    }
    pub fn close(self: *uciSearcher) !void {
        self.interrupt = true;
        self.schedul.interrupt = true;
        self.schedul._threadPool.close();
    }
    pub fn getSearchStatus(p_self: *uciSearcher) searchStatus {
        if (p_self.interrupt) {
            return .INTERRUPTED;
        }
        return p_self.schedul._threadPool.getSearchStatus();
    }
};

pub fn waitingRoomOneShot(self: *enginel.engine) !void {
    const stat = self.searcher.getSearchStatus();
    if (stat == .INTERRUPTED or stat == .FINISHED) {
        self.searcher.schedul.searching = false;
        self.searcher.schedul.timeM.reset();
        const decision = self.searcher.schedul.extractBest();
        sendFinal(self, &decision);
        if (stat == .INTERRUPTED) {
            self.searcher.schedul.handleInterrupt();
        }
        if (self.options.trackMetrics) {
            self.metric.addPlies(decision.depth);
        }
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
    depth: u16 = 0,
    pub inline fn invertScore(p_self: *moveDecisionExt) void {
        p_self.scoring = -p_self.scoring;
    }
    pub inline fn isBetter(p_self: *moveDecisionExt, other: *moveDecisionExt) bool {
        return p_self.scoring > other.scoring;
    }
    pub fn copy(self: moveDecisionExt) moveDecisionExt {
        return self;
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
    pub inline fn reset(p_self: *timeManager) void {
        p_self.remainingTimeMs = 0;
        p_self.stopWatch.reset();
    }
    pub inline fn setRemainingTimeMs(p_self: *timeManager, timeMs: i64) void {
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
    timeM: timeManager = .{},
    _threadPool: threadingl.threadPool = .{},
    interrupt: bool = false,
    searching: bool = false,
    pub inline fn reset(self: *scheduler) void {
        self.interrupt = false;
        self.timeM.reset();
    }
    pub fn handleInterrupt(p_self: *scheduler) void {
        p_self._threadPool.stop();
        p_self._threadPool.waitOnFinish();
    }
    pub fn entryPointSearch(p_self: *scheduler, p_engine: *enginel.engine, state: boardl.boardState, depth: u16, features: searchFeatures) searchReport {
        // only used in the benchmark files
        if (!p_self._threadPool.running) {
            return .{};
        }
        p_self.timeM.startSearchTick();
        defer p_self.timeM.stopWatch.stop();
        const pack: threadingl.searchPackage = .{ .depth = depth, .features = features, .scheduler = p_self, .chessState = state };

        p_self._threadPool.submit(&pack) catch {
            @panic(":)");
        };
        p_self._threadPool.waitOnFinish();

        const decision = p_self.extractBest();
        const res = p_self._threadPool.getCombinedInfo();
        sendFinal(p_engine, &decision);
        return .{ .move = decision.move, .timeTakenMs = p_self.timeM.timeSinceStartMs(), .searchStat = res.searchStat, .score = decision.scoring };
    }
    pub inline fn extractBest(p_self: *scheduler) moveDecisionExt {
        const res = p_self._threadPool.getCombinedInfo();
        return res.currentBest.copy();
    }
};

pub fn dispatchUciGoCmd(p_engine: *enginel.engine, cmdBuffer: []const u8, config: enginel.goArgStruct) bool {
    _ = cmdBuffer;
    const pack: threadingl.searchPackage = .{ .chessState = p_engine.state, .depth = config.depth, .features = p_engine.options.searchF, .scheduler = &(p_engine.searcher.schedul) };
    p_engine.searcher.schedul.searching = true;
    p_engine.searcher.schedul.timeM.startSearchTick();
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
pub fn startSearch(p_state: *boardl.boardState, features: searchFeatures, maxDepth: u16) threadingl.threadInfo {
    var sched: scheduler = .{};
    sched.timeM.setRemainingTimeMs(std.math.maxInt(i64));
    sched.timeM.startSearchTick();
    var info: threadingl.threadInfo = .{ .alive = true };
    _startSearch(&sched, p_state, &info, features, maxDepth);
    return info;
}
pub fn _startSearch(sched: *scheduler, p_state: *boardl.boardState, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: u16) void {
    // everything gets "returned" via the p_info
    // launched as single threaded
    // redundant as the thread beeing launch already sets this beforehand, however the previous init serves just to prevent very early return (ie: status == .FINISHED) when nothing happened
    p_info.working = true;
    defer p_info.working = false;
    if (features.useHash) {
        hashl.hashTable.nextGeneration();
    }
    const fmoves = moveGenl.generateLegalMoves(p_state);
    if (fmoves.len == 1) {
        p_info.currentBest.move = fmoves.moves[0];
        p_info.currentBest.scoring = heuristicl.c_evaluate(p_state, p_state.whiteToMove());
        p_info.currentBest.line.len = 1;
        p_info.currentBest.line.moves[0] = fmoves.moves[0];
        return;
    }
    var depth: u16 = 0;
    depth = aspirationWindow(sched, p_state, p_info, features, maxDepth);
    p_info.depth = depth;
    //sched.searching = false;
    //_sendFinal(&p_info.currentBest);
}

pub fn aspirationWindow(sched: *const scheduler, p_state: *boardl.boardState, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: u16) u16 {
    var depth: u16 = if (features.useStaticSearch) maxDepth else 1;
    var ss: alphaBetal.searchStack = .{};
    var score = alphaBetal.searchEntrypoint(p_state, p_info, depth, &features, &ss, -weightl.simpleCheckMateScore, weightl.simpleCheckMateScore);
    while (p_info.alive and canExtendSearch(&sched.timeM, depth, maxDepth, score, &features)) {
        depth += 1;
        score = alphaBetal.aspirationSearchEntrypoint(p_state, p_info, depth, &features, &ss, score);
        ss.setPrevLine(&p_info.currentBest.line);
        if (features.reportProgress) {
            sendPartial(depth, p_info);
        }
    }
    return depth;
}

pub fn canExtendSearch(timer: *const timeManager, depth: u16, maxDepth: u16, score: scoreType, p_features: *const searchFeatures) bool {
    if (p_features.fixedDepth and depth == maxDepth or (depth >= typel.MAX_PLY)) {
        return false;
    }
    if (chessl.isMate(score) or timer.isOvertimeSearching()) {
        return false;
    }
    const prevTime: i64 = timer.timeSinceStartMs();
    const floatTime: f64 = @floatFromInt(timer.remainingTimeMs);
    const maxTime: i64 = @intFromFloat(floatTime * configl.SCHEDULER_MAX_TIME_FRCT);
    return ((prevTime * configl.SCHEDULER_GROWTH_TIME_EST) < maxTime);
}

pub fn sendPartial(depth: u16, p_info: *const threadingl.threadInfo) void {
    const n_nodes: i64 = @intCast(p_info.searchStat.n_nodeExplored);
    const n_cut = p_info.searchStat.n_cutoffs;
    var msgBuffer: [configl.MAX_USER_INPUT]u8 = @splat(0); // Buffer for stdout
    const final_info = std.fmt.bufPrint(&msgBuffer, "info depth {d} score cp {d} nodes {d} cutoff: {d} currmove {s} pv {f}\n", .{ depth, p_info.currentBest.scoring, n_nodes, n_cut, utilsl.trimStr(&p_info.currentBest.move.getStr()), p_info.currentBest.line }) catch unreachable;
    respondNoEng(utilsl.trimStr(final_info)) catch {};
}

pub fn sendFinal(p_self: *enginel.engine, decision: *const moveDecisionExt) void {
    var buffer = std.mem.zeroes([32]u8);
    const msg = std.fmt.bufPrint(&buffer, "bestmove {s}\n", .{utilsl.trimStr(&decision.move.getStr())}) catch unreachable;
    p_self.respondNonFmt(msg);
}
pub fn _sendFinal(decision: *const moveDecisionExt) void {
    var buffer = std.mem.zeroes([32]u8);
    const msg = std.fmt.bufPrint(&buffer, "bestmove {s}\n", .{utilsl.trimStr(&decision.move.getStr())}) catch unreachable;
    respondNoEng(msg) catch unreachable;
}

pub fn respondNoEng(msg: []const u8) !void {
    var buffer: [configl.MAX_USER_INPUT]u8 = @splat(0); // Buffer for stdout
    var writer = std.Io.File.stdout().writer(mainl.getGlobalIo(), &buffer);
    const interface = &writer.interface;
    try interface.writeAll(msg);
    try interface.flush();
}
