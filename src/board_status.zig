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
    items: [movel.MAX_MATCH_LENGTH]status,
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

    WCastlingK: bool = true,
    WCastlingQ: bool = true,

    BCastlingK: bool = true,
    BCastlingQ: bool = true,
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
    pub fn onKingMove(self: status, comptime whiteMove: bool) status {
        if (comptime whiteMove) {
            return .{ .whiteToMove = !whiteMove, .WCastlingK = false, .WCastlingQ = false, .BCastlingK = self.BCastlingK, .BCastlingQ = self.BCastlingQ };
        } else {
            return .{ .whiteToMove = !whiteMove, .BCastlingK = false, .BCastlingQ = false, .WCastlingK = self.WCastlingK, .WCastlingQ = self.WCastlingQ };
        }
    }
    pub fn onRookMove(self: status, rooks: u64) status {
        if (isLeftRook(rooks)) {
            if (comptime self.whiteToMove) {
                return .{ .whiteToMove = !self.whiteToMove, .WCastlingK = self.WCastlingK, .WCastlingQ = false, .BCastlingK = self.BCastlingK, .BCastlingQ = self.BCastlingQ };
            } else {
                return .{ .whiteToMove = !self.whiteToMove, .WCastlingK = self.WCastlingK, .WCastlingQ = self.WCastlingQ, .BCastlingK = self.BCastlingK, .BCastlingQ = false };
            }
        } else if (isRightRook(rooks)) {
            if (comptime self.whiteToMove) {
                return .{ .whiteToMove = !self.whiteToMove, .WCastlingK = false, .WCastlingQ = self.WCastlingQ, .BCastlingK = self.BCastlingK, .BCastlingQ = self.BCastlingQ };
            } else {
                return .{ .whiteToMove = !self.whiteToMove, .WCastlingK = false, .WCastlingQ = self.WCastlingQ, .BCastlingK = self.BCastlingK, .BCastlingQ = self.BCastlingQ };
            }
        }
        return self;
    }
    pub fn castlingKey(self: status) u4 {
        const ret: u4 = @intCast(@intFromBool(self.WCastlingK));
        return ret | (@intFromBool(self.WCastlingQ) << 1) | (@intFromBool(self.BCastlingK) << 2) | (@intFromBool(self.BCastlingQ) << 3);
    }
};
pub fn isLeftRook(rook: u64) bool {
    return (rook & LEFT_ROOKS) != chessl.EMPTY;
}
pub fn isRightRook(rook: u64) bool {
    return (rook & RIGHT_ROOKS) != chessl.EMPTY;
}
