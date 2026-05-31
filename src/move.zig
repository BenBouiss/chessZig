const std = @import("std");
const build_options = @import("build_options");

const chess = @import("chess.zig");
const mainl = @import("main.zig");
const hashl = @import("hashTable.zig");
const stringl = @import("string.zig");
const typel = @import("type.zig");

const utilsl = @import("utils.zig");

const e_piece = chess.e_piece;
const string = stringl.string;
const Key = hashl.Key;

pub const e_moveFlags = enum(u4) { QUIETMOVE = 0, DOUBLEPAWN = 1, KINGCASTLE = 2, QUEENCASTLE = 3, CAPTURE = 4, ENPASSANT = 5, KNIGHTPROMO = 8, BISHOPPROMO = 9, ROOKPROMO = 10, QUEENPROMO = 11, KNIGHTPROMOCAPTURE = 12, BISHOPPROMOCAPTURE = 13, ROOKPROMOCAPTURE = 14, QUEENPROMOCAPTURE = 15 };

const MOVE_STR_MAX_LENGTH = 5;

pub fn build_move(from: u8, to: u8, flag: u8) IMove {
    //var m_move: u16 = (flag);
    //m_move <<= 6;
    //m_move |= (to);
    //m_move <<= 6;
    //m_move |= (from);
    //const ret: IMove = .{ .m_move = m_move };
    //return ret;
    return .{ .m_move = (@as(u16, @intCast(flag)) << 12) | (@as(u16, @intCast(to)) << 6) | (@as(u16, @intCast(from))) };
}
pub fn build_move_in(from: u8, to: u8, flag: u8, p_out: *moveContainer) *IMove {
    p_out.moves[p_out.len] = .{ .m_move = (@as(u16, @intCast(flag)) << 12) | (@as(u16, @intCast(to)) << 6) | (@as(u16, @intCast(from))) };
    p_out.len += 1;
    return &p_out.moves[p_out.len - 1];
}

pub const moveInfo = struct {
    fromP: e_piece = .nEmptySquare,
    toP: e_piece = .nEmptySquare,
    to: u8 = 0,
    from: u8 = 0,
    flag: e_moveFlags = .QUIETMOVE,

    pub inline fn isCastle(self: moveInfo) bool {
        return self.flag == .KINGCASTLE or self.flag == .QUEENCASTLE;
    }

    pub inline fn isPromotion(self: moveInfo) bool {
        return (@intFromEnum(self.flag) >= @intFromEnum(e_moveFlags.KNIGHTPROMO));
    }
    pub inline fn isCapture(self: moveInfo) bool {
        return (@intFromEnum(self.flag) & @intFromEnum(e_moveFlags.CAPTURE) != 0);
    }
};
pub const IMove = extern struct {
    // <flag>: 4 bits, <to>: 6 bits, <from>: 6 bits ["start": 0th bit]
    m_move: u16 = 0,

    pub inline fn setFlag(p_self: *IMove, flag: u8) void {
        p_self.m_move &= (0xFFF);
        p_self.m_move |= (@as(u16, flag) << 12);
    }

    pub inline fn equal(self: IMove, other: IMove) bool {
        return (self.m_move == other.m_move);
    }

    pub fn isIn(self: IMove, move_arr: moveContainer) bool {
        for (0..move_arr.len) |i| {
            const move = move_arr.moves[i];
            if (self.equal(move)) {
                return true;
            }
        }
        return false;
    }
    pub fn getType(self: IMove) typel.e_moveType {
        if (self.isEnpassant()) {
            return .EP;
        }
        if (self.isCastle()) {
            return .CASTLE;
        }
        if (self.isPromotion()) {
            return .PROMOTION;
        }
        return .STANDARD;
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
        return (self.getFlag() & @intFromEnum(e_moveFlags.CAPTURE) != 0);
    }
    pub inline fn isQuietMove(self: IMove) bool {
        return self.getFlag() == @intFromEnum(e_moveFlags.QUIETMOVE);
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
    pub inline fn isCastle(self: IMove) bool {
        const flag = self.getFlag();
        return (flag == @intFromEnum(e_moveFlags.KINGCASTLE)) or (flag == @intFromEnum(e_moveFlags.QUEENCASTLE));
    }
    pub inline fn isEnpassant(self: IMove) bool {
        return (self.getFlag() == @intFromEnum(e_moveFlags.ENPASSANT));
    }
    pub inline fn isDoublePush(self: IMove) bool {
        return (self.getFlag() == @intFromEnum(e_moveFlags.DOUBLEPAWN));
    }
    pub inline fn isValid(self: IMove) bool {
        return (self.m_move != 0);
    }
    pub inline fn copy(self: IMove) IMove {
        return .{ .m_move = self.m_move };
    }
    pub fn getStr(self: IMove) [5]u8 {
        var strM: [5]u8 = undefined;
        const r1 = chess.strFromLERF(@enumFromInt(self.getFrom()));
        const r2 = chess.strFromLERF(@enumFromInt(self.getTo()));
        strM[0] = r1[0];
        strM[1] = r1[1];
        strM[2] = r2[0];
        strM[3] = r2[1];
        if (self.isPromotion()) {
            strM[4] = chess.getStrFromPiece(chess.flagPromotionToPiece(self.getFlag(), false));
        } else {
            strM[4] = 0;
        }
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
            ret.moves[i] = .{};
        }
        ret.len = len;
        return ret;
    }
    pub inline fn append(p_self: *moveContainer, move: IMove) void {
        p_self.moves[p_self.len] = move;
        p_self.len += 1;
    }

    pub fn isDifferent(self: moveContainer, other: moveContainer) bool {
        for (0..self.len) |i| {
            const move = self.moves[i];
            if (!move.isIn(other)) {
                return true;
            }
        }
        for (0..other.len) |i| {
            const move = other.moves[i];
            if (!move.isIn(self)) {
                return true;
            }
        }
        return false;
    }
    pub fn printDifference(self: moveContainer, other: moveContainer) void {
        std.debug.print("[DEBUG] printDifference: Size of container (1): {d}, size of container (2): {d}\n", .{ self.len, other.len });
        var biggerContainer = self;
        var smallerContainer = other;
        if (other.len > self.len) {
            biggerContainer = other;
            smallerContainer = self;
            std.debug.print("Printing the values found in container (2) not found in countainer (1): \n", .{});
        } else {
            std.debug.print("Printing the values found in container (1) not found in countainer (2): \n", .{});
        }
        for (0..biggerContainer.len) |i| {
            const move = biggerContainer.moves[i];
            if (!move.isIn(smallerContainer)) {
                std.debug.print("{s}-{} ", .{ move.getStr(), move.getFlag() });
            }
        }

        std.debug.print("\n Other container: \n '", .{});
        for (0..smallerContainer.len) |i| {
            const move = smallerContainer.moves[i];
            if (!move.isIn(biggerContainer)) {
                std.debug.print("{s}-{} ", .{ move.getStr(), move.getFlag() });
            }
        }
        std.debug.print(" '\n", .{});
        smallerContainer.print();
        biggerContainer.print();
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
    pub fn convertToArrayList(self: moveContainer, alloc: std.mem.Allocator) !std.ArrayList(IMove) {
        var ret = try std.ArrayList(IMove).initCapacity(alloc, self.len);
        for (0..self.len) |i| {
            try ret.append(alloc, self.moves[i].copy());
        }
        return ret;
    }
    pub fn cutEvenly(self: moveContainer, alloc: std.mem.Allocator, size: usize) !std.ArrayList(std.ArrayList(IMove)) {
        var arr = try self.convertToArrayList(alloc);
        defer arr.deinit(alloc);
        return try utilsl.cutArrayListEvenly(IMove, alloc, arr, size);
    }
};

//source: https://math.stackexchange.com/questions/194008/how-many-turns-can-a-chess-game-take-at-maximum
pub const MAX_MATCH_LENGTH: usize = 4096;
pub const MAX_MATCH_LENGTH_STR: usize = MAX_MATCH_LENGTH * (5 + 1);
pub const matchMoveContainer = struct {
    moves: [MAX_MATCH_LENGTH]IMove = undefined,
    keyCodes: [MAX_MATCH_LENGTH]u64 = undefined,
    irreversible: [MAX_MATCH_LENGTH]bool = undefined,

    lastIrreversibleMoveIndex: u16 = 0,
    len: u16 = 0,

    pub fn print(p_self: *const matchMoveContainer) void {
        // FOR DEBUG ONLY
        var line_str = p_self.getLineString(mainl.getGlobalGPA()) catch {
            return;
        };
        defer line_str.free(mainl.getGlobalGPA());
        std.debug.print("{s}\n", .{line_str._slice()});
        return;
    }
    pub fn append(p_self: *matchMoveContainer, move: IMove, key: Key, pawnMove: bool) bool {
        if (move.isCapture() or pawnMove) {
            p_self.lastIrreversibleMoveIndex = p_self.len;
            p_self.irreversible[p_self.len] = true;
        } else {
            p_self.irreversible[p_self.len] = false;
        }
        p_self.moves[p_self.len] = move;
        p_self.keyCodes[p_self.len] = key.code;
        p_self.len += 1;
        return true;
    }

    pub fn getRepetitions(self: *const matchMoveContainer) u8 {
        var count: u8 = 0;
        if (self.len >= (self.lastIrreversibleMoveIndex + 4)) {
            const keyRepet = self.keyCodes[self.len - 1];
            for (self.lastIrreversibleMoveIndex..self.len - 1) |i| {
                if (self.keyCodes[i] == keyRepet) {
                    count += 1;
                }
                if (count >= 2) {
                    return count;
                }
            }
        }
        return count;
    }
    pub inline fn checkRepetitions(self: *const matchMoveContainer) bool {
        const count = self.getRepetitions();
        return count >= 2;
    }

    pub fn popMove(p_self: *matchMoveContainer) IMove {
        p_self.len -= 1;
        if (p_self.len == 0) {
            p_self.lastIrreversibleMoveIndex = 0;
        } else if (p_self.lastIrreversibleMoveIndex == p_self.len) {
            p_self.lastIrreversibleMoveIndex = @intCast(p_self.len - 1);
            while (p_self.lastIrreversibleMoveIndex > 0) : (p_self.lastIrreversibleMoveIndex -= 1) {
                if (p_self.irreversible[p_self.lastIrreversibleMoveIndex]) {
                    break;
                }
            }
        }
        return p_self.moves[p_self.len];
    }
    pub inline fn popMoveVoid(p_self: *matchMoveContainer) void {
        _ = p_self.popMove();
    }
    pub inline fn getLastMove(self: matchMoveContainer) IMove {
        return self.moves[self.len - 1];
    }
    pub fn getLineFillString(self: matchMoveContainer, lineStr: *string) void {
        for (0..self.len) |i| {
            const move = self.moves[i];
            const moveStr = move.getStr();
            if (moveStr[4] == 0) {
                _ = lineStr.extend(moveStr[0..4]);
            } else {
                _ = lineStr.extend(&moveStr);
            }
            _ = lineStr.put(' ');
        }
        return;
    }
    pub fn getLineString(self: matchMoveContainer, alloc: std.mem.Allocator) !string {
        var lineStr: string = try string.initZero(alloc, self.len * (MOVE_STR_MAX_LENGTH + 1));
        self.getLineFillString(&lineStr);
        return lineStr;
    }
    pub fn getLineFromBuffer(self: matchMoveContainer, buffer: []u8) string {
        var lineStr: string = string.initFromBuffer(buffer);
        self.getLineFillString(&lineStr);
        return lineStr;
    }
    pub fn getLineStatic(self: matchMoveContainer) [MAX_MATCH_LENGTH_STR]u8 {
        var ret: [MAX_MATCH_LENGTH_STR]u8 = std.mem.zeroes([MAX_MATCH_LENGTH_STR]u8);
        var idx: usize = 0;

        for (0..self.len) |i| {
            const move = self.moves[i];
            const moveStr = move.getStr();
            if (moveStr[4] == 0) {
                @memcpy(ret[idx .. idx + 4], moveStr[0..4]);
                idx += 4;
            } else {
                //_ = lineStr.extend(&moveStr);
                @memcpy(ret[idx .. idx + 5], moveStr[0..5]);
                idx += 5;
            }
            ret[idx] = ' ';
            idx += 1;
            //_ = lineStr.put(' ');
        }
        return ret;
    }
};

pub const moveBBState = struct {
    pawnMoves: u64 = 0,
    pawnAttacks: u64 = 0,
    bishopMoves: u64 = 0,
    knightMoves: u64 = 0,
    rookMoves: u64 = 0,
    queenMoves: u64 = 0,
    kingMoves: u64 = 0,
    // possible extras here
    doubleMoves: u64 = 0,
    enPassantMoves: u64 = 0,
    promotionMoves: u64 = 0,

    queenSideCastlingMoves: u64 = 0,
    kingSideCastlingMoves: u64 = 0,

    pub inline fn resetAll(p_self: *moveBBState) void {
        p_self.* = .{};
    }
    pub fn resetPiece(p_self: *moveBBState, piece: e_piece) void {
        switch (piece) {
            .nWhitePawn, .nBlackPawn => {
                p_self.pawnAttacks = chess.EMPTY;
                p_self.pawnMoves = chess.EMPTY;
                p_self.enPassantMoves = chess.EMPTY;
                p_self.promotionMoves = chess.EMPTY;
            },
            .nWhiteBishop, .nBlackBishop => {
                p_self.bishopMoves = chess.EMPTY;
            },
            .nWhiteKnight, .nBlackKnight => {
                p_self.knightMoves = chess.EMPTY;
            },
            .nWhiteRook, .nBlackRook => {
                p_self.rookMoves = chess.EMPTY;
            },
            .nWhiteQueen, .nBlackQueen => {
                p_self.queenMoves = chess.EMPTY;
            },
            .nWhiteKing, .nBlackKing => {
                p_self.kingMoves = chess.EMPTY;
                p_self.kingSideCastlingMoves = chess.EMPTY;
                p_self.queenSideCastlingMoves = chess.EMPTY;
            },
        }
    }

    pub inline fn isEmpty(self: *const moveBBState) bool {
        return (self.pawnMoves | self.pawnAttacks | self.bishopMoves | self.knightMoves | self.rookMoves | self.queenMoves | self.kingMoves | self.doubleMoves) == chess.EMPTY;
    }
    pub inline fn getAttackedMask(self: *const moveBBState, occB: u64) u64 {
        return (self.pawnAttacks | self.bishopMoves | self.knightMoves | self.rookMoves | self.queenMoves | self.kingMoves) & occB;
    }
    pub inline fn andFn(self: *const moveBBState, bb: u64) moveBBState {
        return .{ .pawnMoves = self.pawnMoves & bb, .pawnAttacks = self.pawnAttacks & bb, .doubleMoves = self.doubleMoves & bb, .bishopMoves = self.bishopMoves & bb, .knightMoves = self.knightMoves & bb, .rookMoves = self.rookMoves & bb, .queenMoves = self.queenMoves & bb, .kingMoves = self.kingMoves & bb, .enPassantMoves = self.enPassantMoves & bb, .promotionMoves = self.promotionMoves & bb, .queenSideCastlingMoves = self.queenSideCastlingMoves & bb, .kingSideCastlingMoves = self.kingSideCastlingMoves & bb };
    }
    pub inline fn orFn(self: *const moveBBState, bb: u64) moveBBState {
        return .{ .pawnMoves = self.pawnMoves | bb, .pawnAttacks = self.pawnAttacks | bb, .doubleMoves = self.doubleMoves | bb, .bishopMoves = self.bishopMoves | bb, .knightMoves = self.knightMoves | bb, .rookMoves = self.rookMoves | bb, .queenMoves = self.queenMoves | bb, .kingMoves = self.kingMoves | bb, .enPassantMoves = self.enPassantMoves | bb, .promotionMoves = self.promotionMoves | bb, .queenSideCastlingMoves = self.queenSideCastlingMoves | bb, .kingSideCastlingMoves = self.kingSideCastlingMoves | bb };
    }

    pub inline fn collapse(self: *const moveBBState) u64 {
        return self.pawnMoves | self.pawnAttacks | self.doubleMoves | self.bishopMoves | self.knightMoves | self.rookMoves | self.queenMoves | self.kingMoves | self.enPassantMoves | self.promotionMoves | self.queenSideCastlingMoves | self.kingSideCastlingMoves;
    }

    pub fn andEq(p_self: *moveBBState, bb: u64) void {
        p_self.pawnMoves &= bb;
        p_self.pawnAttacks &= bb;
        p_self.doubleMoves &= bb;
        p_self.bishopMoves &= bb;
        p_self.knightMoves &= bb;
        p_self.rookMoves &= bb;
        p_self.queenMoves &= bb;
        p_self.kingMoves &= bb;

        p_self.enPassantMoves &= bb;
        p_self.promotionMoves &= bb;
        p_self.queenSideCastlingMoves &= bb;
        p_self.kingSideCastlingMoves &= bb;
        return;
    }
    pub fn orEq(p_self: *moveBBState, bb: u64) void {
        p_self.pawnMoves |= bb;
        p_self.pawnAttacks |= bb;
        p_self.doubleMoves |= bb;
        p_self.bishopMoves |= bb;
        p_self.knightMoves |= bb;
        p_self.rookMoves |= bb;
        p_self.queenMoves |= bb;
        p_self.kingMoves |= bb;

        p_self.enPassantMoves |= bb;
        p_self.promotionMoves |= bb;
        p_self.queenSideCastlingMoves |= bb;
        p_self.kingSideCastlingMoves |= bb;
        return;
    }

    pub fn print(self: moveBBState) void {
        // for debugging purposes
        std.debug.print("Pawn moves: \n", .{});
        chess.print_bitboard(self.pawnMoves);
        std.debug.print("Pawn attacks: \n", .{});
        chess.print_bitboard(self.pawnAttacks);

        std.debug.print("Pawn double moves: \n", .{});
        chess.print_bitboard(self.doubleMoves);
        std.debug.print("Pawn enpassant: \n", .{});
        chess.print_bitboard(self.enPassantMoves);
        std.debug.print("Pawn promotion: \n", .{});
        chess.print_bitboard(self.promotionMoves);

        std.debug.print("Bishop moves: \n", .{});
        chess.print_bitboard(self.bishopMoves);
        std.debug.print("Knight moves: \n", .{});
        chess.print_bitboard(self.knightMoves);
        std.debug.print("Rook moves: \n", .{});
        chess.print_bitboard(self.rookMoves);

        std.debug.print("Queen moves: \n", .{});
        chess.print_bitboard(self.queenMoves);
        std.debug.print("King moves: \n", .{});
        chess.print_bitboard(self.kingMoves);
    }
    pub fn count(self: *const moveBBState) u64 {
        var ret: u64 = @intCast(chess.popcount(self.pawnMoves));
        ret += @intCast(chess.popcount(self.bishopMoves));
        ret += @intCast(chess.popcount(self.doubleMoves));
        ret += @intCast(chess.popcount(self.enPassantMoves));
        ret += @intCast(chess.popcount(self.kingMoves));
        ret += @intCast(chess.popcount(self.kingSideCastlingMoves));
        ret += @intCast(chess.popcount(self.knightMoves));
        ret += @intCast(chess.popcount(self.pawnAttacks));
        ret += @intCast(chess.popcount(self.promotionMoves));
        ret += @intCast(chess.popcount(self.queenMoves));
        ret += @intCast(chess.popcount(self.queenSideCastlingMoves));
        ret += @intCast(chess.popcount(self.rookMoves));
        return ret;
    }
    pub inline fn rawCount(p_self: *const moveBBState) u64 {
        return @intCast(chess.popcount(p_self.collapse()));
    }
};

pub const line = struct {
    moves: [typel.MAX_PLY]IMove = undefined,
    len: usize = 0,
    pub fn format(self: *const line, writer: *std.Io.Writer) !void {
        for (0..self.len) |i| {
            try writer.print("{s} ", .{utilsl.trimStr(&self.moves[i].getStr())});
        }
    }
    pub fn print(self: *const line) void {
        for (0..self.len) |i| {
            std.debug.print("{s} ", .{self.moves[i].getStr()});
        }
        std.debug.print("\n", .{});
    }
    pub fn setLineFromPV(self: *line, pv: *pvContainer) void {
        self.len = pv.len;
        for (0..self.len) |i| {
            self.moves[i] = pv.moves[i];
        }
    }
    pub fn copyFromLine(self: *line, other: *line) void {
        for (0..other.len) |i| {
            self.moves[i] = other.moves[i];
        }
        self.len = other.len;
    }
};
pub const pvContainer = struct {
    moves: [typel.MAX_PLY]IMove = undefined,
    len: u8 = 0,

    pub fn print(self: *const pvContainer) void {
        for (0..self.len) |i| {
            std.debug.print("{s} ", .{self.moves[i].getStr()});
        }
        std.debug.print("\n", .{});
    }
    pub fn onBestMove(self: *pvContainer, move: IMove, other: ?*const pvContainer) void {
        if (other) |child| {
            self.len = child.len;
            @memcpy(self.moves[1 .. self.len + 1], child.moves[0..self.len]);
            //for (0..child.len) |i| {
            //    self.moves[1 + i] = child.moves[i];
            //}
        } else {
            self.len = 0;
        }
        self.moves[0] = move;
        self.len += 1;
    }
};
