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
pub var counterMoves: [64][64]IMove = undefined;

// indexes: sideToMove, piece, fromSq, toSq
// https://www.chessprogramming.org/History_Heuristic#Update
pub var historyHeuristic: [2][64][64]scoreType = std.mem.zeroes([2][64][64]scoreType);

// fPiece cPiece toSq
//pub var captureHistory: [12][12][64]scoreType = std.mem.zeroes([12][12][64]scoreType);

pub fn _initMoveOrdering() void {
    historyHeuristic = std.mem.zeroes([2][64][64]scoreType);
    killerMoves = std.mem.zeroes([64][2]IMove);
    counterMoves = std.mem.zeroes([64][64]IMove);
    //captureHistory = std.mem.zeroes([12][12][64]scoreType);
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
