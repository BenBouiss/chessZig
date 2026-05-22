const chess = @import("chess.zig");
const typel = @import("type.zig");
const std = @import("std");
pub const e_square = typel.e_square;

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
    pub inline fn copy(self: squareInfo) squareInfo {
        return .{ .sq = self.sq, .file = self.file, .rank = self.rank, .diagonal = self.diagonal, .antidiagonal = self.antidiagonal };
    }
    pub fn print(self: squareInfo) void {
        std.debug.print("{} ", .{self.sq});
    }
    pub inline fn getBB(self: squareInfo) u64 {
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
    pub inline fn getAllAttackingSquares(self: squareInfo) u64 {
        return self.getDiagBB() | self.getAntiDiagBB() | self.getRankBB() | self.getFileBB() | chess.knightAttacks(self.getBB());
    }
    pub inline fn visibilitySquares(self: squareInfo) u64 {
        return self.getDiagBB() | self.getAntiDiagBB() | self.getRankBB() | self.getFileBB();
    }
    pub inline fn getHorizontalBB(self: squareInfo) u64 {
        return self.getRankBB() | self.getFileBB();
    }
    pub inline fn getDiagonalsBB(self: squareInfo) u64 {
        return self.getDiagBB() | self.getAntiDiagBB();
    }
    pub fn computeBenDistance(self: squareInfo, other: squareInfo) i8 {
        const deltaF: i8 = @as(i8, @intCast(self.file)) - @as(i8, @intCast(other.file));
        const deltaR: i8 = @as(i8, @intCast(self.rank)) - @as(i8, @intCast(other.rank));
        return @as(i8, @intCast(@abs(deltaF) + @abs(deltaR)));
    }
};
pub const maxBenDistance = 14;

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
    while (_bb != 0) {
        const lsb = chess.bitscan(_bb);
        _bb ^= chess.xToBitboard(lsb);
        _ = ret.addCheckSquare(squareInfo.init(@enumFromInt(lsb)));
    }
    return ret;
}
