const std = @import("std");
const chess = @import("../chess.zig");
const movel = @import("../move.zig");
const moveGenl = @import("../move_generation.zig");
const heuristicl = @import("../heuristic.zig");
const weightl = @import("../weights.zig");
const threadingl = @import("threading.zig");
const schedulerl = @import("scheduler.zig");
const hashl = @import("../hashTable.zig");
const utilsl = @import("../utils.zig");
const configl = @import("../config.zig");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const scoreType = heuristicl.scoreType;

const moveDecisionExt = schedulerl.moveDecisionExt;
const searchFeatures = schedulerl.searchFeatures;

const threadInfo = threadingl.threadInfo;

pub fn getScoreMaskFromTurn(white: bool) scoreType {
    if (white) {
        return 1;
    }
    return -1;
}

pub fn searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, feature: searchFeatures) void {
    if (feature.useHash) {
        return texelTransf_searchEntrypoint(p_state, p_startingMoves, p_info, depth, true, feature.useTexelEvaluation, feature.useQuiescence);
    }
    return texelTransf_searchEntrypoint(p_state, p_startingMoves, p_info, depth, false, feature.useTexelEvaluation, feature.useQuiescence);
}
pub fn texelTransf_searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, comptime useHash: bool, useTexel: bool, useQuiescence: bool) void {
    if (useTexel) {
        return quiescTransf_searchEntrypoint(p_state, p_startingMoves, p_info, depth, useHash, true, useQuiescence);
    }
    return quiescTransf_searchEntrypoint(p_state, p_startingMoves, p_info, depth, useHash, false, useQuiescence);
}
pub fn quiescTransf_searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, comptime useHash: bool, comptime useTexel: bool, useQuiescence: bool) void {
    if (useQuiescence) {
        return _searchEntrypoint(p_state, p_startingMoves, p_info, depth, useHash, useTexel, true);
    }
    return _searchEntrypoint(p_state, p_startingMoves, p_info, depth, useHash, useTexel, false);
}

pub fn _searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, comptime useHash: bool, comptime useTexel: bool, comptime useQuiescence: bool) void {
    p_info.running = true;

    const alpha: scoreType = -weightl.simpleCheckMateScore;
    const beta: scoreType = weightl.simpleCheckMateScore;

    for (0..p_startingMoves.items.len) |i| {
        const move = p_startingMoves.items[i];

        p_state.makeMove(move);

        const score = -searchLoop(p_state, p_info, depth - 1, alpha, beta, useHash, useTexel, useQuiescence);

        _ = p_state.undoMove();

        if (i == 0 or p_info.currentBest.scoring < score) {
            p_info.currentBest.move = move;
            p_info.currentBest.scoring = score;
        }
    }
    p_info.running = false;
}
fn searchLoop(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, comptime useHash: bool, comptime useTexel: bool, comptime useQuiescence: bool) scoreType {
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());
    if (depth <= 0 or !p_info.running) {
        p_info.n_nodeExplored += 1;
        if (comptime useQuiescence) {
            if (p_state.getLastMove().isCapture()) {
                // perform quiesc
                return quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, alpha, beta);
            }
        }
        if (comptime useTexel) {
            const score = color_mask * heuristicl.texelEvaluation(p_state);
            return score;
        } else {
            const score = color_mask * heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
            return score;
        }
    }
    if (p_state.isStaleMateRepetition()) {
        if (comptime useHash) {
            const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.key, @intCast(depth), weightl.simpleStalemateScore);
            _ = hashl.hashTable.storeEntry(&s_entry);
            // might be useful for late game
            //hashl.hashTable.overwriteEvaluationEntries(&s_entry, heuristicl.simpleStalemateScore);
        }
        return weightl.simpleStalemateScore;
    }
    if (comptime useHash) {
        const entry = hashl.getEntryFromMatch(p_state.key, @intCast(depth));
        if (entry.valid) {
            p_info.n_hashRetrieve += 1;
            return color_mask * entry.eval();
        }
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    const indexes = heuristicl.eval_move_sorting_mask(&fmoves);
    var _alpha = alpha;
    var finalScore: scoreType = 0;
    for (0..fmoves.len) |i| {
        const idx = indexes[i];
        const move: IMove = fmoves.moves[idx];

        _ = p_state.makeMove(move);

        const score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, useHash, useTexel, useQuiescence);

        _ = p_state.undoMove();

        if (i == 0 or finalScore < score) {
            finalScore = score;
        }
        if (finalScore > _alpha) {
            _alpha = finalScore;
        }
        if (_alpha >= beta) {
            break;
        }
    }
    if (fmoves.len == 0) {
        if (!p_state.isLegal(p_state.whiteToMove())) {
            finalScore = -(weightl.simpleCheckMateScore + @as(scoreType, @intCast(depth)));
        } else {
            finalScore = weightl.simpleStalemateScore;
        }
    }
    if (comptime useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.key, @intCast(depth), color_mask * finalScore);
        _ = hashl.hashTable.storeEntry(&s_entry);
    }
    return finalScore;
}
pub fn quiescenceSearch(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType) scoreType {
    // first vers adapt of the pseudo code: https://www.chessprogramming.org/Quiescence_Search
    var _alpha = alpha;
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());
    const static_eval = color_mask * heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
    if (depth == 0 or !p_info.running) {
        p_info.n_nodeExplored += 1;
        return static_eval;
    }
    var best_value = static_eval;
    if (best_value >= beta) {
        return best_value;
    }
    if (best_value > _alpha) {
        _alpha = best_value;
    }
    const fmoves: moveContainer = moveGenl.generateLegalMoves_ordered(p_state, true);
    const indexes = heuristicl.eval_move_sorting_mask(&fmoves);
    for (0..fmoves.len) |i| {
        const idx = indexes[i];
        const move: IMove = fmoves.moves[idx];
        p_state.makeMove(move);

        const score = -quiescenceSearch(p_state, p_info, depth - 1, -beta, -_alpha);

        _ = p_state.undoMove();

        if (score >= beta) {
            return score;
        }
        if (score > _alpha) {
            _alpha = score;
        }
        if (score > best_value) {
            best_value = score;
        }
    }
    return best_value;
}
//pub fn seeCapture(p_board: *chess.Board_state, from: u8, to: u8, white: bool) scoreType {
//    var value: scoreType = 0;
//}
