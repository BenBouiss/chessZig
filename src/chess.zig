const std = @import("std");

//https://stackoverflow.com/questions/76384694/how-to-do-conditional-compilation-with-zig
const build_options = @import("build_options");

pub const fastBitscan = build_options.fastBitscan;
const ignoreChecks = build_options.fastBitscan;
const useMagic = build_options.useMagic;
const useStaged = build_options.useStaged;
const useDebug = build_options.useDebug;

const chess = @import("chess.zig");
const utils = @import("utils.zig");
const exploration = @import("exploration.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const moveGenl = @import("move_generation.zig");
const heuristicl = @import("heuristic.zig");
const intrinsicsl = @import("intrinsics.zig");
const tablel = @import("moveTables.zig");
const magicl = @import("magic.zig");
const mainl = @import("main.zig");

const IMove = movel.IMove;
const e_moveFlags = movel.e_moveFlags;
const moveContainer = movel.moveContainer;
const matchMoveContainer = movel.matchMoveContainer;
const cachedTables = tablel.cachedTables;
const GLOBAL_ALLOC = mainl.GLOBAL_ALLOC;

const e_matchFlag = exploration.e_matchFlag;

const e_square = squarel.e_square;
const squareInfo = squarel.squareInfo;

const _alloc = mainl.GLOBAL_ALLOC;
pub inline fn get_global_alloc() std.mem.Allocator {
    return _alloc;
}

pub const NUMBER_PLAYER: u8 = 2;
pub const ROW_SIZE: u8 = 8;
pub const COL_SIZE: u8 = 8;
pub const N_SQUARES: u8 = ROW_SIZE * COL_SIZE;
pub const MAX_POSSIBLE_MOVE: u8 = 218;
pub const N_PIECES = 15;
pub const N_PIECES_TYPES = 6;
pub const QUEENSIDECASTLEID = 0;
pub const KINGCASTLEID = 1;
pub const KINGSIDECASTLEID = 2;
pub const INVALID_POSITION: i8 = -1;

pub const EMPTY: u64 = 0;
pub const ONE: u64 = 1;
pub const ONE_u8: u64 = 1;
pub const UNIVERSE: u64 = std.math.maxInt(u64);
//const UNIVERSE: u64 = -1;

// see calc or src/utils.py
pub const aFile: u64 = 0x101010101010101;
pub const firstRank: u64 = 0xFF;
pub const notAFile: u64 = 0xfefefefefefefefe; // ~0x0101010101010101
pub const notABFile: u64 = 0xfcfcfcfcfcfcfcfc;
pub const notGHFile: u64 = 0x3f3f3f3f3f3f3f3f;
pub const notHFile: u64 = 0x7f7f7f7f7f7f7f7f; // ~0x8080808080808080
pub const whitePawnPromoRank: u64 = 0xFF00000000000000;
pub const blackPawnPromoRank: u64 = 0xFF;

pub const whitePawnDoubleRank: u64 = 0xFF00;
pub const blackPawnDoubleRank: u64 = 0xFF000000000000;

pub const whitePawnEnpassantRank: u64 = 0xFF0000000000;
pub const blackPawnEnpassantRank: u64 = 0xFF0000;

const DEFAULT_POSITION: u64 = 0xFDFD06000040FFDF;
pub const DEFAULT_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq";
const shift = [8]c_int{ 9, 1, -7, -8, -9, -1, 7, 8 };
const avoidWrap = [8]u64{
    0xfefefefefefefe00,
    0xfefefefefefefefe,
    0x00fefefefefefefe,
    0x00ffffffffffffff,
    0x007f7f7f7f7f7f7f,
    0x7f7f7f7f7f7f7f7f,
    0x7f7f7f7f7f7f7f00,
    0xffffffffffffff00,
};
// taken from hqperft from github
const MASK_CASTLING = [64]u8{ 13, 15, 15, 15, 12, 15, 15, 14, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 7, 15, 15, 15, 3, 15, 15, 11 };

pub const e_piece = enum(u8) { nWhite = 1, nWhitePawn = 2, nWhiteBishop = 3, nWhiteKnight = 4, nWhiteRook = 5, nWhiteQueen = 6, nWhiteKing = 7, nBlack = 8, nBlackPawn = 9, nBlackBishop = 10, nBlackKnight = 11, nBlackRook = 12, nBlackQueen = 13, nBlackKing = 14, nEmptySquare = 0 };

pub const e_color = enum(u8) { WHITE = 0, BLACK = 1 };

const arr_color_conv = [2]e_piece{ e_piece.nWhite, e_piece.nBlack };
const arr_color_inv = [2]e_color{ e_color.BLACK, e_color.WHITE };
const arr_piece_str = [_]u8{ '_', '1', 'P', 'B', 'N', 'R', 'Q', 'K', '2', 'p', 'b', 'n', 'r', 'q', 'k' };

//const e_piece_str = enum(u8) { nWhitePawn = "P", nBlackPawn = "p", nWhiteBishop = "B", nWhiteKnight = "N", nWhiteKing = "K", nWhiteRook = "R", BlackBisho = "b", nBlackRook = "r", nWhiteQueen = "Q", n_BlackKnight = "n", nBlackQueen = "q", nBlackKing = "k" };

pub const e_direction = enum(u8) { NORTH = 0, SOUTH = 1, WEST = 2, EAST = 3, NORTHWEST = 4, SOUTHEAST = 5, NORTHEAST = 6, SOUTHWEST = 7 };

const debug_err = error{earlyReturn};

pub fn stringToLERF(sq: *[2]u8) e_square {
    if ((sq[0] < 'a') or (sq[0] > 'h')) {
        return .invalid;
    }
    if ((sq[1] < '1') or (sq[1] > '9')) {
        return .invalid;
    }
    return @enumFromInt((sq[0] - 'a') + ((sq[1] - '1') * ROW_SIZE));
}

pub fn flagPromotionToPiece(flag: u8, turn: e_color) e_piece {
    if ((flag == @intFromEnum(e_moveFlags.KNIGHTPROMO)) or (flag == @intFromEnum(e_moveFlags.KNIGHTPROMOCAPTURE))) {
        const piece: u8 = @intFromEnum(e_piece.nWhiteKnight) - 1 + @intFromEnum(convertColorToColorPiece(turn));
        return @enumFromInt(piece);
    } else if ((flag == @intFromEnum(e_moveFlags.BISHOPPROMO)) or (flag == @intFromEnum(e_moveFlags.BISHOPPROMOCAPTURE))) {
        const piece: u8 = @intFromEnum(e_piece.nWhiteBishop) - 1 + @intFromEnum(convertColorToColorPiece(turn));
        return @enumFromInt(piece);
    } else if ((flag == @intFromEnum(e_moveFlags.ROOKPROMO)) or (flag == @intFromEnum(e_moveFlags.ROOKPROMOCAPTURE))) {
        const piece: u8 = @intFromEnum(e_piece.nWhiteRook) - 1 + @intFromEnum(convertColorToColorPiece(turn));
        return @enumFromInt(piece);
    } else if ((flag == @intFromEnum(e_moveFlags.QUEENPROMO)) or (flag == @intFromEnum(e_moveFlags.QUEENPROMOCAPTURE))) {
        const piece: u8 = @intFromEnum(e_piece.nWhiteQueen) - 1 + @intFromEnum(convertColorToColorPiece(turn));
        return @enumFromInt(piece);
    }
    return e_piece.nEmptySquare;
}

pub fn _genShift(x: u64, s: i8) u64 {
    var ret: u64 = x;
    if (s >= 0) {
        for (0..@intCast(s)) |_| {
            ret <<= 1;
        }
    } else {
        for (0..@intCast(-s)) |_| {
            ret >>= 1;
        }
    }
    return ret;
}

pub fn genShift(x: u64, s: i8) u64 {
    if (s >= 0) {
        return x << @intCast(s);
    } else {
        return x >> @intCast(-s);
    }
    return 0;
}

pub fn sqToBitboard(sq: e_square) u64 {
    return ONE << @intCast(@intFromEnum(sq));
}

pub fn xToBitboard(x: u8) u64 {
    return ONE << @intCast(x);
}

pub fn free_move_history(move_arr: std.array_list) void {
    _ = move_arr;
    return;
}

//
// bitScanForward
// @author Martin Läuter (1997)
//         Charles E. Leiserson
//         Harald Prokop
//         Keith H. Randall
// "Using de Bruijn Sequences to Index a 1 in a Computer Word"
// @param bb bitboard to scan
// @precondition bb != 0
// @return index (0..63) of least significant one bit
//

pub fn bitscan(bb: u64) i8 {
    if (comptime fastBitscan) {
        var ret: u32 = undefined;
        _ = intrinsicsl._BitScanForward64(&ret, bb);
        return @intCast(ret);
    } else {
        return bitscanK(bb);
    }
}
pub fn bitscanK(b: u64) i8 {
    if (b == 0) {
        return -1;
    }
    var lsb: u64 = (((b - 1)) ^ b) & b;
    var count: i8 = -1;
    while (lsb != 0) {
        count += 1;
        lsb = lsb >> 1;
    }
    return count;
}
const lsb_64_table = [64]i8{ 63, 30, 3, 32, 59, 14, 11, 33, 60, 24, 50, 9, 55, 19, 21, 34, 61, 29, 2, 53, 51, 23, 41, 18, 56, 28, 1, 43, 46, 27, 0, 35, 62, 31, 58, 4, 5, 49, 54, 6, 15, 52, 12, 40, 7, 42, 45, 16, 25, 57, 48, 13, 10, 39, 8, 44, 20, 47, 38, 22, 17, 37, 36, 26 };

const r_index64 = [64]i8{ 0, 47, 1, 56, 48, 27, 2, 60, 57, 49, 41, 37, 28, 16, 3, 61, 54, 58, 35, 52, 50, 42, 21, 44, 38, 32, 29, 23, 17, 11, 4, 62, 46, 55, 26, 59, 40, 36, 15, 53, 34, 51, 20, 43, 31, 22, 10, 45, 25, 39, 14, 33, 19, 30, 9, 24, 13, 18, 8, 12, 7, 6, 5, 63 };

///*
// bitScanReverse
// @authors Kim Walisch, Mark Dickinson
// @param bb bitboard to scan
// @precondition bb != 0
// @return index (0..63) of most significant one bit
///
/// This function and the one above are branchless version of bitScan and r_bitScan, function are from chessprogramming.org
pub fn r_bitscan(bb: u64) i8 {
    if (comptime fastBitscan) {
        var ret: u32 = undefined;
        _ = intrinsicsl._BitScanForwardReverse64(&ret, bb);
        return @intCast(ret);
    } else {
        return r_bitscanK(bb);
    }
}

pub fn r_bitscanK(b: u64) i8 {
    if (b == 0) {
        return -1;
    }
    var bb = b;
    var count: i8 = -1;
    while (bb != 0) {
        count += 1;
        bb = (bb >> 1);
    }
    return count;
}
pub fn print_board(p_board: *Board_state) void {
    var print_buffer: [8][8]u8 = undefined;
    @memset(&print_buffer, .{ 0, 0, 0, 0, 0, 0, 0, 0 });
    var sq: i8 = 0;
    var bb: u64 = undefined;
    var curr_letter: u8 = 0;
    for (0..p_board.pieceBB.len) |idx| {
        if (idx == @intFromEnum(e_piece.nEmptySquare)) {
            bb = ~p_board.occupiedBB;
        } else {
            bb = p_board.pieceBB[idx];
        }
        if (bb == 0) {
            continue;
        }
        if (idx == @intFromEnum(e_piece.nWhite) or idx == @intFromEnum(e_piece.nBlack)) {
            continue;
        }

        while (bb != 0) {
            sq = bitscan(bb);
            if (sq == INVALID_POSITION) {
                continue;
            }
            curr_letter = arr_piece_str[idx];
            print_buffer[@intCast(@divTrunc(sq, ROW_SIZE))][@intCast(@mod(sq, ROW_SIZE))] = curr_letter;
            bb = bb ^ (ONE << @intCast(sq));
        }
    }
    var i: i8 = 7;

    std.debug.print("   _______________\n", .{});
    while (i >= 0) {
        for (0..8) |j| {
            if (j == 0) {
                std.debug.print("{d}| ", .{i + 1});
            }
            std.debug.print("{c} ", .{print_buffer[@intCast(i)][@intCast(j)]});
        }
        i -= 1;
        std.debug.print("|\n", .{});
    }
    std.debug.print("   _______________\n", .{});
    std.debug.print("   a b c d e f g h\n\n", .{});
    return;
}

fn getPieceFromStr(letter: u8) e_piece {
    var count: i8 = 0;
    for (arr_piece_str) |arr_l| {
        if (letter == arr_l) {
            return @enumFromInt(count);
        }
        count += 1;
    }
    return e_piece.nEmptySquare;
}

pub fn getBoardFromFen(fen: []const u8, alloc: std.mem.Allocator) Board_state {
    // var ret: Board_state = undefined;
    // _ = ret.init_board() catch void;
    var ret = getEmptyBoardState(alloc);
    var letter = fen[0];
    var board_offset = N_SQUARES - 8;
    var post_init: bool = false;
    var offset: i8 = 0;
    var tmp_enum: e_piece = e_piece.nEmptySquare;
    var letter_int: u8 = 0;
    while (offset < fen.len) : (offset += 1) {
        letter = fen[@intCast(offset)];
        if (!post_init) {
            if (letter == '/') {
                board_offset -= 16;
                continue;
            }
            if (letter == ' ') {
                post_init = true;
                continue;
            }
            if (std.ascii.isDigit(letter)) {
                letter_int = letter - '0';
                board_offset += letter_int;
                continue;
            }
            tmp_enum = getPieceFromStr(letter);

            if (!ret.placePiece(tmp_enum, @enumFromInt(board_offset))) {
                //std.debug.print("Placement failed at: {d} val: {d}\n", .{ board_offset, @intFromEnum(tmp_enum) });
            }
            if (board_offset != N_SQUARES) {
                board_offset += 1;
            }
        } else {
            if (letter == ' ') {
                continue;
            }
            if (letter == 'w') {
                ret.turn = e_color.WHITE;
            } else if (letter == 'b') {
                ret.turn = e_color.BLACK;
            } else if (letter == 'K') {
                ret.castlingBB |= (ONE << 7);
                ret.castlingBB |= (ONE << 4);
                ret.castling |= 1;
            } else if (letter == 'Q') {
                ret.castlingBB |= (ONE);
                ret.castlingBB |= (ONE << 4);
                ret.castling |= 2;
            } else if (letter == 'k') {
                ret.castlingBB |= (ONE << 63);
                ret.castlingBB |= (ONE << 60);
                ret.castling |= 4;
            } else if (letter == 'q') {
                ret.castlingBB |= (ONE << 56);
                ret.castlingBB |= (ONE << 60);
                ret.castling |= 8;
            }
        }
    }
    initBothSidePinnedBB(&ret);
    return ret;
}

pub fn getDefaultBoard() Board_state {
    var ret: Board_state = undefined;
    ret.pieceBB[@intFromEnum(e_piece.nWhitePawn)] = 0xFF00;
    ret.pieceBB[@intFromEnum(e_piece.nBlackPawn)] = 0xFF000000000000;

    ret.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] = 0x24;
    ret.pieceBB[@intFromEnum(e_piece.nBlackBishop)] = 0x2400000000000000;

    ret.pieceBB[@intFromEnum(e_piece.nWhiteKing)] = 0x10;
    ret.pieceBB[@intFromEnum(e_piece.nBlackKing)] = 0x1000000000000000;

    ret.pieceBB[@intFromEnum(e_piece.nWhiteKnight)] = 0x42;
    ret.pieceBB[@intFromEnum(e_piece.nBlackKnight)] = 0x4200000000000000;

    ret.pieceBB[@intFromEnum(e_piece.nWhiteQueen)] = 0x8;
    ret.pieceBB[@intFromEnum(e_piece.nBlackQueen)] = 0x800000000000000;

    ret.pieceBB[@intFromEnum(e_piece.nWhiteRook)] = 0x81;
    ret.pieceBB[@intFromEnum(e_piece.nBlackRook)] = 0x8100000000000000;

    ret.pieceBB[@intFromEnum(e_piece.nWhite)] = 0x81000000000000;
    ret.pieceBB[@intFromEnum(e_piece.nBlack)] = 0x81000000000000;
    ret.pieceBB[@intFromEnum(e_piece.nEmptySquare)] = 0xFFFFFFFF0000;

    ret.turn = e_color.WHITE;

    return ret;
}

pub inline fn invertColor(color: e_color) e_color {
    if (color == .WHITE) {
        return .BLACK;
    }
    return .WHITE;
    //return arr_color_inv[@intFromEnum(color)];
}
pub inline fn isPawnPiece(piece: e_piece) bool {
    return (piece == .nWhitePawn or piece == .nBlackPawn);
}

pub inline fn isRookPiece(piece: e_piece) bool {
    return (piece == .nWhiteRook or piece == .nBlackRook);
}

pub inline fn isKingPiece(piece: e_piece) bool {
    return (piece == .nWhiteKing or piece == .nBlackKing);
}

pub fn canMove(from: e_square, to: e_square, occ: u64) bool {
    return (inBetween(from, to) & occ) == 0;
}

pub fn inBetween(from: e_square, to: e_square) u64 {
    return tablel.arrRectangular[@intFromEnum(from)][@intFromEnum(to)];
}

pub fn getRookPiece(turn: e_color) e_piece {
    return @enumFromInt(@intFromEnum(e_piece.nWhiteRook) + @intFromEnum(convertColorToColorPiece(turn)) - 1);
}

pub fn updateCastlingRookStatus(p_state: *Board_state, sq: u8) void {
    p_state.castlingBB &= (UNIVERSE ^ (ONE << @intCast(sq)));
}

pub fn updateCastlingKingStatus(p_state: *Board_state, turn: e_color) void {
    p_state.castlingBB &= (UNIVERSE ^ (ONE << @intCast(p_state.getKingSq(turn))));
}
pub fn initBothSidePinnedBB(p_state: *Board_state) void {
    p_state.pinnedBB = getPinnedBB(p_state, .WHITE);
    p_state.pinnedBB |= getPinnedBB(p_state, .BLACK);
    return;
}

pub fn getPinnedBB(p_state: *Board_state, comptime turn: e_color) u64 {
    if (comptime turn == .WHITE) {
        const diagWhite = moveGenl.diagPinned(p_state.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)], p_state.pieceBB[@intFromEnum(e_piece.nWhiteKing)], ~p_state.occupiedBB);
        const lineWhite = moveGenl.linePinned(p_state.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)], p_state.pieceBB[@intFromEnum(e_piece.nWhiteKing)], ~p_state.occupiedBB);
        return diagWhite | lineWhite;
    } else {
        const diagBlack = moveGenl.diagPinned(p_state.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)], p_state.pieceBB[@intFromEnum(e_piece.nBlackKing)], ~p_state.occupiedBB);
        const lineBlack = moveGenl.linePinned(p_state.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)], p_state.pieceBB[@intFromEnum(e_piece.nBlackKing)], ~p_state.occupiedBB);
        return diagBlack | lineBlack;
    }
}
pub fn refreshEnPassantSide(p_state: *Board_state) void {
    p_state.enPassantIdx = 0;
}
pub fn placeEnPassantPawn(p_state: *Board_state, turn: e_color, sqFile: u8) void {
    if (turn == .WHITE) {
        p_state.enPassantIdx = sqFile + 16;
    } else {
        p_state.enPassantIdx = sqFile + 40;
    }
}

pub fn enPassantCaptureLocationFromMove(toBB: u64, turn: e_color) u64 {
    if (turn == .WHITE) {
        return toBB >> 8;
    }
    return toBB << 8;
}
pub fn enPassantCaptureLocationFromSq(sq: u8, turn: e_color) u64 {
    if (turn == .WHITE) {
        return sq - 8;
    }
    return sq + 8;
}
pub fn updateEnPassantStatus(p_state: *Board_state, sq: e_square) void {
    const sq_file = getSqFile(sq);

    refreshEnPassantSide(p_state);
    placeEnPassantPawn(p_state, p_state.turn, sq_file);
}

pub inline fn convertColorToColorPiece(color: e_color) e_piece {
    return arr_color_conv[@intFromEnum(color)];
}

pub const Board_stateContainer = struct {
    array: []Board_state,
    len: usize,

    pub fn free(p_self: *Board_stateContainer, alloc: std.mem.Allocator) void {
        //for (0..p_self.len) |i| {
        //    alloc.free(p_self.array[i].p_stack);
        //}
        alloc.free(p_self.array);
    }
};

pub fn getEmptyBoardState(alloc: std.mem.Allocator) Board_state {
    var ret: Board_state = undefined;
    _ = ret.init_board(alloc) catch void;
    return ret;
}

pub const boardFrame = struct {
    //pieceBB: [N_PIECES]u64 = undefined,
    //c_occupiedBB: [NUMBER_PLAYER]u64 = undefined,
    //occupiedBB: u64 = 0,

    pinnedBB: u64 = 0,
    checkersBB: u64 = 0,
    //castlingBB: u64 = 0,
    enPassantIdx: u8 = 0,
    castling: u8 = 0,

    victim: e_piece = undefined,
};

pub const boardStack = struct {
    stack: [movel.MAX_MATCH_LENGTH]boardFrame = undefined,
    len: u8 = 0,

    pub fn push(p_self: *boardStack, frame: boardFrame) void {
        //std.debug.print("[DEBUG] boardStack.push, pushing frame to stacking current length: {d}\n", .{p_self.len});
        //if (p_self.len == movel.MAX_MATCH_LENGTH) {
        //    @panic("");
        //}
        p_self.stack[p_self.len] = frame;
        p_self.len += 1;
    }
    pub fn pop(p_self: *boardStack) boardFrame {
        if (p_self.len == 0) {
            @panic("");
        }
        p_self.len -= 1;
        return p_self.stack[p_self.len];
    }
};

pub const Board_state = struct {
    players: [NUMBER_PLAYER]exploration.Player = [NUMBER_PLAYER]exploration.Player{ .{}, .{} },
    pieceBB: [N_PIECES]u64 = std.mem.zeroes([N_PIECES]u64),
    c_occupiedBB: [NUMBER_PLAYER]u64,
    pieceArray: [N_SQUARES]e_piece = std.mem.zeroes([N_SQUARES]e_piece),

    enPassantIdx: u8 = 0,

    // castling info
    // first 2 bits white, next 2 black
    // 2 bit: 1st = k, 2st = q
    castling: u8 = 0,
    pinnedBB: u64 = 0,
    checkersBB: u64 = 0,
    castlingBB: u64 = 0,
    occupiedBB: u64 = 0,

    victim: e_piece = .nEmptySquare,
    turn: e_color,
    turn_count: u64 = 0,

    move_history: matchMoveContainer = .{},
    stack: boardStack = .{ .len = 0 },
    //p_stack: *boardStack = undefined,
    rngIntGenerator: std.Random.DefaultPrng,
    randInt: std.Random,
    seed: u64 = 42,

    pub fn init_board(p_self: *Board_state, alloc: std.mem.Allocator) !void {
        @memset(&p_self.pieceBB, 0);
        @memset(&p_self.c_occupiedBB, 0);

        @memset(&p_self.pieceArray, e_piece.nEmptySquare);

        p_self.pieceBB[@intFromEnum(e_piece.nEmptySquare)] = UNIVERSE;
        p_self.turn = e_color.WHITE;
        p_self.turn_count = 0;
        p_self.occupiedBB = 0;

        p_self.castlingBB = 0;
        p_self.castling = 0;

        p_self.pinnedBB = 0;
        p_self.checkersBB = 0;
        p_self.enPassantIdx = 0;

        p_self.victim = .nEmptySquare;

        p_self.move_history = .{};
        p_self.stack = .{ .len = 0 };
        std.debug.print("[DEBUG] from init_board: size of stack : {d} bytes\n", .{@sizeOf(boardStack)});
        _ = alloc;

        p_self.rngIntGenerator = std.Random.DefaultPrng.init(p_self.seed);
        p_self.randInt = p_self.rngIntGenerator.random();

        p_self.players[0].setType(.Human);
        p_self.players[1].setType(.Human);
    }
    pub fn makeFrame(self: Board_state) boardFrame {
        return .{ .castling = self.castling, .pinnedBB = self.pinnedBB, .victim = self.victim, .checkersBB = self.checkersBB, .enPassantIdx = self.enPassantIdx };
    }
    pub fn loadFrame(p_self: *Board_state, p_frame: *boardFrame) void {
        p_self.pinnedBB = p_frame.pinnedBB;
        p_self.checkersBB = p_frame.checkersBB;
        //p_self.castlingBB = p_frame.castlingBB;
        p_self.castling = p_frame.castling;
        p_self.victim = p_frame.victim;
        p_self.enPassantIdx = p_frame.enPassantIdx;
        return;
    }
    pub fn duplicateNTimes(self: Board_state, alloc: std.mem.Allocator, n: usize) !Board_stateContainer {
        var ret: []Board_state = try alloc.alloc(Board_state, n);
        for (0..n) |i| {
            ret[i] = self;

            sanityCheckBoardState(&ret[i]);
        }
        return .{ .array = ret, .len = ret.len };
    }

    pub fn free_board(p_self: *Board_state) void {
        for (0..p_self.players.len) |i| {
            exploration.freePlayer(&p_self.players[i]);
        }
    }
    pub fn setPlayerType(p_self: *Board_state, color: e_color, player_type: exploration.e_playerType) void {
        p_self.players[@intFromEnum(color)].setType(player_type);
    }
    pub fn setPlayerSearchDepth(p_self: *Board_state, color: e_color, depth: u8) void {
        p_self.players[@intFromEnum(color)].setSearchDepth(depth);
    }
    pub fn setPlayerSearcType(p_self: *Board_state, color: e_color, search_type: exploration.e_searchType) void {
        p_self.players[@intFromEnum(color)].setSearchType(search_type);
    }
    pub fn setPlayerHeuristicType(p_self: *Board_state, color: e_color, heuristic_type: heuristicl.e_heuristicType) void {
        p_self.players[@intFromEnum(color)].setHeuristicType(heuristic_type);
    }
    pub fn printHistory(self: Board_state) void {
        for (0..self.move_history.len) |i| {
            const move = self.move_history.moves[i];
            std.debug.print("{s} ", .{move.getStr()});
        }
        std.debug.print("\n", .{});
    }

    pub fn get_piece(p_self: *Board_state, sq: u8) e_piece {
        return p_self.pieceArray[sq];
    }

    pub inline fn invert_turn(p_self: *Board_state) void {
        p_self.turn = invertColor(p_self.turn);
    }

    fn next_turn(p_self: *Board_state) void {
        p_self.invert_turn();
        p_self.turn_count += 1;
    }

    fn _next_turn(p_self: *Board_state, comptime turn: e_color) void {
        if (comptime turn == .WHITE) {
            p_self.turn = .BLACK;
        } else {
            p_self.turn = .WHITE;
        }
        p_self.turn_count += 1;
    }
    fn undo_turn(p_self: *Board_state) void {
        p_self.invert_turn();
        p_self.turn_count -= 1;
    }
    fn _undo_turn(p_self: *Board_state, comptime turn: e_color) void {
        if (comptime turn == .WHITE) {
            p_self.turn = .BLACK;
        } else {
            p_self.turn = .WHITE;
        }
        p_self.turn_count -= 1;
    }
    pub fn placePiece(p_self: *Board_state, piece: e_piece, square: e_square) bool {
        const one_mask: u64 = (ONE << @intCast(@intFromEnum(square)));
        if (p_self.occupiedBB & one_mask != 0) {
            return false;
        }

        p_self.pieceBB[@intFromEnum(piece)] |= one_mask;
        p_self.occupiedBB |= one_mask;
        p_self.pieceBB[@intFromEnum(e_piece.nEmptySquare)] ^= one_mask;
        p_self.pieceArray[@intFromEnum(square)] = piece;
        if (@intFromEnum(piece) < @intFromEnum(e_piece.nBlack)) {
            p_self.pieceBB[@intFromEnum(e_piece.nWhite)] |= one_mask;
            p_self.c_occupiedBB[@intFromEnum(e_color.WHITE)] |= one_mask;
        } else {
            p_self.pieceBB[@intFromEnum(e_piece.nBlack)] |= one_mask;
            p_self.c_occupiedBB[@intFromEnum(e_color.BLACK)] |= one_mask;
        }
        return true;
    }

    pub fn undoMove(p_self: *Board_state) !bool {
        if (p_self.move_history.len == 0) {
            return false;
        }
        p_self.undo_turn();
        //undoEnPassantStatus(p_self);

        var pieceCastle: e_piece = undefined;
        const poped_move: IMove = p_self.move_history.pop();
        const toBB: u64 = ONE << @intCast((poped_move.getTo()));
        const fromBB: u64 = ONE << @intCast((poped_move.getFrom()));
        var moveBB: u64 = (toBB | fromBB);

        //const pieceF: e_piece = p_self.get_piece(poped_move.getTo());
        const pieceF: e_piece = poped_move.getFromPiece();
        const colorF: e_color = getColorFromPiece(pieceF);

        //if (isRookPiece(pieceF)) {
        //    undoCastlingRookStatus(p_self, poped_move.getFrom());
        //} else if (isKingPiece(pieceF)) {
        //    undoCastlingKingStatus(p_self);
        //}
        if (poped_move.isPromotion()) {
            p_self.pieceBB[@intFromEnum(flagPromotionToPiece(poped_move.getFlag(), colorF))] ^= toBB;
            if (colorF == .WHITE) {
                p_self.pieceBB[@intFromEnum(e_piece.nWhitePawn)] ^= fromBB;
            } else {
                p_self.pieceBB[@intFromEnum(e_piece.nBlackPawn)] ^= fromBB;
            }
        } else {
            p_self.pieceBB[@intFromEnum(pieceF)] ^= moveBB;
        }
        p_self.c_occupiedBB[@intFromEnum(colorF)] ^= moveBB;
        if (poped_move.isKingSideCastle()) {
            pieceCastle = getRookPiece(colorF);
            p_self.pieceBB[@intFromEnum(pieceCastle)] ^= (moveBB << 1);
            p_self.c_occupiedBB[@intFromEnum(colorF)] ^= (moveBB << 1);
            moveBB |= (moveBB << 1);
        } else if (poped_move.isQueenSideCastle()) {
            const _castleBB: u64 = (toBB >> 2) | (toBB << 1);
            moveBB |= (_castleBB);
            pieceCastle = getRookPiece(colorF);
            p_self.pieceBB[@intFromEnum(pieceCastle)] ^= (_castleBB);
            p_self.c_occupiedBB[@intFromEnum(colorF)] ^= (_castleBB);
        }

        if (poped_move.isCapture()) {
            if (poped_move.isEnpassant()) {
                const _toBB = enPassantCaptureLocationFromMove(toBB, (p_self.turn));
                p_self.pieceBB[@intFromEnum(poped_move.getCapturePiece())] |= _toBB;
                p_self.c_occupiedBB[@intFromEnum(invertColor(colorF))] |= _toBB;
                p_self.occupiedBB ^= (moveBB | _toBB);
            } else {
                p_self.pieceBB[@intFromEnum(poped_move.getCapturePiece())] |= toBB;
                p_self.c_occupiedBB[@intFromEnum(invertColor(colorF))] |= toBB;
                p_self.occupiedBB |= fromBB;
            }
        } else {
            p_self.occupiedBB ^= moveBB;
        }
        return true;
    }
    //pub fn undoMoveFast(p_self: *Board_state) bool {
    //    if (p_self.move_history.len == 0) {
    //        return false;
    //    }
    //    p_self.undo_turn();
    //    //undoEnPassantStatus(p_self);
    //    const move = p_self.move_history.pop();
    //    const pieceF: e_piece = move.getFromPiece();
    //    if (isPawnPiece(pieceF)) {
    //        _ = p_self.pawnUndoMove(pieceF, move);
    //    } else if (isRookPiece(pieceF)) {
    //        _ = p_self.rookUndoMove(pieceF, move);
    //    } else if (isKingPiece(pieceF)) {
    //        _ = p_self.kingUndoMove(pieceF, move);
    //    } else {
    //        _ = p_self.defaultUndoMove(pieceF, move);
    //    }
    //    return true;
    //}
    pub fn undoMoveFaster(p_self: *Board_state) bool {
        const move = p_self.move_history.pop();
        const pieceF: e_piece = move.getFromPiece();

        var popped = (p_self.stack.pop());
        p_self.loadFrame(&popped);

        p_self.pieceArray[move.getFrom()] = pieceF;
        switch (pieceF) {
            .nWhitePawn => {
                p_self._undo_turn(.BLACK);
                _ = p_self.pawnUndoMove(.nWhitePawn, move);
            },
            .nWhiteBishop => {
                p_self._undo_turn(.BLACK);
                _ = p_self.defaultUndoMove(.nWhiteBishop, move);
            },
            .nWhiteKnight => {
                p_self._undo_turn(.BLACK);
                _ = p_self.defaultUndoMove(.nWhiteKnight, move);
            },
            .nWhiteQueen => {
                p_self._undo_turn(.BLACK);
                _ = p_self.defaultUndoMove(.nWhiteQueen, move);
            },
            .nWhiteRook => {
                p_self._undo_turn(.BLACK);
                _ = p_self.defaultUndoMove(.nWhiteRook, move);
            },
            .nWhiteKing => {
                p_self._undo_turn(.BLACK);
                _ = p_self.kingUndoMove(.nWhiteKing, move);
            },

            .nBlackPawn => {
                p_self._undo_turn(.WHITE);
                _ = p_self.pawnUndoMove(.nBlackPawn, move);
            },
            .nBlackBishop => {
                p_self._undo_turn(.WHITE);
                _ = p_self.defaultUndoMove(.nBlackBishop, move);
            },
            .nBlackKnight => {
                p_self._undo_turn(.WHITE);
                _ = p_self.defaultUndoMove(.nBlackKnight, move);
            },
            .nBlackQueen => {
                p_self._undo_turn(.WHITE);
                _ = p_self.defaultUndoMove(.nBlackQueen, move);
            },
            .nBlackRook => {
                p_self._undo_turn(.WHITE);
                _ = p_self.defaultUndoMove(.nBlackRook, move);
            },
            .nBlackKing => {
                p_self._undo_turn(.WHITE);
                _ = p_self.kingUndoMove(.nBlackKing, move);
            },
            .nWhite, .nBlack, .nEmptySquare => {
                @panic("???");
            },
        }
        if (comptime useDebug) {
            sanityCheckBoardState(p_self);
        }
        return true;
    }
    pub fn undoMoveFastest(p_self: *Board_state) bool {
        //std.debug.print("[DEBUG] undoMoveFastest: last known here\n", .{});
        _ = p_self;
        @panic("Do not use undoMoveFastest: \n");
        //p_self.undo_turn();
        //var popped = (p_self.stack.pop());
        //p_self.loadFrame(&popped);
        //_ = p_self.move_history.pop();
        //return true;
    }
    pub fn cstexpr_pawnUndoMove(p_self: *Board_state, piece: e_piece, move: IMove, comptime turn: e_color) bool {
        const toBB: u64 = ONE << @intCast(move.getTo());
        const fromBB: u64 = ONE << @intCast(move.getFrom());
        const moveBB: u64 = (toBB | fromBB);
        var opp_c: e_color = .BLACK;
        if (comptime turn == .BLACK) {
            opp_c = .WHITE;
        }
        if (move.isPromotion()) {
            p_self.pieceBB[@intFromEnum(flagPromotionToPiece(move.getFlag(), turn))] ^= toBB;
            p_self.pieceBB[@intFromEnum(piece)] ^= fromBB;
        } else {
            p_self.pieceBB[@intFromEnum(piece)] ^= moveBB;
        }
        p_self.c_occupiedBB[@intFromEnum(turn)] ^= moveBB;

        if (move.isCapture()) {
            if (move.isEnpassant()) {
                const _toBB = enPassantCaptureLocationFromMove(toBB, turn);
                p_self.pieceBB[@intFromEnum(move.getCapturePiece())] |= _toBB;
                p_self.c_occupiedBB[@intFromEnum(opp_c)] |= _toBB;
                p_self.occupiedBB ^= (moveBB | _toBB);
            } else {
                p_self.pieceBB[@intFromEnum(move.getCapturePiece())] |= toBB;
                p_self.c_occupiedBB[@intFromEnum(opp_c)] |= toBB;
                p_self.occupiedBB |= fromBB;
            }
        } else {
            p_self.occupiedBB ^= moveBB;
        }
        return true;
    }
    pub fn pawnUndoMove(p_self: *Board_state, piece: e_piece, move: IMove) bool {
        const toSq: u8 = move.getTo();
        const toBB: u64 = ONE << @intCast(toSq);
        const fromBB: u64 = ONE << @intCast(move.getFrom());
        const moveBB: u64 = (toBB | fromBB);

        if (move.isPromotion()) {
            p_self.pieceBB[@intFromEnum(flagPromotionToPiece(move.getFlag(), p_self.turn))] ^= toBB;
            p_self.pieceBB[@intFromEnum(piece)] ^= fromBB;
        } else {
            p_self.pieceBB[@intFromEnum(piece)] ^= moveBB;
        }
        p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= moveBB;

        if (move.isCapture()) {
            const cPiece = move.getCapturePiece();
            if (move.isEnpassant()) {
                const _toBB = enPassantCaptureLocationFromMove(toBB, (p_self.turn));

                p_self.pieceBB[@intFromEnum(cPiece)] |= _toBB;
                p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] |= _toBB;
                p_self.occupiedBB ^= (moveBB | _toBB);
                p_self.pieceArray[enPassantCaptureLocationFromSq(toSq, p_self.turn)] = cPiece;
                p_self.pieceArray[toSq] = .nEmptySquare;
            } else {
                p_self.pieceBB[@intFromEnum(move.getCapturePiece())] |= toBB;
                p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] |= toBB;
                p_self.occupiedBB |= fromBB;
                p_self.pieceArray[toSq] = cPiece;
            }
        } else {
            p_self.occupiedBB ^= moveBB;
            p_self.pieceArray[toSq] = .nEmptySquare;
        }
        return true;
    }

    pub fn kingUndoMove(p_self: *Board_state, piece: e_piece, move: IMove) bool {
        var pieceCastle: e_piece = undefined;
        const toSq: u8 = move.getTo();
        const toBB: u64 = ONE << @intCast(toSq);
        const fromBB: u64 = ONE << @intCast(move.getFrom());
        var moveBB: u64 = (toBB | fromBB);

        p_self.pieceBB[@intFromEnum(piece)] ^= moveBB;
        p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= moveBB;
        if (move.isCapture()) {
            const cPiece = move.getCapturePiece();
            p_self.pieceBB[@intFromEnum(cPiece)] |= toBB;
            p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] |= toBB;
            p_self.occupiedBB |= fromBB;
            p_self.pieceArray[toSq] = cPiece;
            return true;
        } else if (move.isKingSideCastle()) {
            pieceCastle = getRookPiece(p_self.turn);
            p_self.pieceBB[@intFromEnum(pieceCastle)] ^= (moveBB << 1);
            p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= (moveBB << 1);
            moveBB |= (moveBB << 1);
            p_self.pieceArray[toSq + 1] = pieceCastle;
            p_self.pieceArray[toSq - 1] = .nEmptySquare;
        } else if (move.isQueenSideCastle()) {
            const _castleBB: u64 = (toBB >> 2) | (toBB << 1);
            moveBB |= (_castleBB);
            pieceCastle = getRookPiece(p_self.turn);
            p_self.pieceBB[@intFromEnum(pieceCastle)] ^= (_castleBB);
            p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= (_castleBB);
            p_self.pieceArray[toSq - 1] = pieceCastle;
            p_self.pieceArray[toSq + 1] = .nEmptySquare;
        }

        p_self.pieceArray[toSq] = .nEmptySquare;
        p_self.occupiedBB ^= moveBB;

        return true;
    }
    pub fn defaultUndoMove(p_self: *Board_state, piece: e_piece, move: IMove) bool {
        const toSq = move.getTo();
        const toBB: u64 = ONE << @intCast(toSq);
        const fromBB: u64 = ONE << @intCast(move.getFrom());
        const moveBB: u64 = (toBB | fromBB);

        p_self.pieceBB[@intFromEnum(piece)] ^= moveBB;
        p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= moveBB;
        if (move.isCapture()) {
            const cPiece = move.getCapturePiece();
            p_self.pieceBB[@intFromEnum(cPiece)] |= toBB;
            p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] |= toBB;
            p_self.occupiedBB |= fromBB;
            p_self.pieceArray[toSq] = cPiece;
        } else {
            p_self.pieceArray[toSq] = .nEmptySquare;
            p_self.occupiedBB ^= moveBB;
        }

        return true;
    }
    pub fn rookMakeMove(p_self: *Board_state, piece: e_piece, move: IMove) bool {
        //updateCastlingRookStatus(p_self, move.getFrom());
        _ = p_self.defaultMakeMove(piece, move);
        return true;
    }
    pub fn kingMakeMove(p_self: *Board_state, piece: e_piece, move: IMove) bool {
        //updateCastlingKingStatus(p_self, p_self.turn);

        var pieceCastle: e_piece = undefined;
        const toSq = move.getTo();
        const toBB: u64 = ONE << @intCast(toSq);
        const fromSq = move.getFrom();
        const fromBB: u64 = ONE << @intCast(fromSq);
        var moveBB = toBB | fromBB;
        p_self.castling &= MASK_CASTLING[@intCast(toSq)] & MASK_CASTLING[@intCast(fromSq)];

        p_self.pieceBB[@intFromEnum(piece)] ^= moveBB;
        p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= moveBB;
        p_self.pieceArray[toSq] = piece;
        if (move.isCapture()) {
            p_self.pieceBB[@intFromEnum(move.getCapturePiece())] ^= toBB;
            p_self.occupiedBB ^= fromBB;
            p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] ^= toBB;
            return true;
        } else {
            if (move.isKingSideCastle()) {
                pieceCastle = getRookPiece(p_self.turn);
                p_self.pieceBB[@intFromEnum(pieceCastle)] ^= (moveBB << 1);
                p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= (moveBB << 1);
                moveBB |= (moveBB << 1);
                p_self.occupiedBB ^= moveBB;
                p_self.pieceArray[toSq - 1] = pieceCastle;
                p_self.pieceArray[toSq + 1] = .nEmptySquare;
            } else if (move.isQueenSideCastle()) {
                const _castleBB: u64 = (toBB >> 2) | (toBB << 1);
                moveBB |= (_castleBB);
                pieceCastle = getRookPiece(p_self.turn);
                p_self.pieceBB[@intFromEnum(pieceCastle)] ^= (_castleBB);
                p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= (_castleBB);
                p_self.occupiedBB ^= moveBB;
                p_self.pieceArray[toSq + 1] = pieceCastle;
                p_self.pieceArray[toSq - 1] = .nEmptySquare;
            } else {
                p_self.occupiedBB ^= moveBB;
            }
        }
        return true;
    }

    pub fn makeMoveFaster(p_self: *Board_state, move: IMove) bool {
        const pieceF: e_piece = move.getFromPiece();
        p_self.stack.push(p_self.makeFrame());
        p_self.pieceArray[move.getFrom()] = .nEmptySquare;
        refreshEnPassantSide(p_self);
        switch (pieceF) {
            .nWhitePawn => {
                _ = p_self.pawnMakeMove(.nWhitePawn, move);
                p_self._next_turn(.WHITE);
            },
            .nWhiteBishop => {
                _ = p_self.defaultMakeMove(.nWhiteBishop, move);
                p_self._next_turn(.WHITE);
            },
            .nWhiteKnight => {
                _ = p_self.defaultMakeMove(.nWhiteKnight, move);
                p_self._next_turn(.WHITE);
            },
            .nWhiteQueen => {
                _ = p_self.defaultMakeMove(.nWhiteQueen, move);
                p_self._next_turn(.WHITE);
            },
            .nWhiteRook => {
                _ = p_self.rookMakeMove(.nWhiteRook, move);
                p_self._next_turn(.WHITE);
            },
            .nWhiteKing => {
                _ = p_self.kingMakeMove(.nWhiteKing, move);
                p_self._next_turn(.WHITE);
            },

            .nBlackPawn => {
                _ = p_self.pawnMakeMove(.nBlackPawn, move);
                p_self._next_turn(.BLACK);
            },
            .nBlackBishop => {
                _ = p_self.defaultMakeMove(.nBlackBishop, move);
                p_self._next_turn(.BLACK);
            },
            .nBlackKnight => {
                _ = p_self.defaultMakeMove(.nBlackKnight, move);
                p_self._next_turn(.BLACK);
            },
            .nBlackQueen => {
                _ = p_self.defaultMakeMove(.nBlackQueen, move);
                p_self._next_turn(.BLACK);
            },
            .nBlackRook => {
                _ = p_self.rookMakeMove(.nBlackRook, move);
                p_self._next_turn(.BLACK);
            },
            .nBlackKing => {
                _ = p_self.kingMakeMove(.nBlackKing, move);
                p_self._next_turn(.BLACK);
            },
            .nWhite, .nBlack, .nEmptySquare => {
                @panic("???");
            },
        }
        if (useStaged) {
            getCheckers(p_self, p_self.turn);
        }
        //getCheckers(p_self, currTurn);
        _ = p_self.move_history.append(move);
        //sanityCheckBoardState(p_self);

        return true;
    }

    pub fn makeMoveUpdate(p_self: *Board_state, move: IMove) void {
        // test to reduce the makeMove load
        p_self.stack.push(p_self.makeFrame());
        _ = p_self.move_history.append(move);
        p_self.victim = .nEmptySquare;
        p_self.enPassantIdx = 0;

        const toSq = move.getTo();
        const fromSq = move.getFrom();
        const toBB = xToBitboard(toSq);
        const fromBB = xToBitboard(fromSq);
        const moveBB = fromBB | toBB;
        const fromPiece = p_self.get_piece(fromSq);
        const victim = move.getCapturePiece();
        const colorOffset: u8 = @intFromEnum(convertColorToColorPiece(p_self.turn)) - 1;

        p_self.castling &= MASK_CASTLING[@intCast(toSq)] & MASK_CASTLING[@intCast(fromSq)];
        p_self.pieceArray[fromSq] = .nEmptySquare;

        p_self.pieceBB[@intFromEnum(fromPiece)] ^= moveBB;
        p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= moveBB;
        p_self.pieceArray[toSq] = fromPiece;

        if (victim != .nEmptySquare) {
            p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] ^= toBB;
            p_self.occupiedBB ^= fromBB;
            p_self.pieceBB[@intFromEnum(victim)] ^= toBB;
            p_self.victim = victim;
        } else {
            p_self.occupiedBB ^= moveBB;
        }
        //if (move.isEnpassant()) {
        //    std.debug.print("[DEBUG] makeMoveUpdate: found a enpassant move: \n", .{});
        //    print_boardstate(p_self);
        //    print_bitboard(p_self.occupiedBB);
        //    print_bitboard(p_self.c_occupiedBB[0]);
        //    print_bitboard(p_self.c_occupiedBB[1]);
        //    print_bitboard(p_self.pieceBB[@intFromEnum(e_piece.nWhitePawn)]);
        //}
        if (isKingPiece(fromPiece)) {
            const castleIdx: u8 = @intFromEnum(e_piece.nWhiteRook);
            const castlePiece: e_piece = @enumFromInt(castleIdx + colorOffset);
            if (move.isKingSideCastle()) {
                const castleBB = (xToBitboard(toSq - 1) | (xToBitboard(toSq + 1)));
                p_self.pieceArray[toSq - 1] = castlePiece;
                p_self.pieceArray[toSq + 1] = .nEmptySquare;

                p_self.pieceBB[@intFromEnum(castlePiece)] ^= castleBB;
                p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= (castleBB);
                p_self.occupiedBB ^= castleBB;
                //
            } else if (move.isQueenSideCastle()) {
                const castleBB = (xToBitboard(toSq + 1) | (xToBitboard(toSq - 1)));
                p_self.pieceArray[toSq + 1] = castlePiece;
                p_self.pieceArray[toSq - 1] = .nEmptySquare;

                p_self.pieceBB[@intFromEnum(castlePiece)] ^= castleBB;
                p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= (castleBB);
                p_self.occupiedBB ^= castleBB;
                //
            }
        } else if (isPawnPiece(fromPiece)) {
            if (move.isPromotion()) {
                // can also be or and not xor
                const promPiece = flagPromotionToPiece(move.getFlag(), p_self.turn);
                p_self.pieceBB[@intFromEnum(promPiece)] ^= toBB;
                p_self.pieceBB[@intFromEnum(fromPiece)] ^= toBB;
                p_self.pieceArray[toSq] = promPiece;
            } else if (move.isDoublePush()) {
                // middle between from and to
                p_self.enPassantIdx = (fromSq + toSq) / 2;
            } else if (move.isEnpassant()) {
                const victimSq: e_square = getSqFromCoord(getSqIdxRank(fromSq), getSqIdxFile(toSq));
                const victimBB = sqToBitboard(victimSq);
                const bisBB = victimBB | toBB;

                p_self.pieceArray[@intFromEnum(victimSq)] = .nEmptySquare;

                p_self.pieceBB[@intFromEnum(victim)] ^= bisBB;

                p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] ^= bisBB;

                p_self.occupiedBB ^= bisBB;
            }
        }
        //if (move.isEnpassant()) {
        //    std.debug.print("[DEBUG] makeMoveUpdate: found a enpassant move(after): \n", .{});
        //    print_boardstate(p_self);
        //    print_bitboard(p_self.occupiedBB);
        //    print_bitboard(p_self.c_occupiedBB[0]);
        //    print_bitboard(p_self.c_occupiedBB[1]);
        //    print_bitboard(p_self.pieceBB[@intFromEnum(e_piece.nWhitePawn)]);
        //}
        p_self.next_turn();
        if (comptime useDebug) {
            sanityCheckBoardState(p_self);
        }
        if (comptime useStaged) {
            getCheckers(p_self, p_self.turn);
        }
    }

    pub fn pawnMakeMove(p_self: *Board_state, piece: e_piece, move: IMove) bool {
        const toBB: u64 = ONE << @intCast(move.getTo());
        const fromBB: u64 = ONE << @intCast(move.getFrom());
        const moveBB = toBB | fromBB;

        p_self.pieceBB[@intFromEnum(piece)] ^= moveBB;
        p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= moveBB;
        p_self.occupiedBB ^= moveBB;
        p_self.pieceArray[move.getTo()] = piece;
        if (move.isQuietMove()) {
            return true;
        } else if (move.isDoublePush()) {
            updateEnPassantStatus(p_self, @enumFromInt(move.getTo()));
        } else if (move.isPromotion()) {
            if (move.isCapture()) {
                p_self.pieceBB[@intFromEnum(move.getCapturePiece())] ^= toBB;
                p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] ^= toBB;
            }
            const prom_piece: e_piece = flagPromotionToPiece(move.getFlag(), p_self.turn);
            p_self.pieceArray[move.getTo()] = prom_piece;
            p_self.pieceBB[@intFromEnum(piece)] ^= toBB;
            p_self.pieceBB[@intFromEnum(prom_piece)] ^= toBB;
        } else if (move.isEnpassant()) {
            const _toBB = enPassantCaptureLocationFromMove(toBB, p_self.turn);
            p_self.pieceArray[enPassantCaptureLocationFromSq(move.getTo(), p_self.turn)] = .nEmptySquare;
            p_self.pieceBB[@intFromEnum(move.getCapturePiece())] ^= _toBB;
            p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] ^= _toBB;
            p_self.occupiedBB ^= (_toBB);
        } else if (move.isCapture()) {
            p_self.pieceBB[@intFromEnum(move.getCapturePiece())] ^= toBB;
            p_self.occupiedBB ^= toBB;
            p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] ^= toBB;
        }
        return true;
    }

    pub fn defaultMakeMove(p_self: *Board_state, piece: e_piece, move: IMove) bool {
        const toSq = move.getTo();
        const fromSq = move.getFrom();

        const toBB: u64 = ONE << @intCast(toSq);
        const fromBB: u64 = ONE << @intCast(fromSq);
        const moveBB = toBB | fromBB;

        p_self.castling &= MASK_CASTLING[@intCast(toSq)] & MASK_CASTLING[@intCast(fromSq)];

        p_self.pieceBB[@intFromEnum(piece)] ^= moveBB;
        p_self.c_occupiedBB[@intFromEnum(p_self.turn)] ^= moveBB;
        p_self.pieceArray[move.getTo()] = piece;
        if (move.isCapture()) {
            p_self.pieceBB[@intFromEnum(move.getCapturePiece())] ^= toBB;
            p_self.occupiedBB ^= fromBB;
            p_self.c_occupiedBB[@intFromEnum(invertColor(p_self.turn))] ^= toBB;
        } else {
            p_self.occupiedBB ^= moveBB;
        }
        return true;
    }

    pub fn printBoardMoveInfo(p_self: *Board_state, move: IMove) void {
        const pieceF = p_self.get_piece(move.getTo());
        const colorF = getColorFromPiece(pieceF);

        std.debug.print("[DEBUG] From printBoardMoveInfo: Printing relevant info for move: ", .{});
        move.print();
        std.debug.print(" order: occupied / c_occupied / piece\n ", .{});
        print_bitboard(p_self.occupiedBB);
        print_bitboard(p_self.c_occupiedBB[@intFromEnum(colorF)]);
        print_bitboard(p_self.pieceBB[@intFromEnum(pieceF)]);
        return;
    }

    pub fn getLastMove(self: Board_state) IMove {
        const n = self.move_history.len;
        if (n == 0) {
            return .{};
        }
        return self.move_history.moves[n - 1];
    }
    pub fn isFull(self: Board_state) bool {
        // also occupiedBB == UNIVERSE
        return ((self.pieceBB[@intFromEnum(e_color.WHITE)] | self.pieceBB[@intFromEnum(e_color.BLACK)]) == UNIVERSE);
    }
    pub fn emptyMask(self: Board_state) u64 {
        // also ~occupiedBB
        //return (~self.pieceBB[@intFromEnum(e_color.WHITE)] | ~self.pieceBB[@intFromEnum(e_color.BLACK)]);
        return ~self.occupiedBB;
    }
    pub fn isEmpty(self: Board_state) bool {
        // also occupiedBB == EMPTY
        return ((self.pieceBB[@intFromEnum(e_color.WHITE)] | self.pieceBB[@intFromEnum(e_color.BLACK)]) == EMPTY);
    }

    pub fn getKingBB(self: Board_state, color: e_color) u64 {
        if (color == e_color.WHITE) {
            return self.pieceBB[@intFromEnum(e_piece.nWhiteKing)];
        }
        return self.pieceBB[@intFromEnum(e_piece.nBlackKing)];
    }
    pub fn getKingSq(self: Board_state, color: e_color) i8 {
        return bitscan(self.getKingBB(color));
    }

    pub fn cstgetKingBB(self: Board_state, comptime color: e_color) u64 {
        if (comptime color == e_color.WHITE) {
            return self.pieceBB[@intFromEnum(e_piece.nWhiteKing)];
        }
        return self.pieceBB[@intFromEnum(e_piece.nBlackKing)];
    }

    pub fn cstgetKingSq(self: Board_state, comptime color: e_color) i8 {
        return bitscan(self.cstgetKingBB(color));
    }

    pub fn canKingSideCastle(self: Board_state, turn: e_color) bool {
        //const kingBB = self.getKingBB(turn);

        if (turn == .BLACK) {
            //return ((((self.castlingBB & kingBB) << 3) & self.castlingBB) != 0) and (canMove(.e8, .h8, self.occupiedBB));
            return ((self.castling & 4) != 0) and (canMove(.e8, .h8, self.occupiedBB));
        }
        //return ((((self.castlingBB & kingBB) << 3) & self.castlingBB) != 0) and (canMove(.e1, .h1, self.occupiedBB));
        return ((self.castling & 1) != 0) and (canMove(.e1, .h1, self.occupiedBB));
    }
    pub fn canQueenSideCastle(self: Board_state, turn: e_color) bool {
        //const kingBB = self.getKingBB(turn);
        if (turn == .BLACK) {
            //return ((((self.castlingBB & kingBB) >> 4) & self.castlingBB) != 0) and (canMove(.e8, .a8, self.occupiedBB));
            return ((self.castling & 8) != 0) and (canMove(.e8, .a8, self.occupiedBB));
        }
        //return ((((self.castlingBB & kingBB) >> 4) & self.castlingBB) != 0) and (canMove(.e1, .a1, self.occupiedBB));
        return ((self.castling & 2) != 0) and (canMove(.e1, .a1, self.occupiedBB));
    }

    pub fn getPieceCount(self: Board_state, piece: e_piece) i8 {
        return l_popcount(self.pieceBB[@intFromEnum(piece)]);
    }
    pub fn getSidePieceCount(self: Board_state, color: e_color) i8 {
        return l_popcount(self.c_occupiedBB[@intFromEnum(color)]);
    }

    pub fn isLegalM(p_self: *Board_state, turn: e_color, move: IMove, all_attacks: u64) bool {
        // faster than previous _islegal going from ~100-150k nodes/s to 250-300k nodes per sec
        if (move.isCastle()) {
            return isCastleLegalPostMove(p_self, turn, move, all_attacks);
        }
        const king_attacks = getAllAttackMaskFromKing(p_self, turn);
        return king_attacks == 0;
    }
    pub fn isLegal(p_self: *Board_state, turn: e_color) bool {
        // faster than previous _islegal going from ~100-150k nodes/s to 250-300k nodes per sec
        const king_attacks = getAllAttackMaskFromKing(p_self, turn);
        return king_attacks == 0;
    }
    pub fn _isLegal(p_self: *Board_state, turn: e_color) bool {
        const all_attack = getAllAttackMask(p_self, p_self.occupiedBB, invertColor(turn));
        const king_bb = p_self.getKingBB(turn);
        if (king_bb == 0) {
            return false;
        }
        return (king_bb & all_attack) == 0;
    }

    //pub fn isLegalFast(p_self: *Board_state, all_attack: u64, move: IMove, p_kingSq: *const squareInfo, p_checks: *const squarel.checkContainer) bool {
    //    const kingBB = (ONE << @intCast(@intFromEnum(p_kingSq.sq)));
    //    const isAttacked: bool = (kingBB & all_attack) != 0;

    //    const iTo = move.getTo();
    //    const to: e_square = @enumFromInt(iTo);
    //    const toBB = ONE << @intCast(iTo);

    //    const iFrom = move.getFrom();
    //    const from: e_square = @enumFromInt(iFrom);
    //    const fromBB = ONE << @intCast(iFrom);
    //    const tPinnedBB: u64 = p_self.pinnedBB[@intFromEnum(p_self.turn)];
    //    if (from != p_kingSq.sq) {
    //        if (p_checks.isDoubleCheck()) {
    //            return false;
    //        }
    //        if ((tPinnedBB & fromBB) != 0) {
    //            return ((tPinnedBB & toBB) != 0 and !isAttacked);
    //        }

    //        //blocking or capturing as non king
    //        return (((toBB & tPinnedBB) != 0) or (p_checks.squares[0].sq == to) or !isAttacked);
    //    }

    //    const toKingBB = (ONE << @intCast(@intFromEnum(to)));
    //    // either no pinning piece is found or the pinned piece can be captured
    //    const isNotPinned = (tPinnedBB & toKingBB) == 0;
    //    const isToSecure = ((all_attack & toKingBB) == 0);
    //    return (isNotPinned and isToSecure);
    //}
    pub fn isLegalFast(p_self: *Board_state, all_attack: u64, move: IMove, p_kingSq: *const squareInfo, p_checks: *const squarel.checkContainer, diagPieceBB: u64, linePieceBB: u64) bool {
        const kingBB = (ONE << @intCast(@intFromEnum(p_kingSq.sq)));
        const isAttacked: bool = (kingBB & all_attack) != 0;
        const to: e_square = @enumFromInt(move.getTo());
        const from: e_square = @enumFromInt(move.getFrom());
        if (from != p_kingSq.sq) {
            if (p_checks.isDoubleCheck()) {
                return false;
            }
            const pinnedBB = isPiecePinned(p_self.occupiedBB, from, p_kingSq, diagPieceBB, linePieceBB);
            if (pinnedBB != EMPTY) {
                if (p_checks.isCheck() and (pinnedBB != p_checks.squares[0].getBB())) {
                    return false;
                }
                const capturedPinned = (bitscan(pinnedBB) == @intFromEnum(to));
                return ((pinnedBB == isPiecePinned(p_self.occupiedBB ^ (ONE << @intCast(@intFromEnum(from))), to, p_kingSq, diagPieceBB, linePieceBB)) or capturedPinned);
            }

            if (!isAttacked) {
                return true;
            }
            //blocking or capturing as non king
            const last_pin = isPiecePinned(p_self.occupiedBB, to, p_kingSq, diagPieceBB, linePieceBB);

            return ((last_pin == p_checks.squares[0].getBB()) or (p_checks.squares[0].sq == to));
        }
        const toKing = squareInfo.init(to);
        const pinInfo = (isPiecePinned(p_self.occupiedBB, from, &toKing, diagPieceBB, linePieceBB));
        // either no pinning piece is found or the pinned piece can be captured
        const isNotPinned = (pinInfo == EMPTY) or ((pinInfo ^ toKing.getBB()) == EMPTY);
        const isToSecure = ((all_attack & toKing.getBB()) == 0);
        return (isNotPinned and isToSecure);
    }

    pub fn isStaleThreeFold(self: Board_state) bool {
        // TODO: Make it actually adhere to the rule ie check for 3 BOARD_STATE repeated during the _whole_ game
        _ = self;
        return false;
    }

    pub fn setSeed(p_self: *Board_state, seed: u64) void {
        p_self.rngIntGenerator.seed(seed);
        p_self.randInt = p_self.rngIntGenerator.random();
    }
    pub fn getFen(self: Board_state) []const u8 {
        const ret = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w";
        _ = self;
        return ret;
    }
};
pub fn isCastleLegalPreMove(p_self: *Board_state, turn: e_color, move: IMove, all_attacks: u64) bool {
    const kingBB = p_self.getKingBB(turn);
    if (move.isKingSideCastle()) {
        if ((all_attacks & (kingBB | (kingBB << 1) | (kingBB << 2))) != 0) {
            return false;
        }
    } else {
        if ((all_attacks & (kingBB | (kingBB >> 1) | (kingBB >> 2))) != 0) {
            return false;
        }
    }
    return true;
}
pub fn isCastleLegalPostMove(p_self: *Board_state, turn: e_color, move: IMove, all_attacks: u64) bool {
    const kingBB = p_self.getKingBB(turn);
    if (move.isKingSideCastle()) {
        if ((all_attacks & (kingBB | (kingBB >> 1) | (kingBB >> 2))) != 0) {
            return false;
        }
    } else {
        if ((all_attacks & (kingBB | (kingBB << 1) | (kingBB << 2))) != 0) {
            return false;
        }
    }
    return true;
}
pub fn sanityCheckBoardState(p_board_state: *Board_state) void {
    var panic: bool = false;
    // white checks
    const n_white_p = p_board_state.getPieceCount(e_piece.nWhitePawn) + p_board_state.getPieceCount(e_piece.nWhiteBishop) + p_board_state.getPieceCount(e_piece.nWhiteKnight) + p_board_state.getPieceCount(e_piece.nWhiteRook) + p_board_state.getPieceCount(e_piece.nWhiteQueen) + p_board_state.getPieceCount(e_piece.nWhiteKing);
    const n_white_g = p_board_state.getSidePieceCount(e_color.WHITE);
    const white_king = p_board_state.getKingBB(e_color.WHITE);
    if (n_white_g != n_white_p) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Number of white pieces inconsistent from occupiedBB({d}) to pieceBB({d})\n", .{ n_white_g, n_white_p });
        panic = true;
    }
    if (white_king == 0) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Alert the white king is missing!!\n", .{});
        panic = true;
    }
    // black checks

    const n_black_p = p_board_state.getPieceCount(e_piece.nBlackPawn) + p_board_state.getPieceCount(e_piece.nBlackBishop) + p_board_state.getPieceCount(e_piece.nBlackKnight) + p_board_state.getPieceCount(e_piece.nBlackRook) + p_board_state.getPieceCount(e_piece.nBlackQueen) + p_board_state.getPieceCount(e_piece.nBlackKing);
    const n_black_g = p_board_state.getSidePieceCount(e_color.BLACK);

    const black_king = p_board_state.getKingBB(e_color.BLACK);

    if (n_black_g != n_black_p) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Number of black pieces inconsistent from occupiedBB({d}) to pieceBB({d})\n", .{ n_black_g, n_black_p });
        panic = true;
    }
    if (black_king == 0) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Alert the black king is missing!!\n", .{});
        panic = true;
    }
    if (panic) {
        print_board(p_board_state);
        const move = p_board_state.getLastMove();
        std.debug.print("[PANIC] sanityCheckBoardState: last move performed: {s}-{}-{}-{}\n", .{ move.getStr(), move.getFlag(), move.getFromPiece(), move.getCapturePiece() });
        @panic("Sanity check(s) failed");
    }
}

pub fn print_boardstate(p_board_state: *Board_state) void {
    if (p_board_state.turn == e_color.WHITE) {
        std.debug.print("Current turn: White\n", .{});
    } else {
        std.debug.print("Current turn: Black\n", .{});
    }

    print_board(p_board_state);
    std.debug.print("Turn number: {d}, move stored: {d}\n", .{ p_board_state.turn_count, p_board_state.move_history.len });
    std.debug.print("Current evaluation: {d} \n", .{heuristicl.simpleHeuristic(p_board_state)});

    const valid_w = p_board_state.isLegal(e_color.WHITE);
    const valid_b = p_board_state.isLegal(e_color.BLACK);
    if (!valid_w) {
        std.debug.print("White is checked\n", .{});
    }
    if (!valid_b) {
        std.debug.print("Black is checked\n", .{});
    } else {
        std.debug.print("Board is valid\n", .{});
    }
    if (p_board_state.turn_count > 0) {
        std.debug.print("Previous move: ", .{});
        p_board_state.move_history.moves[p_board_state.move_history.len - 1].print();
        std.debug.print("\n", .{});
    }
    std.debug.print("Castling BB: ", .{});
    print_bitboard(p_board_state.castlingBB);
    sanityCheckBoardState(p_board_state);
}

pub fn print_bitboard(bitboard: u64) void {
    std.debug.print("Printing bitboard: {x} {d} ({b})\n", .{ bitboard, bitboard, bitboard });
    var _bitboard = bitboard;
    const mask: u64 = UNIVERSE & (~(UNIVERSE >> 8));
    var row: u8 = undefined;
    for (0..8) |_| {
        row = @intCast((_bitboard & mask) >> 56);
        //row = @intCast(_bitboard % 256);
        if (row == 0) {
            std.debug.print("00000000\n", .{});
        } else {
            for (0..8) |_| {
                if (row % 2 != 0) {
                    std.debug.print("1", .{});
                } else {
                    std.debug.print("0", .{});
                }
                row = row >> 1;
            }
            std.debug.print("\n", .{});
        }
        _bitboard = _bitboard << 8;
    }

    return;
}

pub fn shiftEast(b: u64) u64 {
    return (b & notHFile) << 1;
}
pub fn shiftNortheast(b: u64) u64 {
    return (b & notHFile) << 9;
}
pub fn shiftSoutheast(b: u64) u64 {
    return (b & notHFile) >> 7;
}
pub fn shiftWest(b: u64) u64 {
    return (b & notAFile) >> 1;
}
pub fn shiftSouthwest(b: u64) u64 {
    return (b & notAFile) >> 9;
}
pub fn shiftNorthwest(b: u64) u64 {
    return (b & notAFile) << 7;
}

pub fn l_popcount(x: u64) i8 {
    // Kernighan's way
    // x &= (x - 1)
    // (x - 1)  resets every bit before(and including)the LSB
    // x & (x-1) removes the LSB
    var count: i8 = 0;
    var _x: u64 = x;
    while (_x != 0) {
        _x &= (_x - 1);
        count += 1;
    }
    return count;
}

//var popCountOfByte256: [256]c_char = undefined;
//
//pub fn initpopCountOfByte256() void {
//    popCountOfByte256[0] = 0;
//    for (0..256) |i| {
//        popCountOfByte256[i] = popCountOfByte256[i / 2] + (i & 1);
//    }
//}
//
//pub fn p_popcount(x: u64) c_int {
//    return popCountOfByte256[x & 0xff] +
//        popCountOfByte256[(x >> 8) & 0xff] +
//        popCountOfByte256[(x >> 16) & 0xff] +
//        popCountOfByte256[(x >> 24) & 0xff] +
//        popCountOfByte256[(x >> 32) & 0xff] +
//        popCountOfByte256[(x >> 40) & 0xff] +
//        popCountOfByte256[(x >> 48) & 0xff] +
//        popCountOfByte256[x >> 56];
//}

const k1: u64 = (0x5555555555555555); //  -1/3
const k2: u64 = (0x3333333333333333); //  -1/5
const k4: u64 = (0x0f0f0f0f0f0f0f0f); //  -1/17
const kf: u64 = (0x0101010101010101); //  -1/255

pub fn c_popcount(x: u64) c_int {
    x = x - ((x >> 1) & k1); // put count of each 2 bits into those 2 bits
    x = (x & k2) + ((x >> 2) & k2); // put count of each 4 bits into those 4 bits
    x = (x + (x >> 4)) & k4; // put count of each 8 bits into those 8 bits
    x = (x * kf) >> 56; // returns 8 most significant bits of x + (x<<8) + (x<<16) + (x<<24) + ...
    return @intCast(x);
}

pub fn knightAttacks(knights: u64) u64 {
    // reconstructs perfectly the cycles (+6, +15, +17, +10) (-10, -17 , -15, -6) and apply the notFileMasks to remove file "overflow"
    // Bitboard a
    // a =         1    (64)
    // 0 1 2 3 4 5 6 7
    // a << 1
    // a =           1  (128)
    const l1 = (knights >> 1) & notHFile;
    const l2 = (knights >> 2) & notGHFile;
    const r1 = (knights << 1) & notAFile;
    const r2 = (knights << 2) & notABFile;
    const h1 = l1 | r1;
    const h2 = l2 | r2;
    return (h1 << 16) | (h1 >> 16) | (h2 << 8) | (h2 >> 8);
}

pub fn kingAttacks(sq: i8) u64 {
    var ret: u64 = EMPTY;
    const pos: u64 = (ONE << @intCast(sq));

    ret |= (pos >> 8);
    ret |= (pos << 8);

    if (pos & notAFile != 0) {
        ret |= (pos >> 1);
        ret |= (pos << 7);
        ret |= (pos >> 9);
    }

    if (pos & notHFile != 0) {
        ret |= (pos << 1);
        ret |= (pos << 9);
        ret |= (pos >> 7);
    }

    return ret;
}

pub fn diagonalMask(sq: i8) u64 {
    const maindia: u64 = (0x8040201008040201);
    const diag: i8 = (sq & 7) - (sq >> 3);
    if (diag >= 0) {
        return maindia >> @intCast(diag * 8);
    } else {
        return maindia << @intCast(-diag * 8);
    }
}

pub fn antiDiagMask(sq: i8) u64 {
    const maindia: u64 = (0x0102040810204080);
    const diag: i8 = 7 - (sq & 7) - (sq >> 3);
    if (diag >= 0) {
        return maindia >> @intCast(diag * 8);
    } else {
        return maindia << @intCast(-diag * 8);
    }
}

pub inline fn fileMaskFromFileN(file: u8) u64 {
    return aFile << @intCast(file);
}
pub inline fn rankMaskFromRankN(rank: u8) u64 {
    return firstRank << @intCast(8 * rank);
}

// pre init sliding moves

pub fn simplePawnMask(sq: e_square, color: e_color) u64 {
    var ret: u64 = EMPTY;
    const _sq: u6 = @intCast(@intFromEnum(sq));
    const pos: u64 = ONE << _sq;
    if (color == e_color.BLACK) {
        if (_sq < 8) {
            return EMPTY;
        }
        if (pos & notHFile != 0) {
            ret |= (ONE << (_sq - 7));
        }
        if (pos & notAFile != 0) {
            ret |= (ONE << (_sq - 9));
        }
    } else if (color == e_color.WHITE) {
        if (_sq > 55) {
            return EMPTY;
        }
        if (pos & notAFile != 0) {
            ret |= (ONE << (_sq + 7));
        }
        if (pos & notHFile != 0) {
            ret |= (ONE << (_sq + 9));
        }
    }
    return ret;
}

pub fn getAttackPositiveRay(occupied: u64, dir: e_direction, square: e_square) u64 {
    const attacks = cachedTables.rayAttacks[@intFromEnum(square)][@intFromEnum(dir)];
    const blocking: u64 = occupied & attacks;
    if (blocking == 0) {
        return attacks;
    }
    const sq: i8 = bitscan(blocking);
    if (sq == -1) {
        return EMPTY;
    }
    const _sq: u8 = @bitCast(sq);
    return attacks ^ cachedTables.rayAttacks[_sq][@intFromEnum(dir)];
}

pub fn getAttackRay(occupied: u64, comptime dir: e_direction, square: e_square) u64 {
    const attacks = cachedTables.rayAttacks[@intFromEnum(square)][@intFromEnum(dir)];
    const blocking: u64 = occupied & attacks;
    if (blocking == 0) {
        return attacks;
    }
    var sq: i8 = undefined;
    switch (dir) {
        e_direction.NORTH, e_direction.NORTHEAST, e_direction.NORTHWEST, e_direction.EAST => {
            sq = bitscan(blocking);
        },

        e_direction.SOUTH, e_direction.SOUTHEAST, e_direction.SOUTHWEST, e_direction.WEST => {
            sq = r_bitscan(blocking);
        },
    }

    const _sq: u8 = @bitCast(sq);
    return attacks ^ cachedTables.rayAttacks[_sq][@intFromEnum(dir)];
}

pub fn diagonalAttacks(bb: u64, sq: e_square) u64 {
    return getAttackRay(bb, e_direction.NORTHEAST, sq) | getAttackRay(bb, e_direction.SOUTHWEST, sq); // ^ +
}

pub fn antiDiagAttacks(bb: u64, sq: e_square) u64 {
    return getAttackRay(bb, e_direction.NORTHWEST, sq) | getAttackRay(bb, e_direction.SOUTHEAST, sq); // ^ +
}

pub fn fileAttacks(bb: u64, sq: e_square) u64 {
    return getAttackRay(bb, e_direction.NORTH, sq) | getAttackRay(bb, e_direction.SOUTH, sq); // ^ +
}

pub fn rankAttacks(bb: u64, sq: e_square) u64 {
    return getAttackRay(bb, e_direction.EAST, sq) | getAttackRay(bb, e_direction.WEST, sq); // ^ +
}
pub fn getRookAttacks(occBB: u64, sq: e_square) u64 {
    if (comptime useMagic) {
        return magicl.getRookMoves(sq, occBB);
    } else {
        var ret = fileAttacks(occBB, sq);
        ret |= rankAttacks(occBB, sq);
        return ret;
    }
}
pub fn getBishopAttacks(occBB: u64, sq: e_square) u64 {
    if (comptime useMagic) {
        return magicl.getBishopMoves(sq, occBB);
    } else {
        var ret = antiDiagAttacks(occBB, sq);
        ret |= diagonalAttacks(occBB, sq);
        return ret;
    }
}
pub fn getPawnAttacks(sq: e_square, color: e_color) u64 {
    return cachedTables.SimplePawnAttack[@intFromEnum(color)][@intFromEnum(sq)];
}

pub fn getKingAttacks(sq: e_square) u64 {
    return cachedTables.KingAttack[@intFromEnum(sq)];
}

pub fn xrayRookAttacks(occ: u64, blockers: u64, rookSq: e_square) u64 {
    const attacks = getRookAttacks(occ, rookSq);
    const _blockers = blockers & attacks;
    return attacks ^ getRookAttacks(occ ^ _blockers, rookSq);
}

pub fn xrayBishopAttacks(occ: u64, blockers: u64, bishopSq: e_square) u64 {
    const attacks = getBishopAttacks(occ, bishopSq);
    const _blockers = blockers & attacks;
    return attacks ^ getBishopAttacks(occ ^ _blockers, bishopSq);
}

pub inline fn getSqRank(sq: e_square) u8 {
    return @intFromEnum(sq) / ROW_SIZE;
}
pub inline fn getSqIdxRank(sq: u8) u8 {
    return (sq) / ROW_SIZE;
}

pub inline fn getSqFile(sq: e_square) u8 {
    return @intFromEnum(sq) % ROW_SIZE;
}
pub inline fn getSqIdxFile(sq: u8) u8 {
    return (sq) % ROW_SIZE;
}

pub inline fn getSqFromCoord(rank: u8, file: u8) e_square {
    return @enumFromInt(8 * rank + file);
}

pub inline fn getSqDiag(sq: e_square) i8 {
    //  const diag: i8 = (sq & 7) - (sq >> 3);
    const _sq: i8 = @intCast(@intFromEnum(sq));
    return (_sq & 7) - (_sq >> 3);
}

pub inline fn getSqAntiDiag(sq: e_square) i8 {
    const _sq: i8 = @intCast(@intFromEnum(sq));
    return 7 - (_sq & 7) - (_sq >> 3);
}

pub fn getAllAttackingSquares(sq: e_square) u64 {
    const sqBB = ONE << @intFromEnum(sq);
    const file = getSqFile(sq);
    const rank = getSqRank(sq);

    return knightAttacks(sqBB) | fileMaskFromFileN(file) | rankMaskFromRankN(rank) | diagonalMask(@intFromEnum(sq)) | antiDiagMask(@intFromEnum(sq));
}

pub fn _AllAttackPawnMask(bb_piece: u64, turn: e_color) u64 {
    var ret: u64 = EMPTY;
    var sq: i8 = 0;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);
        if (sq == INVALID_POSITION) {
            continue;
        }
        ret |= cachedTables.SimplePawnAttack[@intFromEnum(turn)][@intCast(sq)];
        _bb_piece ^= (ONE << @intCast(sq));
    }
    return ret;
}

pub fn _AllAttackKnightMask(bb_piece: u64) u64 {
    return knightAttacks(bb_piece);
}

pub fn _AllAttackBishopMask(bb_piece: u64, occ_bb: u64) u64 {
    var ret: u64 = EMPTY;
    var sq: i8 = 0;
    var sq_e: e_square = e_square.a1;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);
        if (sq == INVALID_POSITION) {
            continue;
        }
        sq_e = @enumFromInt(sq);
        ret |= getBishopAttacks(occ_bb, sq_e);
        _bb_piece ^= (ONE << @intCast(sq));
    }
    return ret;
}

pub fn _AllAttackRookMask(bb_piece: u64, occ_bb: u64) u64 {
    var ret: u64 = EMPTY;
    var sq: i8 = 0;
    var sq_e: e_square = e_square.a1;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);

        if (sq == INVALID_POSITION) {
            continue;
        }
        sq_e = @enumFromInt(sq);
        ret |= getRookAttacks(occ_bb, sq_e);

        _bb_piece ^= (ONE << @intCast(sq));
    }
    return ret;
}

pub fn _AllAttackQueenMask(bb_piece: u64, occ_bb: u64) u64 {
    var ret: u64 = EMPTY;
    var sq: i8 = 0;
    var sq_e: e_square = e_square.a1;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);
        if (sq == INVALID_POSITION) {
            continue;
        }
        sq_e = @enumFromInt(sq);

        ret |= getRookAttacks(occ_bb, sq_e);
        ret |= getBishopAttacks(occ_bb, sq_e);

        _bb_piece ^= (ONE << @intCast(sq));
    }
    return ret;
}

pub fn _AllAttackKingMask(bb_piece: u64) u64 {
    var ret: u64 = EMPTY;
    var sq: i8 = 0;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);
        if (sq == INVALID_POSITION) {
            continue;
        }
        ret |= getKingAttacks(@enumFromInt(sq));
        _bb_piece ^= (ONE << @intCast(sq));
    }
    return ret;
}

pub fn getAllAttackMaskXrayKing(p_board: *Board_state, turn: e_color) u64 {
    var ret: u64 = EMPTY;
    var color_offset = @intFromEnum(e_piece.nWhite) - 1;
    var other_color: e_color = e_color.BLACK;

    if (turn == e_color.BLACK) {
        color_offset = @intFromEnum(e_piece.nBlack) - 1;
        other_color = e_color.WHITE;
    }
    const kingBB = p_board.getKingBB(turn);
    p_board.occupiedBB ^= kingBB;
    ret |= _AllAttackPawnMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhitePawn)], turn);
    ret |= _AllAttackKnightMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKnight)]);
    ret |= _AllAttackBishopMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteBishop)], p_board.occupiedBB);
    ret |= _AllAttackRookMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteRook)], p_board.occupiedBB);
    ret |= _AllAttackQueenMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteQueen)], p_board.occupiedBB);
    ret |= _AllAttackKingMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKing)]);
    p_board.occupiedBB ^= kingBB;

    return ret;
}
pub fn getAllAttackMask(p_board: *Board_state, occBB: u64, turn: e_color) u64 {
    var ret: u64 = EMPTY;
    var color_offset = @intFromEnum(e_piece.nWhite) - 1;
    var other_color: e_color = e_color.BLACK;
    if (turn == e_color.BLACK) {
        color_offset = @intFromEnum(e_piece.nBlack) - 1;
        other_color = e_color.WHITE;
    }
    ret |= _AllAttackPawnMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhitePawn)], turn);
    ret |= _AllAttackKnightMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKnight)]);
    ret |= _AllAttackBishopMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteBishop)], occBB);
    ret |= _AllAttackRookMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteRook)], occBB);
    ret |= _AllAttackQueenMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteQueen)], occBB);
    ret |= _AllAttackKingMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKing)]);

    return ret;
}

pub fn getAllAttackMaskFromKing(p_board: *Board_state, turn: e_color) u64 {
    if (turn == .WHITE) {
        return cst_getAllAttackMaskFromKing(p_board, .WHITE);
    } else {
        return cst_getAllAttackMaskFromKing(p_board, .BLACK);
    }
}
pub fn cst_getAllAttackMaskFromKing(p_board: *Board_state, comptime turn: e_color) u64 {
    var ret: u64 = EMPTY;

    const kingbb = p_board.getKingBB(turn);
    if (comptime turn == e_color.WHITE) {
        ret |= _AllAttackKnightMask(kingbb) & p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)];
        ret |= _AllAttackBishopMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
        ret |= _AllAttackRookMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
        ret |= _AllAttackPawnMask(kingbb, e_color.WHITE) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)]);

        ret |= _AllAttackKingMask(kingbb) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackKing)]);
    } else {
        ret |= _AllAttackKnightMask(kingbb) & p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)];
        ret |= _AllAttackBishopMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
        ret |= _AllAttackRookMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);

        ret |= _AllAttackPawnMask(kingbb, e_color.BLACK) & (p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)]);
        ret |= _AllAttackKingMask(kingbb) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteKing)]);
    }
    return ret;
}
pub fn getCheckers(p_board: *Board_state, turn: e_color) void {
    //TODO check for later implementation in hqperft github
    var rq: u64 = undefined;
    var bq: u64 = undefined;
    var n: u64 = undefined;
    var p: u64 = undefined;
    var pinned: u64 = 0;
    var o: e_color = undefined;
    if (turn == .WHITE) {
        rq = p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)];
        bq = p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)];
        n = p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)];
        p = p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)];
        o = .BLACK;
    } else {
        rq = p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
        bq = p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
        n = p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)];
        p = p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)];
        o = .WHITE;
    }
    const kingSq = p_board.getKingSq(turn);
    const king_E: e_square = @enumFromInt(kingSq);
    var pinner = xrayRookAttacks(p_board.occupiedBB, p_board.c_occupiedBB[@intFromEnum(turn)], king_E) & rq;
    while (pinner != EMPTY) {
        const pinsq = bitscan(pinner);
        pinner &= pinner - 1;
        pinned |= inBetween(@enumFromInt(pinsq), king_E);
    }
    //sanityCheckBoardState(p_board);
    pinner = xrayBishopAttacks(p_board.occupiedBB, p_board.c_occupiedBB[@intFromEnum(turn)], king_E) & bq;
    while (pinner != EMPTY) {
        const pinsq = bitscan(pinner);
        pinner &= pinner - 1;
        pinned |= inBetween(@enumFromInt(pinsq), king_E);
    }
    var directChecks = (getBishopAttacks(p_board.occupiedBB, king_E) & bq) | (getRookAttacks(p_board.occupiedBB, king_E) & rq);
    var _check = directChecks;
    while (_check != EMPTY) {
        const checksq = bitscan(_check);
        _check &= _check - 1;
        directChecks |= inBetween(@enumFromInt(checksq), king_E);
    }
    directChecks |= getPawnAttacks(king_E, o) & p;
    directChecks |= knightAttacks(ONE << @intCast(kingSq)) & n;

    p_board.pinnedBB = pinned;
    p_board.checkersBB = directChecks;
    return;
}

pub fn extendIMoveArray(p_arr1: *std.ArrayList(IMove), p_arr2: *std.ArrayList(IMove)) !void {
    if (p_arr2.items.len == 0) {
        return;
    }
    for (0..p_arr2.items.len) |move_idx| {
        try p_arr1.append(get_global_alloc(), p_arr2.items[move_idx]);
    }
}

pub fn getColorFromPiece(piece: e_piece) e_color {
    //if (@intFromEnum(piece) < @intFromEnum(e_piece.nBlack)) {
    //    return e_color.WHITE;
    //}
    //return e_color.BLACK;
    return @enumFromInt(@intFromEnum(piece) / @intFromEnum(e_piece.nBlack));
}

pub fn isPiecePinned(occBB: u64, sq: e_square, p_kingSq: *const squareInfo, diagPieceBB: u64, linePieceBB: u64) u64 {
    const bishopAtts = getBishopAttacks(occBB, sq);
    const kingBB = p_kingSq.getBB();
    const sqInfo = squareInfo.init(sq);

    const diagatts = [_]u64{ bishopAtts & sqInfo.getAntiDiagBB(), bishopAtts & sqInfo.getDiagBB() };

    if ((((diagatts[0] & diagPieceBB) != 0) and ((diagatts[0] & kingBB) != 0))) {
        return (diagatts[0] & diagPieceBB);
    }

    if (((diagatts[1] & diagPieceBB) != 0) and ((diagatts[1] & kingBB) != 0)) {
        return (diagatts[1] & diagPieceBB);
    }

    const rookAtts = getRookAttacks(occBB, sq);
    const lineatts = [_]u64{ rookAtts & sqInfo.getFileBB(), rookAtts & sqInfo.getRankBB() };

    if (((lineatts[0] & linePieceBB) != 0) and ((lineatts[0] & kingBB) != 0)) {
        return (lineatts[0] & linePieceBB);
    }

    if (((lineatts[1] & linePieceBB) != 0) and ((lineatts[1] & kingBB) != 0)) {
        return (lineatts[1] & linePieceBB);
    }
    //} else {
    //    const kingBB = (ONE << @intCast(@intFromEnum(p_kingSq.sq)));
    //    const diagatts = [_]u64{ antiDiagAttacks(occBB, sq), diagonalAttacks(occBB, sq) };

    //    const lineatts = [_]u64{ fileAttacks(occBB, sq), rankAttacks(occBB, sq) };

    //    if ((((diagatts[0] & diagPieceBB) != 0) and ((diagatts[0] & kingBB) != 0))) {
    //        return (diagatts[0] & diagPieceBB);
    //    }

    //    if (((diagatts[1] & diagPieceBB) != 0) and ((diagatts[1] & kingBB) != 0)) {
    //        return (diagatts[1] & diagPieceBB);
    //    }

    //    if (((lineatts[0] & linePieceBB) != 0) and ((lineatts[0] & kingBB) != 0)) {
    //        return (lineatts[0] & linePieceBB);
    //    }

    //    if (((lineatts[1] & linePieceBB) != 0) and ((lineatts[1] & kingBB) != 0)) {
    //        return (lineatts[1] & linePieceBB);
    //    }
    //}
    return EMPTY;
}

pub fn print_ray_attacks(sq: u8) void {
    std.debug.print("\n################ Ray attack state ################ \n", .{});

    std.debug.print("Ray attack north\n", .{});
    print_bitboard(cachedTables.rayAttacks[sq][@intFromEnum(e_direction.NORTH)]);

    std.debug.print("Ray attack north east\n", .{});
    print_bitboard(cachedTables.rayAttacks[sq][@intFromEnum(e_direction.NORTHEAST)]);

    std.debug.print("Ray attack north west\n", .{});
    print_bitboard(cachedTables.rayAttacks[sq][@intFromEnum(e_direction.NORTHWEST)]);

    std.debug.print("Ray attack south\n", .{});
    print_bitboard(cachedTables.rayAttacks[sq][@intFromEnum(e_direction.SOUTH)]);

    std.debug.print("Ray attack south east\n", .{});
    print_bitboard(cachedTables.rayAttacks[sq][@intFromEnum(e_direction.SOUTHEAST)]);

    std.debug.print("Ray attack south west\n", .{});
    print_bitboard(cachedTables.rayAttacks[sq][@intFromEnum(e_direction.SOUTHWEST)]);

    std.debug.print("Ray attack east\n", .{});
    print_bitboard(cachedTables.rayAttacks[sq][@intFromEnum(e_direction.EAST)]);

    std.debug.print("Ray attack west\n", .{});
    print_bitboard(cachedTables.rayAttacks[sq][@intFromEnum(e_direction.WEST)]);
    std.debug.print("\n################ Exiting ray attack state ################ \n", .{});
}

pub fn print_template_bitboard() void {
    std.debug.print("Ben\n", .{});
    std.debug.print("Empty: {d} ({b}), \nUniverse: {d} ({b})\n", .{ EMPTY, EMPTY, UNIVERSE, UNIVERSE });
    print_bitboard(UNIVERSE);
    print_bitboard(UNIVERSE >> 1);
    std.debug.print("\nnotAFile \n", .{});
    print_bitboard(notAFile);

    std.debug.print("\nnotHFile \n", .{});
    print_bitboard(notHFile);

    std.debug.print("\nshiftEast\n", .{});
    print_bitboard(shiftEast(UNIVERSE));

    std.debug.print("\nshiftNortheast\n", .{});
    print_bitboard(shiftNortheast(UNIVERSE));

    std.debug.print("\nshiftNorthwest\n", .{});
    print_bitboard(shiftNorthwest(UNIVERSE));

    std.debug.print("\nshiftSoutheast\n", .{});
    print_bitboard(shiftSoutheast(UNIVERSE));

    std.debug.print("\nshiftSouthwest\n", .{});
    print_bitboard(shiftSouthwest(UNIVERSE));

    std.debug.print("\nshiftWest\n", .{});
    print_bitboard(shiftWest(UNIVERSE));

    for (0..avoidWrap.len) |i| {
        std.debug.print("\nAvoid wrap mov: {d}\n", .{shift[i]});
        print_bitboard(avoidWrap[i]);
    }
    var knights = EMPTY;
    knights |= 1 << 15;
    std.debug.print("\nKnight move on the sides\n", .{});
    print_bitboard(knights);
    print_bitboard(knightAttacks(knights));
    var test_board: u64 = ((EMPTY | 1) << 8);
    test_board |= (1 << 9);
    std.debug.print("\nBitscan test: {d}\n", .{bitscan(test_board)});
    std.debug.print("\nBitscan test on empty: {d}\n", .{bitscan(EMPTY)});

    test_board = 0;
    test_board |= (1 << 49) | (1 << 56);
    //std.debug.print("bitscanForward testing {d}\n", .{bitScanForward(test_board)});
    print_bitboard(test_board);

    std.debug.print("DEFAULT POSITION: \n", .{});
    print_bitboard(DEFAULT_POSITION);
    print_bitboard(getAttackRay(DEFAULT_POSITION, e_direction.NORTHWEST, e_square.g2));

    print_bitboard(DEFAULT_POSITION);
    print_bitboard(getAttackRay(DEFAULT_POSITION, e_direction.SOUTHEAST, e_square.c6));

    var def_board = getDefaultBoard();
    print_board(&def_board);

    var fen_board = getBoardFromFen(DEFAULT_FEN, GLOBAL_ALLOC);
    print_boardstate(&fen_board);

    std.debug.print("Chess test\n", .{});
    var test_board2: Board_state = getEmptyBoardState(GLOBAL_ALLOC);
    print_bitboard(test_board2.occupiedBB);
    const initBB: u64 = 1;

    test_board2.occupiedBB = initBB;
    std.debug.print("\nBefore move\n\n", .{});
    print_bitboard(test_board2.occupiedBB);
    print_bitboard(test_board2.pieceBB[@intFromEnum(e_piece.nWhiteBishop)]);

    std.debug.print("\n\nPrinting the Bishop attack move from the 18nth square\n", .{});
    print_bitboard(cachedTables.RookAttack[31]);

    return;
}

pub fn inferFlagFromMovement(p_state: *Board_state, from: e_square, to: e_square, line_buffer: [MAX_USER_INPUT]u8) u8 {
    var ret_flag: u8 = @intFromEnum(e_moveFlags.QUIETMOVE);
    var diff: i8 = 0;
    const c_piece = p_state.get_piece(@intFromEnum(to));
    if (c_piece != .nEmptySquare) {
        ret_flag |= @intFromEnum(e_moveFlags.CAPTURE);
    }

    if (line_buffer[4] != 0) {
        if (line_buffer[4] == 'b' or line_buffer[4] == 'B') {
            ret_flag |= @intFromEnum(e_moveFlags.BISHOPPROMO);
        } else if (line_buffer[4] == 'n' or line_buffer[4] == 'N') {
            ret_flag |= @intFromEnum(e_moveFlags.KNIGHTPROMO);
        } else if (line_buffer[4] == 'r' or line_buffer[4] == 'R') {
            ret_flag |= @intFromEnum(e_moveFlags.ROOKPROMO);
        } else if (line_buffer[4] == 'q' or line_buffer[4] == 'Q') {
            ret_flag |= @intFromEnum(e_moveFlags.QUEENPROMO);
        }
    }
    const pieceMove = p_state.get_piece(@intFromEnum(from));
    if (isKingPiece(pieceMove)) {
        diff = @intCast(line_buffer[0]);
        diff -= @intCast(line_buffer[2]);
        if (utils.absolute(diff) == 2) {
            if (line_buffer[0] > line_buffer[2]) {
                ret_flag = @intFromEnum(e_moveFlags.QUEENCASTLE);
            } else {
                ret_flag = @intFromEnum(e_moveFlags.KINGCASTLE);
            }
        }
    } else if (isPawnPiece(pieceMove)) {
        diff = @intCast(line_buffer[1]);
        diff -= @intCast(line_buffer[3]);
        if (utils.absolute(diff) == 2) {
            ret_flag |= @intFromEnum(e_moveFlags.DOUBLEPAWN);
        }
        if ((line_buffer[0] != line_buffer[2]) and (c_piece == .nEmptySquare)) {
            ret_flag |= @intFromEnum(e_moveFlags.ENPASSANT);
        }
    }
    return ret_flag;
}

pub fn emptyLineBuffer(line_buffer: []u8) void {
    for (0..line_buffer.len) |i| {
        line_buffer[i] = 0;
    }
}

const MAX_USER_INPUT: u8 = 5;

fn getUserStdinput() [MAX_USER_INPUT]u8 {
    var stdin_buffer = std.mem.zeroes([MAX_USER_INPUT]u8);
    var line_buffer = std.mem.zeroes([MAX_USER_INPUT]u8);
    var stdin = std.fs.File.stdin().reader(&stdin_buffer);
    var w: std.io.Writer = .fixed(&line_buffer);
    _ = stdin.interface.streamDelimiter(&w, '\n') catch unreachable;
    return line_buffer;
}

pub fn askUserMove(p_state: *Board_state) !IMove {
    var line_buffer = std.mem.zeroes([MAX_USER_INPUT]u8);
    var from: e_square = undefined;
    var to: e_square = undefined;
    var flag: u8 = 0;
    std.debug.print("Please enter a move: ", .{});
    while (true) {
        line_buffer = getUserStdinput();
        std.debug.print("\n", .{});
        if (line_buffer[0] == 0) {
            std.debug.print("Please enter a valid move: ", .{});
            continue;
        }
        from = stringToLERF(line_buffer[0..2]);
        to = stringToLERF(line_buffer[2..4]);
        if ((from == .invalid) or (to == .invalid)) {
            std.debug.print("Please enter a valid move: ", .{});
            continue;
        }
        flag = inferFlagFromMovement(p_state, from, to, line_buffer);
        break;
    }
    var ret = movel.build_move(@intFromEnum(from), @intFromEnum(to), flag, p_state.get_piece(@intFromEnum(from)));
    if ((flag & @intFromEnum(e_moveFlags.CAPTURE)) != 0) {
        if (flag == @intFromEnum(e_moveFlags.ENPASSANT)) {
            if (p_state.turn == .WHITE) {
                ret.setCapture(.nBlackPawn);
            } else {
                ret.setCapture(.nWhitePawn);
            }
        } else {
            ret.setCapture(p_state.get_piece(@intFromEnum(to)));
        }
    }
    return ret;
}

pub fn askContinue() void {
    std.debug.print("Press continue: ", .{});
    var stdin_buffer: [32]u8 = undefined;
    var line_buffer: [32]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&stdin_buffer);
    var w: std.io.Writer = .fixed(&line_buffer);

    _ = stdin.interface.streamDelimiterLimit(&w, '\n', .unlimited) catch void;

    std.debug.print("\n", .{});
    return;
}

pub fn match_routine(p_state: *Board_state) void {
    var curr_player: exploration.Player = undefined;
    var status: e_matchFlag = undefined;
    while (true) {
        print_boardstate(p_state);
        curr_player = p_state.players[@intFromEnum(p_state.turn)];
        status = exploration.handlePlayer(p_state, curr_player) catch |err| {
            std.debug.print("[DEBUG] match_routine: caught err: {} board might be bugged: \n", .{err});
            print_board(p_state);
            return;
        };
        switch (status) {
            .CheckMate, .StaleMate, .Error => {
                std.debug.print("[DEBUG] match_routine: match is over flag: {} \n", .{status});
                askContinue();
                break;
            },
            .Continue => {},
        }
        utils.clear();
    }

    return;
}

pub fn _default_scenarios() void {
    const fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w";
    std.debug.print("Testing fen: {s}\n", .{fen});
    var board_promo = getBoardFromFen(fen, GLOBAL_ALLOC);
    print_boardstate(&board_promo);
    askContinue();
}

pub fn _mate_scenario() void {
    const fen = "k7/6r1/8/7P/7K/7P/6q1/8 b";
    var board_mate = getBoardFromFen(fen, GLOBAL_ALLOC);
    print_boardstate(&board_mate);
    askContinue();
    board_mate.setPlayerType(.BLACK, .DepthBot);
    board_mate.setPlayerSearchDepth(.BLACK, 2);
    board_mate.setPlayerType(.WHITE, .Human);
    match_routine(&board_mate);

    askContinue();
}
pub fn _pin_scenario() void {
    std.debug.print("[DEBUG] pin scenario: \n", .{});
    const fen = "k1p4R/1q2q1rq/8/Q2PPP2/q2PKP1q/3PPP2/4q1q1/1q6 b";

    var board = getBoardFromFen(fen, GLOBAL_ALLOC);
    //const kingInfo = squareInfo.init(@enumFromInt(board.getKingSq(.WHITE)));
    print_boardstate(&board);
    getCheckers(&board, .WHITE);
    std.debug.print("[DEBUG] _pin_scenario: W checkers\n", .{});
    print_bitboard(board.checkersBB);
    std.debug.print("[DEBUG] _pin_scenario: W pinned \n", .{});
    print_bitboard(board.pinnedBB);

    getCheckers(&board, .BLACK);
    std.debug.print("[DEBUG] _pin_scenario: B checkers\n", .{});
    print_bitboard(board.checkersBB);
    std.debug.print("[DEBUG] _pin_scenario: B pinned \n", .{});
    print_bitboard(board.pinnedBB);
    var sq: e_square = .a1;
    var sqInfo: squareInfo = squareInfo.init(sq);

    std.debug.print("[DEBUG] _pin_scenario: bb for d4\n", .{});
    sq = .d4;
    sqInfo = squareInfo.init(sq);
    print_bitboard(magicl.getBishopMoves(sq, board.occupiedBB));
    print_bitboard(sqInfo.getDiagBB());
    print_bitboard(sqInfo.getAntiDiagBB());

    print_bitboard(magicl.getRookMoves(sq, board.occupiedBB));
    print_bitboard(sqInfo.getFileBB());
    print_bitboard(sqInfo.getRankBB());

    std.debug.print("[DEBUG] _pin_scenario: bb for d5\n", .{});
    sq = .d5;
    print_bitboard(magicl.getBishopMoves(sq, board.occupiedBB));
    print_bitboard(magicl.getRookMoves(sq, board.occupiedBB));

    std.debug.print("[DEBUG] _pin_scenario: bb for e5\n", .{});
    sq = .e5;
    print_bitboard(magicl.getBishopMoves(sq, board.occupiedBB));
    print_bitboard(magicl.getRookMoves(sq, board.occupiedBB));

    std.debug.print("[DEBUG] _pin_scenario: bb for f5\n", .{});
    sq = .f5;
    print_bitboard(magicl.getBishopMoves(sq, board.occupiedBB));
    print_bitboard(magicl.getRookMoves(sq, board.occupiedBB));

    std.debug.print("[DEBUG] _pin_scenario: bb for f4\n", .{});
    sq = .f4;
    print_bitboard(magicl.getBishopMoves(sq, board.occupiedBB));
    print_bitboard(magicl.getRookMoves(sq, board.occupiedBB));

    std.debug.print("[DEBUG] _pin_scenario: bb for f3\n", .{});
    sq = .f3;
    print_bitboard(magicl.getBishopMoves(sq, board.occupiedBB));
    print_bitboard(magicl.getRookMoves(sq, board.occupiedBB));

    std.debug.print("[DEBUG] _pin_scenario: bb for e3\n", .{});
    sq = .e3;
    print_bitboard(magicl.getBishopMoves(sq, board.occupiedBB));
    print_bitboard(magicl.getRookMoves(sq, board.occupiedBB));

    askContinue();

    return;
}

pub fn test_scenarios() void {
    // testing promotion scenario
    //const str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w";
    //_default_scenarios();
    //utils.clear();
    //_promo_scenario();
    //utils.clear();
    //_castle_scenario();
    //_mate_scenario();
    _pin_scenario();
    return;
}

pub fn main() !void {
    test_scenarios();
    return;
}
