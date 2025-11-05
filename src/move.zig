const std = @import("std");
const chess = @import("chess.zig");
const squarel = @import("square.zig");

const e_piece = chess.e_piece;
const e_square = squarel.e_square;

const e_moveFlags = chess.e_moveFlags;

pub fn build_move(from: u8, to: u8, flag: u8) IMove {
    var m_move: u16 = (flag & 0xF);
    m_move <<= 6;
    m_move |= (to & 0x3F);
    m_move <<= 6;
    m_move |= (from & 0x3F);
    const ret: IMove = .{ .m_move = m_move };
    return ret;
}

pub const IMove = struct {
    c_piece: e_piece = e_piece.nEmptySquare,
    m_move: u16 = 0,

    pub fn setCapture(p_self: *IMove, capture: e_piece) void {
        p_self.c_piece = capture;
    }

    pub fn equal(self: IMove, other: IMove) bool {
        return ((self.m_move == other.m_move) and (self.c_piece == other.c_piece));
    }
    pub fn isIn(self: IMove, move_arr: moveContainer) bool {
        for (move_arr.moves) |move| {
            if (self.equal(move)) {
                return true;
            }
        }
        return false;
    }
    pub inline fn getFrom(self: IMove) u8 {
        return @intCast((self.m_move & 0x3F));
    }
    pub inline fn getTo(self: IMove) u8 {
        return @intCast((self.m_move & (0xFC0)) >> 6);
    }
    pub inline fn getFlag(self: IMove) u8 {
        return @intCast((self.m_move & (0xF000)) >> 12);
    }
    pub inline fn isCapture(self: IMove) bool {
        const ret = (self.getFlag() & @intFromEnum(e_moveFlags.CAPTURE) != 0);
        return ret;
    }
    pub inline fn isPromotion(self: IMove) bool {
        return (self.getFlag() >= @intFromEnum(e_moveFlags.KNIGHTPROMO));
    }
    pub inline fn isKingSideCastle(self: IMove) bool {
        return (self.getFlag() == @intFromEnum(e_moveFlags.KINGCASTLE));
    }
    pub inline fn isQueenSideCastle(self: IMove) bool {
        return (self.getFlag() == @intFromEnum(e_moveFlags.QUEENCASTLE));
    }
    pub inline fn isEnpassant(self: IMove) bool {
        return (self.getFlag() == @intFromEnum(e_moveFlags.ENPASSANT));
    }

    pub inline fn isValid(self: IMove) bool {
        return (self.m_move != 0);
    }
    pub fn copy(self: IMove) IMove {
        return .{ .m_move = self.m_move, .c_piece = self.c_piece };
    }
    pub fn getStr(self: IMove) [4]u8 {
        var strM: [4]u8 = undefined;
        const r1 = stringFromLERF(@enumFromInt(self.getFrom()));
        const r2 = stringFromLERF(@enumFromInt(self.getTo()));
        strM[0] = r1[0];
        strM[1] = r1[1];
        strM[2] = r2[0];
        strM[3] = r2[1];
        return strM;
    }
    pub fn print(self: IMove) void {
        std.debug.print("{s} ", .{self.getStr()});
    }
};

pub const moveContainer = struct {
    moves: [chess.MAX_POSSIBLE_MOVE]IMove = undefined,
    len: u8 = 0,

    pub fn init(len: u8) moveContainer {
        var ret: moveContainer = undefined;
        for (0..len) |i| {
            ret.move[i] = 0;
        }
        ret.len = len;
    }
    pub fn append(p_self: *moveContainer, move: IMove) bool {
        if (p_self.len == chess.MAX_POSSIBLE_MOVE) {
            return false;
        }
        p_self.moves[p_self.len] = move.copy();
        p_self.len += 1;
        return true;
    }

    pub fn extend(p_self: *moveContainer, p_other: *const moveContainer) bool {
        if ((p_self.len + p_other.len) > chess.MAX_POSSIBLE_MOVE) {
            return false;
        }
        for (0..p_other.len) |i| {
            p_self.moves[p_self.len + i] = p_other.moves[i].copy();
        }
        p_self.len += p_other.len;
        return true;
    }

    pub fn shuffle(p_self: *moveContainer, rand: std.Random) void {
        //const tmp_buffer = p_self.moves[0..p_self.len];
        std.Random.shuffle(rand, IMove, p_self.moves[0..p_self.len]);
    }
    pub fn sample(self: moveContainer, rand: std.Random) usize {
        return rand.uintAtMost(u8, @intCast(self.len - 1));
    }
    pub fn print(self: moveContainer) void {
        std.debug.print("Container's length: {d} \n", .{self.len});
        std.debug.print("<<<< ", .{});
        var i: usize = 0;
        for (self.moves) |move| {
            std.debug.print("{s} ", .{move.getStr()});
            if (self.len != 0) {
                if (i == (self.len - 1)) {
                    std.debug.print(">>>>", .{});
                }
            }
            i += 1;
        }
        std.debug.print("\n", .{});
    }
};

pub fn stringFromLERF(sq: e_square) [2]u8 {
    var ret: [2]u8 = undefined;
    const sq_i: u8 = @intFromEnum(sq);
    ret[0] = 'a' + sq_i % 8;
    ret[1] = '1' + sq_i / 8;
    return ret;
}
