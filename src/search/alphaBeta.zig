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
const zwsl = @import("zws.zig");
const pvsl = @import("pvs.zig");

const IMove = movel.IMove;
const pvContainer = movel.pvContainer;
const scoreType = heuristicl.scoreType;
const threadInfo = threadingl.threadInfo;

pub fn getScoreMaskFromTurn(white: bool) scoreType {
    if (white) {
        return 1;
    }
    return -1;
}

pub fn searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, p_features: *const schedulerl.searchFeatures, prevLine: *const movel.line) i8 {
    p_info.working = true;
    const alpha: scoreType = -weightl.simpleCheckMateScore;
    const beta: scoreType = weightl.simpleCheckMateScore;

    _ = p_startingMoves;
    var pv: pvContainer = .{};

    var score: scoreType = 0;

    switch (p_features.searchType) {
        .STD => {
            score = searchLoop(p_state, p_info, depth, alpha, beta, p_features, 0, &pv, prevLine, .PV);
        },
        .PVS => {
            score = pvsl.searchLoop(p_state, p_info, depth, alpha, beta, p_features, 0, &pv, prevLine, .PV);
        },
        .ZWS => {
            score = zwsl.searchLoop(p_state, p_info, p_features, &pv, prevLine, depth, 0, alpha, beta, .PV, false);
        },
    }

    const move = pv.pv_arr[0][0];
    p_info.currentBest.move = move;
    p_info.currentBest.scoring = score;
    p_info.currentBest.line.setLineFromPV(&pv);

    if (p_info.alive) {
        return 0;
    }
    // 1 is error
    return 1;
}
pub const searchType = enum { NonPV, PV };

fn searchLoop(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, p_features: *const schedulerl.searchFeatures, ply: u16, pv: *pvContainer, prevLine: *const movel.line, comptime t: searchType) scoreType {
    if (comptime t == .PV) {
        pv.setLen(ply);
    }
    var _alpha = alpha;
    if (p_state.isStaleMateRepetition()) {
        if (p_features.useHash) {
            const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.key, @intCast(depth), weightl.simpleStalemateScore);
            _ = hashl.hashTable.storeEntry(&s_entry, p_state.key.code);
        }
        return weightl.simpleStalemateScore;
    }

    if (depth <= 0 or !p_info.alive) {
        return handleTerminalState(p_state, p_info, alpha, beta, p_features, ply, pv, prevLine, t);
    }

    var hashMove: IMove = .{};
    var hashFlag: hashl.nodeType = .UPPER;
    if (p_features.useHash) {
        const entry = hashl.getEntryFromMatch(p_state.key, @intCast(depth));
        if (entry) |_entry| {
            p_info.searchStat.n_hashRetrieve += 1;
            hashMove = _entry.val.search.bestMove;
        }
    }

    // null move prunning here
    // R = 3
    const ischeck = p_state.isChecked();
    if (p_features.useNullPrune and ply != 0) {
        // see chess programming video
        const R: u16 = 2 + 1;
        if (depth > R and !ischeck and !p_state.isEndGame()) {
            p_state.makeNullMove();
            const score = -searchLoop(p_state, p_info, depth - R, -beta, 1 - beta, p_features, ply + R, pv, prevLine, .NonPV);
            p_state.undoNullMove();
            if (score >= beta) {
                p_info.searchStat.n_cutoffs += 1;
                return score;
            }
        }
    }
    var canFutility: bool = false;
    var static_eval: scoreType = 0;
    if (p_features.useFutility and !ischeck and @abs(alpha) < weightl.simpleCheckMateScore and heuristicl.sideCountScore(p_state, p_state.whiteToMove(), &heuristicl.globalHeuristic) > heuristicl.globalHeuristic.RookValue and depth <= 2) {
        static_eval = heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
        canFutility = (static_eval + heuristicl.futilityMargin[depth]) < _alpha;
    }
    const fmoves = moveGenl.generateLegalMoves(p_state);
    var order = heuristicl.eval_move_sorting_mask(p_state, &fmoves, ply, prevLine, hashMove, depth);
    var useLMR: bool = false;
    //https://www.chessprogramming.org/Late_Move_Reductions
    if (p_features.useLMR and depth > 3 and !ischeck) {
        heuristicl.computeLateMoveReduc(p_state, &order, depth, &fmoves);
        useLMR = true;
    }

    var finalScore: scoreType = 0;
    var bestMove: IMove = .{};
    for (0..fmoves.len) |i| {
        const idx = order.indexes[i];
        const move: IMove = fmoves.moves[idx];

        if (canFutility) {
            if (ply > 4 and !moveGenl.moveDeliverCheck(p_state, move) and !move.isCapture() and !move.isPromotion()) {
                continue;
            }
        }

        p_state.makeMove(move);

        var score: scoreType = 0;

        if (useLMR) {
            if (p_state.isChecked() or i <= 4) {
                score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
            } else {
                if (order.depths[i] != (depth - 1)) {
                    //score = -searchLoop(p_state, p_info, order.depths[i], -(_alpha + 1), -_alpha, p_features, ply + 1, pv, prevLine, t);
                    score = -searchLoop(p_state, p_info, order.depths[i], -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
                    if (score > _alpha) {
                        score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
                    }
                } else {
                    score = -searchLoop(p_state, p_info, order.depths[i], -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
                }
            }
        } else {
            score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
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
                heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), heuristicl.computeHistoryBonus(depth));
            }
        }
        if (_alpha >= beta) {
            // save here the killer moves
            if (!isCapture) {
                heuristicl.onKillerMove(move, ply);

                const bonus = heuristicl.computeHistoryBonus(depth);
                heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), bonus);
                for (0..fmoves.len) |j| {
                    const _move = fmoves.moves[j];
                    if (!_move.isCapture() and j != i) {
                        heuristicl.updateHistoryHeurist(p_state.whiteToMove(), _move.getFrom(), _move.getTo(), -bonus);
                    }
                }
            }
            if (p_features.useHash) {
                const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.key, @intCast(depth), finalScore, .LOWER, move);
                _ = hashl.hashTable.storeEntry(&s_entry, p_state.key.code);
            }
            p_info.searchStat.n_cutoffs += 1;
            return finalScore;
        }
    }
    if (fmoves.len == 0) {
        if (!p_state.isLegal(p_state.whiteToMove())) {
            finalScore = -(weightl.simpleCheckMateScore + @as(scoreType, @intCast(depth)));
        } else {
            finalScore = weightl.simpleStalemateScore;
        }
    } else {
        if (p_features.useHash) {
            const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.key, @intCast(depth), finalScore, hashFlag, bestMove);
            _ = hashl.hashTable.storeEntry(&s_entry, p_state.key.code);
        }
    }

    return finalScore;
}

pub fn handleTerminalState(p_state: *chess.Board_state, p_info: *threadInfo, alpha: scoreType, beta: scoreType, p_features: *const schedulerl.searchFeatures, ply: u16, pv: *pvContainer, prevLine: *const movel.line, comptime t: searchType) scoreType {
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());
    if (p_features.useHash) {
        const entry = hashl.getEntryFromMatch(p_state.key, 0);
        if (entry) |_entry| {
            p_info.searchStat.n_hashRetrieve += 1;
            return _entry.eval();
        }
    }
    p_info.searchStat.n_nodeExplored += 1;
    if (p_features.useQuiescence) {
        const ischeck = p_state.isChecked();
        if (p_state.getLastMove().isCapture() or ischeck) {
            // perform quiesc
            const score = quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, alpha, beta, ply, ischeck, pv, prevLine, t);
            if (p_features.useHash) {
                const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.key, 0, score);
                _ = hashl.hashTable.storeEntry(&s_entry, p_state.key.code);
            }
            return score;
        }
    }

    const score = color_mask * heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);

    if (p_features.useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.key, 0, score);
        _ = hashl.hashTable.storeEntry(&s_entry, p_state.key.code);
    }
    return score;
}

pub fn quiescenceSearch(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, ply: u16, wasChecked: bool, pv: *pvContainer, prevLine: *const movel.line, comptime t: searchType) scoreType {
    // first vers adapt of the pseudo code: https://www.chessprogramming.org/Quiescence_Search
    if (comptime t == .PV) {
        pv.setLen(ply);
    }
    var _alpha = alpha;
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());
    const static_eval = color_mask * heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);

    if (depth == 0 or !p_info.alive) {
        p_info.searchStat.n_nodeExplored += 1;
        return static_eval;
    }
    var best_value = static_eval;
    // stand pat https://www.chessprogramming.org/Quiescence_Search#StandPat
    if (best_value >= beta) {
        p_info.searchStat.n_cutoffs += 1;
        return best_value;
    }
    //https://www.chessprogramming.org/Delta_Pruning
    const BIG_DELTA = weightl.simpleQueenScore;

    if (best_value > _alpha) {
        if (comptime t == .PV) {
            pv.onBestMove(p_state.getLastMove(), ply - 1);
        }
        _alpha = best_value;
    }

    var gen: heuristicl.moveGenerator = heuristicl.moveGenerator.init();
    gen.fetchNext(p_state);
    const order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, prevLine, .{}, depth);
    var i: usize = 0;
    while (gen.pickNext(&order)) |move| : (i += 1) {
        //const fmoves = moveGenl.generateLegalMoves_capture(p_state);
        //for (0..fmoves.len) |i| {
        //const move = fmoves.moves[i];
        var _delta = BIG_DELTA;
        if (move.isPromotion()) {
            _delta += weightl.simpleQueenScore - 200;
        }
        // delta pruning
        if (static_eval < (_alpha - _delta)) {
            return _alpha;
        }

        // if move nor capture nor checking
        // problem here where a checking sequence ie
        // black checked -> white not checked nor capture = end of quiescence, the search might need to continue

        p_state.makeMove(move);

        const score = -quiescenceSearch(p_state, p_info, depth - 1, -beta, -_alpha, ply + 1, wasChecked, pv, prevLine, t);

        _ = p_state.undoMove();

        if (i == 0 or score > best_value) {
            best_value = score;
        }
        if (score >= beta) {
            p_info.searchStat.n_cutoffs += 1;
            return score;
        }
        if (score > _alpha) {
            _alpha = score;
            if (comptime t == .PV) {
                pv.onBestMove(move, ply);
            }
        }
    }
    return best_value;
}
