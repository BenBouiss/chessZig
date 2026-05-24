const std = @import("std");

const typel = @import("type.zig");
const boardl = @import("board.zig");

pub const networkScale = 400;
pub const qA = 255;
pub const qB = 64;
pub const HL_SIZE = 1024; // 1024 or 3072 per the site(?)
pub const INPUT_SIZE = 768; // 6 pieces x 2 colors x 64 sqs

//https://www.chessprogramming.org/NNUE
pub const network = struct {
    accWeights: [INPUT_SIZE][HL_SIZE]i16 = std.mem.zeroes([INPUT_SIZE][HL_SIZE]i16),
    accBiases: [HL_SIZE]i16 = std.mem.zeroes([HL_SIZE]i16),

    outputWeights: [2 * HL_SIZE]i16 = std.mem.zeroes([2 * HL_SIZE]i16),
    outputBiase: i16 = 0,
};
pub const accumulator = struct {
    values: [HL_SIZE]i16 = std.mem.zeroes([HL_SIZE]i16),
    pub fn addNetwork(self: *accumulator, n: *network, index: usize) void {
        for (0..HL_SIZE) |i| {
            self.values[i] += n.accWeights[index][i];
        }
    }
    pub fn subNetwork(self: *accumulator, n: *network, index: usize) void {
        for (0..HL_SIZE) |i| {
            self.values[i] -= n.accWeights[index][i];
        }
    }
};
pub const accumulatorPair = struct {
    w: accumulator = .{},
    b: accumulator = .{},
};

pub inline fn networkIndex(piece: typel.e_pieceType, color: typel.e_color, sq: typel.e_square) usize {
    return @intFromEnum(color) * 64 * 6 + @intFromEnum(piece) * 64 + @intFromEnum(sq);
}
pub fn networkIndexPerspective(piece: typel.e_pieceType, color: typel.e_color, sq: typel.e_square, perspective: typel.e_color) usize {
    var side: usize = @intFromEnum(color);
    var _sq: usize = @intFromEnum(sq);
    if (perspective == .BLACK) {
        side = 1 - side;
        _sq = sq ^ 56;
    }
    return side * 64 * 6 + @intFromEnum(piece) * 64 + _sq;
}

// easier to vectorize compared to below
//pub inline fn activationFunc(val: i16) i16 {
//    return std.math.clamp(val, 0, qA);
//}
pub inline fn activationFunc(val: i16) i32 {
    return std.math.pow(i32, std.math.clamp(val, 0, qA), 2);
}
pub fn forward(n: *const network, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    var ret: i32 = 0;
    for (0..HL_SIZE) |i| {
        ret += activationFunc(stm_acc.values[i]) * @as(i32, @intCast(n.outputWeights[i]));
        ret += activationFunc(nstm_acc.values[i]) * @as(i32, @intCast(n.outputWeights[i + HL_SIZE]));
    }
    // only used with the activ that uses the pow(2) SCReLU
    ret /= qA;
    ret *= networkScale;
    ret /= (qA * qB);
    return ret;
}

pub fn main(alloc: std.mem.Allocator) !void {
    _ = alloc;
}
