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

const nnuel = @import("nnue.zig");

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
    t: timeInfo = .{},
    softTimeLimit: i64 = 0,
    originalSoftTimeLim: i64 = 0,

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
        p_self.t.timeMs = 0;
        p_self.stopWatch.reset();
    }
};

pub const timeInfo = struct {
    timeMs: i64 = std.math.maxInt(i64),
    incMs: i64 = 0,
};

pub const scheduler = struct {
    _threadPool: threadingl.threadPool = .{},
    interrupt: bool = false,

    pub inline fn reset(self: *scheduler) void {
        self.interrupt = false;
    }
    pub inline fn close(self: *scheduler) void {
        self.interrupt = true;
        self._threadPool.close();
    }
    pub fn handleInterrupt(p_self: *scheduler) void {
        p_self._threadPool.stop();
        p_self._threadPool.waitOnFinish();
    }
    pub fn entryPointSearch(p_self: *scheduler, state: boardl.boardState, depth: depthT, features: searchFeatures) searchReport {
        // only used in the benchmark files
        if (!p_self._threadPool.running) {
            return .{};
        }
        var sw: timel.stopWatch = .init(true);

        const pack: threadingl.searchPackage = .{ .depth = depth, .features = features, .chessState = state, .time = .{} };

        p_self._threadPool.submit(pack) catch {
            @panic(":)");
        };
        p_self._threadPool.waitOnFinish();

        const decision = p_self.extractBest();
        const res = p_self._threadPool.getCombinedInfo();
        return .{ .move = decision.move, .timeTakenMs = sw.timeSinceStartMs(), .searchStat = res.searchStat, .score = decision.scoring };
    }
    pub inline fn extractBest(p_self: *scheduler) moveDecisionExt {
        const res = p_self._threadPool.getCombinedInfo();
        return res.currentBest.copy();
    }
};

pub fn dispatchUciGoCmd(p_engine: *enginel.engine, config: enginel.goArgStruct) bool {
    var pack: threadingl.searchPackage = .{ .chessState = p_engine.state, .depth = config.depth, .features = p_engine.options.searchF };
    if (p_engine.state.whiteToMove()) {
        pack.time.timeMs = config.wtime;
        pack.time.incMs = config.winc;
    } else {
        pack.time.timeMs = config.btime;
        pack.time.incMs = config.binc;
    }
    p_engine.scheduler._threadPool.submit(pack) catch {
        p_engine.respond("engineOp threadPoolSubmit failed crashing");
        _ = p_engine.executeQuitProcedure();
        @panic(":)");
    };

    return true;
}
pub fn startSearch(p_state: *boardl.boardState, features: searchFeatures, maxDepth: depthT) threadingl.threadInfo {
    const t: timeInfo = .{};
    var info: threadingl.threadInfo = .{ .alive = true };
    _ = _startSearch(p_state, &info, features, maxDepth, t);
    return info;
}
pub fn _startSearch(p_state: *boardl.boardState, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: depthT, time: timeInfo) depthT {
    // everything gets "returned" via the p_info
    // launched as single threaded
    // redundant as the thread beeing launch already sets this beforehand, however the previous init serves just to prevent very early return (ie: status == .FINISHED) when nothing happened
    var tm: timeManager = .{ .t = time };
    tm.stopWatch.startTimeTick();

    p_info.stopWatch = .init(true);
    p_info.searchStat = .{};
    p_info.depth = 0;
    p_info.seldepth = 0;
    p_info.checkTime = 0;
    p_info.criticalTimeMs = @divFloor(tm.t.timeMs, configl.SCHEDULER_CRITICAL_TIME_DIV);

    tm.originalSoftTimeLim = @divFloor(tm.t.timeMs, configl.SCHEDULER_MAX_TIME_DIV) + @divFloor(tm.t.incMs, configl.SCHEDULER_MAX_TIME_INC_DIV);
    tm.softTimeLimit = tm.originalSoftTimeLim;

    hashl.hashTable.nextGeneration();

    const fmoves = moveGenl.generateLegalMoves(p_state);
    if (fmoves.len == 1) {
        sendFinal(fmoves.moves[0]) catch unreachable;
        return 1;
    }
    var threadD: alphaBetal.threadData = .{};
    for (0..fmoves.len) |i| {
        threadD.rootMoves[i] = .{ .move = fmoves.moves[i], .nodes = 0 };
    }
    threadD.nnueStack.len = 1;
    if (comptime configl.USE_NNUE) {
        //p_state.frame.nnueAccumul = nnuel.computeAccPair(&nnuel.nnueNet.net, p_state);
        threadD.nnueStack.items[0] = nnuel.computeAccPair(&nnuel.nnueNet, p_state);
    }
    const depth = aspirationWindow(&tm, p_state, p_info, features, maxDepth, &threadD);
    p_info.depth = depth;
    return depth;
}

pub fn aspirationWindow(tm: *timeManager, p_state: *boardl.boardState, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: depthT, threadD: *alphaBetal.threadData) depthT {
    var depth: depthT = if (features.useStaticSearch) maxDepth else 1;

    var ss: alphaBetal.searchStack = .{};
    var alpha = -weightl.simpleCheckMateScore;
    var beta = weightl.simpleCheckMateScore;
    var delta = weightl.aspirationCoefficient;

    var score = alphaBetal.searchEntrypoint(p_state, p_info, depth, &ss, alpha, beta, threadD);
    var validDecision: IMove = p_info.currentBest.move;
    var samePrevBestMove: scoreType = 0;
    var prevBest: IMove = .{};
    var innerLoopRep: usize = 0;

    while (p_info.alive and canExtendSearch(tm, depth, maxDepth, score, &features)) {
        depth += 1;
        var _depth = depth;
        score = alphaBetal.searchEntrypoint(p_state, p_info, _depth, &ss, alpha, beta, threadD);
        innerLoopRep = 0;

        while (p_info.alive and (score <= alpha or score >= beta)) {
            innerLoopRep += 1;
            if (score <= alpha) {
                beta = @divFloor(alpha + beta, 2);
                alpha -= delta;
                _depth = depth;
            } else if (score >= beta) {
                beta += delta;
                _depth = @max(1, _depth - 1);
            }
            delta += @divFloor(delta, 3);

            score = alphaBetal.searchEntrypoint(p_state, p_info, _depth, &ss, alpha, beta, threadD);
        }
        if (!p_info.alive) {
            break;
        }
        validDecision = p_info.currentBest.move;
        ss.setPrevLine(&p_info.currentBest.line);

        if (prevBest.equal(validDecision)) {
            samePrevBestMove = @min(samePrevBestMove + 1, @as(usize, @intCast(weightl.bestMoveMax)));
        } else {
            samePrevBestMove = 1;
            prevBest = validDecision;
        }
        //threadD.printRooMoves();
        if (features.reportProgress) {
            sendPartial(p_info, tm.timeSinceStartMs(), depth, innerLoopRep);
        }
        if (depth > weightl.aspirationMinDepthVar) {
            //alpha = score - delta;
            //beta = score + delta;
            alpha = score - weightl.aspirationCoefficient;
            beta = score + weightl.aspirationCoefficient;
        } else {
            alpha = -weightl.simpleCheckMateScore;
            beta = weightl.simpleCheckMateScore;
        }
    }
    sendFinal(validDecision) catch unreachable;
    return depth;
}

//https://www.chessprogramming.org/Time_Management
pub fn canExtendSearch(timer: *const timeManager, depth: depthT, maxDepth: depthT, score: scoreType, p_features: *const searchFeatures) bool {
    if ((p_features.fixedDepth and depth == maxDepth) or (depth >= typel.MAX_PLY) or chessl.isMate(score)) {
        return false;
    }
    return ((timer.timeSinceStartMs() * weightl.schedulerGrowthEstim) < timer.softTimeLimit);
}

pub fn sendPartial(p_info: *const threadingl.threadInfo, timeSinceStartMs: i64, depth: depthT, innerLoop: usize) void {
    var msgBuffer: [2 * configl.MAX_USER_INPUT]u8 = undefined;
    const nNodes: i64 = @intCast(p_info.searchStat.n_nodeExplored);
    const nps = @divFloor(nNodes * 1000, (1 + timeSinceStartMs));

    const final_info = std.fmt.bufPrint(&msgBuffer, "info depth {d} seldepth {d} loop {d} score cp {d} nodes {d} nps {d} currmove {s} pv {f}\n", .{ depth, p_info.seldepth, innerLoop, p_info.currentBest.scoring, nNodes, nps, utilsl.trimStr(&p_info.currentBest.move.getStr()), p_info.currentBest.line }) catch {
        @panic("hehehehe");
    };
    respondNoEng(utilsl.trimStr(final_info)) catch unreachable;
}

pub fn sendFinal(move: IMove) !void {
    var buffer = std.mem.zeroes([16]u8);
    const msg = try std.fmt.bufPrint(&buffer, "bestmove {s}\n", .{utilsl.trimStr(&move.getStr())});
    try respondNoEng(msg);
}

pub inline fn respondNoEng(msg: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(mainl.getGlobalIo(), msg);
}
