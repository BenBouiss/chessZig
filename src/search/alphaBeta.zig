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
pub const depthCommunication = struct {
    depth: u16 = 0,
    depthSet: bool = false,
    lock: bool = false,
    pub inline fn acquireLock(p_self: *depthCommunication) void {
        var cumulTime: u64 = 0;
        while (p_self.lock) {
            if (cumulTime > configl.DEBUG_INACTIVITY_READING_NS) {
                std.debug.print("[INACTIVITY] inputThreading.engine: no activity found in the last {d}s \n", .{configl.DEBUG_INACTIVITY_READING_S});
                cumulTime = 0;
            }
        }
        p_self.lock = true;
    }
    pub inline fn releaseLock(p_self: *depthCommunication) void {
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
};

pub fn _alphaBetaWaitingRoom(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depthCom: *depthCommunication, feat: searchFeatures) void {
    var startTime = std.time.nanoTimestamp();
    while (p_info.alive) {
        const cumulTime = std.time.nanoTimestamp() - startTime;
        if (cumulTime > configl.DEBUG_INACTIVITY_READING_NS) {
            std.debug.print("[INACTIVITY] alphaBetaWaitingRoom: no activity found in the last {d}s \n", .{configl.DEBUG_INACTIVITY_READING_S});
            startTime = std.time.nanoTimestamp();
        }
        // wait for a depth to be submitted
        if (!depthCom.depthSet) {
            continue;
        }
        depthCom.depthSet = false;

        if (searchEntrypoint(p_state, p_startingMoves, p_info, depthCom.depth, feat) == 1) {
            startTime = std.time.nanoTimestamp();
            break;
        }
    }
}
pub fn alphaBetaWaitingRoom(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depthCom: *depthCommunication, feat: searchFeatures) void {
    while (p_info.alive) {
        // for some reason if this function gets updated too fast the scheduler gets bricked in the handleInterrupt method
        // trying to join on a thread with p_info.alive = false?
        //
        // FIXME: ???
        std.Thread.sleep(configl.WR_TICKRATE_NS);
        // wait for a depth to be submitted
        if (!depthCom.depthSet) {
            continue;
        }
        depthCom.depthSet = false;
        if (searchEntrypoint(p_state, p_startingMoves, p_info, depthCom.depth, feat) == 1) {
            break;
        }
    }
}

pub fn searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, feature: searchFeatures) i8 {
    if (feature.useHash) {
        return texelTransf_searchEntrypoint(p_state, p_startingMoves, p_info, depth, true, feature.useTexelEvaluation, feature.useQuiescence);
    }
    return texelTransf_searchEntrypoint(p_state, p_startingMoves, p_info, depth, false, feature.useTexelEvaluation, feature.useQuiescence);
}
pub fn texelTransf_searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, comptime useHash: bool, useTexel: bool, useQuiescence: bool) i8 {
    if (useTexel) {
        return quiescTransf_searchEntrypoint(p_state, p_startingMoves, p_info, depth, useHash, true, useQuiescence);
    }
    return quiescTransf_searchEntrypoint(p_state, p_startingMoves, p_info, depth, useHash, false, useQuiescence);
}
pub fn quiescTransf_searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, comptime useHash: bool, comptime useTexel: bool, useQuiescence: bool) i8 {
    if (useQuiescence) {
        return _searchEntrypoint(p_state, p_startingMoves, p_info, depth, useHash, useTexel, true);
    }
    return _searchEntrypoint(p_state, p_startingMoves, p_info, depth, useHash, useTexel, false);
}

pub fn _searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, comptime useHash: bool, comptime useTexel: bool, comptime useQuiescence: bool) i8 {
    p_info.working = true;
    defer p_info.working = false;
    const alpha: scoreType = -weightl.simpleCheckMateScore;
    const beta: scoreType = weightl.simpleCheckMateScore;

    for (0..p_startingMoves.items.len) |i| {
        const move = p_startingMoves.items[i];

        p_state.makeMove(move);

        const score = -searchLoop(p_state, p_info, depth - 1, alpha, beta, useHash, useTexel, useQuiescence, 0);

        _ = p_state.undoMove();

        if (i == 0 or p_info.currentBest.scoring < score) {
            p_info.currentBest.move = move;
            p_info.currentBest.scoring = score;
        }
    }
    if (p_info.alive) {
        return 0;
    }
    // 1 is error
    return 1;
}
fn searchLoop(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, comptime useHash: bool, comptime useTexel: bool, comptime useQuiescence: bool, ply: u16) scoreType {
    const color_mask = getScoreMaskFromTurn(p_state.whiteToMove());
    if (depth <= 0 or !p_info.alive) {
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

        const score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha, useHash, useTexel, useQuiescence, ply + 1);

        _ = p_state.undoMove();

        if (i == 0 or finalScore < score) {
            finalScore = score;
        }
        if (finalScore > _alpha) {
            _alpha = finalScore;
            if (!move.isCapture()) {
                //heuristicl.historyHeuristic[@intFromBool(p_state.whiteToMove())][move.getFrom()][move.getTo()] += depth;
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
