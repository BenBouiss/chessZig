const std = @import("std");

const assert = std.debug.assert;
//https://stackoverflow.com/questions/76384694/how-to-do-conditional-compilation-with-zig
const build_options = @import("build_options");

pub const fastBitscan = build_options.fastBitscan;
const ignoreChecks = build_options.fastBitscan;
const useMagic = build_options.useMagic;
const useStaged = build_options.useStaged;
const useDebug = build_options.useDebug;
const useAVX2 = build_options.useAVX2;

const utils = @import("utils.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const moveGenl = @import("move_generation.zig");
const heuristicl = @import("heuristic.zig");
const intrinsicsl = @import("intrinsics.zig");
const tablel = @import("moveTables.zig");
const magicl = @import("magic.zig");
const mainl = @import("main.zig");
const hashl = @import("hashTable.zig");
const board_statusl = @import("board_status.zig");

const IMove = movel.IMove;
const e_moveFlags = movel.e_moveFlags;
const moveContainer = movel.moveContainer;
const matchMoveContainer = movel.matchMoveContainer;
const cachedTables = tablel.cachedTables;
const status = board_statusl.status;

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
pub const INVALID_ENPASSANT_FILE: u8 = 8;

pub const EMPTY: u64 = 0;
pub const ONE: u64 = 1;
pub const UNIVERSE: u64 = std.math.maxInt(u64);

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

// 8 pieces per row + 7 '/' = 71
// turn + 4 castling rights + enPassant sq + 3 spaces = 80
// round that up to 100? the match score can be ommited?
pub const MAX_FEN_LENGTH: u8 = 120;
pub const DEFAULT_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 0";

pub const e_piece = enum(u8) { nWhitePawn = 0, nWhiteBishop = 1, nWhiteKnight = 2, nWhiteRook = 3, nWhiteQueen = 4, nWhiteKing = 5, nBlackPawn = 6, nBlackBishop = 7, nBlackKnight = 8, nBlackRook = 9, nBlackQueen = 10, nBlackKing = 11, nEmptySquare = 12, nWhite = 13, nBlack = 14 };

pub const e_color = enum(u8) { BLACK = 0, WHITE = 1 };

const arr_color_conv = [2]e_piece{ e_piece.nBlack, e_piece.nWhite };
const arr_color_inv = [2]e_color{ e_color.WHITE, e_color.BLACK };
const arr_piece_str = [_]u8{ 'P', 'B', 'N', 'R', 'Q', 'K', 'p', 'b', 'n', 'r', 'q', 'k', '_', '1', '2' };

pub const e_direction = enum(u8) { NORTH = 0, SOUTH = 1, WEST = 2, EAST = 3, NORTHWEST = 4, SOUTHEAST = 5, NORTHEAST = 6, SOUTHWEST = 7 };

pub const debug_err = error{ fenErr, earlyReturn, valueErr, memErr };

pub fn strFromLERF(sq: e_square) [2]u8 {
    var ret: [2]u8 = undefined;
    const sq_i: u8 = @intFromEnum(sq);
    ret[0] = 'a' + sq_i % 8;
    ret[1] = '1' + sq_i / 8;
    return ret;
}

pub fn stringToLERF(sq: *[2]u8) e_square {
    if ((sq[0] < 'a') or (sq[0] > 'h')) {
        return .invalid;
    }
    if ((sq[1] < '1') or (sq[1] > '9')) {
        return .invalid;
    }
    return @enumFromInt((sq[0] - 'a') + ((sq[1] - '1') * ROW_SIZE));
}
pub fn cst_stringToLERF(sq: *const [2]u8) e_square {
    if ((sq[0] < 'a') or (sq[0] > 'h')) {
        return .invalid;
    }
    if ((sq[1] < '1') or (sq[1] > '9')) {
        return .invalid;
    }
    return @enumFromInt((sq[0] - 'a') + ((sq[1] - '1') * ROW_SIZE));
}
pub fn flagPromotionToPiece(flag: u8, white: bool) e_piece {
    const color_offset = _getColorPieceOffset(white);
    if ((flag == @intFromEnum(e_moveFlags.KNIGHTPROMO)) or (flag == @intFromEnum(e_moveFlags.KNIGHTPROMOCAPTURE))) {
        const piece: u8 = @intFromEnum(e_piece.nWhiteKnight) + color_offset;
        return @enumFromInt(piece);
    } else if ((flag == @intFromEnum(e_moveFlags.BISHOPPROMO)) or (flag == @intFromEnum(e_moveFlags.BISHOPPROMOCAPTURE))) {
        const piece: u8 = @intFromEnum(e_piece.nWhiteBishop) + color_offset;
        return @enumFromInt(piece);
    } else if ((flag == @intFromEnum(e_moveFlags.ROOKPROMO)) or (flag == @intFromEnum(e_moveFlags.ROOKPROMOCAPTURE))) {
        const piece: u8 = @intFromEnum(e_piece.nWhiteRook) + color_offset;
        return @enumFromInt(piece);
    } else if ((flag == @intFromEnum(e_moveFlags.QUEENPROMO)) or (flag == @intFromEnum(e_moveFlags.QUEENPROMOCAPTURE))) {
        const piece: u8 = @intFromEnum(e_piece.nWhiteQueen) + color_offset;
        return @enumFromInt(piece);
    }
    return e_piece.nEmptySquare;
}

pub fn sqToBitboard(sq: e_square) u64 {
    return ONE << @intCast(@intFromEnum(sq));
}

pub fn xToBitboard(x: u8) u64 {
    return ONE << @intCast(x);
}

/// https://www.chessprogramming.org/Flipping_Mirroring_and_Rotating#Rotating
pub fn rotate180(bb: u64) u64 {
    var x: u64 = bb;
    const h1: u64 = (0x5555555555555555);
    const h2: u64 = (0x3333333333333333);
    const h4: u64 = (0x0F0F0F0F0F0F0F0F);
    const v1: u64 = (0x00FF00FF00FF00FF);
    const v2: u64 = (0x0000FFFF0000FFFF);
    x = ((x >> 1) & h1) | ((x & h1) << 1);
    x = ((x >> 2) & h2) | ((x & h2) << 2);
    x = ((x >> 4) & h4) | ((x & h4) << 4);
    x = ((x >> 8) & v1) | ((x & v1) << 8);
    x = ((x >> 16) & v2) | ((x & v2) << 16);
    x = (x >> 32) | (x << 32);
    return x;
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

pub fn bitscan(bb: u64) u8 {
    // assumes bb is non empty
    if (comptime fastBitscan) {
        var ret: u32 = undefined;
        _ = intrinsicsl._BitScanForward64(&ret, bb);
        return @intCast(ret);
    } else {
        return bitscanK(bb);
    }
}
pub fn bitscanK(b: u64) u8 {
    var lsb: u64 = (((b - 1)) ^ b) & b;
    var count: i8 = -1;
    while (lsb != 0) {
        count += 1;
        lsb = lsb >> 1;
    }
    return count;
}

///*
// bitScanReverse
// @authors Kim Walisch, Mark Dickinson
// @param bb bitboard to scan
// @precondition bb != 0
// @return index (0..63) of most significant one bit
///
/// This function and the one above are branchless version of bitScan and r_bitScan, function are from chessprogramming.org
pub fn r_bitscan(bb: u64) u8 {
    if (comptime fastBitscan) {
        var ret: u32 = undefined;
        _ = intrinsicsl._BitScanForwardReverse64(&ret, bb);
        return @intCast(ret);
    } else {
        return r_bitscanK(bb);
    }
}

pub fn r_bitscanK(b: u64) u8 {
    var bb = b;
    var count: u8 = 0;
    while (bb != 0) {
        count += 1;
        bb = (bb >> 1);
    }
    return count;
}
pub fn print_board(p_board: *Board_state) void {
    var print_buffer: [8][8]u8 = undefined;
    @memset(&print_buffer, .{ 0, 0, 0, 0, 0, 0, 0, 0 });
    //var bb: u64 = undefined;
    //var curr_letter: u8 = 0;
    for (0..N_SQUARES) |sq| {
        const _sq: u8 = @intCast(sq);
        const piece = p_board.get_piece(_sq);
        const pieceStr = getStrFromPiece(piece);
        print_buffer[getSqIdxRank(_sq)][getSqIdxFile(_sq)] = pieceStr;
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

pub fn printBoardValidity(p_state: *Board_state) void {
    const valid_w = p_state.isLegal(true);
    const valid_b = p_state.isLegal(false);
    var v: bool = true;
    if (!valid_w) {
        v = false;
        std.debug.print("White is checked\n", .{});
    }
    if (!valid_b) {
        v = false;
        std.debug.print("Black is checked\n", .{});
    }
    if (v) {
        std.debug.print("Board is valid\n", .{});
    }
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
pub fn getStrFromPiece(piece: e_piece) u8 {
    return arr_piece_str[@intFromEnum(piece)];
}

pub fn getBoardFromFen_pieces(alloc: std.mem.Allocator, fen: []const u8) debug_err!Board_state {
    var ret = getEmptyBoardState(alloc) catch {
        return debug_err.memErr;
    };
    var offset: i8 = 0;
    var board_offset = N_SQUARES - 8;
    var commitedRowSize: u8 = 0;
    while (offset < fen.len) : (offset += 1) {
        const letter: u8 = fen[@intCast(offset)];
        if (letter == '/') {
            board_offset -= 16;
            if (commitedRowSize != 8) {
                std.debug.print("[DEBUG] getBoardFromFen: malformed fen code, malformed row with {d} elements \n", .{commitedRowSize});
                return debug_err.fenErr;
            }
            commitedRowSize = 0;
            continue;
        }
        if (letter == ' ') {
            if (board_offset != (N_SQUARES - 8)) {
                return ret;
            }
            continue;
        }
        if (std.ascii.isDigit(letter)) {
            const letter_int: u8 = letter - '0';
            board_offset += letter_int;
            commitedRowSize += letter_int;
            continue;
        }
        const tmp_enum = getPieceFromStr(letter);

        if (board_offset == N_SQUARES) {
            std.debug.print("[DEBUG] getBoardFromFen_pieces: letter: {d}, fen: {s}\n", .{ letter, fen });
            for (0..fen.len) |i| {
                std.debug.print("({c}, {d}), ", .{ fen[i], fen[i] });
            }
            std.debug.print("[DEBUG] getBoardFromFen_pieces. \n", .{});
        }
        if (!ret.placePiece(tmp_enum, @enumFromInt(board_offset))) {
            std.debug.print("[DEBUG] getBoardFromFen_pieces: Fen problem with piece placement {s}\n", .{fen});
            print_board(&ret);
        }
        if (board_offset != (N_SQUARES)) {
            board_offset += 1;
            commitedRowSize += 1;
        }
    }
    return ret;
}
pub fn getBoardFromFen_turn(p_state: *Board_state, turnToken: []const u8) bool {
    assert(turnToken.len == 1);
    const turnLetter = utils.lowerLetter(turnToken[0]);
    if (turnLetter == 'w') {
        p_state.stat.whiteToMove = true;
    } else if (turnLetter == 'b') {
        p_state.stat.whiteToMove = false;
    } else {
        std.debug.print("[PANIC] getBoardFromFen_turn: turn letter found: letter: {c} token: {s}\n", .{ turnLetter, turnToken });
        @panic("Unknown turn found");
    }
    return true;
}

pub fn getBoardFromFen_castle(p_state: *Board_state, turnToken: []const u8) bool {
    assert(turnToken.len != 0);
    if (turnToken[0] == '-') {
        p_state.stat.WCastlingK = false;
        p_state.stat.WCastlingQ = false;
        p_state.stat.BCastlingK = false;
        p_state.stat.BCastlingQ = false;
    } else {
        for (0..turnToken.len) |i| {
            const letter = turnToken[i];
            if (letter == 'K' or letter == 'H') {
                p_state.stat.WCastlingK = true;
            } else if (letter == 'Q' or letter == 'A') {
                p_state.stat.WCastlingQ = true;
            } else if (letter == 'k' or letter == 'h') {
                p_state.stat.BCastlingK = true;
            } else if (letter == 'q' or letter == 'a') {
                p_state.stat.BCastlingQ = true;
            }
        }
    }
    return true;
}
pub fn getBoardFromFen_enPassant(p_state: *Board_state, turnToken: []const u8) bool {
    assert(turnToken.len != 0);
    if (turnToken[0] == '-') {
        p_state.enPassantIdx = 0;
    } else {
        assert(turnToken.len == 2);
        const sq = cst_stringToLERF(turnToken[0..2]);
        p_state.enPassantIdx = @intFromEnum(sq);
    }
    return true;
}
pub fn getBoardFromFen_clockMove(turnToken: []const u8) u16 {
    assert(turnToken.len != 0);
    const nbr = std.fmt.parseInt(u16, turnToken, 10) catch {
        return 0;
    };
    return nbr;
}
/// All memory used by the alloc is freed at return
pub fn getBoardFromFen(alloc: std.mem.Allocator, fen: []const u8) debug_err!Board_state {
    var tokens = utils.split(u8, alloc, fen, ' ') catch {
        return debug_err.fenErr;
    };
    defer tokens.deinit(alloc);
    if (tokens.items.len < 6) {
        return debug_err.fenErr;
    }
    //utils.printArrayListTasStr([]const u8, tokens);
    var board = try getBoardFromFen_pieces(alloc, tokens.items[0]);
    _ = getBoardFromFen_turn(&board, tokens.items[1]);
    _ = getBoardFromFen_castle(&board, tokens.items[2]);
    _ = getBoardFromFen_enPassant(&board, tokens.items[3]);
    board.halfMoveClock = @intCast(getBoardFromFen_clockMove(tokens.items[4]));
    board.turn_count = @intCast(getBoardFromFen_clockMove(tokens.items[5]));
    if (comptime useStaged) {
        getCheckers(&board, board.whiteToMove());
    }
    return board;
}

pub fn getBoardFromUciFen(uciStr: []const u8, alloc: std.mem.Allocator, debug: bool) !Board_state {
    var ret = getBoardFromFen(alloc, uciStr) catch unreachable;
    try applyUciMoves(&ret, uciStr, alloc, debug);
    return ret;
}
pub fn applyUciMoves(p_board: *Board_state, uciStr: []const u8, alloc: std.mem.Allocator, debug: bool) !void {
    const moves = try getEmptyMoveListFromStr(uciStr, alloc);
    if (debug) {
        std.debug.print("[DEBUG] applyUciMoves: Moves found in str: ", .{});
        for (0..moves.len) |i| {
            const move = moves.moves[i];
            std.debug.print("{s} ", .{move.getStr()});
        }
        std.debug.print("\n", .{});
    }
    for (0..moves.len) |i| {
        var move = moves.moves[i];
        fillMoveFromState(p_board, &move);
        p_board.makeMove(move);
        if (debug) {
            sanityCheckBoardState(p_board);
        }
    }
}
pub fn getEmptyMoveListFromStr(strBuffer: []const u8, alloc: std.mem.Allocator) !movel.matchMoveContainer {
    var cmd_split = try utils.split(u8, alloc, strBuffer, ' ');
    defer cmd_split.deinit(alloc);
    var ret: movel.matchMoveContainer = .{};

    for (cmd_split.items) |cmd| {
        if (cmd.len != 4 and cmd.len != 5) {
            continue;
        }
        const from = cst_stringToLERF(cmd[0..2]);
        const to = cst_stringToLERF(cmd[2..4]);
        if (from == .invalid or to == .invalid) {
            continue;
        }
        var flag: u8 = 0;
        if (cmd.len > 4) {
            if (cmd[4] != 0) {
                if (cmd[4] == 'b' or cmd[4] == 'B') {
                    flag |= @intFromEnum(e_moveFlags.BISHOPPROMO);
                } else if (cmd[4] == 'n' or cmd[4] == 'N') {
                    flag |= @intFromEnum(e_moveFlags.KNIGHTPROMO);
                } else if (cmd[4] == 'r' or cmd[4] == 'R') {
                    flag |= @intFromEnum(e_moveFlags.ROOKPROMO);
                } else if (cmd[4] == 'q' or cmd[4] == 'Q') {
                    flag |= @intFromEnum(e_moveFlags.QUEENPROMO);
                }
            }
        }
        const move = movel.build_move(@intFromEnum(from), @intFromEnum(to), flag, .nEmptySquare);
        _ = ret.append(move, .{ .code = EMPTY });
    }
    return ret;
}

pub fn getMoveListFromStr(p_state: *Board_state, strBuffer: []const u8, alloc: std.mem.Allocator) !std.ArrayList(IMove) {
    // /!\ this assumes that the p_state is updated for the corresponding move to "decode", not suitable for a position startpos parsing
    var cmd_split = try utils.split(u8, alloc, strBuffer, ' ');
    var ret = try std.ArrayList(IMove).initCapacity(alloc, cmd_split.items.len);

    defer cmd_split.deinit(alloc);

    var from: e_square = undefined;
    var to: e_square = undefined;
    for (cmd_split.items) |cmd| {
        if (cmd.len != 4 and cmd.len != 5) {
            continue;
        }
        from = cst_stringToLERF(cmd[0..2]);
        to = cst_stringToLERF(cmd[2..4]);
        if (from == .invalid or to == .invalid) {
            continue;
        }
        const flag: u8 = inferFlagFromMovement(p_state, from, to, cmd);
        const piece = p_state.get_piece(@intFromEnum(from));
        var toPiece = p_state.get_piece(@intFromEnum(to));
        var move = movel.build_move(@intFromEnum(from), @intFromEnum(to), flag, piece);
        if (move.isEnpassant()) {
            if (p_state.whiteToMove()) {
                toPiece = .nBlackPawn;
            } else {
                toPiece = .nWhitePawn;
            }
        }
        move.setCapture(toPiece);
        ret.append(alloc, move) catch unreachable;
    }
    return ret;
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

pub fn invertColor(color: e_color) e_color {
    if (color == .WHITE) {
        return .BLACK;
    }
    return .WHITE;
}
pub fn getColorPieceOffset(color: e_color) u8 {
    if (color == .WHITE) {
        return 0;
    }
    return N_PIECES_TYPES;
}
pub fn _getColorPieceOffset(white: bool) u8 {
    if (white) {
        return 0;
    }
    return N_PIECES_TYPES;
}
pub const Board_stateContainer = struct {
    array: []Board_state,
    len: usize,

    pub fn free(p_self: *Board_stateContainer, alloc: std.mem.Allocator) void {
        alloc.free(p_self.array);
        for (0..p_self.len) |i| {
            p_self.array[i].free(alloc);
        }
    }
};

pub fn getEmptyBoardState(alloc: std.mem.Allocator) !Board_state {
    return try Board_state.init(alloc);
}

pub const boardFrame = struct {
    pinnedBB: u64 = 0,
    checkersBB: u64 = 0,
    key: hashl.Key = .{},

    lastMove: IMove = .{},
    enPassantIdx: u8 = 0,
    halfMoveClock: u8 = 0,
    victim: e_piece = .nEmptySquare,
};

pub const boardStack = struct {
    stack: [movel.MAX_MATCH_LENGTH]boardFrame = undefined,
    len: usize = 0,

    pub fn push(p_self: *boardStack, p_frame: *const boardFrame) void {
        if (comptime useDebug) {
            if (p_self.len == movel.MAX_MATCH_LENGTH) {
                @panic("Board stack is full, forgot to pop?");
            }
        }
        p_self.stack[p_self.len] = p_frame.*;
        p_self.len += 1;
    }
    pub fn pop(p_self: *boardStack) boardFrame {
        if (comptime useDebug) {
            if (p_self.len == 0) {
                @panic("Popping from empty boardframe, forgot to push?");
            }
        }
        p_self.len -= 1;
        return p_self.stack[p_self.len];
    }
};

pub const Board_state = struct {
    pieceBB: [N_PIECES]u64 = std.mem.zeroes([N_PIECES]u64),
    c_occupiedBB: [NUMBER_PLAYER]u64,
    pieceArray: [N_SQUARES]e_piece = std.mem.zeroes([N_SQUARES]e_piece),

    wKingSq: e_square = .a1,
    bKingSq: e_square = .a1,

    pinnedBB: u64 = 0,
    checkersBB: u64 = 0,

    //wPinnedBB: u64 = 0,
    //wCheckersBB: u64 = 0,
    //bPinnedBB: u64 = 0,
    //bCheckersBB: u64 = 0,

    occupiedBB: u64 = 0,
    key: hashl.Key = .{},
    halfMoveClock: u8 = 0,
    enPassantIdx: u8 = 0,

    // big structures might be better to alloc then and
    // only store the pointers(?)
    // 184KB current size need better way
    //s_stack: *board_statusl.statusStack = undefined,
    //move_history: *matchMoveContainer = undefined,
    //stack: *boardStack = undefined,

    s_stack: board_statusl.statusStack = .{},
    move_history: matchMoveContainer = .{},
    stack: boardStack = .{},
    victim: e_piece = .nEmptySquare,
    turn_count: u64 = 0,
    stat: status = .{},

    lastMove: IMove = .{},
    rngIntGenerator: std.Random.DefaultPrng,
    randInt: std.Random,
    seed: u64 = 42,
    isInit: bool = false,

    pub fn init(alloc: std.mem.Allocator) !Board_state {
        var ret: Board_state = undefined;
        @memset(&ret.pieceBB, 0);
        @memset(&ret.c_occupiedBB, 0);
        @memset(&ret.pieceArray, e_piece.nEmptySquare);

        ret.stat = .{};
        ret.turn_count = 0;
        ret.occupiedBB = 0;

        ret.halfMoveClock = 0;
        ret.key = .{};

        ret.pinnedBB = 0;
        ret.checkersBB = 0;
        ret.enPassantIdx = 0;

        ret.victim = .nEmptySquare;

        ret.lastMove = .{};

        ret.move_history = .{};
        ret.stack = .{};
        ret.s_stack = .{};

        _ = alloc;
        // stack vs heap
        //ret.move_history = try alloc.create(matchMoveContainer);
        //ret.stack = try alloc.create(boardStack);
        //ret.s_stack = try alloc.create(board_statusl.statusStack);
        //ret.move_history.* = .{};
        //ret.stack.* = .{};
        //ret.s_stack.* = .{};
        //ret.isInit = true;
        if (useDebug) {
            std.debug.print("[DEBUG] from Board_state.init: size of board state: {d} bytes\n", .{@sizeOf(Board_state)});
            std.debug.print("[DEBUG] from Board_state.init: size of stack : {d} bytes\n", .{@sizeOf(boardStack)});
        }

        ret.rngIntGenerator = std.Random.DefaultPrng.init(ret.seed);
        ret.randInt = ret.rngIntGenerator.random();
        //
        return ret;
    }
    pub fn free(p_self: *Board_state, alloc: std.mem.Allocator) void {
        _ = alloc;
        _ = p_self;
        //if (p_self.isInit) {
        //    alloc.destroy(p_self.stack);
        //    alloc.destroy(p_self.s_stack);
        //    alloc.destroy(p_self.move_history);
        //    p_self.isInit = false;
        //}
    }
    pub inline fn whiteToMove(self: Board_state) bool {
        return self.stat.whiteToMove;
    }
    pub fn makeFrame(self: Board_state) boardFrame {
        return .{ .pinnedBB = self.pinnedBB, .victim = self.victim, .checkersBB = self.checkersBB, .enPassantIdx = self.enPassantIdx, .lastMove = self.lastMove, .key = self.key, .halfMoveClock = self.halfMoveClock };
    }
    pub fn loadFrame(p_self: *Board_state, p_frame: *const boardFrame) void {
        p_self.pinnedBB = p_frame.pinnedBB;
        p_self.checkersBB = p_frame.checkersBB;
        p_self.victim = p_frame.victim;
        p_self.enPassantIdx = p_frame.enPassantIdx;
        p_self.lastMove = p_frame.lastMove;
        p_self.key = p_frame.key;
        p_self.halfMoveClock = p_frame.halfMoveClock;
        return;
    }
    pub fn duplicateNTimes(self: Board_state, alloc: std.mem.Allocator, n: usize) !Board_stateContainer {
        var ret: []Board_state = try alloc.alloc(Board_state, n);
        for (0..n) |i| {
            ret[i] = self;

            //ret[i].stack = try alloc.create(boardStack);
            //ret[i].s_stack = try alloc.create(board_statusl.statusStack);
            //ret[i].move_history = try alloc.create(matchMoveContainer);

            //ret[i].stack.* = self.stack.*;
            //ret[i].s_stack.* = self.s_stack.*;
            //ret[i].move_history.* = self.move_history.*;

            if (comptime useDebug) {
                sanityCheckBoardState(&ret[i]);
            }
        }
        return .{ .array = ret, .len = ret.len };
    }

    pub fn printHistory(self: Board_state) void {
        for (0..self.move_history.len) |i| {
            const move = self.move_history.moves[i];
            std.debug.print("{s} ", .{move.getStr()});
        }
        std.debug.print("\n", .{});
    }

    pub fn get_fen(self: *Board_state) [MAX_FEN_LENGTH]u8 {
        var ret = std.mem.zeroes([MAX_FEN_LENGTH]u8);
        var miscOffset: u8 = 0;
        var emptyNumber: u8 = 0;
        var board_offset = N_SQUARES - 8;
        for (0..N_SQUARES) |i| {
            if (i % ROW_SIZE == 0 and i != 0) {
                if (emptyNumber != 0) {
                    ret[miscOffset] = '0' + emptyNumber;
                    emptyNumber = 0;
                    miscOffset += 1;
                }
                ret[miscOffset] = '/';
                miscOffset += 1;
                board_offset -= 16;
            }
            const piece = self.get_piece(board_offset);
            if (piece != .nEmptySquare) {
                if (emptyNumber != 0) {
                    ret[miscOffset] = '0' + emptyNumber;
                    emptyNumber = 0;
                    miscOffset += 1;
                }
                const pieceStr = getStrFromPiece(piece);
                ret[miscOffset] = pieceStr;
                miscOffset += 1;
            } else {
                emptyNumber += 1;
            }
            board_offset += 1;
        }
        //const endPiece = N_SQUARES - (1 + miscOffset);
        const endPiece = miscOffset;
        ret[endPiece] = ' ';
        if (self.whiteToMove()) {
            ret[endPiece + 1] = 'w';
        } else {
            ret[endPiece + 1] = 'b';
        }
        ret[endPiece + 2] = ' ';
        var castleOffset: u8 = 0;
        if (self.stat.canKingsideCastle(true)) {
            ret[endPiece + 3 + castleOffset] = 'H';
            castleOffset += 1;
        }
        if (self.stat.canQueensideCastle(true)) {
            ret[endPiece + 3 + castleOffset] = 'A';
            castleOffset += 1;
        }
        if (self.stat.canKingsideCastle(false)) {
            ret[endPiece + 3 + castleOffset] = 'h';
            castleOffset += 1;
        }
        if (self.stat.canQueensideCastle(false)) {
            ret[endPiece + 3 + castleOffset] = 'a';
            castleOffset += 1;
        }
        var endCastlOffset: u8 = endPiece + 3 + castleOffset;
        var endEnPassantOffset: u8 = 0;
        if (castleOffset == 0) {
            ret[endCastlOffset] = '-';
            endCastlOffset += 1;
        }
        ret[endCastlOffset] = ' ';

        if (self.enPassantIdx == 0) {
            ret[endCastlOffset + 1] = '-';
            endEnPassantOffset = endCastlOffset + 1;
        } else {
            const sqStr = strFromLERF(@enumFromInt(self.enPassantIdx));
            ret[endCastlOffset + 1] = sqStr[0];
            ret[endCastlOffset + 2] = sqStr[1];
            endEnPassantOffset = endCastlOffset + 2;
        }
        ret[endEnPassantOffset + 1] = ' ';
        var buffer: [20]u8 = undefined;
        const halfMove = std.fmt.bufPrint(&buffer, "{}", .{self.halfMoveClock}) catch {
            return ret;
        };
        var offset: u8 = 0;
        for (halfMove) |letter| {
            ret[endEnPassantOffset + 2 + offset] = letter;
            offset += 1;
        }
        const endHalfMoveOffset: u8 = offset + endEnPassantOffset + 2;
        ret[endHalfMoveOffset] = ' ';
        offset = 0;
        const fullMoveClock = std.fmt.bufPrint(&buffer, "{}", .{self.turn_count}) catch {
            return ret;
        };
        for (fullMoveClock) |letter| {
            ret[endHalfMoveOffset + 1 + offset] = letter;
            offset += 1;
        }
        return ret;
    }
    pub fn get_piece(p_self: *Board_state, sq: u8) e_piece {
        return p_self.pieceArray[sq];
    }

    pub inline fn invert_turn(p_self: *Board_state) void {
        p_self.stat.whiteToMove = !p_self.stat.whiteToMove;
    }

    pub fn next_turn(p_self: *Board_state) void {
        p_self.invert_turn();
        p_self.turn_count += 1;
    }

    fn undo_turn(p_self: *Board_state) void {
        p_self.invert_turn();
        p_self.turn_count -= 1;
    }

    pub fn placePiece(p_self: *Board_state, piece: e_piece, square: e_square) bool {
        //std.debug.print("[DEBUG] placePiece: Placing piece {} {square}\n", .{piece});
        const one_mask: u64 = sqToBitboard(square);
        if (p_self.occupiedBB & one_mask != 0) {
            return false;
        }

        p_self.pieceBB[@intFromEnum(piece)] |= one_mask;
        p_self.occupiedBB |= one_mask;
        p_self.pieceBB[@intFromEnum(e_piece.nEmptySquare)] ^= one_mask;
        p_self.pieceArray[@intFromEnum(square)] = piece;
        if (@intFromEnum(piece) < N_PIECES_TYPES) {
            p_self.c_occupiedBB[@intFromEnum(e_color.WHITE)] |= one_mask;
        } else {
            p_self.c_occupiedBB[@intFromEnum(e_color.BLACK)] |= one_mask;
        }
        if (piece == .nWhiteKing) {
            p_self.wKingSq = square;
        } else if (piece == .nBlackKing) {
            p_self.bKingSq = square;
        }
        return true;
    }

    pub fn undoMove(p_self: *Board_state) bool {
        if (p_self.whiteToMove()) {
            return undoMove_cst(p_self, false);
        } else {
            return undoMove_cst(p_self, true);
        }
    }
    pub fn undoMove_cst(p_self: *Board_state, comptime white: bool) bool {
        // test to reduce the undoMove load

        if (comptime useDebug) {
            sanityCheckBoardState(p_self);
        }
        p_self.turn_count -= 1;
        const s_popped = (p_self.s_stack.pop());
        p_self.stat = s_popped;

        const popped_move = p_self.getLastMove();
        const victim = p_self.victim;

        const toSq: u8 = popped_move.getTo();
        const toBB = xToBitboard(toSq);

        const fromSq: u8 = popped_move.getFrom();
        const fromBB = xToBitboard(fromSq);

        var castlePiece: e_piece = .nWhiteRook;
        if (comptime !white) {
            castlePiece = .nBlackRook;
        }
        var piece = p_self.get_piece(toSq);

        p_self.pieceBB[@intFromEnum(piece)] ^= toBB;
        if (popped_move.isPromotion()) {
            piece = popped_move.getFromPiece();
        }
        p_self.pieceBB[@intFromEnum(piece)] ^= fromBB;
        p_self.c_occupiedBB[@intFromBool(white)] ^= (fromBB | toBB);
        p_self.occupiedBB ^= (fromBB | toBB);
        p_self.pieceArray[toSq] = .nEmptySquare;
        p_self.pieceArray[fromSq] = piece;

        if (victim != .nEmptySquare) {
            p_self.pieceBB[@intFromEnum(victim)] ^= toBB;
            p_self.c_occupiedBB[@intFromBool(!white)] ^= toBB;
            p_self.occupiedBB ^= toBB;
            p_self.pieceArray[toSq] = victim;
        }
        if (popped_move.isEnpassant()) {
            const victimSq: e_square = getSqFromCoord(getSqIdxRank(fromSq), getSqIdxFile(toSq));
            const victimBB: u64 = sqToBitboard(victimSq);
            const bisBB = victimBB | toBB;
            p_self.pieceArray[toSq] = .nEmptySquare;
            p_self.pieceArray[@intFromEnum(victimSq)] = victim;

            p_self.pieceBB[@intFromEnum(victim)] ^= bisBB;
            p_self.c_occupiedBB[@intFromBool(!white)] ^= bisBB;

            p_self.occupiedBB ^= bisBB;
        } else if (isKingPiece(piece)) {
            if (comptime white) {
                // white called thus black king moved
                p_self.wKingSq = @enumFromInt(fromSq);
            } else {
                p_self.bKingSq = @enumFromInt(fromSq);
            }
            if (toSq == (fromSq + 2)) {
                const castleBB = (xToBitboard(toSq - 1) | (xToBitboard(toSq + 1)));
                p_self.pieceArray[toSq + 1] = castlePiece;
                p_self.pieceArray[toSq - 1] = .nEmptySquare;

                p_self.pieceBB[@intFromEnum(castlePiece)] ^= castleBB;
                p_self.c_occupiedBB[@intFromBool(white)] ^= (castleBB);
                p_self.occupiedBB ^= castleBB;
            } else if (toSq == (fromSq - 2)) {
                const castleBB = (xToBitboard(toSq + 1) | (xToBitboard(toSq - 2)));
                p_self.pieceArray[toSq - 2] = castlePiece;
                p_self.pieceArray[toSq + 1] = .nEmptySquare;

                p_self.pieceBB[@intFromEnum(castlePiece)] ^= castleBB;
                p_self.c_occupiedBB[@intFromBool(white)] ^= (castleBB);
                p_self.occupiedBB ^= castleBB;
            }
        }

        if (comptime useDebug) {
            sanityCheckBoardState(p_self);
        }
        _ = p_self.move_history.popMove();

        const popped = (p_self.stack.pop());
        p_self.loadFrame(&popped);

        return true;
    }
    pub fn makeMove(p_self: *Board_state, move: IMove) void {
        if (p_self.whiteToMove()) {
            p_self.makeMove_cst(move, true);
        } else {
            p_self.makeMove_cst(move, false);
        }
    }
    pub fn makeMove_cst(p_self: *Board_state, move: IMove, comptime white: bool) void {
        // test to reduce the makeMove load
        if (comptime useDebug) {
            sanityCheckBoardState(p_self);
        }

        p_self.stack.push(&p_self.makeFrame());
        p_self.s_stack.push(p_self.stat);

        p_self.lastMove = move;
        p_self.victim = .nEmptySquare;
        hashl.updateKey(&p_self.key, &hashl.zobristKeys.playKey);
        hashl.updateKey(&p_self.key, &hashl.zobristKeys.castlingKeys[p_self.stat.castlingKey()]);
        hashl.updateKey(&p_self.key, &hashl.zobristKeys.enPassantKeys[p_self.enPassantIdx]);
        p_self.enPassantIdx = 0;

        const toSq = move.getTo();
        const fromSq = move.getFrom();
        const toBB = xToBitboard(toSq);
        const fromBB = xToBitboard(fromSq);
        const moveBB = fromBB | toBB;
        const fromPiece = p_self.get_piece(fromSq);
        const victim = move.getCapturePiece();

        p_self.pieceArray[fromSq] = .nEmptySquare;

        p_self.pieceBB[@intFromEnum(fromPiece)] ^= moveBB;
        p_self.c_occupiedBB[@intFromBool(p_self.whiteToMove())] ^= moveBB;
        p_self.pieceArray[toSq] = fromPiece;

        p_self.occupiedBB ^= moveBB;
        p_self.halfMoveClock += 1;
        if (victim != .nEmptySquare) {
            p_self.c_occupiedBB[@intFromBool(!p_self.whiteToMove())] ^= toBB;
            p_self.occupiedBB ^= toBB;
            p_self.pieceBB[@intFromEnum(victim)] ^= toBB;
            p_self.victim = victim;
            hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(victim)][toSq]);
            p_self.halfMoveClock = 0;
            if (isRookPiece(victim)) {
                p_self.stat = p_self.stat.onRookMove(toBB, !white);
            }
        }

        if (isKingPiece(fromPiece)) {
            if (comptime white) {
                if (fromSq == 4 and toSq == 6) {
                    p_self.pieceArray[toSq + 1] = .nEmptySquare;
                    p_self.pieceArray[toSq - 1] = .nWhiteRook;
                    p_self.pieceBB[@intFromEnum(e_piece.nWhiteRook)] ^= board_statusl.wCastleKRookBit;
                    p_self.c_occupiedBB[@intFromBool(true)] ^= board_statusl.wCastleKRookBit;
                    p_self.occupiedBB ^= board_statusl.wCastleKRookBit;
                    hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(e_piece.nWhiteRook)][@intCast(toSq - 1)]);
                    hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(e_piece.nWhiteRook)][@intCast(toSq + 1)]);
                } else if (fromSq == 4 and toSq == 2) {
                    p_self.pieceArray[toSq - 2] = .nEmptySquare;
                    p_self.pieceArray[toSq + 1] = e_piece.nWhiteRook;
                    p_self.pieceBB[@intFromEnum(e_piece.nWhiteRook)] ^= board_statusl.wCastleQRookBit;
                    p_self.c_occupiedBB[@intFromBool(p_self.whiteToMove())] ^= board_statusl.wCastleQRookBit;
                    p_self.occupiedBB ^= board_statusl.wCastleQRookBit;
                    hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(e_piece.nWhiteRook)][@intCast(toSq + 1)]);
                    hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(e_piece.nWhiteRook)][@intCast(toSq - 2)]);
                }

                p_self.wKingSq = @enumFromInt(toSq);
            } else {
                if (fromSq == 60 and toSq == 62) {
                    p_self.pieceArray[@intFromEnum(e_square.h8)] = .nEmptySquare;
                    p_self.pieceArray[@intFromEnum(e_square.f8)] = .nBlackRook;
                    p_self.pieceBB[@intFromEnum(e_piece.nBlackRook)] ^= board_statusl.bCastleKRookBit;
                    p_self.c_occupiedBB[@intFromBool(false)] ^= board_statusl.bCastleKRookBit;
                    p_self.occupiedBB ^= board_statusl.bCastleKRookBit;
                    hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(e_piece.nBlackRook)][@intCast(toSq - 1)]);
                    hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(e_piece.nBlackRook)][@intCast(toSq + 1)]);
                } else if (fromSq == 60 and toSq == 58) {
                    p_self.pieceArray[@intFromEnum(e_square.a8)] = .nEmptySquare;
                    p_self.pieceArray[@intFromEnum(e_square.d8)] = e_piece.nBlackRook;
                    p_self.pieceBB[@intFromEnum(e_piece.nBlackRook)] ^= board_statusl.bCastleQRookBit;
                    p_self.c_occupiedBB[@intFromBool(false)] ^= board_statusl.bCastleQRookBit;
                    p_self.occupiedBB ^= board_statusl.bCastleQRookBit;
                    hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(e_piece.nBlackRook)][@intCast(toSq + 1)]);
                    hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(e_piece.nBlackRook)][@intCast(toSq - 2)]);
                }
                p_self.bKingSq = @enumFromInt(toSq);
            }
            p_self.stat = p_self.stat.onKingMove();
        } else if (isPawnPiece(fromPiece)) {
            p_self.halfMoveClock = 0;
            if (move.isPromotion()) {
                // can also be or and not xor
                const promPiece = flagPromotionToPiece(move.getFlag(), p_self.whiteToMove());
                p_self.pieceBB[@intFromEnum(promPiece)] ^= toBB;
                p_self.pieceBB[@intFromEnum(fromPiece)] ^= toBB;
                p_self.pieceArray[toSq] = promPiece;
                hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(fromPiece)][toSq]);
                hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(promPiece)][toSq]);
            } else if (move.isDoublePush()) {
                // middle between from and to
                p_self.enPassantIdx = (fromSq + toSq) / 2;
            } else if (move.isEnpassant()) {
                const victimSq: e_square = getSqFromCoord(getSqIdxRank(fromSq), getSqIdxFile(toSq));
                const victimBB = sqToBitboard(victimSq);
                const bisBB = victimBB | toBB;

                p_self.pieceArray[@intFromEnum(victimSq)] = .nEmptySquare;

                p_self.pieceBB[@intFromEnum(victim)] ^= bisBB;

                p_self.c_occupiedBB[@intFromBool(!p_self.whiteToMove())] ^= bisBB;

                p_self.occupiedBB ^= bisBB;
                hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(victim)][@intFromEnum(victimSq)]);
                hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(victim)][toSq]);
            }

            p_self.stat.whiteToMove = !p_self.stat.whiteToMove;
        } else if (isRookPiece(fromPiece)) {
            p_self.stat = p_self.stat.onRookMove(fromBB, white);
        } else {
            p_self.stat.whiteToMove = !p_self.stat.whiteToMove;
        }

        hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(fromPiece)][fromSq]);
        hashl.updateKey(&p_self.key, &hashl.zobristKeys.pieceKeys[@intFromEnum(fromPiece)][toSq]);
        hashl.updateKey(&p_self.key, &hashl.zobristKeys.castlingKeys[p_self.stat.castlingKey()]);
        hashl.updateKey(&p_self.key, &hashl.zobristKeys.enPassantKeys[p_self.enPassantIdx]);

        _ = p_self.move_history.append(move, p_self.key);
        p_self.turn_count += 1;

        if (comptime useDebug) {
            sanityCheckBoardState(p_self);
        }
        if (comptime useStaged) {
            getCheckers_cst(p_self, !white);
        }
    }

    pub inline fn getLastMove(self: Board_state) IMove {
        return self.lastMove;
    }
    pub inline fn isFull(self: Board_state) bool {
        return (self.occupiedBB) == UNIVERSE;
    }
    pub inline fn emptyMask(self: Board_state) u64 {
        return ~self.occupiedBB;
    }
    pub inline fn isEmpty(self: Board_state) bool {
        return (self.occupiedBB == EMPTY);
    }

    pub fn getKingBB(self: Board_state, white: bool) u64 {
        if (white) {
            return self.pieceBB[@intFromEnum(e_piece.nWhiteKing)];
        }
        return self.pieceBB[@intFromEnum(e_piece.nBlackKing)];
    }
    pub inline fn getKingSq(self: Board_state, white: bool) e_square {
        if (white) {
            return self.wKingSq;
        }
        return self.bKingSq;
    }
    pub fn isCastleLegalPreMove(p_self: *Board_state, white: bool, move: IMove, all_attacks: u64) bool {
        const kingBB = p_self.getKingBB(white);
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

    pub fn canKingSideCastle(self: Board_state, comptime white: bool) bool {
        if (comptime white) {
            return self.stat.canKingsideCastle(white) and (canMove(.e1, .h1, self.occupiedBB));
        }
        return (self.stat.canKingsideCastle(white) and (canMove(.e8, .h8, self.occupiedBB)));
    }
    pub fn canQueenSideCastle(self: Board_state, comptime white: bool) bool {
        if (comptime white) {
            return self.stat.canQueensideCastle(true) and (canMove(.e1, .a1, self.occupiedBB));
        }
        return self.stat.canQueensideCastle(false) and (canMove(.e8, .a8, self.occupiedBB));
    }
    pub fn canKingSideCastleAtt(self: Board_state, white: bool, attackedSquares: u64) bool {
        if (white) {
            return self.stat.canKingsideCastle(true) and canMove(.e1, .h1, self.occupiedBB) and ((attackedSquares & inBetween(.e1, .h1)) == EMPTY);
        }
        return self.stat.canKingsideCastle(false) and canMove(.e8, .h8, self.occupiedBB) and ((attackedSquares & inBetween(.e8, .h8)) == EMPTY);
    }
    pub fn canQueenSideCastleAtt(self: Board_state, white: bool, attackedSquares: u64) bool {
        if (white) {
            return self.stat.canQueensideCastle(true) and canMove(.e1, .a1, self.occupiedBB) and ((attackedSquares & inBetween(.e1, .a1)) == EMPTY);
        }
        return self.stat.canQueensideCastle(false) and canMove(.e8, .a8, self.occupiedBB) and ((attackedSquares & inBetween(.e8, .a8)) == EMPTY);
    }

    pub fn getPieceCount(self: Board_state, piece: e_piece) i8 {
        return l_popcount(self.pieceBB[@intFromEnum(piece)]);
    }
    pub fn getSidePieceCount(self: Board_state, color: e_color) i8 {
        return l_popcount(self.c_occupiedBB[@intFromEnum(color)]);
    }

    pub fn isLegal(p_self: *Board_state, white: bool) bool {
        // faster than previous _islegal going from ~100-150k nodes/s to 250-300k nodes per sec
        const king_attacks = getAllAttackMaskFromKing(p_self, white);
        return king_attacks == 0;
    }
    pub fn isInsufficientMaterial(p_self: *Board_state) bool {
        if (l_popcount(p_self.pieceBB[@intFromEnum(e_piece.nWhitePawn)] | p_self.pieceBB[@intFromEnum(e_piece.nBlackPawn)]) != 0) {
            return false;
        }
        if (l_popcount(p_self.pieceBB[@intFromEnum(e_piece.nWhiteQueen)] | p_self.pieceBB[@intFromEnum(e_piece.nBlackQueen)]) != 0) {
            return false;
        }
        if (l_popcount(p_self.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_self.pieceBB[@intFromEnum(e_piece.nBlackRook)]) != 0) {
            return false;
        }
        // TODO add the cases KBB vs K or others
        return true;
    }

    pub fn isLegalFast(p_self: *Board_state, all_attack: u64, move: IMove, p_kingSq: *const squareInfo, p_checks: *const squarel.checkContainer, diagPieceBB: u64, linePieceBB: u64) bool {
        const kingBB = sqToBitboard(p_kingSq.sq);
        const isAttacked: bool = (kingBB & all_attack) != 0;
        const to: e_square = @enumFromInt(move.getTo());
        const from: e_square = @enumFromInt(move.getFrom());
        if (from != p_kingSq.sq) {
            if (p_checks.isDoubleCheck()) {
                return false;
            }
            const pinnedBB = isPiecePinned(p_self.occupiedBB, from, p_kingSq, diagPieceBB, linePieceBB);
            if (pinnedBB != EMPTY) {
                // piece is pinned path
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
            var _to = to;
            if (move.isEnpassant()) {
                _to = getSqFromCoord(getSqRank(from), getSqFile(to));
            }

            return ((last_pin == p_checks.squares[0].getBB()) or (p_checks.squares[0].sq == _to));
        }
        const toKing = squareInfo.init(to);
        const pinInfo = (isPiecePinned(p_self.occupiedBB, from, &toKing, diagPieceBB, linePieceBB));
        // either no pinning piece is found or the pinned piece can be captured
        const isNotPinned = (pinInfo == EMPTY) or ((pinInfo ^ toKing.getBB()) == EMPTY);
        const isToSecure = ((all_attack & toKing.getBB()) == 0);
        return (isNotPinned and isToSecure);
    }

    pub fn isFiftyMoveRepetition(self: *Board_state) bool {
        return self.halfMoveClock >= 50;
    }
    pub fn isStaleThreeFold(self: *Board_state) bool {
        return self.move_history.checkRepetitions();
    }
    pub fn isStaleMateRepetition(p_self: *Board_state) bool {
        return p_self.isFiftyMoveRepetition() or p_self.isStaleThreeFold();
    }

    pub fn setSeed(p_self: *Board_state, seed: u64) void {
        p_self.rngIntGenerator.seed(seed);
        p_self.randInt = p_self.rngIntGenerator.random();
    }
};

pub fn pieceArrayToBB(pieceArray: [N_SQUARES]e_piece) u64 {
    var ret: u64 = EMPTY;
    for (0..N_SQUARES) |i| {
        const piece_E = pieceArray[i];
        const _bb = ONE << @intCast(i);
        if (piece_E != .nEmptySquare) {
            ret |= _bb;
        }
    }
    return ret;
}
pub fn sanityCheckBoardState(p_board_state: *Board_state) void {
    var panic: bool = false;
    // white checks
    const n_white_p = p_board_state.getPieceCount(e_piece.nWhitePawn) + p_board_state.getPieceCount(e_piece.nWhiteBishop) + p_board_state.getPieceCount(e_piece.nWhiteKnight) + p_board_state.getPieceCount(e_piece.nWhiteRook) + p_board_state.getPieceCount(e_piece.nWhiteQueen) + p_board_state.getPieceCount(e_piece.nWhiteKing);
    const n_white_g = p_board_state.getSidePieceCount(e_color.WHITE);
    const white_king = p_board_state.getKingBB(true);
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

    const black_king = p_board_state.getKingBB(false);

    if (n_black_g != n_black_p) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Number of black pieces inconsistent from occupiedBB({d}) to pieceBB({d})\n", .{ n_black_g, n_black_p });
        panic = true;
    }
    if (black_king == 0) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Alert the black king is missing!!\n", .{});
        panic = true;
    }

    const _bbfromPieceArr = pieceArrayToBB(p_board_state.pieceArray);
    const empty_count = l_popcount(~_bbfromPieceArr);
    const piece_count = l_popcount(_bbfromPieceArr);

    if (piece_count != (n_white_g + n_black_g)) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Number of pieces in pieceArray not consistent with population counts. Expected {d} got {d}\n", .{ n_white_g + n_black_g, piece_count });
        std.debug.print("PieceArray: {any}\n", .{p_board_state.pieceArray});
        for (0..8) |i| {
            for (0..8) |j| {
                std.debug.print("{}, ", .{p_board_state.pieceArray[(7 - i) * ROW_SIZE + j]});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("Occupied: \n", .{});
        print_bitboard(p_board_state.occupiedBB);
        panic = true;
    }
    if ((_bbfromPieceArr ^ p_board_state.occupiedBB) != EMPTY) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: pieces are present in the pieceArray that are not in the occupied BB\n", .{});
        std.debug.print("PieceArray BB: \n", .{});
        print_bitboard(_bbfromPieceArr);

        std.debug.print("Occupied: \n", .{});
        print_bitboard(p_board_state.occupiedBB);
        panic = true;
    }
    const empty_count_g = l_popcount(~p_board_state.occupiedBB);
    if (empty_count != (empty_count_g)) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Number of empty spaces in pieceArray not consistent with population counts. Expected {d} got {d}. OccupiedBB: \n", .{ empty_count_g, empty_count });
        print_bitboard(p_board_state.occupiedBB);
        panic = true;
    }

    if (panic) {
        print_board(p_board_state);
        const move = p_board_state.getLastMove();
        std.debug.print("[PANIC] sanityCheckBoardState: last move performed: {s}-{}-{}-{} turn: {}\n", .{ move.getStr(), move.getFlag(), move.getFromPiece(), move.getCapturePiece(), p_board_state.whiteToMove() });
        //p_board_state.move_history.print();

        @panic("Sanity check(s) failed");
    }
}

pub fn print_boardstate(p_board_state: *Board_state) void {
    if (p_board_state.whiteToMove()) {
        std.debug.print("Current turn: White\n", .{});
    } else {
        std.debug.print("Current turn: Black\n", .{});
    }

    print_board(p_board_state);
    std.debug.print("Castling right: {d}\n", .{p_board_state.stat.castlingKey()});
    std.debug.print("En passant idx: {d}\n", .{p_board_state.enPassantIdx});
    std.debug.print("Zobrist key: {x}\n", .{p_board_state.key.code});
    const fen = p_board_state.get_fen();
    std.debug.print("Fen code: {s}\n", .{fen});
    std.debug.print("Turn number: {d}, move stored: {d}\n", .{ p_board_state.turn_count, p_board_state.move_history.len });
    std.debug.print("Current evaluation: {d} \n", .{heuristicl.simpleHeuristic(p_board_state)});

    printBoardValidity(p_board_state);

    if (p_board_state.turn_count > 0) {
        std.debug.print("Previous move: ", .{});
        p_board_state.lastMove.print();
        std.debug.print("\n", .{});
    }

    std.debug.print("Repetition status: Half clock counter: {d}, repetitions counter: {d}, irreversible move index: {d}\n", .{ p_board_state.halfMoveClock, p_board_state.move_history.getRepetitions(), p_board_state.move_history.lastIrreversibleMoveIndex });
    std.debug.print("Repetition stalemate status: {}\n", .{p_board_state.isStaleMateRepetition()});

    //std.debug.print("All moves: \n", .{});
    //const _moves = moveGenl.generatePseudolegalMoves(p_board_state);
    //_moves.print();
    //std.debug.print("Available moves: \n", .{});
    const moves = moveGenl.generateLegalMoves(p_board_state);
    moves.print();
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

pub fn l_getMsbIdx(x: u64) u8 {
    var count: u8 = 0;
    var _x = x;
    while (_x != EMPTY) {
        _x >>= 1;
        count += 1;
    }
    return count;
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

pub fn getAttackPositiveRay(occupied: u64, dir: e_direction, square: e_square) u64 {
    const attacks = cachedTables.rayAttacks[@intFromEnum(square)][@intFromEnum(dir)];
    const blocking: u64 = occupied & attacks;
    if (blocking == 0) {
        return attacks;
    }
    const sq: u8 = bitscan(blocking);
    return attacks ^ cachedTables.rayAttacks[sq][@intFromEnum(dir)];
}

pub fn getAttackRay(occupied: u64, comptime dir: e_direction, square: e_square) u64 {
    const attacks = cachedTables.rayAttacks[@intFromEnum(square)][@intFromEnum(dir)];
    const blocking: u64 = occupied & attacks;
    if (blocking == 0) {
        return attacks;
    }
    var sq: u8 = undefined;
    switch (dir) {
        e_direction.NORTH, e_direction.NORTHEAST, e_direction.NORTHWEST, e_direction.EAST => {
            sq = bitscan(blocking);
        },

        e_direction.SOUTH, e_direction.SOUTHEAST, e_direction.SOUTHWEST, e_direction.WEST => {
            sq = r_bitscan(blocking);
        },
    }

    return attacks ^ cachedTables.rayAttacks[sq][@intFromEnum(dir)];
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

pub fn getPawnAttacks(sq: e_square, comptime white: bool) u64 {
    const sqBB = sqToBitboard(sq);
    if (comptime white) {
        return ((sqBB << 7) & notHFile) | ((sqBB << 9) & notAFile);
    } else {
        return ((sqBB >> 7) & notAFile) | ((sqBB >> 9) & notHFile);
    }
}

pub fn getKingAttacks(sq: e_square) u64 {
    return tablel.cachedKingTable.KingAttack[@intFromEnum(sq)];
}

pub fn xrayRookAttacks(occ: u64, blockers: u64, rookSq: e_square) u64 {
    const attacks = getRookAttacks(occ, rookSq);
    const _blockers = (blockers & attacks) ^ occ;
    return attacks ^ getRookAttacks(_blockers, rookSq);
}

pub fn xrayBishopAttacks(occ: u64, blockers: u64, bishopSq: e_square) u64 {
    const attacks = getBishopAttacks(occ, bishopSq);
    const _blockers = (blockers & attacks) ^ occ;
    return attacks ^ getBishopAttacks(_blockers, bishopSq);
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
    const _sq: i8 = @intCast(@intFromEnum(sq));
    return (_sq & 7) - (_sq >> 3);
}

pub inline fn getSqAntiDiag(sq: e_square) i8 {
    const _sq: i8 = @intCast(@intFromEnum(sq));
    return 7 - (_sq & 7) - (_sq >> 3);
}

pub fn fillFile(mask: u64) u64 {
    return moveGenl.northOne(moveGenl.northOccl(mask, UNIVERSE)) | moveGenl.southOne(moveGenl.southOccl(mask, UNIVERSE)) | mask;
}
pub fn isolatedPawns(pawn: u64) u64 {
    // isolated pawn: pawn without a neighboring pawn
    // fill the ranks from top to bottom with a fill algo
    // then ~(shift left | shift right) & pawn
    // careful of clipping
    //const cols = moveGenl.northOne(moveGenl.northOccl(pawn, UNIVERSE)) | moveGenl.southOne(moveGenl.southOccl(pawn, UNIVERSE)) | pawn;
    const cols = fillFile(pawn);
    const lmask = (cols << 1) & notHFile;
    const rmask = (cols >> 1) & notAFile;
    return ~(lmask | rmask) & pawn;
}
pub fn stackedPawns(pawn: u64) u64 {
    // stacked pawns: multiple pawns present on the same file
    //

    const upPawns = pawn & (moveGenl.northOne(moveGenl.northOccl(pawn, UNIVERSE)));
    const downPawns = pawn & (moveGenl.southOne(moveGenl.southOccl(pawn, UNIVERSE)));
    const tripleFiles = (upPawns & downPawns);
    return upPawns | downPawns | tripleFiles;
}

pub fn getAllAttackingSquares(sq: e_square) u64 {
    const sqBB = sqToBitboard(sq);
    const file = getSqFile(sq);
    const rank = getSqRank(sq);

    return knightAttacks(sqBB) | fileMaskFromFileN(file) | rankMaskFromRankN(rank) | diagonalMask(@intFromEnum(sq)) | antiDiagMask(@intFromEnum(sq));
}

pub fn _AllAttackPawnMask(bb_piece: u64, white: bool) u64 {
    if (white) {
        return _AllAttackPawnMask_cst(bb_piece, true);
    }
    return _AllAttackPawnMask_cst(bb_piece, false);
}

pub fn _AllAttackPawnMask_cst(bb_piece: u64, comptime white: bool) u64 {
    var ret: u64 = EMPTY;
    if (comptime white) {
        ret |= (bb_piece << 7) & notHFile;
        ret |= (bb_piece << 9) & notAFile;
        return ret;
    } else {
        ret |= (bb_piece >> 7) & notAFile;
        ret |= (bb_piece >> 9) & notHFile;
        return ret;
    }
}

pub inline fn _AllAttackKnightMask(bb_piece: u64) u64 {
    return knightAttacks(bb_piece);
}

pub fn _AllAttackBishopMask(bb_piece: u64, occ_bb: u64) u64 {
    var ret: u64 = EMPTY;
    var sq_e: e_square = e_square.a1;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        const sq = bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;

        sq_e = @enumFromInt(sq);
        ret |= getBishopAttacks(occ_bb, sq_e);
    }
    return ret;
}

pub fn _AllAttackRookMask(bb_piece: u64, occ_bb: u64) u64 {
    var ret: u64 = EMPTY;
    var sq_e: e_square = e_square.a1;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        const sq = bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;

        sq_e = @enumFromInt(sq);
        ret |= getRookAttacks(occ_bb, sq_e);
    }
    return ret;
}

pub fn _AllAttackQueenMask(bb_piece: u64, occ_bb: u64) u64 {
    var ret: u64 = EMPTY;
    var sq_e: e_square = e_square.a1;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        const sq = bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        sq_e = @enumFromInt(sq);

        ret |= getRookAttacks(occ_bb, sq_e);
        ret |= getBishopAttacks(occ_bb, sq_e);
    }
    return ret;
}

pub fn _AllAttackKingMask(bb_piece: u64) u64 {
    var ret: u64 = EMPTY;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        const sq = bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        ret |= getKingAttacks(@enumFromInt(sq));
    }
    return ret;
}

pub fn getAllAttackMaskXrayKing(p_board: *Board_state, white: bool) u64 {
    var ret: u64 = EMPTY;
    var color_offset: u8 = 0;

    if (!white) {
        color_offset = 6;
        ret |= _AllAttackPawnMask_cst(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhitePawn)], false);
    } else {
        ret |= _AllAttackPawnMask_cst(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhitePawn)], true);
    }
    const kingBB = p_board.getKingBB(white);
    p_board.occupiedBB ^= kingBB;
    ret |= _AllAttackKnightMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKnight)]);
    ret |= _AllAttackBishopMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteBishop)], p_board.occupiedBB);
    ret |= _AllAttackRookMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteRook)], p_board.occupiedBB);
    ret |= _AllAttackQueenMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteQueen)], p_board.occupiedBB);
    ret |= _AllAttackKingMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKing)]);
    p_board.occupiedBB ^= kingBB;

    return ret;
}
pub fn getAllAttackMask(p_board: *Board_state, occBB: u64, white: bool) u64 {
    var ret: u64 = EMPTY;
    var color_offset: u8 = 0;
    if (white) {
        ret |= _AllAttackPawnMask_cst(p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)], true);
    } else {
        color_offset = 6;
        ret |= _AllAttackPawnMask_cst(p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)], false);
    }
    ret |= _AllAttackKnightMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKnight)]);
    ret |= _AllAttackBishopMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteBishop)], occBB);
    ret |= _AllAttackRookMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteRook)], occBB);
    ret |= _AllAttackQueenMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteQueen)], occBB);
    ret |= _AllAttackKingMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKing)]);

    return ret;
}

pub fn getAllAttackMaskFromKing(p_board: *Board_state, white: bool) u64 {
    if (white) {
        return cst_getAllAttackMaskFromKing(p_board, true);
    } else {
        return cst_getAllAttackMaskFromKing(p_board, false);
    }
}
pub fn cst_getAllAttackMaskFromKing(p_board: *Board_state, comptime white: bool) u64 {
    var ret: u64 = EMPTY;

    if (comptime white) {
        const kingbb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteKing)];
        ret |= _AllAttackKnightMask(kingbb) & p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)];
        ret |= _AllAttackBishopMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
        ret |= _AllAttackRookMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
        ret |= _AllAttackPawnMask(kingbb, white) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)]);

        ret |= _AllAttackKingMask(kingbb) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackKing)]);
    } else {
        const kingbb = p_board.pieceBB[@intFromEnum(e_piece.nBlackKing)];
        ret |= _AllAttackKnightMask(kingbb) & p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)];
        ret |= _AllAttackBishopMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
        ret |= _AllAttackRookMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);

        ret |= _AllAttackPawnMask(kingbb, white) & (p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)]);
        ret |= _AllAttackKingMask(kingbb) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteKing)]);
    }
    return ret;
}
pub fn getCheckers(p_board: *Board_state, white: bool) void {
    // this method is responsible for ~30-40% of the compute cost of perft
    // plan when loading a fen do a "full" get checkers
    // when making a move: do a "partial" get checkers using the previous state
    if (white) {
        getCheckers_cst(p_board, true);
    } else {
        getCheckers_cst(p_board, false);
    }
    return;
}
//pub fn getPartialCheckers(p_board: *Board_state, whiteMoved: bool, lastMove: IMove) void {
//    // this method assumes that the previous move performed was legal, as the moveGen should not let it go through
//    // thus the current player who made the move should not be in check
//    const to: u8 = lastMove.getTo();
//    const toPiece: e_piece = p_board.
//    if (whiteMoved) {
//        p_board.wCheckersBB = EMPTY;
//    } else {
//        p_board.bCheckersBB = EMPTY;
//    }
//
//    return;
//}

pub fn getCheckers_cst(p_board: *Board_state, comptime white: bool) void {
    var rq: u64 = undefined;
    var bq: u64 = undefined;
    var n: u64 = undefined;
    var p: u64 = undefined;
    var king_E: e_square = undefined;
    if (comptime white) {
        rq = p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)];
        bq = p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)];
        n = p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)];
        p = p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)];
        king_E = p_board.wKingSq;
    } else {
        rq = p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
        bq = p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
        n = p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)];
        p = p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)];
        king_E = p_board.bKingSq;
    }

    const cachedBishAtt = getBishopAttacks(p_board.occupiedBB, king_E);
    const cachedRookAtt = getRookAttacks(p_board.occupiedBB, king_E);
    var directChecks = (cachedBishAtt & bq) | (cachedRookAtt & rq);
    var _check = directChecks;
    while (_check != EMPTY) {
        const checksq = bitscan(_check);
        _check &= _check - 1;
        directChecks |= inBetween(@enumFromInt(checksq), king_E);
    }
    directChecks |= getPawnAttacks(king_E, white) & p;
    directChecks |= knightAttacks(sqToBitboard(king_E)) & n;

    if (comptime useAVX2) {
        p_board.pinnedBB = moveGenl.getPinned_avx2(p_board, white);
    } else {
        var pinned: u64 = 0;
        const rBlockers = (p_board.c_occupiedBB[@intFromBool(white)] & cachedRookAtt) ^ p_board.occupiedBB;
        var pinner = (cachedRookAtt ^ getRookAttacks(rBlockers, king_E)) & rq;
        while (pinner != EMPTY) {
            const pinsq = bitscan(pinner);
            pinner &= pinner - 1;
            pinned |= inBetween(@enumFromInt(pinsq), king_E);
        }

        const bBlockers = (p_board.c_occupiedBB[@intFromBool(white)] & cachedBishAtt) ^ p_board.occupiedBB;
        pinner = (cachedBishAtt ^ getBishopAttacks(bBlockers, king_E)) & bq;
        while (pinner != EMPTY) {
            const pinsq = bitscan(pinner);
            pinner &= pinner - 1;
            pinned |= inBetween(@enumFromInt(pinsq), king_E);
        }
        p_board.pinnedBB = pinned;
    }

    p_board.checkersBB = directChecks;
    return;
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
    return EMPTY;
}

pub fn fillMoveFromState(p_state: *Board_state, move: *IMove) void {
    const fromIdx: u8 = move.getFrom();
    const toIdx: u8 = move.getTo();
    var c_piece = p_state.get_piece(toIdx);
    const f_piece = p_state.get_piece(fromIdx);
    var flag: u8 = move.getFlag();
    if (c_piece != .nEmptySquare) {
        flag |= @intFromEnum(e_moveFlags.CAPTURE);
    }
    if (isKingPiece(f_piece)) {
        var diff: i8 = @intCast(fromIdx);
        diff -= @intCast(toIdx);
        if (utils.absolute(diff) == 2) {
            if (fromIdx > toIdx) {
                flag |= @intFromEnum(e_moveFlags.QUEENCASTLE);
            } else {
                flag |= @intFromEnum(e_moveFlags.KINGCASTLE);
            }
        }
    } else if (isPawnPiece(f_piece)) {
        var diff: i8 = @intCast(fromIdx);
        diff -= @intCast(toIdx);
        if (utils.absolute(diff) == 16) {
            flag |= @intFromEnum(e_moveFlags.DOUBLEPAWN);
        }
        if ((getSqIdxFile(fromIdx) != getSqIdxFile(toIdx)) and (c_piece == .nEmptySquare)) {
            flag |= @intFromEnum(e_moveFlags.ENPASSANT);
            if (p_state.whiteToMove()) {
                c_piece = .nBlackPawn;
            } else {
                c_piece = .nWhitePawn;
            }
        }
    }
    move.setFlag(flag);
    move.setFromPiece(f_piece);
    move.setCapture(c_piece);
}

pub fn inferFlagFromMovement(p_state: *Board_state, from: e_square, to: e_square, line_buffer: []const u8) u8 {
    const fromIdx: u8 = @intFromEnum(from);
    const toIdx: u8 = @intFromEnum(to);

    var ret_flag: u8 = @intFromEnum(e_moveFlags.QUIETMOVE);
    var diff: i8 = 0;
    const c_piece = p_state.get_piece(@intFromEnum(to));
    if (c_piece != .nEmptySquare) {
        ret_flag |= @intFromEnum(e_moveFlags.CAPTURE);
    }

    if (line_buffer.len > 4) {
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
    }
    const pieceMove = p_state.get_piece(@intFromEnum(from));
    if (isKingPiece(pieceMove)) {
        diff = @intCast(fromIdx);
        diff -= @intCast(toIdx);
        if (utils.absolute(diff) == 2) {
            if (fromIdx > toIdx) {
                ret_flag = @intFromEnum(e_moveFlags.QUEENCASTLE);
            } else {
                ret_flag = @intFromEnum(e_moveFlags.KINGCASTLE);
            }
        }
    } else if (isPawnPiece(pieceMove)) {
        diff = @intCast(fromIdx);
        diff -= @intCast(toIdx);
        if (utils.absolute(diff) == 16) {
            ret_flag |= @intFromEnum(e_moveFlags.DOUBLEPAWN);
        }
        if ((getSqIdxFile(fromIdx) != getSqIdxFile(toIdx)) and (c_piece == .nEmptySquare)) {
            ret_flag |= @intFromEnum(e_moveFlags.ENPASSANT);
        }
    }
    return ret_flag;
}

pub fn _pin_scenario() void {
    std.debug.print("[DEBUG] pin scenario: \n", .{});
    const fen = "k1p4R/1q2q1rq/8/Q2PPP2/q2PKP1q/3PPP2/4q1q1/1q6 b - - 0 0";

    var board = getBoardFromFen(get_global_alloc(), fen) catch {};
    print_boardstate(&board);
    getCheckers(&board, true);
    std.debug.print("[DEBUG] _pin_scenario: W checkers\n", .{});
    print_bitboard(board.checkersBB);
    std.debug.print("[DEBUG] _pin_scenario: W pinned \n", .{});
    print_bitboard(board.pinnedBB);

    getCheckers(&board, false);
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

    utils.askContinue();

    return;
}

pub fn test_scenarios() void {
    _pin_scenario();
    return;
}
pub fn test_avx() !void {
    const fen = "k1p4R/1q2q1rq/8/Q2PPP2/q2RKP1q/3PPP2/4q1q1/1q6 w - - 0 0";
    //const fen = DEFAULT_FEN;
    var state = try getBoardFromFen(get_global_alloc(), fen);
    const bb = moveGenl.avx2DumbFill(&state, true).collapse();
    const _bb = moveGenl.avx2DumbFill(&state, false).collapse();
    print_board(&state);
    print_bitboard(bb);
    print_bitboard(_bb);

    const _pinners = moveGenl.getPinned_avx2(&state, false);
    print_bitboard(_pinners);

    const pinners = moveGenl.getPinned_avx2(&state, true);
    print_bitboard(pinners);

    getCheckers(&state, true);
    print_bitboard(state.pinnedBB);
    print_boardstate(&state);
}
pub fn test_isolated() !void {
    std.debug.print("[DEBUG] test_isolated: starting\n", .{});
    const initBB: u64 = 0xFF00;
    print_bitboard(initBB);
    print_bitboard(isolatedPawns(initBB));

    const _initBB: u64 = 0xF500;
    print_bitboard(_initBB);
    print_bitboard(isolatedPawns(_initBB));

    const overKill: u64 = 0x44004400D500;
    print_bitboard(overKill);
    print_bitboard(isolatedPawns(overKill));

    return;
}
pub fn test_stackedPawn() !void {
    std.debug.print("[DEBUG] test_stackedPawn: starting\n", .{});
    const initBB: u64 = 0xFF00;
    print_bitboard(initBB);
    print_bitboard(stackedPawns(initBB));

    const overKill: u64 = 0x44004402D700;
    print_bitboard(overKill);
    print_bitboard(stackedPawns(overKill));
}

pub fn main() !void {
    mainl.initAll();
    //try test_avx();
    try test_isolated();

    try test_stackedPawn();
    //test_scenarios();
    return;
}
