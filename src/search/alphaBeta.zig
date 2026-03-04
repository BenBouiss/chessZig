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
        //
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

    var pv: pvContainer = .{};
    for (0..p_startingMoves.items.len) |i| {
        const move = p_startingMoves.items[i];

        p_state.makeMove(move);

        const score = -searchLoop(p_state, p_info, depth - 1, alpha, beta, p_features, 1, &pv, prevLine);

        _ = p_state.undoMove();

        if (i == 0 or p_info.currentBest.scoring < score) {
            p_info.currentBest.move = move;
            p_info.currentBest.scoring = score;
            pv.onBestMove(move, 0);
            p_info.currentBest.line.setLineFromPV(&pv);
            //std.debug.print("[DEBUG] searchEntrypoint: new best line found {f} cp {d}\n", .{ p_info.currentBest.line, score });
        }
    }
    if (p_info.alive) {
        return 0;
    }
    // 1 is error
    return 1;
}
fn searchLoop(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, p_features: *const searchFeatures, ply: u16, pv: *pvContainer, prevLine: *const movel.line) scoreType {
    pv.setLen(ply);
    if (p_state.isStaleMateRepetition()) {
        if (p_features.useHash) {
            const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.key, @intCast(depth), weightl.simpleStalemateScore);
            _ = hashl.hashTable.storeEntry(&s_entry);
            // might be useful for late game
            //hashl.hashTable.overwriteEvaluationEntries(&s_entry, heuristicl.simpleStalemateScore);
        }
        return weightl.simpleStalemateScore;
    }
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());

    if (depth <= 0 or !p_info.alive) {
        p_info.n_nodeExplored += 1;
        if (p_features.useQuiescence) {
            const ischeck = p_state.isChecked();
            if (p_state.getLastMove().isCapture() or ischeck) {
                // perform quiesc
                return quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, alpha, beta, p_features, ply, ischeck, pv, prevLine);
            }
        }
        if (p_features.useTexelEvaluation) {
            const score = color_mask * heuristicl.texelEvaluation(p_state);
            return score;
        } else {
            const score = color_mask * heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
            return score;
        }
    }

    if (p_features.useHash) {
        const entry = hashl.getEntryFromMatch(p_state.key, @intCast(depth));
        if (entry.valid) {
            p_info.n_hashRetrieve += 1;
            return color_mask * entry.eval();
        }
    }
    var _alpha = alpha;
    // null move prunning here
    // R = 3
    if (comptime configl.DEFAULT_USE_NULLPRUNE) {
        // see chess programming video
        const R: u16 = 2 + 1;
        if (depth > R) {
            p_state.makeNullMove();
            const score = -searchLoop(p_state, p_info, depth - 1 - R, -beta, -_alpha, p_features, ply + 1 + R, pv, prevLine);
            p_state.undoNullMove();
            if (score >= beta) {
                return beta;
            }
        }
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    const indexes = heuristicl.eval_move_sorting_mask(&fmoves, ply, prevLine, p_features);
    var finalScore: scoreType = 0;
    for (0..fmoves.len) |i| {
        const idx = indexes[i];
        const move: IMove = fmoves.moves[idx];

        _ = p_state.makeMove(move);

        const score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, pv, prevLine);

        _ = p_state.undoMove();

        if (i == 0 or finalScore < score) {
            finalScore = score;
        }
        if (finalScore > _alpha) {
            _alpha = finalScore;
            if (!move.isCapture()) {
                heuristicl.updateHistoryHeurist(p_state.whiteToMove(), move.getFrom(), move.getTo(), heuristicl.computeHistoryBonus(depth));
            }
            pv.onBestMove(move, ply);
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
    if (p_features.useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.key, @intCast(depth), color_mask * finalScore);
        _ = hashl.hashTable.storeEntry(&s_entry);
    }
    return finalScore;
}
pub fn quiescenceSearch(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, p_features: *const searchFeatures, ply: u16, wasChecked: bool, pv: *pvContainer, prevLine: *const movel.line) scoreType {
    // first vers adapt of the pseudo code: https://www.chessprogramming.org/Quiescence_Search
    pv.setLen(ply);
    var _alpha = alpha;
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());
    const static_eval = color_mask * heuristicl.evaluate(p_state, &heuristicl.globalHeuristic);
    if (depth == 0 or !p_info.alive) {
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

    //const indexes = heuristicl.cst_eval_move_sorting_mask(&fmoves, ply, undefined, false);
    const indexes = heuristicl.eval_move_sorting_mask(&fmoves, ply, prevLine, p_features);
    for (0..fmoves.len) |i| {
        const idx = indexes[i];
        const move: IMove = fmoves.moves[idx];

        p_state.makeMove(move);

        // if move nor capture nor checking
        // problem here where a checking sequence ie
        // black checked -> white not checked nor capture = end of quiescence, the search might need to continue
        if (!move.isCapture() and !wasChecked) {
            _ = p_state.undoMove();
            continue;
        }
        const score = -quiescenceSearch(p_state, p_info, depth - 1, -beta, -_alpha, p_features, ply + 1, wasChecked, pv, prevLine);

        _ = p_state.undoMove();
        if (score > best_value) {
            best_value = score;
        }
        if (score >= beta) {
            return score;
        }
        if (score > _alpha) {
            _alpha = score;
            pv.onBestMove(move, ply);
        }
    }
    return best_value;
}
