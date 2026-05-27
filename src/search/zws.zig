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
const boardl = @import("../board.zig");

const IMove = movel.IMove;
const scoreType = heuristicl.scoreType;
const searchStack = alphaBetal.searchStack;

//https://www.chessprogramming.org/Principal_Variation_Search#cite_note-23
pub fn searchLoop(p_state: *boardl.boardState, p_info: *threadingl.threadInfo, p_features: *const schedulerl.searchFeatures, pv: *movel.pvContainer, depth: u16, ply: u16, alpha: scoreType, beta: scoreType, comptime t: alphaBetal.searchType, ss: *searchStack) scoreType {
    if (comptime t == .PV) {
        pv.setLen(ply);
    }
    var _alpha = alpha;
    var _depth = depth;
    const white: bool = p_state.whiteToMove();
    if (p_state.isStaleMateRepetition()) {
        return weightl.simpleStalemateScore;
    }
    var finalScore: scoreType = 0;
    var bestMove: IMove = .{};
    var hashMove: IMove = .{};
    var hashFlag: hashl.nodeType = .UPPER;
    const skipQuietMoves: bool = false;
    if (p_features.useHash and depth > 2) {
        const entry = hashl.getEntryFromMatch(p_state.frame.key, @intCast(_depth));
        if (entry) |_entry| {
            p_info.searchStat.n_hashRetrieve += 1;
            //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
            if (comptime t == .NonPV) {
                const tmp = _entry.val.search.nodeT();
                const eval = _entry.eval();
                if (tmp == .ALL) {
                    return eval;
                } else if (tmp == .LOWER) {
                    if (eval >= beta) {
                        return eval;
                    }
                } else if (tmp == .UPPER) {
                    if (eval >= _alpha) {
                        return eval;
                    }
                }
            }
            hashMove = _entry.val.search.bestMove;
        }
    }

    if (_depth == 0 or !p_info.alive) {
        return alphaBetal.handleTerminalState(p_state, p_info, alpha, beta, p_features, ply, pv, t, ss);
    }
    const f: boardl.boardFrame = .copy(p_state);
    var currS = ss.getFrame(ply);
    const static_eval = heuristicl.c_evaluate(p_state, &heuristicl.globalHeuristic, white);
    currS.staticEval = .{ .s = static_eval, .t = .STD };
    const ischeck = p_state.isChecked();

    var improving: bool = false;
    if (ischeck) {
        //
    } else if (ss.getPrevFrame(ply, 2).staticEval.t != .NONE) {
        improving = currS.staticEval.s > ss.getPrevFrame(ply, 2).staticEval.s;
    } else if (ss.getPrevFrame(ply, 4).staticEval.t != .NONE) {
        improving = currS.staticEval.s > ss.getPrevFrame(ply, 4).staticEval.s;
    } else {
        improving = true;
    }

    // null move prunning here
    // R = 3
    const isEndGame = p_state.isEndGame();
    if (p_features.useNullPrune and ply != 0) {
        // see chess programming video
        const R: u16 = if (improving) (2 + 1) else 4;
        if (_depth > R and !ischeck and !isEndGame) {
            p_state.makeNullMove();
            const score = -searchLoop(p_state, p_info, p_features, pv, _depth - R, ply + R, -beta, 1 - beta, .NonPV, ss);
            p_state.undoNullMove();
            p_state.frame = f;
            if (score >= beta) {
                p_info.searchStat.n_cutoffs += 1;
                return score;
            }
        }
    }

    // staged
    var gen: heuristicl.moveGenerator = heuristicl.moveGenerator.init();
    gen.fetchNext(p_state);
    // captures are now in
    var useLMR = false;
    var hashMoveIsQuiet: bool = false;
    if (hashMove.isValid()) {
        if (hashMove.isQuietMove()) {
            gen.moves.append(hashMove);
            hashMoveIsQuiet = true;
        }
    }
    var order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, hashMove, _depth, currS.prevLineMove);

    if (p_features.useLMR and _depth > 3 and !ischeck) {
        heuristicl.computeLateMoveReduc(p_state, &order, _depth, &gen.moves);
        useLMR = true;
    }
    //https://www.talkchess.com/forum3/viewtopic.php?f=7&t=74403
    var canFutility: bool = false;
    var futilityScore: scoreType = 0;
    if (p_features.useFutility and !ischeck and @abs(alpha) < weightl.simpleCheckMateScore and _depth == 1 and comptime t == .NonPV) {
        const margin: scoreType = if (improving) heuristicl.futilityMargin else 100;
        futilityScore = heuristicl.c_materialImbalance(p_state, &heuristicl.globalHeuristic, white) + margin;
        canFutility = true;
    }

    if (!ischeck and comptime t == .NonPV) {
        //https://www.chessprogramming.org/Razoring limited razoring
        const margin: scoreType = if (improving) 300 else 100;
        if (p_features.useRFP and _depth == 2) {
            if (currS.staticEval.getScore() >= (beta + margin)) {
                return (currS.staticEval.getScore() + beta) >> 1;
            }
        }
        if (p_features.useRazoring) {
            const eval = heuristicl.c_materialImbalance(p_state, &heuristicl.globalHeuristic, white);
            if (_depth == 3 and (eval + 600) <= _alpha and p_state.getTotalPieceCount(!white) > 3) {
                _depth = 2;
            }
        }
    }

    var i: usize = 0;
    var tot: usize = 0;

    if (gen.moves.len == 0) {
        gen.fetchNext(p_state);
        order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, hashMove, _depth, currS.prevLineMove);
        if (useLMR) {
            heuristicl.computeLateMoveReduc(p_state, &order, _depth, &gen.moves);
        }
    }
    var i_reset: bool = false;
    while (gen.pickNext(&order)) |move| : (i += 1) {
        if (!skipQuietMoves and i == (gen.moves.len - 1) and gen.extra == .CAPTURES) {
            gen.fetchNext(p_state);
            order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, hashMove, _depth, currS.prevLineMove);

            if (useLMR) {
                heuristicl.computeLateMoveReduc(p_state, &order, _depth, &gen.moves);
            }
            i_reset = true;
        } else if (i_reset) {
            i = 0;
            i_reset = false;
            if (hashMoveIsQuiet) {
                continue;
            }
        }
        if (canFutility) {
            if (!moveGenl.moveDeliverCheck(p_state, move) and (futilityScore + heuristicl.mat_gain(p_state, move)) < _alpha and tot > 4 and !move.isPromotion()) {
                continue;
            }
        }

        _ = p_state.makeMove(move);

        var score: scoreType = 0;
        if (i == 0) {
            score = -searchLoop(p_state, p_info, p_features, pv, _depth - 1, ply + 1, -beta, -_alpha, t, ss);
        } else {
            if (useLMR and (order.depths[i] < (_depth - 1))) {
                score = -searchLoop(p_state, p_info, p_features, pv, order.depths[i], ply + 1, -_alpha - 1, -_alpha, .NonPV, ss);
            } else {
                score = _alpha + 1;
            }
            if (score > _alpha) {
                score = -searchLoop(p_state, p_info, p_features, pv, _depth - 1, ply + 1, -_alpha - 1, -_alpha, .NonPV, ss);
            }

            //https://web.archive.org/web/20150212051846/http://www.glaurungchess.com/lmr.html
            if (score > _alpha and comptime t == .PV) {
                score = -searchLoop(p_state, p_info, p_features, pv, _depth - 1, ply + 1, -beta, -_alpha, .PV, ss);
            }
        }

        _ = p_state.undoMove();
        p_state.frame = f;

        if (tot == 0 or finalScore < score) {
            finalScore = score;
            bestMove = move;
            if (ply == 0) {
                pv.onBestMove(move, ply);
            }
        }
        if (finalScore > _alpha) {
            _alpha = finalScore;
            hashFlag = .ALL;
            if (comptime t == .PV) {
                pv.onBestMove(move, ply);
            }
            if (!(gen.extra == .CAPTURES)) {
                heuristicl.updateHistoryHeurist(white, move.getFrom(), move.getTo(), heuristicl.computeHistoryBonus(_depth));
            }
        }
        if (_alpha >= beta) {
            // save here the killer moves
            if (!(gen.extra == .CAPTURES)) {
                heuristicl.onKillerMove(move, ply);
            }

            const bonus = heuristicl.computeHistoryBonus(_depth);
            heuristicl.updateHistoryHeurist(white, move.getFrom(), move.getTo(), bonus);
            for (0..gen.moves.len) |j| {
                const idx = order.indexes[j];
                const _move = gen.moves.moves[idx];
                if (!_move.isCapture() and j != i) {
                    heuristicl.updateHistoryHeurist(white, _move.getFrom(), _move.getTo(), -bonus);
                }
            }
            if (p_features.useHash) {
                const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), _alpha, .LOWER, move);
                _ = hashl.hashTable.storeEntry(&s_entry, p_state.frame.key.code);
            }

            p_info.searchStat.n_cutoffs += 1;
            return _alpha;
        }
        tot += 1;
    }
    if (tot == 0) {
        if (p_state.isChecked()) {
            _alpha = -(weightl.simpleCheckMateScore + @as(scoreType, @intCast(_depth)));
        } else {
            _alpha = weightl.simpleStalemateScore;
        }
    }
    if (p_features.useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), _alpha, hashFlag, bestMove);
        _ = hashl.hashTable.storeEntry(&s_entry, p_state.frame.key.code);
    }

    return _alpha;
}
