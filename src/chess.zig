const std = @import("std");

//https://stackoverflow.com/questions/76384694/how-to-do-conditional-compilation-with-zig
const build_options = @import("build_options");

pub const fastBitscan = build_options.fastBitscan;
const useMagic = build_options.useMagic;
const useStaged = build_options.useStaged;
const useDebug = build_options.useDebug;
const useAVX2 = build_options.useAVX2;

const typel = @import("type.zig");
pub const e_piece = typel.e_piece;

const utils = @import("utils.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const moveGenl = @import("move_generation.zig");
const heuristicl = @import("heuristic.zig");
const intrinsicsl = @import("intrinsics.zig");
const tablel = @import("moveTables.zig");
const magicl = @import("magic.zig");
const hashl = @import("hashTable.zig");
const boardl = @import("board.zig");
const board_statusl = @import("board_status.zig");
const stringl = @import("string.zig");
const schedulerl = @import("search/scheduler.zig");

const IMove = movel.IMove;
const e_moveFlags = movel.e_moveFlags;
const matchMoveContainer = movel.matchMoveContainer;
const status = board_statusl.status;

const e_square = squarel.e_square;
const squareInfo = squarel.squareInfo;
pub const Board_state = boardl.boardState;

pub const NUMBER_PLAYER: u8 = 2;
pub const ROW_SIZE: u8 = 8;
pub const N_SQUARES: u8 = 64;
pub const MAX_POSSIBLE_MOVE: u8 = 218;
pub const N_PIECES = 12;
pub const N_PIECES_TYPES = 6;
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

pub fn stringToLERF(sq: *const [2]u8) e_square {
    if ((sq[0] < 'a') or (sq[0] > 'h')) {
        return .invalid;
    }
    if ((sq[1] < '1') or (sq[1] > '9')) {
        return .invalid;
    }
    return @enumFromInt((sq[0] - 'a') + ((sq[1] - '1') << 3));
}
pub fn flagPromotionToPiece(flag: u8, white: bool) e_piece {
    const color_offset = getColorPieceOffset(white);
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
pub fn letterPromoToFlag(letter: u8) e_moveFlags {
    if (letter == 'b' or letter == 'B') {
        return .BISHOPPROMO;
    }
    if (letter == 'n' or letter == 'N') {
        return .KNIGHTPROMO;
    }
    if (letter == 'r' or letter == 'R') {
        return .ROOKPROMO;
    }
    if (letter == 'q' or letter == 'Q') {
        return .QUEENPROMO;
    }
    return .QUIETMOVE;
}

pub inline fn sqToBitboard(sq: e_square) u64 {
    return ONE << @intCast(@intFromEnum(sq));
}

pub inline fn xToBitboard(x: u8) u64 {
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

pub inline fn ipopcount(x: u64) i8 {
    return @intCast(popcount(x));
}

pub inline fn popcount(bb: u64) u8 {
    return @as(u8, @popCount(bb));
}
pub inline fn bitscan(bb: u64) u8 {
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

pub inline fn r_bitscan(bb: u64) u8 {
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
pub fn print_board(p_board: *const Board_state) void {
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

pub fn printBoardValidity(p_state: *const Board_state) void {
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

pub fn getBoardFromFen_pieces(fen: []const u8) debug_err!Board_state {
    var ret = Board_state.init();
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
pub fn getBoardFromFen_turn(p_state: *Board_state, turnToken: []const u8) debug_err!bool {
    if (turnToken.len != 1) {
        return debug_err.fenErr;
    }
    const turnLetter = utils.lowerLetter(turnToken[0]);
    if (turnLetter == 'w') {
        p_state.frame.stat.setTurn(true);
    } else if (turnLetter == 'b') {
        p_state.frame.stat.setTurn(false);
    } else {
        std.debug.print("[PANIC] getBoardFromFen_turn: turn letter found: letter: {c} token: {s}\n", .{ turnLetter, turnToken });
        @panic("Unknown turn found");
    }
    return true;
}

pub fn getBoardFromFen_castle(p_state: *Board_state, turnToken: []const u8) bool {
    std.debug.assert(turnToken.len != 0);
    if (turnToken[0] == '-') {
        p_state.frame.stat = .init(p_state.whiteToMove(), false, false, false, false);
    } else {
        for (0..turnToken.len) |i| {
            const letter = turnToken[i];
            if (letter == 'K' or letter == 'H') {
                p_state.frame.stat.setWCastlingK(true);
            } else if (letter == 'Q' or letter == 'A') {
                p_state.frame.stat.setWCastlingQ(true);
            } else if (letter == 'k' or letter == 'h') {
                p_state.frame.stat.setBCastlingK(true);
            } else if (letter == 'q' or letter == 'a') {
                p_state.frame.stat.setBCastlingQ(true);
            }
        }
    }
    return true;
}
pub fn getBoardFromFen_enPassant(p_state: *Board_state, turnToken: []const u8) bool {
    std.debug.assert(turnToken.len != 0);
    if (turnToken[0] == '-') {
        p_state.frame.enPassantIdx = 0;
    } else {
        std.debug.assert(turnToken.len == 2);
        const sq = stringToLERF(turnToken[0..2]);
        p_state.frame.enPassantIdx = @intFromEnum(sq);
    }
    return true;
}
pub fn getBoardFromFen_clockMove(turnToken: []const u8) u16 {
    std.debug.assert(turnToken.len != 0);
    const nbr = std.fmt.parseInt(u16, turnToken, 10) catch {
        return 0;
    };
    return nbr;
}
pub fn getBoardFromFen(fen: []const u8) debug_err!Board_state {
    const nTokens = utils.str_countLetter(fen, ' ');
    if (nTokens < 5) {
        return debug_err.fenErr;
    }
    var gen = utils.splitGenerator(u8).init(fen, ' ');
    var board = try getBoardFromFen_pieces(gen.next().?);
    _ = try getBoardFromFen_turn(&board, gen.next().?);
    _ = getBoardFromFen_castle(&board, gen.next().?);
    _ = getBoardFromFen_enPassant(&board, gen.next().?);
    board.frame.halfMoveClock = @intCast(getBoardFromFen_clockMove(gen.next().?));
    board.b.turnCount = @intCast(getBoardFromFen_clockMove(gen.next().?));
    if (comptime useStaged) {
        onMoveStaged(&board, board.whiteToMove());
    }
    return board;
}

pub fn getBoardFromUciFen(uciStr: []const u8, debug: bool) !Board_state {
    var ret = getBoardFromFen(uciStr) catch {
        std.debug.print("[PANIC] getboardFromUciFen: error while parsing {s}\n", .{uciStr});
        @panic("");
    };
    try applyUciMoves(&ret, uciStr, debug);
    return ret;
}
pub fn applyUciMoves(p_board: *Board_state, uciStr: []const u8, debug: bool) !void {
    const moves = getEmptyMoveListFromStr(uciStr);
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
    if (comptime useStaged) {
        onMoveStaged(p_board, p_board.whiteToMove());
    }
}
pub fn getEmptyMoveListFromStr(strBuffer: []const u8) movel.matchMoveContainer {
    var gen = utils.splitGenerator(u8).init(strBuffer, ' ');
    var ret: movel.matchMoveContainer = .{};

    while (gen.next()) |cmd| {
        if (cmd.len != 4 and cmd.len != 5) {
            continue;
        }
        const from = stringToLERF(cmd[0..2]);
        const to = stringToLERF(cmd[2..4]);
        if (from == .invalid or to == .invalid) {
            continue;
        }
        var flag: u8 = 0;
        if (cmd.len > 4 and cmd[4] != 0) {
            flag |= @intFromEnum(letterPromoToFlag(cmd[4]));
        }
        const move = movel.build_move(@intFromEnum(from), @intFromEnum(to), flag);
        _ = ret.append(move, .{ .code = EMPTY }, false);
    }
    return ret;
}
pub fn getFirstMoveFromStr(p_state: *Board_state, strBuffer: []const u8) IMove {
    // /!\ this assumes that the p_state is updated for the corresponding move to "decode", not suitable for a position startpos parsing
    var gen = utils.splitGenerator(u8).init(strBuffer, ' ');

    while (gen.next()) |cmd| {
        if (cmd.len != 4 and cmd.len != 5) {
            continue;
        }
        const from = stringToLERF(cmd[0..2]);
        const to = stringToLERF(cmd[2..4]);
        if (from == .invalid or to == .invalid) {
            continue;
        }
        var move = movel.build_move(@intFromEnum(from), @intFromEnum(to), 0);
        if (cmd.len > 4 and cmd[4] != 0) {
            move.setFlag(@intFromEnum(letterPromoToFlag(cmd[4])));
        }
        fillMoveFromState(p_state, &move);
        return move;
    }
    return .{};
}

pub inline fn isPawnPiece(piece: e_piece) bool {
    return (piece == .nWhitePawn or piece == .nBlackPawn);
}
pub inline fn pawnFromColor(white: bool) e_piece {
    if (white) {
        return .nWhitePawn;
    }
    return .nBlackPawn;
}

pub inline fn isRookPiece(piece: e_piece) bool {
    return (piece == .nWhiteRook or piece == .nBlackRook);
}

pub inline fn isKingPiece(piece: e_piece) bool {
    return (piece == .nWhiteKing or piece == .nBlackKing);
}

pub inline fn canMove(from: e_square, to: e_square, occ: u64) bool {
    return (inBetween(from, to) & occ) == 0;
}

pub inline fn inBetween(from: e_square, to: e_square) u64 {
    return tablel.arrRectangular[@intFromEnum(from)][@intFromEnum(to)];
}
pub inline fn safetyArea(sq: e_square) u64 {
    return tablel.safetyArea[@intFromEnum(sq)];
}

pub inline fn getColorPieceOffset(white: bool) u8 {
    if (white) {
        return 0;
    }
    return N_PIECES_TYPES;
}
pub inline fn getColorFromPiece(piece: e_piece) bool {
    return @intFromEnum(piece) < N_PIECES_TYPES;
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

pub fn updateKeyOnMove(comptime white: bool, move: IMove, promotion: bool, castle: bool, comptime capture: bool, fromPiece: e_piece, info: *const boardl.boardFrame) hashl.Key {
    var key = info.key;
    const to = move.getTo();
    const from = move.getFrom();
    var _fromPiece = fromPiece;

    // make the piece at the dest appear
    hashl.updateKey(&key, hashl.zobristKeys.pieceKeys[@intFromEnum(_fromPiece)][to]);
    if (promotion) {
        _fromPiece = if (comptime white) .nWhitePawn else .nBlackPawn;
    }
    // removed the starting piece
    hashl.updateKey(&key, hashl.zobristKeys.pieceKeys[@intFromEnum(_fromPiece)][from]);
    if (comptime capture) {
        // take care of the victim
        if (move.isEnpassant()) {
            const victimSq: e_square = getSqFromCoord(getSqIdxRank(from), getSqIdxFile(to));
            const p: e_piece = if (comptime white) .nBlackPawn else .nWhitePawn;
            hashl.updateKey(&key, hashl.zobristKeys.pieceKeys[@intFromEnum(p)][@intFromEnum(victimSq)]);
        } else {
            hashl.updateKey(&key, hashl.zobristKeys.pieceKeys[@intFromEnum(info.victim)][to]);
        }
    } else {
        // check castling
        if (castle) {
            const r: e_piece = if (comptime white) .nWhiteRook else .nBlackRook;
            if (move.isQueenSideCastle()) {
                hashl.updateKey(&key, hashl.zobristKeys.pieceKeys[@intFromEnum(r)][to - 2]);
                hashl.updateKey(&key, hashl.zobristKeys.pieceKeys[@intFromEnum(r)][to + 1]);
            } else {
                hashl.updateKey(&key, hashl.zobristKeys.pieceKeys[@intFromEnum(r)][to + 1]);
                hashl.updateKey(&key, hashl.zobristKeys.pieceKeys[@intFromEnum(r)][to - 1]);
            }
        }
    }

    hashl.updateKey(&key, hashl.zobristKeys.castlingKeys[info.stat.castlingKey()]);
    hashl.updateKey(&key, hashl.zobristKeys.enPassantKeys[info.enPassantIdx]);
    hashl.updateKey(&key, hashl.zobristKeys.playKey);
    return key;
}

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
pub fn sanityCheckBoardState(p_board_state: *const Board_state) void {
    var panic: bool = false;

    // white checks
    const n_white_p = p_board_state.getPieceCount(e_piece.nWhitePawn) + p_board_state.getPieceCount(e_piece.nWhiteBishop) + p_board_state.getPieceCount(e_piece.nWhiteKnight) + p_board_state.getPieceCount(e_piece.nWhiteRook) + p_board_state.getPieceCount(e_piece.nWhiteQueen) + p_board_state.getPieceCount(e_piece.nWhiteKing);
    const n_white_g = p_board_state.getSidePieceCount(.WHITE);
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
    const n_black_g = p_board_state.getSidePieceCount(.BLACK);

    const black_king = p_board_state.getKingBB(false);

    if (n_black_g != n_black_p) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Number of black pieces inconsistent from occupiedBB({d}) to pieceBB({d})\n", .{ n_black_g, n_black_p });
        panic = true;
    }
    if (black_king == 0) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Alert the black king is missing!!\n", .{});
        panic = true;
    }

    const _bbfromPieceArr = pieceArrayToBB(p_board_state.b.pieceArray);
    const empty_count = popcount(~_bbfromPieceArr);
    const piece_count = popcount(_bbfromPieceArr);

    if (piece_count != (n_white_g + n_black_g)) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Number of pieces in pieceArray not consistent with population counts. Expected {d} got {d}\n", .{ n_white_g + n_black_g, piece_count });
        std.debug.print("PieceArray: {any}\n", .{p_board_state.b.pieceArray});
        for (0..8) |i| {
            for (0..8) |j| {
                std.debug.print("{}, ", .{p_board_state.b.pieceArray[(7 - i) * ROW_SIZE + j]});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("Occupied: \n", .{});
        print_bitboard(p_board_state.b.occupiedBB());
        panic = true;
    }
    if ((_bbfromPieceArr ^ p_board_state.b.occupiedBB()) != EMPTY) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: pieces are present in the pieceArray that are not in the occupied BB\n", .{});
        std.debug.print("PieceArray BB: \n", .{});
        print_bitboard(_bbfromPieceArr);

        std.debug.print("Occupied: \n", .{});
        print_bitboard(p_board_state.b.occupiedBB());
        panic = true;
    }
    if ((_bbfromPieceArr ^ (p_board_state.b.c_occupiedBB[0] | p_board_state.b.c_occupiedBB[1])) != EMPTY) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: pieces are present in the pieceArray that are not in the c_occupied's BB\n", .{});
        std.debug.print("PieceArray BB: \n", .{});
        print_bitboard(_bbfromPieceArr);

        std.debug.print("Occupied w: \n", .{});
        print_bitboard(p_board_state.b.c_occupiedBB[1]);
        std.debug.print("Occupied b: \n", .{});
        print_bitboard(p_board_state.b.c_occupiedBB[0]);
        panic = true;
    }
    const empty_count_g = popcount(~p_board_state.b.occupiedBB());
    if (empty_count != (empty_count_g)) {
        std.debug.print("[DEBUG] from sanityCheckBoardState: Number of empty spaces in pieceArray not consistent with population counts. Expected {d} got {d}. OccupiedBB: \n", .{ empty_count_g, empty_count });
        print_bitboard(p_board_state.b.occupiedBB());
        panic = true;
    }

    if (panic) {
        print_board(p_board_state);
        const move = p_board_state.getLastMove();
        std.debug.print("[PANIC] sanityCheckBoardState: last move performed: {s}-{} {} {} turn: {}\n", .{ move.getStr(), move.getFlag(), p_board_state.getCapturePiece(move), p_board_state.frame.victim, p_board_state.whiteToMove() });
        std.debug.print("[PANIC] sanityCheckBoardState: history (len {d}):\n", .{p_board_state.moveHistory.len});
        p_board_state.moveHistory.print();

        @panic("Sanity check(s) failed");
    }
}

pub fn print_boardstate(p_board_state: *const Board_state) void {
    if (p_board_state.whiteToMove()) {
        std.debug.print("Current turn: White\n", .{});
    } else {
        std.debug.print("Current turn: Black\n", .{});
    }
    print_board(p_board_state);
    std.debug.print("Zobrist key: 0x{x}\n", .{p_board_state.frame.key.code});
    const fen = p_board_state.get_fen();
    std.debug.print("Fen code: {s}\n", .{fen});
    std.debug.print("Castling right: {d}\n", .{p_board_state.frame.stat.castlingKey()});

    const moves = moveGenl.generateLegalMoves(p_board_state);
    std.debug.print("Turn number: {d}, move stored: {d}, legal moves {d}\n", .{ p_board_state.b.turnCount, p_board_state.moveHistory.len, moves.len });
    printBoardValidity(p_board_state);
    if (p_board_state.b.turnCount > 0) {
        std.debug.print("Previous move: {s}\n", .{p_board_state.frame.lastMove.getStr()});
    }

    std.debug.print("Repetition status: Half clock counter: {d}, repetitions counter: {d}, irreversible move index: {d}\n", .{ p_board_state.frame.halfMoveClock, p_board_state.moveHistory.getRepetitions(), p_board_state.moveHistory.lastIrreversibleMoveIndex });
    std.debug.print("Repetition stalemate status: {}\n", .{p_board_state.isStaleMateRepetition()});

    const eval = heuristicl.evaluate_debug(p_board_state, &heuristicl.globalHeuristic);
    std.debug.print("Current evaluation: phase {d} \n", .{p_board_state.getPhase()});
    eval.print();

    sanityCheckBoardState(p_board_state);
}

pub fn print_bitboard(bitboard: u64) void {
    std.debug.print("Printing bitboard: 0x{x} {d} ({b})\n", .{ bitboard, bitboard, bitboard });
    var _bitboard = bitboard;
    const mask: u64 = UNIVERSE & (~(UNIVERSE >> 8));
    var row: u8 = undefined;
    for (0..8) |_| {
        row = @intCast((_bitboard & mask) >> 56);
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
        return maindia >> @intCast(diag << 3);
    } else {
        return maindia << @intCast((-diag) << 3);
    }
}

pub fn antiDiagMask(sq: i8) u64 {
    const maindia: u64 = (0x0102040810204080);
    const diag: i8 = 7 - (sq & 7) - (sq >> 3);
    if (diag >= 0) {
        return maindia >> @intCast(diag << 3);
    } else {
        return maindia << @intCast((-diag) << 3);
    }
}

pub inline fn fileMaskFromFileN(file: u8) u64 {
    return aFile << @intCast(file);
}
pub inline fn rankMaskFromRankN(rank: u8) u64 {
    return firstRank << @intCast(8 * rank);
}

pub fn getAttackRay(occupied: u64, comptime dir: e_direction, square: e_square) u64 {
    const attacks = tablel.cachedTables.rayAttacks[@intFromEnum(square)][@intFromEnum(dir)];
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

    return attacks ^ tablel.cachedTables.rayAttacks[sq][@intFromEnum(dir)];
}

pub inline fn diagonalAttacks(bb: u64, sq: e_square) u64 {
    return getAttackRay(bb, e_direction.NORTHEAST, sq) | getAttackRay(bb, e_direction.SOUTHWEST, sq);
}

pub inline fn antiDiagAttacks(bb: u64, sq: e_square) u64 {
    return getAttackRay(bb, e_direction.NORTHWEST, sq) | getAttackRay(bb, e_direction.SOUTHEAST, sq);
}

pub inline fn fileAttacks(bb: u64, sq: e_square) u64 {
    return getAttackRay(bb, e_direction.NORTH, sq) | getAttackRay(bb, e_direction.SOUTH, sq);
}

pub inline fn rankAttacks(bb: u64, sq: e_square) u64 {
    return getAttackRay(bb, e_direction.EAST, sq) | getAttackRay(bb, e_direction.WEST, sq);
}
pub inline fn getRookAttacks(occBB: u64, sq: e_square) u64 {
    if (comptime useMagic) {
        return magicl.getRookMoves(sq, occBB);
    } else {
        var ret = fileAttacks(occBB, sq);
        ret |= rankAttacks(occBB, sq);
        return ret;
    }
}
pub inline fn getBishopAttacks(occBB: u64, sq: e_square) u64 {
    if (comptime useMagic) {
        return magicl.getBishopMoves(sq, occBB);
    } else {
        var ret = antiDiagAttacks(occBB, sq);
        ret |= diagonalAttacks(occBB, sq);
        return ret;
    }
}
pub inline fn getQueenAttacks(occBB: u64, sq: e_square) u64 {
    if (comptime useMagic) {
        return magicl.getRookMoves(sq, occBB) | magicl.getBishopMoves(sq, occBB);
    } else {
        var ret = fileAttacks(occBB, sq);
        ret |= rankAttacks(occBB, sq);
        ret |= antiDiagAttacks(occBB, sq);
        ret |= diagonalAttacks(occBB, sq);
        return ret;
    }
}

pub inline fn getPawnAttacks(sq: e_square, comptime white: bool) u64 {
    const sqBB = sqToBitboard(sq);
    return getPawnAttacksFromBB(sqBB, white);
}
pub inline fn getPawnAttacksFromBB(bb: u64, comptime white: bool) u64 {
    if (comptime white) {
        return ((bb << 7) & notHFile) | ((bb << 9) & notAFile);
    } else {
        return ((bb >> 7) & notAFile) | ((bb >> 9) & notHFile);
    }
}

pub inline fn getKingAttacks(sq: e_square) u64 {
    return tablel.cachedKingTable.KingAttack[@intFromEnum(sq)];
}
pub fn getRelevantAttacks(piece: e_piece, sq: e_square, occ: u64) u64 {
    switch (piece) {
        .nWhiteKing, .nBlackKing => {
            return getKingAttacks(sq);
        },
        .nWhiteBishop, .nBlackBishop => {
            return getBishopAttacks(occ, sq);
        },
        .nWhiteRook, .nBlackRook => {
            return getRookAttacks(occ, sq);
        },
        .nWhiteKnight, .nBlackKnight => {
            return knightAttacks(sqToBitboard(sq));
        },
        .nWhitePawn => {
            return getPawnAttacks(sq, true);
        },
        .nBlackPawn => {
            return getPawnAttacks(sq, false);
        },
        .nWhiteQueen, .nBlackQueen => {
            return getQueenAttacks(occ, sq);
        },
        .nWhite, .nBlack, .nEmptySquare => {
            @panic("???");
        },
    }
}

pub inline fn xrayRookAttacks(occ: u64, blockers: u64, rookSq: e_square) u64 {
    const attacks = getRookAttacks(occ, rookSq);
    const _blockers = (blockers & attacks) ^ occ;
    return attacks ^ getRookAttacks(_blockers, rookSq);
}

pub inline fn xrayBishopAttacks(occ: u64, blockers: u64, bishopSq: e_square) u64 {
    const attacks = getBishopAttacks(occ, bishopSq);
    const _blockers = (blockers & attacks) ^ occ;
    return attacks ^ getBishopAttacks(_blockers, bishopSq);
}

pub inline fn getSqRank(sq: e_square) u8 {
    return @intFromEnum(sq) >> 3;
}
pub inline fn getSqIdxRank(sq: u8) u8 {
    return (sq) >> 3;
}

pub inline fn getSqFile(sq: e_square) u8 {
    return @intFromEnum(sq) & 7;
}
pub inline fn getSqIdxFile(sq: u8) u8 {
    return (sq) & 7;
}

pub inline fn getSqFromCoord(rank: u8, file: u8) e_square {
    return @enumFromInt((rank << 3) + file);
}

pub inline fn getSqDiag(sq: e_square) i8 {
    const _sq: i8 = @intCast(@intFromEnum(sq));
    return (_sq & 7) - (_sq >> 3);
}

pub inline fn getSqAntiDiag(sq: e_square) i8 {
    const _sq: i8 = @intCast(@intFromEnum(sq));
    return 7 - (_sq & 7) - (_sq >> 3);
}

pub inline fn fillFile(mask: u64) u64 {
    return moveGenl.northOne(moveGenl.northOccl(mask, UNIVERSE)) | moveGenl.southOne(moveGenl.southOccl(mask, UNIVERSE)) | mask;
}
pub inline fn genShift(bb: u64, shift: i8) u64 {
    if (shift < 0) {
        return bb >> @intCast(-shift);
    }
    return bb << @intCast(shift);
}

pub inline fn passedPawns(pawn: u64, opp: u64) u64 {
    // passed pawn: pawn without a neighboring enemy pawn
    // fill the ranks from top to bottom with a fill algo
    // then ~(shift left | shift right) & pawn
    // careful of clipping
    const cols = fillFile(opp);
    const lmask = (cols << 1) & notAFile;
    const rmask = (cols >> 1) & notHFile;
    return ~(lmask | rmask) & pawn;
}

pub inline fn isolatedPawns(pawn: u64) u64 {
    // isolated pawn: pawn without a neighboring pawn
    // fill the ranks from top to bottom with a fill algo
    // then ~(shift left | shift right) & pawn
    // careful of clipping
    const cols = fillFile(pawn);
    const lmask = (cols << 1) & notAFile;
    const rmask = (cols >> 1) & notHFile;
    return ~(lmask | rmask) & pawn;
}
pub inline fn stackedPawns(pawn: u64) u64 {
    // stacked pawns: multiple pawns present on the same file
    const upPawns = pawn & (moveGenl.northOne(moveGenl.northOccl(pawn, UNIVERSE)));
    const downPawns = pawn & (moveGenl.southOne(moveGenl.southOccl(pawn, UNIVERSE)));
    const tripleFiles = (upPawns & downPawns);
    return upPawns | downPawns | tripleFiles;
}

pub inline fn _AllAttackPawnMask(bb_piece: u64, white: bool) u64 {
    if (white) {
        return _AllAttackPawnMask_cst(bb_piece, true);
    }
    return _AllAttackPawnMask_cst(bb_piece, false);
}

pub inline fn _AllAttackPawnMask_cst(bb_piece: u64, comptime white: bool) u64 {
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

pub fn _AllAttackBishopMask(bb_piece: u64, occ_bb: u64) u64 {
    var ret: u64 = EMPTY;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        const sq = bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        ret |= getBishopAttacks(occ_bb, @enumFromInt(sq));
    }
    return ret;
}

pub fn _AllAttackRookMask(bb_piece: u64, occ_bb: u64) u64 {
    var ret: u64 = EMPTY;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        const sq = bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        ret |= getRookAttacks(occ_bb, @enumFromInt(sq));
    }
    return ret;
}

pub fn _AllAttackQueenMask(bb_piece: u64, occ_bb: u64) u64 {
    var ret: u64 = EMPTY;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        const sq = bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        const sq_e: e_square = @enumFromInt(sq);
        ret |= getRookAttacks(occ_bb, sq_e);
        ret |= getBishopAttacks(occ_bb, sq_e);
    }
    return ret;
}

pub fn getAllAttackMask(p_board: *const Board_state, occBB: u64, white: bool) u64 {
    var ret: u64 = EMPTY;
    var color_offset: u8 = 0;
    if (white) {
        ret |= _AllAttackPawnMask_cst(p_board.getPieceBB(.nWhitePawn), true);
        ret |= getKingAttacks(p_board.b.wKingSq);
    } else {
        color_offset = 6;
        ret |= _AllAttackPawnMask_cst(p_board.getPieceBB(.nBlackPawn), false);
        ret |= getKingAttacks(p_board.b.bKingSq);
    }
    ret |= knightAttacks(p_board.b.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKnight)]);
    ret |= _AllAttackBishopMask(p_board.b.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteBishop)], occBB);
    ret |= _AllAttackRookMask(p_board.b.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteRook)], occBB);
    ret |= _AllAttackQueenMask(p_board.b.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteQueen)], occBB);

    return ret;
}

pub inline fn getAllAttackerFromKing(p_board: *const Board_state, white: bool) u64 {
    if (white) {
        return cst_getAllAttackerFromSq(p_board, true, p_board.b.wKingSq);
    } else {
        return cst_getAllAttackerFromSq(p_board, false, p_board.b.bKingSq);
    }
}
pub inline fn getAllAttackerFromSq(p_board: *const Board_state, white: bool, sq: e_square) u64 {
    if (white) {
        return cst_getAllAttackerFromSq(p_board, true, sq);
    } else {
        return cst_getAllAttackerFromSq(p_board, false, sq);
    }
}

pub fn cst_getAllAttackerFromSq(p_board: *const Board_state, comptime white: bool, sq: e_square) u64 {
    var ret: u64 = EMPTY;
    const bb = sqToBitboard(sq);
    if (comptime white) {
        ret |= knightAttacks(bb) & p_board.getPieceBB(.nBlackKnight);
        ret |= _AllAttackBishopMask(bb, p_board.b.occupiedBB()) & (p_board.getPieceBB(.nBlackBishop) | p_board.getPieceBB(.nBlackQueen));
        ret |= _AllAttackRookMask(bb, p_board.b.occupiedBB()) & (p_board.getPieceBB(.nBlackRook) | p_board.getPieceBB(.nBlackQueen));
        ret |= _AllAttackPawnMask(bb, white) & (p_board.getPieceBB(.nBlackPawn));
        ret |= getKingAttacks(sq) & (p_board.getPieceBB(.nBlackKing));
    } else {
        ret |= knightAttacks(bb) & p_board.getPieceBB(.nWhiteKnight);
        ret |= _AllAttackBishopMask(bb, p_board.b.occupiedBB()) & (p_board.getPieceBB(.nWhiteBishop) | p_board.getPieceBB(.nWhiteQueen));
        ret |= _AllAttackRookMask(bb, p_board.b.occupiedBB()) & (p_board.getPieceBB(.nWhiteRook) | p_board.getPieceBB(.nWhiteQueen));
        ret |= _AllAttackPawnMask(bb, white) & (p_board.getPieceBB(.nWhitePawn));
        ret |= getKingAttacks(sq) & (p_board.getPieceBB(.nWhiteKing));
    }
    return ret;
}
pub inline fn getCheckers(p_board: *Board_state, white: bool) void {
    // this method is responsible for ~30-40% of the compute cost of perft when using staged move generation
    // plan when loading a fen do a "full" get checkers
    // when making a move: do a "partial" get checkers using the previous state
    if (white) {
        getCheckers_cst(p_board, true);
    } else {
        getCheckers_cst(p_board, false);
    }
    //p_board.beeingAttacked = getAllAttackMask(p_board, p_board.b.occupiedBB() ^ p_board.getKingBB(white), !white);
    return;
}

pub inline fn onMoveStaged(p_board: *Board_state, white: bool) void {
    getCheckers(p_board, white);
    return;
}

pub fn getCheckers_cst(p_board: *Board_state, comptime white: bool) void {
    const rq: u64 = if (comptime white) (p_board.getPieceBB(.nBlackRook) | p_board.getPieceBB(.nBlackQueen)) else (p_board.getPieceBB(.nWhiteRook) | p_board.getPieceBB(.nWhiteQueen));
    const bq: u64 = if (comptime white) (p_board.getPieceBB(.nBlackBishop) | p_board.getPieceBB(.nBlackQueen)) else (p_board.getPieceBB(.nWhiteBishop) | p_board.getPieceBB(.nWhiteQueen));
    const n: u64 = if (comptime white) p_board.getPieceBB(.nBlackKnight) else p_board.getPieceBB(.nWhiteKnight);
    const p: u64 = if (comptime white) p_board.getPieceBB(.nBlackPawn) else p_board.getPieceBB(.nWhitePawn);
    const king_E = if (comptime white) p_board.b.wKingSq else p_board.b.bKingSq;

    const cachedBishAtt = getBishopAttacks(p_board.b.occupiedBB(), king_E);
    const cachedRookAtt = getRookAttacks(p_board.b.occupiedBB(), king_E);
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
        @panic(":)");
    } else {
        var pinned: u64 = 0;
        const rBlockers = (p_board.b.occupiedBB() & cachedRookAtt) ^ p_board.b.occupiedBB();
        var pinner = (cachedRookAtt ^ getRookAttacks(rBlockers, king_E)) & rq;
        while (pinner != EMPTY) {
            const pinsq = bitscan(pinner);
            pinner &= pinner - 1;
            pinned |= inBetween(@enumFromInt(pinsq), king_E);
        }

        const bBlockers = (p_board.b.occupiedBB() & cachedBishAtt) ^ p_board.b.occupiedBB();
        pinner = (cachedBishAtt ^ getBishopAttacks(bBlockers, king_E)) & bq;
        while (pinner != EMPTY) {
            const pinsq = bitscan(pinner);
            pinner &= pinner - 1;
            pinned |= inBetween(@enumFromInt(pinsq), king_E);
        }
        p_board.frame.pinnedBB = pinned;
    }

    p_board.frame.checkersBB = directChecks;
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
}

pub fn getAllMoveMaskFromX(p_board: *Board_state, white: bool, X: e_square) u64 {
    // only used in the algebraic "decoding"
    var ret: u64 = EMPTY;

    const destBB = sqToBitboard(X);
    if (!white) {
        ret |= knightAttacks(destBB) & p_board.getPieceBB(.nBlackKnight);
        ret |= _AllAttackBishopMask(destBB, p_board.b.occupiedBB()) & (p_board.getPieceBB(.nBlackBishop) | p_board.getPieceBB(.nBlackQueen));
        ret |= _AllAttackRookMask(destBB, p_board.b.occupiedBB()) & (p_board.getPieceBB(.nBlackRook) | p_board.getPieceBB(.nBlackQueen));
        if (p_board.get_piece(@intFromEnum(X)) != .nEmptySquare or p_board.frame.enPassantIdx == @intFromEnum(X)) {
            ret |= (_AllAttackPawnMask(destBB, !white) & (p_board.getPieceBB(.nBlackPawn)));
        }
        ret |= getKingAttacks(X) & (p_board.getPieceBB(.nBlackKing));

        const piece_idx: u8 = @intFromEnum(e_piece.nBlackPawn);
        ret |= (destBB << 8) & (p_board.b.pieceBB[piece_idx]);
        ret |= (((destBB << 8) & (~p_board.b.occupiedBB())) << 8) & ((p_board.b.pieceBB[piece_idx] & blackPawnDoubleRank));
    } else {
        ret |= knightAttacks(destBB) & p_board.getPieceBB(.nWhiteKnight);
        ret |= _AllAttackBishopMask(destBB, p_board.b.occupiedBB()) & (p_board.getPieceBB(.nWhiteBishop) | p_board.getPieceBB(.nWhiteQueen));
        ret |= _AllAttackRookMask(destBB, p_board.b.occupiedBB()) & (p_board.getPieceBB(.nWhiteRook) | p_board.getPieceBB(.nWhiteQueen));

        if (p_board.get_piece(@intFromEnum(X)) != .nEmptySquare or p_board.frame.enPassantIdx == @intFromEnum(X)) {
            ret |= (_AllAttackPawnMask(destBB, !white) & (p_board.getPieceBB(.nWhitePawn)));
        }
        ret |= getKingAttacks(X) & (p_board.getPieceBB(.nWhiteKing));

        const piece_idx: u8 = @intFromEnum(e_piece.nWhitePawn);
        ret |= (destBB >> 8) & (p_board.b.pieceBB[piece_idx]);
        ret |= (((destBB >> 8) & (~p_board.b.occupiedBB())) >> 8) & ((p_board.b.pieceBB[piece_idx] & whitePawnDoubleRank));
    }
    return ret;
}

pub fn algebraicIsLetterPiece(letter: u8) bool {
    // P, B, N, R, Q, K
    return letter == 'P' or letter == 'B' or letter == 'N' or letter == 'R' or letter == 'Q' or letter == 'K';
}
pub fn algebraicIsLetterFile(letter: u8) bool {
    return letter >= 'a' and letter <= 'h';
}
pub fn algebraicIsLetterRank(letter: u8) bool {
    return letter >= '1' and letter <= '8';
}
pub fn algebraicToIMove(p_state: *Board_state, moveStr: *stringl.string) !IMove {
    // exemple of match "1. d4 Nf6 2. c4 e6 3. Nf3 Bb4+ 4. Nbd2 O-O 5. a3 Bxd2+ 6. Bxd2 d6"
    // O-O: castling kingside
    // O-O-O: castling queenside
    // promotions: =
    // capture: x
    // induces a check: + at the end (useless)
    const white = p_state.whiteToMove();
    if (moveStr.containsE("O-O-O", .ignoreCase)) {
        if (white) {
            return movel.build_move(@intFromEnum(e_square.e1), @intFromEnum(e_square.c1), @intFromEnum(e_moveFlags.QUEENCASTLE));
        } else {
            return movel.build_move(@intFromEnum(e_square.e8), @intFromEnum(e_square.c8), @intFromEnum(e_moveFlags.QUEENCASTLE));
        }
    } else if (moveStr.containsE("O-O", .ignoreCase)) {
        if (white) {
            return movel.build_move(@intFromEnum(e_square.e1), @intFromEnum(e_square.g1), @intFromEnum(e_moveFlags.KINGCASTLE));
        } else {
            return movel.build_move(@intFromEnum(e_square.e8), @intFromEnum(e_square.g8), @intFromEnum(e_moveFlags.KINGCASTLE));
        }
    } else if (moveStr.containsE("-", .ignoreCase)) {
        return debug_err.valueErr;
    }
    std.debug.assert(moveStr.len > 1);
    var startXPos = moveStr.len - 2;
    while (startXPos >= 0) {
        const posSq = moveStr._slice()[startXPos .. startXPos + 2];
        if (stringToLERF(posSq[0..2]) != .invalid) {
            break;
        }
        startXPos -= 1;
    }
    const posSq = moveStr._slice()[startXPos .. startXPos + 2];
    const toSq = stringToLERF(posSq[0..2]);
    if (toSq == .invalid) {
        return debug_err.valueErr;
    }

    var potentialFromBB = p_state.b.occupiedBB();
    var color_offset: u8 = 0;
    if (!white) {
        color_offset = 6;
    }

    for (0..startXPos) |letterIdx| {
        const letter = moveStr._slice()[letterIdx];
        if (algebraicIsLetterPiece(letter)) {
            const piece = getPieceFromStr(letter);
            potentialFromBB &= (p_state.b.pieceBB[@intFromEnum(piece) + color_offset]);
        } else if (algebraicIsLetterFile(letter)) {
            const fileNbr: u8 = letter - 'a';
            potentialFromBB &= fileMaskFromFileN(fileNbr);
        } else if (algebraicIsLetterRank(letter)) {
            const rankNbr = letter - '1';
            potentialFromBB &= rankMaskFromRankN(rankNbr);
        }
    }
    potentialFromBB &= getAllMoveMaskFromX(p_state, white, toSq);

    // here filter out the pinned direction only
    if (popcount(potentialFromBB) > 1) {
        const kingSq = p_state.getKingSq(white);
        var _bb = potentialFromBB;
        while (_bb != 0) {
            const _sq = bitscan(_bb);
            _bb &= _bb - 1;
            const _fromBB = xToBitboard(_sq);
            if ((_fromBB & p_state.frame.pinnedBB) != 0) {
                if ((inBetween(kingSq, toSq) & _fromBB) == 0) {
                    potentialFromBB ^= _fromBB;
                }
            }
        }
    }

    if (popcount(potentialFromBB) != 1) {
        // possibly only a pawn move
        if (potentialFromBB & (p_state.b.pieceBB[@intFromEnum(e_piece.nWhitePawn) + color_offset]) != 0) {
            potentialFromBB &= (p_state.b.pieceBB[@intFromEnum(e_piece.nWhitePawn) + color_offset]);
        }

        if (popcount(potentialFromBB) != 1) {
            std.debug.print("[PANIC] algebraicToIMove: potentialFromBB contains 0 or multiple possible source square for token: '{s}'\n", .{moveStr._slice()});
            std.debug.print("[PANIC] algebraicToIMove: startXPos: {d} white: {}\n", .{ startXPos, p_state.whiteToMove() });
            p_state.moveHistory.print();

            print_bitboard(potentialFromBB);
            return debug_err.valueErr;
        }
    }
    const fromSq = bitscan(potentialFromBB);
    var ret: IMove = movel.build_move(fromSq, @intFromEnum(toSq), 0);

    fillMoveFromState(p_state, &ret);
    if (moveStr.containsE("=", .ignoreCase)) {
        const eqIdx = moveStr.findE('=') catch {
            return ret;
        };
        const prom = moveStr._slice()[eqIdx + 1];
        var flag = ret.getFlag();
        flag |= @intFromEnum(letterPromoToFlag(prom));

        ret.setFlag(flag);
    }

    return ret;
}

pub fn test_avx() !void {
    const fen = "k1p4R/1q2q1rq/8/Q2PPP2/q2RKP1q/3PPP2/4q1q1/1q6 w - - 0 0";
    //const fen = DEFAULT_FEN;
    var state = try getBoardFromFen(fen);
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
    print_bitboard(state.frame.pinnedBB);
    print_boardstate(&state);
}
pub fn _algebraicLineToIMoveMatch(alloc: std.mem.Allocator, line: *stringl.string, tmpBoard: *Board_state) !matchMoveContainer {
    var gen = utils.splitGenerator(u8).init(line._slice(), ' ');

    var ret: matchMoveContainer = undefined;
    ret.len = 0;
    ret.lastIrreversibleMoveIndex = 0;
    while (gen.next()) |str| {
        var offset: usize = 0;
        if (utils.contains(str, "1/2-1/2", .ignoreCase) or utils.contains(str, "1-0", .ignoreCase) or utils.contains(str, "0-1", .ignoreCase)) {
            break;
        }
        if (utils.contains(str, ".", .ignoreCase)) {
            if (str.len == 2) {
                continue;
            }
            // needed because sometimes the #turnCount. is next to the move bug on my part
            offset = 2;
        }

        var moveStr = try stringl.string.initFromSlice(alloc, str[offset..str.len]);
        defer moveStr.free(alloc);
        const move = algebraicToIMove(tmpBoard, &moveStr) catch {
            std.debug.print("[PANIC] algebraicLineToIMoveMatch: error found in move decoding line: {s} for token {s}\n", .{ line._slice(), moveStr._slice() });
            @panic("???");
        };
        if (move.isValid()) {
            tmpBoard.makeMove(move);
            _ = ret.append(move, .{}, isPawnPiece(tmpBoard.get_piece(move.getFrom())));
        }
    }
    return ret;
}

pub fn algebraicLineToIMoveMatch(alloc: std.mem.Allocator, line: *stringl.string) !matchMoveContainer {
    var tmpBoard = try getBoardFromFen(DEFAULT_FEN);
    return _algebraicLineToIMoveMatch(alloc, line, &tmpBoard);
}
pub fn algebraicLineToBoardstate(alloc: std.mem.Allocator, line: *stringl.string) !Board_state {
    const moves = try algebraicLineToIMoveMatch(alloc, line);
    var ret = try getBoardFromFen(DEFAULT_FEN);
    for (0..moves.len) |i| {
        const move = moves.moves[i];
        ret.makeMove(move);
        sanityCheckBoardState(&ret);
    }
    return ret;
}

pub fn test_move_heur() !void {
    var tmp: Board_state = try getBoardFromFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1 ");
    print_boardstate(&tmp);
    const moves = moveGenl.generateLegalMoves(&tmp);
    const pv: movel.line = .{};
    const feat: schedulerl.searchFeatures = .{};
    var order = heuristicl.eval_move_sorting_mask(&tmp, &moves, 0, &pv, &feat, undefined);

    heuristicl.computeLateMoveReduc(&tmp, &order, 4, &moves);
    for (0..moves.len) |i| {
        const idx = order.indexes[i];
        const move = moves.moves[idx];
        const score = order.scores[i];
        const depth = order.depths[i];
        std.debug.print("{s} : i:{d} idx:{d} score:{d} depth:{d}\n", .{ move.getStr(), i, idx, score, depth });
    }
}

pub fn main(alloc: std.mem.Allocator) !void {
    _ = alloc;
    //mainl.initAll(alloc, true);
    //try test_avx();
    //try test_move_heur();
    return;
}
