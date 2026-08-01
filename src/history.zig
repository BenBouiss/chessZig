const std = @import("std");

const movel = @import("move.zig");
const typel = @import("type.zig");
const configl = @import("config.zig");
const chessl = @import("chess.zig");
const weightl = @import("weights.zig");

const IMove = movel.IMove;
const scoreType = typel.scoreType;
const e_piece = typel.e_piece;
const e_square = typel.e_square;

// indexes: ply, idx (either 1st or 2nd)
pub var killerMoves: [typel.MAX_PLY][2]IMove = undefined;

// index from, to
//pub var counterMoves: [64][64]IMove = undefined;

// indexes: sideToMove, piece, fromSq, toSq
// https://www.chessprogramming.org/History_Heuristic#Update
pub var historyHeuristic: [2][64][64]scoreType = std.mem.zeroes([2][64][64]scoreType);

// https://www.chessprogramming.org/History_Heuristic#Continuation_History
// combination of couter move heuristic and follow up history. Works via pair of move using the following index template:
//  [nextPiece][nextTo][prevPiece][prevTo]
pub const pieceHistory: type = [13][64]scoreType;

pub var corrHist: [12][64][12][64]scoreType = std.mem.zeroes([12][64][12][64]scoreType);

pub var pawnCorrHist: [2][16384]scoreType = std.mem.zeroes([2][16384]scoreType);
pub var nonPawnCorrHist: [2][2][16384]scoreType = std.mem.zeroes([2][2][16384]scoreType);

//pub var lmrBase: [typel.MAX_PLY][chessl.MAX_POSSIBLE_MOVE]scoreType = std.mem.zeroes([typel.MAX_PLY][chessl.MAX_POSSIBLE_MOVE]scoreType);
pub var lmrBase: [chessl.MAX_POSSIBLE_MOVE]scoreType = std.mem.zeroes([chessl.MAX_POSSIBLE_MOVE]scoreType);

pub var continuationHeuristic: [13][64]pieceHistory = std.mem.zeroes([13][64]pieceHistory);
// fPiece cPiece toSq
pub var captureHistory: [12][12][64]scoreType = std.mem.zeroes([12][12][64]scoreType);

pub fn _initMoveOrdering() void {
    historyHeuristic = std.mem.zeroes([2][64][64]scoreType);
    killerMoves = std.mem.zeroes([typel.MAX_PLY][2]IMove);
    //counterMoves = std.mem.zeroes([64][64]IMove);
    captureHistory = std.mem.zeroes([12][12][64]scoreType);
    continuationHeuristic = std.mem.zeroes([13][64]pieceHistory);
    corrHist = std.mem.zeroes([12][64][12][64]scoreType);

    pawnCorrHist = std.mem.zeroes([2][16384]scoreType);
    nonPawnCorrHist = std.mem.zeroes([2][2][16384]scoreType);

    // https://int0x80.ca/posts/chess-engines/8-pvs
    //for (1..typel.MAX_PLY) |d| {
    //    for (0..chessl.MAX_POSSIBLE_MOVE) |i| {
    //        //const s: f32 = 0.77 + (std.math.log(f32, std.math.e, @floatFromInt(d)) * std.math.log(f32, std.math.e, @floatFromInt(i + 1)) / 2.36);
    //        const s: f32 = 0.77 + (std.math.log(f32, 10, @floatFromInt(d)) * std.math.log(f32, 10, @floatFromInt(i + 1)) / 2.36);
    //        //std.debug.print("{d}\n", .{s});
    //        lmrBase[d][i] = @intFromFloat(s);
    //    }
    //}
    //
    for (0..chessl.MAX_POSSIBLE_MOVE) |i| {
        lmrBase[i] = (weightl.lmr_oldMulti * @as(scoreType, @intCast(std.math.log(usize, 10, @intCast(i + 1)))));
    }
}
pub inline fn pawnHashIndexToIdx(hash: u64) u64 {
    return hash % 16384;
}
pub inline fn onKillerMove(move: IMove, ply: u16) void {
    killerMoves[ply][1] = killerMoves[ply][0];
    killerMoves[ply][0] = move;
}
