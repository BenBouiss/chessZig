const std = @import("std");

const chessl = @import("chess.zig");
const movel = @import("move.zig");

const build_options = @import("build_options");

// Testing Gigantua approach
// massive rewrite needed probably
const useDebug = build_options.useDebug;

const LEFT_ROOKS: u64 = 0x100000000000001;
const RIGHT_ROOKS: u64 = 0x8000000000000080;

pub const wCastleKKingBit: u64 = 0x50;
pub const wCastleKRookBit: u64 = 0xA0;
pub const wCastleQKingBit: u64 = 0x14;
pub const wCastleQRookBit: u64 = 0x9;

pub const bCastleKKingBit: u64 = 0x5000000000000009;
pub const bCastleKRookBit: u64 = 0xA000000000000000;
pub const bCastleQKingBit: u64 = 0x1400000000000000;
pub const bCastleQRookBit: u64 = 0x900000000000000;

pub const e_turn = enum(u2) { BLACK = 0, WHITE = 1 };
pub const statusStack = struct {
    // status: 5 bools
    // size: 5 bytes
    // stacksize = 5 * 4096 = 20 480 bytes
    //
    // if packed to u8 size = 1 byte
    // stacksize = 4096 bytes
    items: [movel.MAX_MATCH_LENGTH]status = undefined,
    len: usize = 0,

    pub inline fn push(p_self: *statusStack, item: status) void {
        p_self.items[p_self.len] = item;
        p_self.len += 1;
    }
    pub inline fn pop(p_self: *statusStack) status {
        if (comptime useDebug) {
            if (p_self.len == 0) {
                @panic("Popping from empty boardframe, forgot to push?");
            }
        }
        p_self.len -= 1;
        return p_self.items[p_self.len];
    }
};

const whiteToMoveMask: u8 = 0x1;
const WCastlingKMask: u8 = 0x2;
const WCastlingQMask: u8 = 0x4;
const WCastlingMask: u8 = 0x6;

const BCastlingKMask: u8 = 0x8;
const BCastlingQMask: u8 = 0x10;
const BCastlingMask: u8 = 0x18;
//offset size
//0  1 bit whiteToMove
//1  1 bit WCastlingK
//2  1 bit WCastlingQ
//3  1 bit BCastlingK
//4  1 bit BCastlingQ
pub const status = struct {
    val: u8 = 0x1,
    pub inline fn init(whiteMove: bool, b_WCastlingK: bool, b_WCastlingQ: bool, b_BCastlingK: bool, b_BCastlingQ: bool) status {
        return .{ .val = @as(u8, @intFromBool(whiteMove)) | (@as(u8, @intFromBool(b_WCastlingK)) << 1) | (@as(u8, @intFromBool(b_WCastlingQ)) << 2) | (@as(u8, @intFromBool(b_BCastlingK)) << 3) | (@as(u8, @intFromBool(b_BCastlingQ)) << 4) };
    }
    pub inline fn whiteToMove(self: status) bool {
        return (self.val & whiteToMoveMask) != 0;
    }
    pub inline fn invertTurn(self: *status) void {
        self.val ^= whiteToMoveMask;
    }
    pub inline fn WCastlingK(self: status) bool {
        return (self.val & WCastlingKMask) != 0;
    }
    pub inline fn WCastlingQ(self: status) bool {
        return (self.val & WCastlingQMask) != 0;
    }
    pub inline fn BCastlingK(self: status) bool {
        return (self.val & BCastlingKMask) != 0;
    }
    pub inline fn BCastlingQ(self: status) bool {
        return (self.val & BCastlingQMask) != 0;
    }

    pub inline fn setTurn(self: *status, white: bool) void {
        self.val &= (~whiteToMoveMask);
        self.val |= @intFromBool(white);
    }
    pub inline fn setWCastlingK(self: *status, b_castling: bool) void {
        self.val &= (~WCastlingKMask);
        self.val |= @as(u8, @intFromBool(b_castling)) << 1;
    }
    pub inline fn setWCastlingQ(self: *status, b_castling: bool) void {
        self.val &= (~WCastlingQMask);
        self.val |= @as(u8, @intFromBool(b_castling)) << 2;
    }
    pub inline fn setBCastlingK(self: *status, b_castling: bool) void {
        self.val &= (~BCastlingKMask);
        self.val |= @as(u8, @intFromBool(b_castling)) << 3;
    }
    pub inline fn setBCastlingQ(self: *status, b_castling: bool) void {
        self.val &= (~BCastlingQMask);
        self.val |= @as(u8, @intFromBool(b_castling)) << 4;
    }

    pub inline fn canCastle(self: status, comptime whiteMove: bool) bool {
        if (comptime whiteMove) {
            return self.WCastlingK() | self.WCastlingQ();
        } else {
            return self.BCastlingK() | self.BCastlingQ();
        }
    }
    pub inline fn canKingsideCastle(self: status, comptime whiteMove: bool) bool {
        if (comptime whiteMove) {
            return self.WCastlingK();
        }
        return self.BCastlingK();
    }
    pub inline fn canQueensideCastle(self: status, comptime whiteMove: bool) bool {
        if (comptime whiteMove) {
            return self.WCastlingQ();
        }
        return self.BCastlingQ();
    }
    pub inline fn onKingMove(self: status) status {
        if (self.whiteToMove()) {
            return .{ .val = self.val & (BCastlingMask) };
        } else {
            return .{ .val = 1 | (self.val & (WCastlingMask)) };
        }
    }
    pub fn onRookMove(self: status, rooks: u64, comptime white: bool) status {
        if (comptime white) {
            if (isLeftRook(rooks)) {
                return .{ .val = self.val & (~(WCastlingQMask | 1)) };
            } else if (isRightRook(rooks)) {
                return .{ .val = self.val & (~(WCastlingKMask | 1)) };
            } else {
                return .{ .val = self.val & (~@as(u8, 1)) };
            }
        } else {
            if (isLeftRook(rooks)) {
                return .{ .val = 1 | (self.val & (~(BCastlingQMask))) };
            } else if (isRightRook(rooks)) {
                return .{ .val = 1 | (self.val & (~(BCastlingKMask))) };
            } else {
                return .{ .val = 1 | self.val };
            }
        }
    }

    pub inline fn castlingKey(self: status) u4 {
        const r1: u4 = @intCast(@intFromBool(self.WCastlingK()));
        const r2: u4 = @intCast(@intFromBool(self.WCastlingQ()));
        const r3: u4 = @intCast(@intFromBool(self.BCastlingK()));
        const r4: u4 = @intCast(@intFromBool(self.BCastlingQ()));
        return r1 | (r2 << 1) | (r3 << 2) | (r4 << 3);
    }
};
pub inline fn isLeftRook(rook: u64) bool {
    return (rook & LEFT_ROOKS) != chessl.EMPTY;
}
pub inline fn isRightRook(rook: u64) bool {
    return (rook & RIGHT_ROOKS) != chessl.EMPTY;
}
