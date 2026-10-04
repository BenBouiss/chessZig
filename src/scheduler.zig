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
const Hash_table = hashl.Hash_table;

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
    dataGen: bool = false,
};

pub const moveDecisionExt = struct {
    move: IMove = .{},
    score: scoreType = 0,
    line: movel.line = .{},
    pub inline fn invertScore(p_self: *moveDecisionExt) void {
        p_self.score = -p_self.score;
    }
    pub inline fn isBetter(p_self: *moveDecisionExt, other: *moveDecisionExt) bool {
        return p_self.score > other.score;
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
    softNodeLim: u64 = std.math.maxInt(u64),
    criticalNodeLim: u64 = std.math.maxInt(u64),
};

pub const scheduler = struct {
    _threadPool: threadingl.threadPool = .{},
    interrupt: bool = false,
    inDatagen: bool = false,

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
        return .{ .move = decision.move, .timeTakenMs = sw.timeSinceStartMs(), .searchStat = res.searchStat, .score = decision.score };
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
        pack.time.softNodeLim = config.nodes;
        pack.time.criticalNodeLim = config.nodes;
    } else {
        pack.time.timeMs = config.btime;
        pack.time.incMs = config.binc;
        pack.time.softNodeLim = config.nodes;
        pack.time.criticalNodeLim = config.nodes;
    }
    p_engine.scheduler._threadPool.submit(pack) catch {
        p_engine.respond("engineOp threadPoolSubmit failed crashing");
        _ = p_engine.executeQuitProcedure();
        @panic(":)");
    };

    return true;
}
pub fn startSearch(p_state: *boardl.boardState, features: searchFeatures, maxDepth: depthT, t: timeInfo, tt: *Hash_table) result {
    var info: threadingl.threadInfo = .{ .alive = true };
    var d: threadingl.threadData = .{};
    const res = _startSearch(p_state, &info, features, maxDepth, t, tt, &d);
    return res;
}
pub fn _startSearch(p_state: *boardl.boardState, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: depthT, time: timeInfo, tt: *Hash_table, d: *threadingl.threadData) result {
    // everything gets "returned" via the p_info
    // launched as single threaded
    // redundant as the thread beeing launch already sets this beforehand, however the previous init serves just to prevent very early return (ie: status == .FINISHED) when nothing happened
    var tm: timeManager = .{ .t = time, .stopWatch = .init(true) };
    p_info.stopWatch = .init(true);
    p_info.alive = true;
    p_info.searchStat = .{};
    p_info.depth = 0;
    p_info.seldepth = 0;
    p_info.checkTime = 0;
    p_info.criticalNodeLim = time.criticalNodeLim;
    d.nodeCount = std.mem.zeroes([64][64]u64);

    p_info.criticalTimeMs = @divFloor(tm.t.timeMs, configl.SCHEDULER_CRITICAL_TIME_DIV);
    tm.originalSoftTimeLim = @divFloor(tm.t.timeMs, configl.SCHEDULER_MAX_TIME_DIV) + @divFloor(3 * tm.t.incMs, configl.SCHEDULER_MAX_TIME_INC_DIV);
    tm.softTimeLimit = tm.originalSoftTimeLim;

    hashl.hashTable.nextGeneration();

    const fmoves = moveGenl.generateLegalMoves(p_state);
    if (fmoves.len == 1 and !features.dataGen) {
        const m = fmoves.moves[0];
        sendFinal(m) catch unreachable;
        return .{ .move = m, .depth = 1 };
    }
    d.excludedMove = .{};
    for (0..fmoves.len) |i| {
        d.rootMoves[i] = .{ .move = fmoves.moves[i], .nodes = 0 };
    }
    d.nnueStack.len = 1;
    if (comptime configl.USE_NNUE) {
        d.nnueStack.items[0] = nnuel.computeAccPair(&nnuel.nnueNet, p_state);
    }
    const res = aspirationWindow(&tm, p_state, p_info, features, maxDepth, d, tt);
    p_info.depth = res.depth;
    return res;
}
pub const result = struct {
    move: IMove = .{},
    score: scoreType = 0,
    depth: depthT = typel.scoreNone,
};

pub fn aspirationWindow(tm: *timeManager, p_state: *boardl.boardState, p_info: *threadingl.threadInfo, features: searchFeatures, maxDepth: depthT, threadD: *threadingl.threadData, tt: *Hash_table) result {
    var depth: depthT = if (features.useStaticSearch) maxDepth else 1;

    var ss: alphaBetal.searchStack = .{};
    var alpha = -weightl.simpleCheckMateScore;
    var beta = weightl.simpleCheckMateScore;
    var delta = weightl.aspirationCoefficient;

    var score = alphaBetal.searchEntrypoint(p_state, p_info, depth, &ss, alpha, beta, threadD, tt);
    var validDecision: IMove = p_info.currentBest.move;
    var samePrevBestMove: scoreType = 0;
    var prevBest: IMove = .{};
    var innerLoopRep: usize = 0;

    while (p_info.alive and canExtendSearch(tm, depth, maxDepth, score, &features, p_info.searchStat.n_nodeExplored)) {
        depth += 1;
        var _depth = depth;
        score = alphaBetal.searchEntrypoint(p_state, p_info, _depth, &ss, alpha, beta, threadD, tt);
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

            score = alphaBetal.searchEntrypoint(p_state, p_info, _depth, &ss, alpha, beta, threadD, tt);
        }
        //if (!p_info.currentBest.move.isValid()) {
        //    p_info.alive = false;
        //}
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
        const nratio: f64 = @as(f64, @floatFromInt(threadD.nodeCount[validDecision.getFrom()][validDecision.getTo()])) / @as(f64, @floatFromInt(p_info.searchStat.n_nodeExplored + 1));
        const lim = 1.5 - nratio;
        tm.softTimeLimit = @intFromFloat(@min(@as(f64, @floatFromInt(tm.originalSoftTimeLim)) * lim, @as(f64, @floatFromInt(p_info.criticalTimeMs))));

        if (features.reportProgress and !features.dataGen) {
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

    if (!features.dataGen) {
        sendFinal(validDecision) catch unreachable;
    }
    return .{ .depth = depth, .move = validDecision, .score = score };
}

//https://www.chessprogramming.org/Time_Management
pub fn canExtendSearch(timer: *const timeManager, depth: depthT, maxDepth: depthT, score: scoreType, p_features: *const searchFeatures, nodes: u64) bool {
    if ((p_features.fixedDepth and depth == maxDepth) or (depth >= (typel.MAX_PLY - 1)) or chessl.isMate(score) or nodes >= timer.t.softNodeLim) {
        return false;
    }
    return timer.timeSinceStartMs() < timer.softTimeLimit;
}

pub fn sendPartial(p_info: *const threadingl.threadInfo, timeSinceStartMs: i64, depth: depthT, innerLoop: usize) void {
    var msgBuffer: [2 * configl.MAX_USER_INPUT]u8 = undefined;
    const nNodes: i64 = @intCast(p_info.searchStat.n_nodeExplored);
    const nps = @divFloor(nNodes * 1000, (1 + timeSinceStartMs));

    const final_info = std.fmt.bufPrint(&msgBuffer, "info depth {d} seldepth {d} loop {d} score cp {d} nodes {d} nps {d} currmove {s} pv {f}\n", .{ depth, p_info.seldepth, innerLoop, p_info.currentBest.score, nNodes, nps, utilsl.trimStr(&p_info.currentBest.move.getStr()), p_info.currentBest.line }) catch {
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
