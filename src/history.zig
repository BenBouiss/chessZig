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

// indexes: sideToMove, piece, fromSq, toSq
// https://www.chessprogramming.org/History_Heuristic#Update

// https://www.chessprogramming.org/History_Heuristic#Continuation_History
// combination of couter move heuristic and follow up history. Works via pair of move using the following index template:
//  [nextPiece][nextTo][prevPiece][prevTo]
pub const pieceHistory: type = [13][64]scoreType;

pub const lmrBase: [typel.MAX_PLY][chessl.MAX_POSSIBLE_MOVE]scoreType = initLMR();

pub fn _initMoveOrdering() void {}
pub fn initLMR() [typel.MAX_PLY][chessl.MAX_POSSIBLE_MOVE]scoreType {
    @setEvalBranchQuota(1000000);
    var ret: [typel.MAX_PLY][chessl.MAX_POSSIBLE_MOVE]scoreType = std.mem.zeroes([typel.MAX_PLY][chessl.MAX_POSSIBLE_MOVE]scoreType);
    for (1..typel.MAX_PLY) |d| {
        for (0..chessl.MAX_POSSIBLE_MOVE) |i| {
            // patricia version
            const s: f32 = 1024 * (0.4 + (std.math.log(f32, std.math.e, @floatFromInt(d)) * std.math.log(f32, std.math.e, @floatFromInt(i + 1)) / 2));
            ret[d][i] = @as(scoreType, @intFromFloat(s));
        }
    }
    return ret;
}
pub inline fn pawnHashIndexToIdx(hash: u64) u64 {
    return hash % 16384;
}
//https://www.chessprogramming.org/History_Heuristic#Update
pub inline fn computeHistoryBonus(depth: typel.depthT) scoreType {
    return @min(weightl.historyBonusCoeff * @as(scoreType, @intCast(depth - 1)), weightl.historyBonusMax);
}
