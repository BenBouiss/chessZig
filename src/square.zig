const chess = @import("chess.zig");
const typel = @import("type.zig");
const std = @import("std");
pub const e_square = typel.e_square;

pub const squareInfo = struct {
    sq: e_square = e_square.a1,
    file: u8 = 0,
    rank: u8 = 0,
    pub fn init(sq: e_square) squareInfo {
        return .{ .sq = sq, .file = chess.getSqFile(sq), .rank = chess.getSqRank(sq) };
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
        return chess.diagonalMask(self.sq);
    }
    pub inline fn getAntiDiagBB(self: squareInfo) u64 {
        return chess.antiDiagonalMask(self.sq);
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
    pub inline fn computeMHDistance(self: squareInfo, other: squareInfo) i8 {
        const deltaF: i8 = @as(i8, @intCast(self.file)) - @as(i8, @intCast(other.file));
        const deltaR: i8 = @as(i8, @intCast(self.rank)) - @as(i8, @intCast(other.rank));
        return @as(i8, @intCast(@abs(deltaF) + @abs(deltaR)));
    }
};
pub const maxBenDistance = 14;
pub const centerSq: e_square = .e4;
