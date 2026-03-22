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
const zwsl = @import("zws.zig");
const pvsl = @import("pvs.zig");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const pvContainer = movel.pvContainer;

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
pub const depthCommunication = struct {
    depth: u16 = 0,
    line: movel.line = .{},
    depthSet: bool = false,
    lock: bool = false,
    pub fn acquireLock(p_self: *depthCommunication) void {
        var cumulTime: u64 = 0;
        while (p_self.lock) {
            if (cumulTime > configl.DEBUG_INACTIVITY_READING_NS) {
                std.debug.print("[INACTIVITY] inputThreading.engine: no activity found in the last {d}s \n", .{configl.DEBUG_INACTIVITY_READING_S});
                cumulTime = 0;
            }
        }
        p_self.lock = true;
    }
    pub fn releaseLock(p_self: *depthCommunication) void {
        p_self.lock = false;
    }
    pub fn setDepth(p_self: *depthCommunication, depth: u16) void {
        p_self.acquireLock();
        if (p_self.depthSet) {
            // if this hits, it means that a search was already set, and a new one was ordered while the previous one is still ongoing
            @panic("???");
        }
        p_self.depth = depth;
        p_self.depthSet = true;
        p_self.releaseLock();
    }
    pub fn setLine(p_self: *depthCommunication, line: *const movel.line) void {
        p_self.acquireLock();
        p_self.line = line.*;
        p_self.releaseLock();
    }
};

pub fn alphaBetaWaitingRoom(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depthCom: *depthCommunication, feat: searchFeatures) void {
    while (p_info.alive) {
        // for some reason if this function gets updated too fast the scheduler gets bricked in the handleInterrupt method
        // trying to join on a thread with p_info.alive = false?
        // FIXME: ???

        std.Thread.sleep(configl.WR_TICKRATE_NS);
        // wait for a depth to be submitted
        //std.Thread.sleep(10 * configl.WR_TICKRATE_NS);
        if (!depthCom.depthSet) {
            continue;
        }
        //std.debug.print("starting search {} depth\n", .{depthCom.depth});
        depthCom.depthSet = false;
        if (searchEntrypoint(p_state, p_startingMoves, p_info, depthCom.depth, &feat, &depthCom.line) == 1) {
            std.debug.print("[ERROR] alphaBetaWaitingRoom: Exiting main thread\n", .{});
            break;
        }
    }
}

pub fn searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, p_features: *const searchFeatures, prevLine: *const movel.line) i8 {
    p_info.working = true;
    defer p_info.working = false;
    const alpha: scoreType = -weightl.simpleCheckMateScore;
    const beta: scoreType = weightl.simpleCheckMateScore;

    _ = p_startingMoves;
    var pv: pvContainer = .{};

    var score: scoreType = 0;

    switch (configl.DEFAULT_SEARCH_TYPE) {
        .STD => {
            score = searchLoop(p_state, p_info, depth, alpha, beta, p_features, 0, &pv, prevLine, .PV);
        },
        .PVS => {
            score = pvsl.searchLoop(p_state, p_info, depth, alpha, beta, p_features, 0, &pv, prevLine, .PV);
        },
        .ZWS => {
            score = zwsl.searchLoop(p_state, p_info, depth, alpha, beta, p_features, 0, &pv, prevLine, .PV);
        },

        .ASPIRATION => {
            score = searchLoop_aspirationPvs(p_state, p_info, depth, alpha, beta, p_features, 0, &pv, prevLine);
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

fn searchLoop(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, p_features: *const searchFeatures, ply: u16, pv: *pvContainer, prevLine: *const movel.line, comptime t: searchType) scoreType {
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
        return handleTerminalState(p_state, p_info, alpha, beta, p_features, ply, pv, prevLine);
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

        p_state.makeMove(move);

        var score: scoreType = 0;
        if (useLMR) {
            if (p_state.isChecked()) {
                score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
            } else {
                score = -searchLoop(p_state, p_info, order.depths[i] - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine, t);
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
            if (comptime t == .PV) {
                pv.onBestMove(move, ply);
            }
            if (!isCapture) {
                heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), depth * depth);
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
                const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.key, @intCast(depth), finalScore, .CUT, move);
                _ = hashl.hashTable.storeEntry(&s_entry);
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
    }
    if (p_features.useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.key, @intCast(depth), finalScore, .PV, bestMove);
        _ = hashl.hashTable.storeEntry(&s_entry);
    }
    return finalScore;
}

//https://www.chessprogramming.org/Principal_Variation_Search#cite_note-23
fn searchLoop_aspirationPvs(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, p_features: *const searchFeatures, ply: u16, pv: *pvContainer, prevLine: *const movel.line) scoreType {
    pv.setLen(ply);
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
        p_info.searchStat.n_nodeExplored += 1;
        const ischeck = p_state.isChecked();
        // perform quiesc by default in aspiration mode ?
        return quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, alpha, beta, p_features, ply, ischeck, pv, prevLine);
    }

    // null move prunning here
    // R = 3
    if (p_features.useNullPrune) {
        // see chess programming video
        const R: u16 = 2 + 1;
        const ischeck = p_state.isChecked();
        if (depth > R and !ischeck and !p_state.isEndGame() and ply > 0) {
            p_state.makeNullMove();
            const score = -searchLoop_aspirationPvs(p_state, p_info, depth - R, -beta, 1 - beta, p_features, ply + R, pv, prevLine, .NonPV);
            p_state.undoNullMove();
            if (score >= beta) {
                p_info.searchStat.n_cutoffs += 1;
                return score;
            }
        }
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    var order = heuristicl.eval_move_sorting_mask(p_state, &fmoves, ply, prevLine, p_features, undefined);
    var useLMR: bool = false;
    //https://www.chessprogramming.org/Late_Move_Reductions
    if (p_features.useLateMoveReduc and depth > 3) {
        heuristicl.computeLateMoveReduc(p_state, &order, depth - 1, &fmoves);
        useLMR = true;
    }
    if (fmoves.len == 0) {
        if (!p_state.isLegal(p_state.whiteToMove())) {
            return -(weightl.simpleCheckMateScore + @as(scoreType, @intCast(depth)));
        } else {
            return weightl.simpleStalemateScore;
        }
    }
    const firstM: IMove = fmoves.moves[order.indexes[0]];

    p_state.makeMove(firstM);
    var finalScore = -searchLoop_aspirationPvs(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine);
    _ = p_state.undoMove();
    if (ply == 0) {
        pv.onBestMove(firstM, ply);
    }
    if (finalScore > _alpha) {
        if (finalScore >= beta) {
            if (!firstM.isCapture()) {
                heuristicl.onKillerMove(firstM, ply);
            }
            p_info.searchStat.n_cutoffs += 1;
            return finalScore;
        }
        _alpha = finalScore;
    }

    for (1..fmoves.len) |i| {
        const idx = order.indexes[i];
        const move: IMove = fmoves.moves[idx];
        const isCapture = move.isCapture();
        p_state.makeMove(move);

        var score = -searchLoop_aspirationPvs(p_state, p_info, depth - 1, -_alpha - 1, -_alpha, p_features, ply + 1, pv, prevLine);

        if (score > _alpha and score < beta) {
            score = -searchLoop_aspirationPvs(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine);
            if (score > _alpha) {
                _alpha = score;
                pv.onBestMove(move, ply);
                if (!isCapture) {
                    heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), heuristicl.computeHistoryBonus(depth));
                }
            }
        }

        _ = p_state.undoMove();

        if (score > finalScore) {
            if (score > beta) {
                if (!isCapture) {
                    heuristicl.onKillerMove(move, ply);
                }
                p_info.searchStat.n_cutoffs += 1;
                return score;
            }
            finalScore = score;
            if (!isCapture) {
                heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), heuristicl.computeHistoryBonus(depth));
            }
        }
    }
    return finalScore;
}
pub fn handleTerminalState(p_state: *chess.Board_state, p_info: *threadInfo, alpha: scoreType, beta: scoreType, p_features: *const searchFeatures, ply: u16, pv: *pvContainer, prevLine: *const movel.line) scoreType {
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());
    p_info.searchStat.n_nodeExplored += 1;
    if (p_features.useQuiescence) {
        const ischeck = p_state.isChecked();
        if (p_state.getLastMove().isCapture() or ischeck) {
            // perform quiesc
            return quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, alpha, beta, p_features, ply, ischeck, pv, prevLine);
        }
    }
    const score = color_mask * heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
    return score;
}

pub fn quiescenceSearch(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, p_features: *const searchFeatures, ply: u16, wasChecked: bool, pv: *pvContainer, prevLine: *const movel.line) scoreType {
    // first vers adapt of the pseudo code: https://www.chessprogramming.org/Quiescence_Search
    pv.setLen(ply);
    var _alpha = alpha;
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());
    const static_eval = color_mask * heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
    if (depth == 0 or !p_info.alive) {
        p_info.searchStat.n_nodeExplored += 1;
        return static_eval;
    }
    var best_value = static_eval;
    if (best_value >= beta) {
        p_info.searchStat.n_cutoffs += 1;
        return best_value;
    }
    if (best_value > _alpha) {
        pv.onBestMove(p_state.getLastMove(), ply - 1);
        _alpha = best_value;
    }
    const fmoves: moveContainer = moveGenl.generateLegalMoves_ordered(p_state, true);

    const indexes = heuristicl.eval_move_sorting_mask(p_state, &fmoves, ply, prevLine, p_features, .{});
    for (0..fmoves.len) |i| {
        const idx = indexes.indexes[i];
        const move: IMove = fmoves.moves[idx];

        // if move nor capture nor checking
        // problem here where a checking sequence ie
        // black checked -> white not checked nor capture = end of quiescence, the search might need to continue

        //if (!move.isCapture() and !wasChecked) {
        //    continue;
        //}
        p_state.makeMove(move);

        const score = -quiescenceSearch(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, wasChecked, pv, prevLine);

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
            pv.onBestMove(move, ply);
        }
    }
    return best_value;
}
