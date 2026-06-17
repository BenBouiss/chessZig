const std = @import("std");

const movel = @import("move.zig");
const typel = @import("type.zig");
const configl = @import("config.zig");

const IMove = movel.IMove;
const scoreType = typel.scoreType;
const e_piece = typel.e_piece;
const e_square = typel.e_square;

// indexes: ply, idx (either 1st or 2nd)
pub var killerMoves: [64][2]IMove = undefined;

// index from, to
//pub var counterMoves: [64][64]IMove = undefined;

// indexes: sideToMove, piece, fromSq, toSq
// https://www.chessprogramming.org/History_Heuristic#Update
pub var historyHeuristic: [2][64][64]scoreType = std.mem.zeroes([2][64][64]scoreType);

// https://www.chessprogramming.org/History_Heuristic#Continuation_History
// combination of couter move heuristic and follow up history. Works via pair of move using the following index template:
//  [nextPiece][nextTo][prevPiece][prevTo]
pub const pieceHistory: type = [12][64]scoreType;
pub var continuationHeuristic: [12][64]pieceHistory = std.mem.zeroes([12][64]pieceHistory);
// fPiece cPiece toSq
//pub var captureHistory: [12][12][64]scoreType = std.mem.zeroes([12][12][64]scoreType);

pub fn _initMoveOrdering() void {
    historyHeuristic = std.mem.zeroes([2][64][64]scoreType);
    killerMoves = std.mem.zeroes([64][2]IMove);
    //counterMoves = std.mem.zeroes([64][64]IMove);
    //captureHistory = std.mem.zeroes([12][12][64]scoreType);
    continuationHeuristic = std.mem.zeroes([12][64]pieceHistory);
}
pub inline fn onKillerMove(move: IMove, ply: u16) void {
    killerMoves[ply][1] = killerMoves[ply][0];
    killerMoves[ply][0] = move;
}
//pub inline fn updateCaptureHistory(fPiece: e_piece, cPiece: e_piece, toSq: u8, bonus: scoreType) void {
//    const _bonus = std.math.clamp(bonus, -configl.MAX_HIST_HEURISTIC_VALUE, configl.MAX_HIST_HEURISTIC_VALUE);
//    captureHistory[@intFromEnum(fPiece)][@intFromEnum(cPiece)][toSq] += _bonus - @divFloor(captureHistory[@intFromEnum(fPiece)][@intFromEnum(cPiece)][toSq] * @as(scoreType, @intCast(@abs(_bonus))), configl.MAX_HIST_HEURISTIC_VALUE);
//}

pub fn updateHistoryHeurist(white: bool, from: u8, to: u8, bonus: scoreType) void {
    const _bonus = std.math.clamp(bonus, -configl.MAX_HIST_HEURISTIC_VALUE, configl.MAX_HIST_HEURISTIC_VALUE);
    const turnIdx = @intFromBool(white);
    historyHeuristic[turnIdx][from][to] += _bonus - @divFloor(historyHeuristic[turnIdx][from][to] * @as(scoreType, @intCast(@abs(_bonus))), configl.MAX_HIST_HEURISTIC_VALUE);
}
pub fn updateContinuationHeurist(heurist: *pieceHistory, piece: e_piece, to: u8, bonus: scoreType) void {
    const _bonus = std.math.clamp(bonus, -configl.MAX_CONTINUATION_HEURISTIC_VALUE, configl.MAX_CONTINUATION_HEURISTIC_VALUE);
    heurist[@intFromEnum(piece)][to] += _bonus - @divFloor(heurist[@intFromEnum(piece)][to] * @as(scoreType, @intCast(@abs(_bonus))), configl.MAX_CONTINUATION_HEURISTIC_VALUE);
}
