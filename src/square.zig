const chess = @import("chess.zig");
const std = @import("std");
pub const e_square = enum(u8) { a1 = 0, b1, c1, d1, e1, f1, g1, h1, a2, b2, c2, d2, e2, f2, g2, h2, a3, b3, c3, d3, e3, f3, g3, h3, a4, b4, c4, d4, e4, f4, g4, h4, a5, b5, c5, d5, e5, f5, g5, h5, a6, b6, c6, d6, e6, f6, g6, h6, a7, b7, c7, d7, e7, f7, g7, h7, a8, b8, c8, d8, e8, f8, g8, h8, invalid };

pub const MAX_CHECKS: u8 = 2;

pub const squareInfo = struct {
    sq: e_square = e_square.a1,
    file: u8 = 0,
    rank: u8 = 0,
    diagonal: i8 = 0,
    antidiagonal: i8 = 0,
    pub fn init(sq: e_square) squareInfo {
        return .{ .sq = sq, .file = chess.getSqFile(sq), .rank = chess.getSqRank(sq), .diagonal = chess.getSqDiag(sq), .antidiagonal = chess.getSqAntiDiag(sq) };
    }
    pub fn copy(self: squareInfo) squareInfo {
        return .{ .sq = self.sq, .file = self.file, .rank = self.rank, .diagonal = self.diagonal, .antidiagonal = self.antidiagonal };
    }
    pub fn print(self: squareInfo) void {
        std.debug.print("{} ", .{self.sq});
    }
    pub fn getBB(self: squareInfo) u64 {
        return chess.ONE << @intCast(@intFromEnum(self.sq));
    }
    pub inline fn getDiagBB(self: squareInfo) u64 {
        return chess.diagonalMask(@intCast(@intFromEnum(self.sq)));
    }
    pub inline fn getAntiDiagBB(self: squareInfo) u64 {
        return chess.antiDiagMask(@intCast(@intFromEnum(self.sq)));
    }
    pub inline fn getFileBB(self: squareInfo) u64 {
        return chess.fileMaskFromFileN(self.file);
    }
    pub inline fn getRankBB(self: squareInfo) u64 {
        return chess.rankMaskFromRankN(self.rank);
    }
    pub fn getAllAttackingSquares(self: squareInfo) u64 {
        return self.getDiagBB() | self.getAntiDiagBB() | self.getRankBB() | self.getFileBB() | chess.knightAttacks(self.getBB());
    }
    pub fn visibilitySquares(self: squareInfo) u64 {
        return self.getDiagBB() | self.getAntiDiagBB() | self.getRankBB() | self.getFileBB();
    }
    pub fn getHorizontalBB(self: squareInfo) u64 {
        return self.getRankBB() | self.getFileBB();
    }
    pub fn getDiagonalsBB(self: squareInfo) u64 {
        return self.getDiagBB() | self.getAntiDiagBB();
    }
};

pub const checkContainer = struct {
    squares: [MAX_CHECKS]squareInfo = std.mem.zeroes([MAX_CHECKS]squareInfo),
    len: usize = 0,

    pub fn addCheckSquare(p_self: *checkContainer, sq: squareInfo) bool {
        if (p_self.len == MAX_CHECKS) {
            return false;
        }
        p_self.squares[p_self.len] = sq.copy();
        p_self.len += 1;
        return true;
    }
    pub inline fn isDoubleCheck(self: checkContainer) bool {
        return self.len == 2;
    }
    pub inline fn isCheck(self: checkContainer) bool {
        return self.len > 0;
    }
    pub fn print(self: checkContainer) void {
        for (0..self.len) |i| {
            self.squares[i].print();
        }
        std.debug.print("\n", .{});
    }
};

pub fn convertBitBoardtoCheckContainer(bb: u64) checkContainer {
    var ret: checkContainer = .{};
    var _bb = bb;
    var lsb: i8 = 0;
    while (_bb != 0) {
        lsb = chess.bitscan(_bb);
        _bb ^= (chess.ONE << @intCast(lsb));
        _ = ret.addCheckSquare(squareInfo.init(@enumFromInt(lsb)));
    }
    return ret;
}
