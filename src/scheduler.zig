const std = @import("std");

const enginel = @import("engine.zig");
const movel = @import("move.zig");
const alphaBetal = @import("alphaBeta.zig");
const threadingl = @import("threading.zig");
const hashl = @import("hashTable.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const weightl = @import("weights.zig");
const timel = @import("time.zig");
const mainl = @import("main.zig");
const boardl = @import("board.zig");
const typel = @import("type.zig");
const chessl = @import("chess.zig");
const moveGenl = @import("move_generation.zig");
const heuristicl = @import("heuristic.zig");
const historyl = @import("history.zig");

const IMove = movel.IMove;
const scoreType = typel.scoreType;
const depthT = typel.depthT;

pub const searchStatus = enum { CONTINUE, INTERRUPTED, FINISHED };

pub const searchReport = struct {
    timeTakenMs: i64 = 0,
    searchStat: threadingl.searchStatistic = .{},
    move: IMove = .{},
    score: scoreType = 0,
};

pub const searchFeatures = struct {
    useStaticSearch: bool = configl.DEFAULT_STATIC_SEARCH,
    fixedDepth: bool = configl.DEFAULT_FIXED_DEPTH,
    reportProgress: bool = configl.DEFAULT_REPORTPROGRESS,
};

pub const moveDecisionExt = struct {
    move: IMove = .{},
    scoring: scoreType = 0,
    line: movel.line = .{},
    depth: depthT = 0,
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
    incMs: i64 = 0,

    pub inline fn startSearchTick(p_self: *timeManager) void {
        p_self.stopWatch.startTimeTick();
    }
    pub inline fn timeSinceStartMs(p_self: *const timeManager) i64 {
        return p_self.stopWatch.timeSinceStartMs();
    }
    pub inline fn timeSinceStartUs(p_self: *const timeManager) i64 {
        return p_self.stopWatch.timeSinceStartUs();
    }
    pub inline fn timeSinceStartSec(p_self: *const timeManager) i64 {
        return p_self.stopWatch.timeSinceStartSec();
    }
    pub inline fn reset(p_self: *timeManager) void {
        p_self.remainingTimeMs = 0;
        p_self.stopWatch.reset();
    }

    pub inline fn isOvertimeSearching(p_self: *const timeManager) bool {
        return (p_self.timeSinceStartMs() > @divFloor(p_self.remainingTimeMs, configl.SCHEDULER_MAX_TIME_DIV));
    }
};
pub fn outOfTime(p_info: *threadingl.threadInfo) bool {
    if (!p_info.alive) return true;
    p_info.checkTime += 1;
    if (p_info.checkTime == 1024) {
        p_info.checkTime = 0;
        if (p_info.stopWatch.timeSinceStartMs() >= p_info.criticalTimeMs) {
            p_info.alive = false;
            return true;
        }
    }
    return false;
}

pub const scheduler = struct {
    timeM: timeManager = .{},
    _threadPool: threadingl.threadPool = .{},
    interrupt: bool = false,
    computedPlies: i64 = 0,
    nPlyCompute: usize = 0,

    pub inline fn reset(self: *scheduler) void {
        self.interrupt = false;
        self.timeM.reset();
    }
    pub inline fn close(self: *scheduler) void {
        self.interrupt = true;
        self._threadPool.close();
    }
    pub fn handleInterrupt(p_self: *scheduler) void {
        p_self._threadPool.stop();
        p_self._threadPool.waitOnFinish();
    }
    pub inline fn setRemainingTimeMs(p_self: *scheduler, timeMs: i64) void {
        p_self.timeM.remainingTimeMs = timeMs;
    }
    pub inline fn setInc(p_self: *scheduler, incMs: i64) void {
        p_self.timeM.incMs = incMs;
    }
    pub fn entryPointSearch(p_self: *scheduler, p_engine: *enginel.engine, state: boardl.boardState, depth: depthT, features: searchFeatures) searchReport {
        // only used in the benchmark files
        _ = p_engine;
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
        return .{ .move = decision.move, .timeTakenMs = p_self.timeM.timeSinceStartMs(), .searchStat = res.searchStat, .score = decision.scoring };
    }
    pub inline fn extractBest(p_self: *scheduler) moveDecisionExt {
        const res = p_self._threadPool.getCombinedInfo();
        return res.currentBest.copy();
    }
};

pub fn dispatchUciGoCmd(p_engine: *enginel.engine, config: enginel.goArgStruct) bool {
    const pack: threadingl.searchPackage = .{ .chessState = p_engine.state, .depth = config.depth, .features = p_engine.options.searchF, .scheduler = &(p_engine.scheduler) };
    p_engine.scheduler.timeM.startSearchTick();
    if (p_engine.state.whiteToMove()) {
        p_engine.scheduler.setRemainingTimeMs(config.wtime);
    } else {
        p_engine.scheduler.setRemainingTimeMs(config.btime);
    }
    p_engine.scheduler._threadPool.submit(&pack) catch {
        p_engine.respond("engineOp threadPoolSubmit failed crashing");
        _ = p_engine.executeQuitProcedure();
        @panic(":)");
    };

    return true;
}
pub fn startSearch(p_state: *boardl.boardState, features: searchFeatures, maxDepth: depthT) threadingl.threadInfo {
    var sched: scheduler = .{};
    sched.setRemainingTimeMs(std.math.maxInt(i64));
    sched.timeM.startSearchTick();
    var info: threadingl.threadInfo = .{ .alive = true };
    _startSearch(&sched, p_state, &info, features, maxDepth);
    return info;
}
pub fn _startSearch(sched: *scheduler, p_state: *boardl.boardState, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: depthT) void {
    // everything gets "returned" via the p_info
    // launched as single threaded
    // redundant as the thread beeing launch already sets this beforehand, however the previous init serves just to prevent very early return (ie: status == .FINISHED) when nothing happened
    p_info.working = true;
    defer sendFinal(p_info.currentBest.move);
    defer p_info.working = false;

    p_info.stopWatch = sched.timeM.stopWatch;
    p_info.checkTime = 0;
    p_info.criticalTimeMs = @divFloor(sched.timeM.remainingTimeMs, configl.SCHEDULER_CRITICAL_TIME_DIV);

    hashl.hashTable.nextGeneration();
    const fmoves = moveGenl.generateLegalMoves(p_state);
    if (fmoves.len == 1) {
        p_info.currentBest = .{ .depth = 1, .move = fmoves.moves[0], .scoring = heuristicl.c_evaluate(p_state, p_state.whiteToMove()), .line = .{ .len = 1 } };
        p_info.currentBest.line.moves[0] = fmoves.moves[0];
        return;
    }
    const depth = aspirationWindow(sched, p_state, p_info, features, maxDepth);
    p_info.depth = depth;
    sched.nPlyCompute += 1;
    sched.computedPlies += depth;
}

pub fn aspirationWindow(sched: *const scheduler, p_state: *boardl.boardState, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: depthT) depthT {
    var depth: depthT = if (features.useStaticSearch) maxDepth else 1;

    var ss: alphaBetal.searchStack = .{};
    var score = alphaBetal.searchEntrypoint(p_state, p_info, depth, &ss, -weightl.simpleCheckMateScore, weightl.simpleCheckMateScore);
    var delta = weightl.aspirationCoefficient;
    var validDecision: IMove = .{};
    while (p_info.alive and canExtendSearch(&sched.timeM, depth, maxDepth, score, &features)) {
        depth += 1;

        var alpha = score - delta;
        var beta = score + delta;
        score = alphaBetal.searchEntrypoint(p_state, p_info, depth, &ss, alpha, beta);
        while ((score <= alpha or score >= beta) and p_info.alive) {
            //
            if (score <= alpha) {
                beta = @divFloor(alpha + beta, 2);
                alpha -= delta;
            } else if (score >= beta) {
                beta += delta;
            }
            delta += @divFloor(delta, 3);

            score = alphaBetal.searchEntrypoint(p_state, p_info, depth, &ss, alpha, beta);
        }
        ss.setPrevLine(&p_info.currentBest.line);
        if (p_info.alive) {
            validDecision = p_info.currentBest.move;
        } else {
            if (validDecision.isValid()) {
                p_info.currentBest.move = validDecision;
            }
            break;
        }
        if (features.reportProgress) {
            sendPartial(p_info, sched.timeM.timeSinceStartMs());
        }
    }
    return depth;
}

//https://www.chessprogramming.org/Time_Management
pub fn canExtendSearch(timer: *const timeManager, depth: depthT, maxDepth: depthT, score: scoreType, p_features: *const searchFeatures) bool {
    if (p_features.fixedDepth and depth == maxDepth or (depth >= typel.MAX_PLY)) {
        return false;
    }
    if (chessl.isMate(score) or timer.isOvertimeSearching()) {
        return false;
    }
    const prevTime: i64 = timer.timeSinceStartMs();
    const maxTime: i64 = @divFloor(timer.remainingTimeMs, configl.SCHEDULER_MAX_TIME_DIV) + @divFloor(timer.incMs, configl.SCHEDULER_MAX_TIME_INC_DIV);
    return ((prevTime * configl.SCHEDULER_GROWTH_TIME_EST) < maxTime);
}

pub inline fn sendPartial(p_info: *const threadingl.threadInfo, timeSinceStartMs: i64) void {
    var msgBuffer: [configl.MAX_USER_INPUT]u8 = undefined;
    const nNodes: i64 = @intCast(p_info.searchStat.n_nodeExplored);
    const nps = @divFloor(nNodes * 1000, (1 + timeSinceStartMs));
    const final_info = std.fmt.bufPrint(&msgBuffer, "info depth {d} seldepth {d} score cp {d} nodes {d} nps {d} currmove {s} pv {f}\n", .{ p_info.depth, p_info.seldepth, p_info.currentBest.scoring, nNodes, nps, utilsl.trimStr(&p_info.currentBest.move.getStr()), p_info.currentBest.line }) catch unreachable;
    respondNoEng(utilsl.trimStr(final_info)) catch unreachable;
}

pub fn sendFinal(move: IMove) void {
    var buffer = std.mem.zeroes([16]u8);
    const msg = std.fmt.bufPrint(&buffer, "bestmove {s}\n", .{utilsl.trimStr(&move.getStr())}) catch unreachable;
    respondNoEng(msg) catch unreachable;
}

pub inline fn respondNoEng(msg: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(mainl.getGlobalIo(), msg);
}
