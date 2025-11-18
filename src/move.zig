const std = @import("std");
const build_options = @import("build_options");

const chess = @import("chess.zig");
const squarel = @import("square.zig");

const e_piece = chess.e_piece;
const e_square = squarel.e_square;

const ignoreChecks = build_options.fastBitscan;

pub const e_moveFlags = enum(u4) { QUIETMOVE = 0, DOUBLEPAWN = 1, KINGCASTLE = 2, QUEENCASTLE = 3, CAPTURE = 4, ENPASSANT = 5, KNIGHTPROMO = 8, BISHOPPROMO = 9, ROOKPROMO = 10, QUEENPROMO = 11, KNIGHTPROMOCAPTURE = 12, BISHOPPROMOCAPTURE = 13, ROOKPROMOCAPTURE = 14, QUEENPROMOCAPTURE = 15 };
pub const e_moveCategory = enum(u4) { QUIET, CAPTURE };

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
const GLOBAL_ALLOC = GPA.allocator();

//pub fn build_move(p_board: *chess.Board_state, from: u8, to: u8, flag: u8, piece: e_piece) IMove {
//    return _build_move(from, to, flag, piece);
//}

pub fn build_move(from: u8, to: u8, flag: u8, piece: e_piece) IMove {
    var m_move: u16 = (flag & 0xF);
    m_move <<= 6;
    m_move |= (to & 0x3F);
    m_move <<= 6;
    m_move |= (from & 0x3F);
    const ret: IMove = .{ .m_move = m_move, .m_piece = (@intFromEnum(piece) & 0xFF) };
    return ret;
}

pub fn build_move_ext(from: u8, to: u8, flag: u8, piece: e_piece, m_restore: u16, m_next: u16) IMove {
    var m_move: u16 = (flag & 0xF);
    m_move <<= 6;
    m_move |= (to & 0x3F);
    m_move <<= 6;
    m_move |= (from & 0x3F);
    const ret: IMove = .{ .m_move = m_move, .m_piece = (@intFromEnum(piece) & 0xFF), .m_restore = m_restore, .m_next = m_next };
    return ret;
}

pub fn boardStateToSpecial(p_board: *chess.Board_state, comptime turn: chess.e_color) u16 {
    var ret: u16 = 0;
    if (comptime turn == .WHITE) {
        const castl_bits = p_board.castlingBB & 0xFF;
        const eP_bits = p_board.enPassantBB[@intFromEnum(chess.e_color.WHITE)] & 0xFF0000;
        ret |= (castl_bits << 8) | eP_bits;
    } else {
        const castl_bits = p_board.castlingBB & 0xFF00000000000000 >> 56;
        const eP_bits = p_board.enPassantBB[@intFromEnum(chess.e_color.BLACK)] & 0xFF0000000000;
        ret |= (castl_bits << 8) | eP_bits;
    }
    return ret;
}

pub const IMove = struct {
    m_move: u16 = 0,
    // first 8 bits = start_piece, last = capture_piece
    m_piece: u16 = 0,

    //size:
    //  for enpassant only 1(one) pawn can be in enpassant state
    //  Restore (present in p_board at move gen time):
    //  <3> pawn en passant
    //  <3> castling possible
    //  Next Provided by move gen
    //  <3> pawn en passant
    //  <3> castling possible
    //m_special: u16 = 0,

    m_restore: u16 = 0,
    m_next: u16 = 0,

    pub fn getRestoreEnpassantBB(self: IMove) u64 {
        return (self.m_restore & 0xFF);
    }
    pub fn getNextEnpassantBB(self: IMove) u64 {
        return (self.m_next & 0xFF);
    }

    pub fn getRestoreCastlingBB(self: IMove) u64 {
        return self.m_restore & 0xFF00;
    }
    pub fn getNextCastlingBB(self: IMove) u64 {
        return self.m_next & 0xFF00;
    }

    pub fn setCapture(p_self: *IMove, capture: e_piece) void {
        //p_self.c_piece = capture;
        var m_piece: u16 = @intFromEnum(capture);
        m_piece <<= 8;
        p_self.m_piece &= (0xFF);
        p_self.m_piece |= (m_piece);
    }

    pub fn equal(self: IMove, other: IMove) bool {
        return ((self.m_move == other.m_move) and (self.m_piece == other.m_piece));
    }

    pub fn softEqual(self: IMove, other: IMove) bool {
        return (self.getFrom() == other.getFrom()) and (self.getTo() == other.getTo());
    }

    pub fn isIn(self: IMove, move_arr: moveContainer) bool {
        for (move_arr.moves) |move| {
            if (self.softEqual(move)) {
                return true;
            }
        }
        return false;
    }
    pub inline fn getFrom(self: IMove) u8 {
        return @intCast((self.m_move & 0x3F));
    }

    pub inline fn getFromPiece(self: IMove) e_piece {
        return @enumFromInt((self.m_piece & 0xFF));
    }

    pub inline fn getCapturePiece(self: IMove) e_piece {
        return @enumFromInt((self.m_piece & 0xFF00) >> 8);
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
    pub fn isCastle(self: IMove) bool {
        return self.isKingSideCastle() or self.isQueenSideCastle();
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
    pub fn copy(self: IMove) IMove {
        return .{ .m_move = self.m_move, .m_piece = self.m_piece };
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

pub const typedMoveContainer = struct {
    quietMoves: moveContainer = .{},
    captureMoves: moveContainer = .{},
    len: u64 = 0,
    pub fn print(self: typedMoveContainer) void {
        std.debug.print("[PRINT] typedMoveContainer: quiet moves: \n", .{});
        self.quietMoves.print();

        std.debug.print("[PRINT] typedMoveContainer: capture moves: \n", .{});
        self.captureMoves.print();
    }

    pub fn flatten(self: typedMoveContainer) moveContainer {
        var ret: moveContainer = .{ .len = 0 };
        _ = ret.extend(&self.quietMoves);
        _ = ret.extend(&self.captureMoves);
        return ret;
    }

    fn append(p_self: *typedMoveContainer, move: IMove, comptime category: e_moveCategory) void {
        if (comptime category == .QUIET) {
            p_self.quietMoves.append(move);
        } else if (comptime category == .CAPTURE) {
            p_self.captureMoves.append(move);
        } else {
            @panic("");
        }
        p_self.len += 1;
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
        //if (p_self.len == chess.MAX_POSSIBLE_MOVE) {
        //    return false;
        //}
        p_self.moves[p_self.len] = move;
        p_self.len += 1;
        return true;
    }

    pub fn extend(p_self: *moveContainer, p_other: *const moveContainer) bool {
        if (comptime !ignoreChecks) {
            if ((p_self.len + p_other.len) > chess.MAX_POSSIBLE_MOVE) {
                return false;
            }
        }
        for (0..p_other.len) |i| {
            p_self.moves[p_self.len + i] = p_other.moves[i];
        }
        p_self.len += p_other.len;
        return true;
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
                std.debug.print("{s} ", .{move.getStr()});
            }
        }

        std.debug.print("\n", .{});
        smallerContainer.print();
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
    pub fn convertToArrayList(self: moveContainer, alloc: std.mem.Allocator) !std.ArrayList(IMove) {
        var ret = try std.ArrayList(IMove).initCapacity(alloc, self.len);
        for (0..self.len) |i| {
            try ret.append(GLOBAL_ALLOC, self.moves[i].copy());
        }
        return ret;
    }
};

//source: https://math.stackexchange.com/questions/194008/how-many-turns-can-a-chess-game-take-at-maximum
pub const MAX_MATCH_LENGTH: usize = 6000;
pub const matchMoveContainer = struct {
    moves: [MAX_MATCH_LENGTH]IMove = undefined,
    len: usize = 0,
    pub fn append(p_self: *matchMoveContainer, move: IMove) bool {
        if (comptime !ignoreChecks) {
            if (p_self.len == MAX_MATCH_LENGTH) {
                return false;
            }
        }
        p_self.moves[p_self.len] = move;
        p_self.len += 1;
        return true;
    }
    pub fn pop(p_self: *matchMoveContainer) IMove {
        if (comptime !ignoreChecks) {
            if (p_self.len == 0) {
                return .{};
            }
        }
        p_self.len -= 1;
        return p_self.moves[p_self.len];
    }
    pub fn fiftyMoveRule(self: matchMoveContainer) bool {
        //for (0..50) |i|{
        //    const move = self.moves[self.len - (i+1)];
        //    if (move.isCapture() or move.
        //}
        _ = self;
        return false;
    }
};

pub fn stringFromLERF(sq: e_square) [2]u8 {
    var ret: [2]u8 = undefined;
    const sq_i: u8 = @intFromEnum(sq);
    ret[0] = 'a' + sq_i % 8;
    ret[1] = '1' + sq_i / 8;
    return ret;
}

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

    pub fn isEmpty(self: moveBBState) bool {
        return (self.pawnMoves | self.pawnAttacks | self.bishopMoves | self.knightMoves | self.rookMoves | self.queenMoves | self.kingMoves | self.doubleMoves) == chess.EMPTY;
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
    pub fn convertToMoveContainer(self: moveBBState) moveContainer {
        _ = self;
        return .{};
    }
};
