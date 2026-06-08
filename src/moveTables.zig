const chess = @import("chess.zig");
const moveGenl = @import("move_generation.zig");
const squarel = @import("square.zig");

const std = @import("std");

const squareInfo = squarel.squareInfo;
const e_square = squarel.e_square;

pub const arrRectangular: [64][64]u64 = initInbetween();
pub const cachedKingTable: [64]u64 = initKingAttacks();
pub const safetyArea: [64]u64 = initSafetyArea();
// https://www.chessprogramming.org/Square_Attacked_By#Obstructed

// https://www.chessprogramming.org/King_Safety will be defined

pub fn initKingAttacks() [64]u64 {
    var ret: [64]u64 = @splat(0);
    for (0..chess.N_SQUARES) |sq| {
        ret[sq] = kingAttacks(@intCast(sq));
    }
    return ret;
}
pub fn kingAttacks(sq: i8) u64 {
    var ret: u64 = chess.EMPTY;
    const pos: u64 = (chess.ONE << @intCast(sq));

    ret |= (pos >> 8);
    ret |= (pos << 8);

    if (pos & chess.notAFile != 0) {
        ret |= (pos >> 1);
        ret |= (pos << 7);
        ret |= (pos >> 9);
    }

    if (pos & chess.notHFile != 0) {
        ret |= (pos << 1);
        ret |= (pos << 9);
        ret |= (pos >> 7);
    }

    return ret;
}

pub fn initInbetween() [64][64]u64 {
    @setEvalBranchQuota(100000);
    var table: [64][64]u64 = std.mem.zeroes([64][64]u64);
    for (0..64) |x| {
        const fromBB = chess.ONE << @intCast(x);
        const fromSq: squareInfo = squareInfo.init(@enumFromInt(x));
        for (0..64) |y| {
            if (x == y) {
                table[x][y] = 0;
                continue;
            }
            const toBB = chess.ONE << @intCast(y);
            const toSq: squareInfo = squareInfo.init(@enumFromInt(y));
            if (fromSq.file == toSq.file) {
                if (x < y) {
                    table[x][y] = moveGenl.northOccl(fromBB, ~toBB) ^ fromBB;
                } else {
                    table[x][y] = moveGenl.southOccl(fromBB, ~toBB) ^ fromBB;
                }
            } else if (fromSq.rank == toSq.rank) {
                if (x < y) {
                    table[x][y] = moveGenl.eastOccl(fromBB, ~toBB) ^ fromBB;
                } else {
                    table[x][y] = moveGenl.westOccl(fromBB, ~toBB) ^ fromBB;
                }
            } else if (fromSq.diagonal == toSq.diagonal) {
                if (x < y) {
                    table[x][y] = moveGenl.northEastOccl(fromBB, ~toBB) ^ fromBB;
                } else {
                    table[x][y] = moveGenl.southWestOccl(fromBB, ~toBB) ^ fromBB;
                }
            } else if (fromSq.antidiagonal == toSq.antidiagonal) {
                if (x < y) {
                    table[x][y] = moveGenl.northWestOccl(fromBB, ~toBB) ^ fromBB;
                } else {
                    table[x][y] = moveGenl.southEastOccl(fromBB, ~toBB) ^ fromBB;
                }
            } else {
                table[x][y] = 0;
                continue;
            }
        }
    }
    return table;
}
pub fn initSafetyArea() [64]u64 {
    @setEvalBranchQuota(100000);
    //const baseSq: i8 = 28;
    var ret: [64]u64 = @splat(0);
    const baseSq: i8 = @intFromEnum(e_square.e4);
    const anchors = [4]squarel.e_square{ .c2, .c6, .g6, .g2 };
    var box: u64 = chess.EMPTY;
    box |= chess.inBetween(anchors[0], anchors[1]);
    box |= chess.inBetween(anchors[1], anchors[2]);
    box |= chess.inBetween(anchors[2], anchors[3]);
    box |= chess.inBetween(anchors[3], anchors[0]);
    box |= (chess.sqToBitboard(anchors[0]) | chess.sqToBitboard(anchors[1]) | chess.sqToBitboard(anchors[2]) | chess.sqToBitboard(anchors[3]));
    for (0..64) |sq| {
        // TODO quick and dirty way, 8 occl in all directions for each squares. Other solutions is moving a "square" of 3x3 around the king square and simulate the queen moves inside it
        // in theory the clipping should not be an issue as the queen move with distance of 3 should not overlap
        var delta: i8 = @intCast(sq);
        delta -= baseSq;
        const newBox = chess.genShift(box, delta);
        ret[sq] = chess.getRookAttacksRay(newBox, @enumFromInt(sq)) | chess.getBishopAttacksRay(newBox, @enumFromInt(sq));

        ret[sq] |= chess.knightAttacks(chess.xToBitboard(@intCast(sq)));
    }
    return ret;
}
