const std = @import("std");
const chess = @import("../chess.zig");
const movel = @import("../move.zig");
const moveGenl = @import("../move_generation.zig");
const heuristicl = @import("../heuristic.zig");
const explorationl = @import("../exploration.zig");
const threadingl = @import("threading.zig");
const schedulerl = @import("scheduler.zig");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const scoreType = heuristicl.scoreType;

const moveDecisionExt = schedulerl.moveDecisionExt;
const threadInfo = threadingl.threadInfo;

pub fn searchEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16) void {
    p_info.running = true;

    const alpha: scoreType = -heuristicl.simpleCheckMateScore;
    const beta: scoreType = heuristicl.simpleCheckMateScore;

    for (0..p_startingMoves.items.len) |i| {
        const move = p_startingMoves.items[i];
        _ = p_state.makeMoveUpdate(move);

        const score = -searchLoop(p_state, p_info, depth - 1, alpha, beta);

        _ = p_state.undoMoveRestore();

        if (i == 0 or p_info.currentBest.scoring < score) {
            p_info.currentBest.move = move;
            p_info.currentBest.scoring = score;
        }
    }
    p_info.running = false;
}
fn searchLoop(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType) scoreType {
    const color_mask: i8 = explorationl.getScoreMaskFromTurn(p_state.whiteToMove());
    if (depth <= 0 or !p_info.running) {
        p_info.n_nodeExplored += 1;
        const score = color_mask * heuristicl.pastHeuristic(p_state);
        return score;
    }
    if (p_state.isStaleMateRepetition()) {
        return heuristicl.simpleStalemateScore;
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    var _alpha = alpha;
    var finalScore: scoreType = 0;
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];
        _ = p_state.makeMoveUpdate(move);

        const score = -searchLoop(p_state, p_info, depth - 1, -beta, -_alpha);

        _ = p_state.undoMoveRestore();

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
            finalScore = -(heuristicl.simpleCheckMateScore + depth);
        } else {
            finalScore = heuristicl.simpleStalemateScore;
        }
    }
    return finalScore;
}
