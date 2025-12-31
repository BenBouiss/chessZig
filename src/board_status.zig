const std = @import("std");

const chessl = @import("chess.zig");
const movel = @import("move.zig");

const build_options = @import("build_options");

// Testing Gigantua approach
// massive rewrite needed probably
const useDebug = build_options.useDebug;

const LEFT_ROOKS: u64 = 0x100000000000001;
const RIGHT_ROOKS: u64 = 0x8000000000000080;

pub const wCastleKKingBit: u64 = 0xA;
pub const wCastleKRookBit: u64 = 0x5;
pub const wCastleQKingBit: u64 = 0x28;
pub const wCastleQRookBit: u64 = 0x90;

pub const bCastleKKingBit: u64 = 0x5000000000000000;
pub const bCastleKRookBit: u64 = 0xA000000000000000;
pub const bCastleQKingBit: u64 = 0x1400000000000000;
pub const bCastleQRookBit: u64 = 0x900000000000000;

pub const statusStack = struct {
    items: [movel.MAX_MATCH_LENGTH]status = undefined,
    len: usize = 0,
    pub fn push(p_self: *statusStack, item: status) void {
        p_self.items[p_self.len] = item;
        p_self.len += 1;
    }
    pub fn pop(p_self: *statusStack) status {
        if (comptime useDebug) {
            if (p_self.len == 0) {
                @panic("Popping from empty boardframe, forgot to push?");
            }
        }
        p_self.len -= 1;
        return p_self.items[p_self.len];
    }
};

pub const status = struct {
    whiteToMove: bool = true,

    WCastlingK: bool = false,
    WCastlingQ: bool = false,

    BCastlingK: bool = false,
    BCastlingQ: bool = false,
    pub fn turn(self: status) chessl.e_color {
        if (self.whiteToMove) {
            return .WHITE;
        }
        return .BLACK;
    }
    pub fn canCastle(self: status, comptime whiteMove: bool) bool {
        if (comptime whiteMove) {
            return self.WCastlingK | self.WCastlingQ;
        } else {
            return self.BCastlingK | self.BCastlingQ;
        }
    }
    pub inline fn canKingsideCastle(self: status, comptime whiteMove: bool) bool {
        if (comptime whiteMove) {
            return self.WCastlingK;
        }
        return self.BCastlingK;
    }
    pub inline fn canQueensideCastle(self: status, comptime whiteMove: bool) bool {
        if (comptime whiteMove) {
            return self.WCastlingQ;
        }
        return self.BCastlingQ;
    }
    pub fn onKingMove(self: status) status {
        if (self.whiteToMove) {
            return .{ .whiteToMove = false, .WCastlingK = false, .WCastlingQ = false, .BCastlingK = self.BCastlingK, .BCastlingQ = self.BCastlingQ };
        } else {
            return .{ .whiteToMove = true, .BCastlingK = false, .BCastlingQ = false, .WCastlingK = self.WCastlingK, .WCastlingQ = self.WCastlingQ };
        }
    }
    pub fn onRookMove(self: status, rooks: u64) status {
        if (isLeftRook(rooks)) {
            if (self.whiteToMove) {
                return .{ .whiteToMove = false, .WCastlingK = self.WCastlingK, .WCastlingQ = false, .BCastlingK = self.BCastlingK, .BCastlingQ = self.BCastlingQ };
            } else {
                return .{ .whiteToMove = true, .WCastlingK = self.WCastlingK, .WCastlingQ = self.WCastlingQ, .BCastlingK = self.BCastlingK, .BCastlingQ = false };
            }
        } else if (isRightRook(rooks)) {
            if (self.whiteToMove) {
                return .{ .whiteToMove = false, .WCastlingK = false, .WCastlingQ = self.WCastlingQ, .BCastlingK = self.BCastlingK, .BCastlingQ = self.BCastlingQ };
            } else {
                return .{ .whiteToMove = true, .WCastlingK = self.WCastlingK, .WCastlingQ = self.WCastlingQ, .BCastlingK = false, .BCastlingQ = self.BCastlingQ };
            }
        }
        return .{ .whiteToMove = !self.whiteToMove, .WCastlingK = false, .WCastlingQ = self.WCastlingQ, .BCastlingK = self.BCastlingK, .BCastlingQ = self.BCastlingQ };
    }
    pub fn castlingKey(self: status) u4 {
        const r1: u4 = @intCast(@intFromBool(self.WCastlingK));
        const r2: u4 = @intCast(@intFromBool(self.WCastlingQ));
        const r3: u4 = @intCast(@intFromBool(self.BCastlingK));
        const r4: u4 = @intCast(@intFromBool(self.BCastlingQ));
        return r1 | (r2 << 1) | (r3 << 2) | (r4 << 3);
    }
};
pub fn isLeftRook(rook: u64) bool {
    return (rook & LEFT_ROOKS) != chessl.EMPTY;
}
pub fn isRightRook(rook: u64) bool {
    return (rook & RIGHT_ROOKS) != chessl.EMPTY;
}
