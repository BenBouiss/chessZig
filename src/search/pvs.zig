const std = @import("std");

const chess = @import("../chess.zig");
const movel = @import("../move.zig");
const moveGenl = @import("../move_generation.zig");
const heuristicl = @import("../heuristic.zig");
const weightl = @import("../weights.zig");
const hashl = @import("../hashTable.zig");
const utilsl = @import("../utils.zig");
const configl = @import("../config.zig");

const threadingl = @import("threading.zig");
const schedulerl = @import("scheduler.zig");
const alphaBetal = @import("alphaBeta.zig");
const zwsl = @import("zws.zig");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const pvContainer = movel.pvContainer;

const scoreType = heuristicl.scoreType;

const moveDecisionExt = schedulerl.moveDecisionExt;
const searchFeatures = schedulerl.searchFeatures;

const threadInfo = threadingl.threadInfo;

pub fn searchLoop(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, p_features: *const searchFeatures, ply: u16, pv: *pvContainer, prevLine: *const movel.line, comptime t: alphaBetal.searchType) scoreType {
    if (comptime t == .PV) {
        pv.setLen(ply);
    }
    var _alpha = alpha;
    if (p_state.isStaleMateRepetition()) {
        if (p_features.useHash) {
            const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.key, @intCast(depth), weightl.simpleStalemateScore);
            _ = hashl.hashTable.storeEntry(&s_entry);
            // might be useful for late game
            //hashl.hashTable.overwriteEvaluationEntries(&s_entry, heuristicl.simpleStalemateScore);
        }
        return weightl.simpleStalemateScore;
    }

    if (depth <= 0 or !p_info.alive) {
        return alphaBetal.handleTerminalState(p_state, p_info, alpha, beta, p_features, ply, pv, prevLine);
    }

    var hashMove: IMove = .{};
    if (p_features.useHash) {
        const entry = hashl.getEntryFromMatch(p_state.key, @intCast(depth));
        if (entry.valid) {
            p_info.searchStat.n_hashRetrieve += 1;
            //if (entry.val.search.t == .CUT) {
            //    return entry.eval();
            //}
            hashMove = entry.val.search.bestMove;
        }
    }

    // null move prunning here
    // R = 3
    if (p_features.useNullPrune) {
        // see chess programming video
        const R: u16 = 2 + 1;
        const ischeck = p_state.isChecked();
        if (depth > R and !ischeck and !p_state.isEndGame() and ply > 0) {
            p_state.makeNullMove();
            const score = -searchLoop(p_state, p_info, depth - R, -beta, 1 - beta, p_features, ply + R, pv, prevLine, .NonPV);
            p_state.undoNullMove();
            if (score >= beta) {
                p_info.searchStat.n_cutoffs += 1;
                return score;
            }
        }
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    var order = heuristicl.eval_move_sorting_mask(p_state, &fmoves, ply, prevLine, p_features, hashMove);
    var useLMR: bool = false;
    //https://www.chessprogramming.org/Late_Move_Reductions
    if (p_features.useLateMoveReduc and depth > 3) {
        heuristicl.computeLateMoveReduc(p_state, &order, depth, &fmoves);
        useLMR = true;
    }

    var finalScore: scoreType = 0;
    var bestMove: IMove = .{};
    for (0..fmoves.len) |i| {
        const idx = order.indexes[i];
        const move: IMove = fmoves.moves[idx];

        _ = p_state.makeMove(move);

        var score: scoreType = 0;
        if (i == 0) {
            score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
        } else {
            score = -searchLoop(p_state, p_info, depth - 1, -_alpha - 1, -_alpha, p_features, ply + 1, pv, prevLine, t);
            if (score > _alpha and ((beta - _alpha) > 1)) {
                score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
            }
        }

        _ = p_state.undoMove();

        const isCapture = move.isCapture();
        if (i == 0 or finalScore < score) {
            finalScore = score;
            bestMove = move;
            if (i == 0 and ply == 0 and comptime t == .PV) {
                pv.onBestMove(move, ply);
            }
        }
        // under no possible scenario can this become >=, the resulting engines only produce drawn games amongst themselves
        if (finalScore > _alpha) {
            _alpha = finalScore;
            if (comptime t == .PV) {
                pv.onBestMove(move, ply);
            }

            if (!isCapture) {
                heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), heuristicl.computeHistoryBonus(depth));
            }
        }
        if (_alpha >= beta) {
            // save here the killer moves
            if (!isCapture) {
                heuristicl.killerMoves[ply][1] = heuristicl.killerMoves[ply][0];
                heuristicl.killerMoves[ply][0] = move;
            }
            if (p_features.useHash) {
                const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.key, @intCast(depth), finalScore, .CUT, move);
                _ = hashl.hashTable.storeEntry(&s_entry);
            }
            p_info.searchStat.n_cutoffs += 1;
            return beta;
        }
    }
    if (fmoves.len == 0) {
        if (!p_state.isLegal(p_state.whiteToMove())) {
            finalScore = -(weightl.simpleCheckMateScore + @as(scoreType, @intCast(depth)));
        } else {
            finalScore = weightl.simpleStalemateScore;
        }
    }
    if (p_features.useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.key, @intCast(depth), finalScore, .PV, bestMove);
        _ = hashl.hashTable.storeEntry(&s_entry);
    }
    return finalScore;
}
