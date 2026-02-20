// line version of the alpha beta algo
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
const lineContainer = movel.lineContainer;
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
    var pv_array = std.mem.zeroes([configl.MAXIMUM_SEARCH_DEPTH][configl.MAXIMUM_SEARCH_DEPTH]IMove);
    var pv_length = std.mem.zeroes([configl.MAXIMUM_SEARCH_DEPTH]usize);

    for (0..p_startingMoves.items.len) |i| {
        const move = p_startingMoves.items[i];

        p_state.makeMove(move);

        const score = -searchLoop(p_state, p_info, depth - 1, alpha, beta, useHash, useTexel, useQuiescence, 0, &pv_array, &pv_length);

        _ = p_state.undoMove();

        if (i == 0 or p_info.currentBest.scoring < score) {
            p_info.currentBest.move = move;
            p_info.currentBest.scoring = score;
        }
        std.debug.print("{s} Line obtained: ", .{move.getStr()});
        for (0..configl.MAXIMUM_SEARCH_DEPTH) |n| {
            const m = pv_array[n][n];
            if (!m.isValid()) {
                std.debug.print("cutting'{s}', ", .{m.getStr()});
                break;
            }
            std.debug.print("{s}, ", .{m.getStr()});
        }
        std.debug.print("\n", .{});
    }
    p_info.running = false;
}
fn searchLoop(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, comptime useHash: bool, comptime useTexel: bool, comptime useQuiescence: bool, ply: u16, pv_arr: *[configl.MAXIMUM_SEARCH_DEPTH][configl.MAXIMUM_SEARCH_DEPTH]IMove, pv_len: *[configl.MAXIMUM_SEARCH_DEPTH]usize) scoreType {
    pv_len[ply] = ply;
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());
    if (depth <= 0 or !p_info.running) {
        p_info.n_nodeExplored += 1;
        if (comptime useQuiescence) {
            if (p_state.getLastMove().isCapture()) {
                // perform quiesc
                return quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, alpha, beta, ply);
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
    const indexes = heuristicl.eval_move_sorting_mask(&fmoves, ply);
    var _alpha = alpha;
    var finalScore: scoreType = 0;
    for (0..fmoves.len) |i| {
        const idx = indexes[i];
        const move: IMove = fmoves.moves[idx];

        _ = p_state.makeMove(move);

        const score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, useHash, useTexel, useQuiescence, ply + 1, pv_arr, pv_len);

        _ = p_state.undoMove();

        if (i == 0 or finalScore < score) {
            finalScore = score;
        }
        if (finalScore > _alpha) {
            _alpha = finalScore;

            pv_arr[ply][ply] = move;
            for (ply + 1..pv_len[ply + 1]) |next_p| {
                pv_arr[ply][next_p] = pv_arr[ply + 1][next_p];
            }
            pv_len[ply] = pv_len[ply + 1];

            if (!move.isCapture()) {
                heuristicl.historyHeuristic[@intFromBool(p_state.whiteToMove())][move.getFrom()][move.getTo()] += depth;
            }
        }
        if (_alpha >= beta) {
            // save here the killer moves
            if (!move.isCapture()) {
                heuristicl.killerMoves[ply][0] = heuristicl.killerMoves[ply][0];
                heuristicl.killerMoves[ply][1] = move;
            }
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
pub fn quiescenceSearch(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, ply: u16) scoreType {
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
    const indexes = heuristicl.eval_move_sorting_mask(&fmoves, ply);
    for (0..fmoves.len) |i| {
        const idx = indexes[i];
        const move: IMove = fmoves.moves[idx];
        p_state.makeMove(move);

        const score = -quiescenceSearch(p_state, p_info, depth - 1, -beta, -_alpha, ply + 1);

        _ = p_state.undoMove();

        if (score >= beta) {
            if (!move.isCapture()) {
                heuristicl.killerMoves[ply][0] = heuristicl.killerMoves[ply][0];
                heuristicl.killerMoves[ply][1] = move;
            }
            return score;
        }
        if (score > _alpha) {
            _alpha = score;
            if (!move.isCapture()) {
                heuristicl.historyHeuristic[@intFromBool(p_state.whiteToMove())][move.getFrom()][move.getTo()] += depth;
            }
        }
        if (score > best_value) {
            best_value = score;
        }
    }
    return best_value;
}
