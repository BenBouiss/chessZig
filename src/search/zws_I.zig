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
    if (false) {
        _depth += 1;
    }
    if (p_state.isStaleMateRepetition()) {
        return weightl.simpleStalemateScore;
    }
    if (_depth <= 0 or !p_info.alive) {
        return alphaBetal.handleTerminalState(p_state, p_info, alpha, beta, p_features, ply, pv, prevLine, t);
    }

    var finalScore: scoreType = 0;
    var bestMove: IMove = .{};
    var hashMove: IMove = .{};
    if (p_features.useHash) {
        const entry = hashl.getEntryFromMatch(p_state.key, @intCast(_depth));
        if (entry) |_entry| {
            p_info.searchStat.n_hashRetrieve += 1;
            if (comptime t == .NonPV) {
                if (_entry.val.search.t == .CUT and ply != 0) {
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

    // staged
    var gen: heuristicl.moveGenerator = heuristicl.moveGenerator.init();
    gen.fetchNext(p_state);
    // captures are now in
    var useLMR = false;
    var order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, prevLine, p_features, hashMove, _depth);

    if (p_features.useLMR and _depth > 3 and !ischeck) {
        heuristicl.computeLateMoveReduc(p_state, &order, _depth, &gen.moves);
        useLMR = true;
    }

    var i: usize = 0;
    var tot: usize = 0;
    var captureOnly: bool = true;
    if (gen.moves.len == 0) {
        gen.fetchNext(p_state);
        order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, prevLine, p_features, hashMove, _depth);
        captureOnly = false;
        if (useLMR) {
            heuristicl.computeLateMoveReduc(p_state, &order, _depth, &gen.moves);
        }
    }
    while (gen.pickNext(&order)) |move| : (i += 1) {
        //std.debug.assert(move.isValid());
        if (i == (gen.moves.len - 1) and gen.extra == .CAPTURES) {
            gen.fetchNext(p_state);
            order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, prevLine, p_features, hashMove, _depth);

            if (useLMR) {
                heuristicl.computeLateMoveReduc(p_state, &order, _depth, &gen.moves);
            }
            i = 0;
        }

        _ = p_state.makeMove(move);

        var score: scoreType = 0;
        if (i == 0) {
            //std.debug.print("First i {s} {d} ply {d} a {d} b {d}\n", .{ move.getStr(), _depth - 1, ply + 1, -beta, -_alpha });
            score = -searchLoop(p_state, p_info, _depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
        } else {
            if (useLMR and (order.depths[i] != (_depth - 1))) {
                score = -searchLoop(p_state, p_info, order.depths[i], -_alpha - 1, -_alpha, p_features, ply + 1, pv, prevLine, .NonPV);
            } else {
                score = _alpha + 1;
            }
            if (score > _alpha) {
                //std.debug.print("other i {s} nonPv({d}) {d} ply {d} a {d} b {d}\n", .{ move.getStr(), i, _depth - 1, ply + 1, -beta, -_alpha });
                score = -searchLoop(p_state, p_info, _depth - 1, -_alpha - 1, -_alpha, p_features, ply + 1, pv, prevLine, .NonPV);
            }

            //https://web.archive.org/web/20150212051846/http://www.glaurungchess.com/lmr.html
            if (score > _alpha and score < beta) {
                //std.debug.print("other i {d}\n", .{_depth - 1});
                //if (score > _alpha and ((beta - _alpha) > 1)) {
                score = -searchLoop(p_state, p_info, _depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, .PV);
            }
        }

        _ = p_state.undoMove();

        if (tot == 0 or finalScore < score) {
            finalScore = score;
            bestMove = move;
            if (tot == 0 and ply == 0 and comptime t == .PV) {
                pv.onBestMove(move, ply);
            }
        }
        if (finalScore > _alpha) {
            _alpha = finalScore;
            if (comptime t == .PV) {
                pv.onBestMove(move, ply);
            }
            if (captureOnly) {
                heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), heuristicl.computeHistoryBonus(_depth));
            }
        }
        if (_alpha >= beta) {
            // save here the killer moves
            heuristicl.onKillerMove(move, ply);

            const bonus = heuristicl.computeHistoryBonus(_depth);
            heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), bonus);
            for (0..gen.moves.len) |j| {
                const idx = order.indexes[j];
                const _move = gen.moves.moves[idx];
                if (!_move.isCapture() and j != i) {
                    heuristicl.updateHistoryHeurist(p_state.whiteToMove(), _move.getFrom(), _move.getTo(), -bonus);
                }
            }
            if (p_features.useHash) {
                const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.key, @intCast(_depth), beta, .CUT, move);
                _ = hashl.hashTable.storeEntry(&s_entry);
            }

            p_info.searchStat.n_cutoffs += 1;
            return _alpha;
        }
        tot += 1;
    }
    if (tot == 0) {
        //if (p_state.isChecked()) {
        if (!p_state.isLegal(p_state.whiteToMove())) {
            _alpha = -(weightl.simpleCheckMateScore + @as(scoreType, @intCast(_depth)));
        } else {
            _alpha = weightl.simpleStalemateScore;
        }
    }

    return _alpha;
}
