const std = @import("std");

const chess = @import("../chess.zig");
const movel = @import("../move.zig");
const moveGenl = @import("../move_generation.zig");
const heuristicl = @import("../heuristic.zig");
const weightl = @import("../weights.zig");
const hashl = @import("../hashTable.zig");
const configl = @import("../config.zig");
const threadingl = @import("threading.zig");
const schedulerl = @import("scheduler.zig");
const alphaBetal = @import("alphaBeta.zig");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const pvContainer = movel.pvContainer;
const scoreType = heuristicl.scoreType;
const moveDecisionExt = schedulerl.moveDecisionExt;
const searchFeatures = schedulerl.searchFeatures;
const threadInfo = threadingl.threadInfo;

//https://www.chessprogramming.org/Principal_Variation_Search#cite_note-23
pub fn searchLoop(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, p_features: *const searchFeatures, ply: u16, pv: *pvContainer, prevLine: *const movel.line, comptime t: alphaBetal.searchType) scoreType {
    if (comptime t == .PV) {
        pv.setLen(ply);
    }
    var _alpha = alpha;
    var _depth = depth;
    if (false)
        _depth += 1;
    if (p_state.isStaleMateRepetition()) {
        return weightl.simpleStalemateScore;
    }

    if (_depth <= 0 or !p_info.alive) {
        return alphaBetal.handleTerminalState(p_state, p_info, alpha, beta, p_features, ply, pv, prevLine, t);
    }

    var hashMove: IMove = .{};
    var hashFlag: hashl.nodeType = .UPPER;
    if (p_features.useHash) {
        const entry = hashl.getEntryFromMatch(p_state.key, @intCast(_depth));
        if (entry) |_entry| {
            p_info.searchStat.n_hashRetrieve += 1;
            if (comptime t == .NonPV) {
                if (_entry.val.search.nodeT() == .LOWER and ply != 0) {
                    return _entry.eval();
                }
            }
            hashMove = _entry.val.search.bestMove;
        }
    }

    // null move prunning here
    // R = 3
    const ischeck = p_state.isChecked();
    if (p_features.useNullPrune and ply != 0) {
        // see chess programming video
        const R: u16 = 2 + 1;
        if (_depth > R and !ischeck and !p_state.isEndGame()) {
            p_state.makeNullMove();
            const score = -searchLoop(p_state, p_info, _depth - R, -beta, 1 - beta, p_features, ply + R, pv, prevLine, .NonPV);
            p_state.undoNullMove();
            if (score >= beta) {
                p_info.searchStat.n_cutoffs += 1;
                return score;
            }
        }
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    var order = heuristicl.eval_move_sorting_mask(p_state, &fmoves, ply, prevLine, hashMove, _depth);
    var useLMR: bool = false;
    //https://www.chessprogramming.org/Late_Move_Reductions
    if (p_features.useLMR and _depth > 3 and !ischeck) {
        heuristicl.computeLateMoveReduc(p_state, &order, _depth, &fmoves);
        useLMR = true;
    }
    const futilityPrune: bool = false;
    var reverseFutilityP: bool = false;
    var static_eval: scoreType = 0;
    var mb: scoreType = 0;
    if (p_features.useFutility) {
        //if (_depth > 1 and _depth <= 4 and !ischeck) {
        //    static_eval = heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
        //    if (static_eval <= (_alpha - heuristicl.e_pieceToHeuristic(p_state.firstPiece(!p_state.whiteToMove()), &heuristicl.globalHeuristic) - heuristicl.e_pieceToHeuristic(p_state.secondPiece(!p_state.whiteToMove()), &heuristicl.globalHeuristic) - 2 * heuristicl.futilityMargin[_depth])) {
        //        futilityPrune = true;
        //    }
        //}
        if (!ischeck and t != .PV and _depth == 3 and @abs(beta) < weightl.simpleCheckMateScore) {
            reverseFutilityP = true;
            if (!futilityPrune) {
                static_eval = heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
            }
            mb = heuristicl.materialImbalance(p_state, &heuristicl.globalHeuristic);
        }
    }
    if (p_features.useRazoring) {
        //https://www.chessprogramming.org/Razoring limited razoring
        const eval = heuristicl.materialImbalance(p_state, &heuristicl.globalHeuristic) + heuristicl.futilityMargin[2];
        if (_depth == 3 and eval <= _alpha and p_state.getBigPieceCount(!p_state.whiteToMove()) > 3) {
            _depth = 2;
        }
        //const eval = heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
        //if (eval < (_alpha - 512 - 293 * depth * depth)) {
        //    const value = alphaBetal.quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, _alpha - 1, _alpha, p_features, ply, p_state.isChecked(), pv, prevLine, .NonPV);
        //    if (value < _alpha and @abs(value) < weightl.simpleCheckMateScore) {
        //        return value;
        //    }
        //}

    }

    var finalScore: scoreType = 0;
    var bestMove: IMove = .{};
    //const margin = 150 * _depth;
    for (0..fmoves.len) |i| {
        const idx = order.indexes[i];
        const move: IMove = fmoves.moves[idx];
        //if (futilityPrune and !moveGenl.moveDeliverCheck(p_state, move) and !move.isCapture() and !move.isPromotion()) {
        //    continue;
        //}
        //if (reverseFutilityP) {
        //    const _see = heuristicl.SEE(p_state, move);
        //    if ((mb + _see) >= (beta + margin)) {
        //        return (mb + _see);
        //    }
        //}
        _ = p_state.makeMove(move);

        var score: scoreType = 0;
        if (i == 0) {
            score = -searchLoop(p_state, p_info, _depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
        } else {
            //if (useLMR and (order.depths[i] != (_depth - 1))) {
            //    score = -searchLoop(p_state, p_info, order.depths[i], -_alpha - 1, -_alpha, p_features, ply + 1, pv, prevLine, .NonPV);
            //} else {
            //    score = _alpha + 1;
            //}
            score = _alpha + 1;
            if (score > _alpha) {
                score = -searchLoop(p_state, p_info, _depth - 1, -_alpha - 1, -_alpha, p_features, ply + 1, pv, prevLine, .NonPV);
            }

            //if (score > _alpha and ((beta - _alpha) > 1)) {
            //https://web.archive.org/web/20150212051846/http://www.glaurungchess.com/lmr.html
            if (score > _alpha and score < beta) {
                score = -searchLoop(p_state, p_info, _depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, .PV);
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
            hashFlag = .ALL;
            if (comptime t == .PV) {
                pv.onBestMove(move, ply);
            }
            if (!isCapture) {
                heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), heuristicl.computeHistoryBonus(_depth));
            }
        }
        if (_alpha >= beta) {
            // save here the killer moves
            heuristicl.onKillerMove(move, ply);

            const bonus = heuristicl.computeHistoryBonus(_depth);
            heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), bonus);
            for (0..fmoves.len) |j| {
                const _move = fmoves.moves[j];
                if (!_move.isCapture() and j != i) {
                    heuristicl.updateHistoryHeurist(p_state.whiteToMove(), _move.getFrom(), _move.getTo(), -bonus);
                }
            }
            if (p_features.useHash) {
                const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.key, @intCast(_depth), beta, .LOWER, move);
                _ = hashl.hashTable.storeEntry(&s_entry, p_state.key.code);
            }

            p_info.searchStat.n_cutoffs += 1;
            return beta;
        }
    }
    if (fmoves.len == 0) {
        if (!p_state.isLegal(p_state.whiteToMove())) {
            _alpha = -(weightl.simpleCheckMateScore + @as(scoreType, @intCast(_depth)));
        } else {
            _alpha = weightl.simpleStalemateScore;
        }
    }

    if (p_features.useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.key, @intCast(_depth), _alpha, hashFlag, bestMove);
        _ = hashl.hashTable.storeEntry(&s_entry, p_state.key.code);
    }

    return _alpha;
}
