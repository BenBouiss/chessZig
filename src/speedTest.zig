const configl = @import("config.zig");
const enginel = @import("engine.zig");
const movel = @import("move.zig");
const chessl = @import("chess.zig");
const moveGenl = @import("move_generation.zig");
const heuristicl = @import("heuristic.zig");
const hashl = @import("hashTable.zig");
const schedulerl = @import("search/scheduler.zig");
const threadingl = @import("search/threading.zig");

const mailn = @import("main.zig");

const std = @import("std");

const engine = enginel.engine;
const IMove = movel.IMove;
const Board_state = chessl.Board_state;
const threadInfo = threadingl.threadInfo;
const threadInfo_container = threadingl.threadInfo_container;
const threadPackageArray = threadingl.threadPackageArray;
const scoreType = heuristicl.scoreType;
const moveDecisionExt = schedulerl.moveDecisionExt;
const debug_err = chessl.debug_err;

/// Benchmark function to test the node generation speed in
/// "real world" settings mainly computing heuristics...
///
///
pub fn executeEngineBenchmark(p_engine: *engine) bool {
    return dispatchBenchmarkExecutor(p_engine);
}

pub fn getScoreMaskFromTurn(white: bool) i8 {
    if (white) {
        return 1;
    }
    return -1;
}

pub fn dispatchBenchmarkExecutor(p_engine: *engine) bool {
    const dispatchThread = std.Thread.spawn(.{}, _executeEngineBenchmark, .{p_engine}) catch {
        return false;
    };
    p_engine.workingThreads.append(p_engine.alloc, dispatchThread) catch {
        return false;
    };
    return true;
}

pub fn _executeEngineBenchmark(p_engine: *engine) void {
    p_engine.searcher.searching = true;
    defer p_engine.searcher.searching = false;
    const depth: u16 = 6;
    const status = defaultFenBenchmark(p_engine, depth);
    if (p_engine.status.debugMode) {
        std.debug.print("[DEBUG] executeEngineBenchmark: status for benchmark defaultFenBenchmark: {}\n", .{status});
    }
}

pub fn defaultFenBenchmark(p_engine: *engine, depth: u16) bool {
    var state: Board_state = chessl.getBoardFromFen(p_engine.alloc, chessl.DEFAULT_FEN) catch {
        return false;
    };
    var moves = moveGenl.generateLegalMoves(&state);
    var pack = threadingl.getThreadPackArray(p_engine.alloc, &state, &moves, 1) catch {
        return false;
    };
    defer threadingl.freeThreadPackArray(p_engine.alloc, &pack);
    const _start: u64 = @intCast(std.time.milliTimestamp());
    const dispStat = dispatchBenchmark(p_engine, &pack, depth);
    if (!dispStat) {
        return false;
    }
    threadingl.waitBenchmarkThread(p_engine, &pack);
    const nodes = threadingl.getCombinedFromPack(&pack);
    const _end: u64 = @intCast(std.time.milliTimestamp());
    var line_str = nodes.currentBest.line.getLineString(p_engine.alloc) catch {
        return false;
    };
    defer line_str.free(p_engine.alloc);
    const msg = std.fmt.allocPrint(p_engine.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d} line: {s}", .{ @divFloor(nodes.n_nodeExplored, (_end - _start + 1)) * 1000, nodes.n_nodeExplored, nodes.n_hashRetrieve, hashl.hashTable.n_insertion, line_str._slice() }) catch {
        return false;
    };
    defer p_engine.alloc.free(msg);
    p_engine.respond(msg);
    return true;
}

pub fn dispatchBenchmark(p_engine: *engine, p_threadPack: *threadPackageArray, depth: u16) bool {
    for (0..p_threadPack.items(._tInfo).len) |thread_id| {
        if (p_engine.status.debugMode) {
            std.debug.print("[DEBUG] dispatchBenchmark: Launching thread n° {d}\n", .{thread_id});
        }
        p_threadPack.items(.threadHandle)[thread_id] = std.Thread.spawn(.{}, entrypointMoveSearchLoop, .{ &p_threadPack.items(.chessState)[thread_id], &p_threadPack.items(.moves)[thread_id], &p_threadPack.items(._tInfo)[thread_id], depth }) catch {
            return false;
        };
    }
    return true;
}

pub fn entrypointMoveSearchLoop(p_state: *chessl.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16) void {
    p_info.running = true;

    const alpha: scoreType = -heuristicl.simpleCheckMateScore;
    const beta: scoreType = heuristicl.simpleCheckMateScore;

    var currentDecision: moveDecisionExt = .{};
    for (0..p_startingMoves.items.len) |i| {
        p_state.stack.push(&p_state.makeFrame());
        const move = p_startingMoves.items[i];
        _ = p_state.makeMove(move);

        _ = currentDecision.line.append(move);

        const score = -moveSearchLoop(p_state, p_info, depth - 1, &currentDecision, alpha, beta);

        _ = p_state.undoMove();

        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);

        if (i == 0 or p_info.currentBest.scoring < score) {
            p_info.currentBest = currentDecision;
            p_info.currentBest.scoring = score;
            p_info.currentBest.move = move;
        }
        // DEBUG
        std.debug.print("[DEBUG] entrypointMoveSearchLoop: Move: {s} best line: ", .{move.getStr()});
        currentDecision.line.print();
        currentDecision.line.popVoid();
    }
    p_info.running = false;
}
pub fn moveSearchLoop(p_state: *chessl.Board_state, p_info: *threadInfo, depth: u16, currentLine: *moveDecisionExt, alpha: scoreType, beta: scoreType) scoreType {
    const color_mask: i8 = getScoreMaskFromTurn(p_state.whiteToMove());
    if (depth <= 0 or !p_info.running) {
        p_info.n_nodeExplored += 1;
        const score = color_mask * heuristicl.pastHeuristic(p_state);
        currentLine.line.merge_match(&p_state.move_history, 0);
        return score;
    }
    if (p_state.isStaleMateRepetition()) {
        currentLine.line.merge_match(&p_state.move_history, 0);
        return heuristicl.simpleStalemateScore;
    }

    const entry = hashl.getEntryFromMatch(p_state.key, @intCast(depth));
    if (entry.valid) {
        p_info.n_hashRetrieve += 1;
        currentLine.scoring = entry.eval();
        return entry.eval();
    }

    const fmoves: movel.moveContainer = moveGenl.generateLegalMoves(p_state);
    const turn = p_state.whiteToMove();
    var _alpha = alpha;
    var decision: moveDecisionExt = .{};
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];
        p_state.stack.push(&p_state.makeFrame());
        _ = p_state.makeMove(move);

        _ = decision.line.append(move);

        const score = -moveSearchLoop(p_state, p_info, depth - 1, &decision, -beta, -_alpha);

        if (i == 0 or currentLine.scoring < score) {
            currentLine.scoring = score;
            currentLine.line.merge(&decision.line, 0);
        }
        decision.line.len -= 1;

        _ = p_state.undoMove();
        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);

        if (currentLine.scoring > _alpha) {
            _alpha = currentLine.scoring;
        }
        if (_alpha >= beta) {
            break;
        }
    }
    if (fmoves.len == 0) {
        if (!p_state.isLegal(turn)) {
            currentLine.scoring = -(heuristicl.simpleCheckMateScore + depth);
        } else {
            currentLine.scoring = heuristicl.simpleStalemateScore;
        }
    }

    const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.key, @intCast(depth), currentLine.scoring);
    _ = hashl.hashTable.storeEntry(&s_entry);
    return currentLine.scoring;
}
