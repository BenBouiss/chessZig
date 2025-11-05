const std = @import("std");

const chess = @import("chess.zig");
const utils = @import("utils.zig");
const exploration = @import("exploration.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const e_matchFlag = exploration.e_matchFlag;
const e_square = squarel.e_square;
const squareInfo = squarel.squareInfo;

const NUMBER_PLAYER: u8 = 2;
const ROW_SIZE: u8 = 8;
const COL_SIZE: u8 = 8;
const N_SQUARES: u8 = ROW_SIZE * COL_SIZE;
pub const MAX_POSSIBLE_MOVE: u8 = 218;

pub const EMPTY: u64 = 0;
pub const ONE: u64 = 1;
pub const UNIVERSE: u64 = std.math.maxInt(u64);
//const UNIVERSE: u64 = -1;

// see calc or src/utils.py
const notAFile: u64 = 0xfefefefefefefefe; // ~0x0101010101010101
const notABFile: u64 = 0xfcfcfcfcfcfcfcfc;
const notGHFile: u64 = 0x3f3f3f3f3f3f3f3f;
const notHFile: u64 = 0x7f7f7f7f7f7f7f7f; // ~0x8080808080808080

const DEFAULT_POSITION: u64 = 0xFDFD06000040FFDF;
pub const DEFAULT_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w";
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

const N_PIECES = 15;
const N_PIECES_TYPES = 6;
//const e_piece = enum(u8) { nWhite, nBlack, nWhitePawn, nBlackPawn, nWhiteBishop, nBlackBishop, nWhiteKnight, nBlackKnight, nWhiteRook, nBlackRook, nWhiteQueen, nBlackQueen, nWhiteKing, nBlackKing, nEmptySquare };

pub const e_piece = enum(u8) { nWhite = 1, nWhitePawn = 2, nWhiteBishop = 3, nWhiteKnight = 4, nWhiteRook = 5, nWhiteQueen = 6, nWhiteKing = 7, nBlack = 8, nBlackPawn = 9, nBlackBishop = 10, nBlackKnight = 11, nBlackRook = 12, nBlackQueen = 13, nBlackKing = 14, nEmptySquare = 0 };

pub const e_color = enum(u8) { WHITE = 0, BLACK = 1 };

const arr_color_conv = [2]e_piece{ e_piece.nWhite, e_piece.nBlack };
const arr_color_inv = [2]e_color{ e_color.BLACK, e_color.WHITE };
const arr_piece_str = [_]u8{ '_', '1', 'P', 'B', 'N', 'R', 'Q', 'K', '2', 'p', 'b', 'n', 'r', 'q', 'k' };

//const e_piece_str = enum(u8) { nWhitePawn = "P", nBlackPawn = "p", nWhiteBishop = "B", nWhiteKnight = "N", nWhiteKing = "K", nWhiteRook = "R", BlackBisho = "b", nBlackRook = "r", nWhiteQueen = "Q", n_BlackKnight = "n", nBlackQueen = "q", nBlackKing = "k" };

pub const e_direction = enum(u8) { NORTH = 0, SOUTH = 1, WEST = 2, EAST = 3, NORTHWEST = 4, SOUTHEAST = 5, NORTHEAST = 6, SOUTHWEST = 7 };

pub const e_moveFlags = enum(u4) { QUIETMOVE = 0, DOUBLEPAWN = 1, KINGCASTLE = 2, QUEENCASTLE = 3, CAPTURE = 4, ENPASSANT = 5, KNIGHTPROMO = 8, BISHOPPROMO = 9, ROOKPROMO = 10, QUEENPROMO = 11, KNIGHTPROMOCAPTURE = 12, BISHOPPROMOCAPTURE = 13, ROOKPROMOCAPTURE = 14, QUEENPROMOCAPTURE = 15 };
const CAPTURE_MASK: i8 = 4;

const INVALID_POSITION: i8 = -1;

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

pub fn print_move_array(move_arr: std.ArrayList(IMove)) void {
    for (move_arr.items) |move| {
        move.print();
    }
    std.debug.print("\n", .{});
}

const Move = struct {
    piece: e_piece,
    color: e_color,
    from: e_square,
    to: e_square,
    cpiece: e_piece = e_piece.nEmptySquare,
    ccolor: e_color = e_color.WHITE,
    turn: i8 = 0,
    promotion: e_piece = e_piece.nEmptySquare,
};

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
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = gpa.allocator();
pub inline fn get_global_alloc() std.mem.Allocator {
    return alloc;
}

pub fn genShift(x: u64, s: i8) u64 {
    if (s >= 0) {
        return x << @intCast(s);
    } else {
        return x >> @intCast(-s);
    }
    return 0;
}

const Attack_masks = struct {
    RookAttack: [N_SQUARES]u64 = undefined,
    BishopAttack: [N_SQUARES]u64 = undefined,
    QueenAttack: [N_SQUARES]u64 = undefined,
    //PawnAttack: [N_SQUARES]u64 = undefined,
    //KnightAttack: [N_SQUARES]u64 = undefined,
    KingAttack: [N_SQUARES]u64 = undefined,
    SimplePawnAttack: [NUMBER_PLAYER][N_SQUARES]u64 = undefined,
};

pub fn free_move_history(move_arr: std.array_list) void {
    _ = move_arr;
    return;
}

pub fn bitscan(b: u64) i8 {
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

pub fn r_bitscan(b: u64) i8 {
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
const index64 = [64]i8{ 0, 47, 1, 56, 48, 27, 2, 60, 57, 49, 41, 37, 28, 16, 3, 61, 54, 58, 35, 52, 50, 42, 21, 44, 38, 32, 29, 23, 17, 11, 4, 62, 46, 55, 26, 59, 40, 36, 15, 53, 34, 51, 20, 43, 31, 22, 10, 45, 25, 39, 14, 33, 19, 30, 9, 24, 13, 18, 8, 12, 7, 6, 5, 63 };

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
pub fn bitScanForward(bb: u64) i8 {
    if (bb == 0) {
        return -1;
    }
    const debruijn64: u64 = (0x03f79d71b4cb0a89);
    return index64[((bb ^ (bb - 1)) *% debruijn64) >> 58];
}

const r_index64 = [64]i8{ 0, 47, 1, 56, 48, 27, 2, 60, 57, 49, 41, 37, 28, 16, 3, 61, 54, 58, 35, 52, 50, 42, 21, 44, 38, 32, 29, 23, 17, 11, 4, 62, 46, 55, 26, 59, 40, 36, 15, 53, 34, 51, 20, 43, 31, 22, 10, 45, 25, 39, 14, 33, 19, 30, 9, 24, 13, 18, 8, 12, 7, 6, 5, 63 };

///*
// bitScanReverse
// @authors Kim Walisch, Mark Dickinson
// @param bb bitboard to scan
// @precondition bb != 0
// @return index (0..63) of most significant one bit
///
/// This function and the one above are branchless version of bitScan and r_bitScan, function are from chessprogramming.org
///
pub fn bitScanReverse(bb: u64) i8 {
    const debruijn64: u64 = (0x03f79d71b4cb0a89);
    bb |= bb >> 1;
    bb |= bb >> 2;
    bb |= bb >> 4;
    bb |= bb >> 8;
    bb |= bb >> 16;
    bb |= bb >> 32;
    return r_index64[(bb *% debruijn64) >> 58];
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

pub fn getBoardFromFen(fen: []const u8) Board_state {
    // var ret: Board_state = undefined;
    // _ = ret.init_board() catch void;
    var ret = getEmptyBoardState();
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
                std.debug.print("Placement failed at: {d} val: {d}\n", .{ board_offset, @intFromEnum(tmp_enum) });
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
            } else {
                ret.turn = e_color.BLACK;
            }
        }
    }
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
    ret.enPassantBB[@intFromEnum(e_color.WHITE)] = EMPTY;
    ret.enPassantBB[@intFromEnum(e_color.BLACK)] = EMPTY;

    return ret;
}

pub fn filterMoveLegal(p_state: *Board_state, move_list: *moveContainer) !moveContainer {
    var ret: moveContainer = .{};
    const turn: e_color = p_state.turn;
    var status: bool = true;
    for (0..move_list.len) |i| {
        status = try p_state.makeMove(move_list.moves[i]);
        if (!status) {
            std.debug.print("From filterMoveLegal: invalid status found: \n", .{});
            print_board(p_state);
        }
        if (p_state.isLegal(turn)) {
            _ = ret.append(move_list.moves[i]);
        }
        _ = try p_state.undoMove();
    }

    return ret;
}

pub fn filterMoveLegalFast(p_state: *Board_state, move_list: *moveContainer) !moveContainer {
    var ret: moveContainer = .{};
    const turn: e_color = p_state.turn;
    var diagPieceBB: u64 = 0;
    var linePieceBB: u64 = 0;
    const cached = getCachedAttackingPiece(p_state, turn);
    const all_attack = getAllAttackMask(p_state, &p_state.attackMask, invertColor(turn));
    const kingSqInfo = squareInfo.init(@enumFromInt(p_state.getKingSq(turn)));
    const checks: squarel.checkContainer = squarel.convertBitBoardtoCheckContainer(getAllAttackMaskFromKing(p_state, turn));
    //if (checks.isCheck()) {
    //    checks.print();
    //}
    linePieceBB = cached[0];
    diagPieceBB = cached[1];
    for (0..move_list.len) |i| {
        if (p_state.isLegalFast(all_attack, move_list.moves[i], &kingSqInfo, &checks, diagPieceBB, linePieceBB)) {
            _ = ret.append(move_list.moves[i]);
        }
    }

    return ret;
}

pub fn getCachedAttackingPiece(p_state: *Board_state, turn: e_color) [2]u64 {
    // [linePieceBB, diagPieceBB];
    var ret = [_]u64{ EMPTY, EMPTY };
    if (turn == e_color.WHITE) {
        ret[0] = (p_state.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
        ret[1] = (p_state.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
    } else {
        ret[0] = (p_state.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
        ret[1] = (p_state.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
    }
    return ret;
}

pub inline fn invertColor(color: e_color) e_color {
    return arr_color_inv[@intFromEnum(color)];
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

pub fn getRookPiece(turn: e_color) e_piece {
    return @enumFromInt(@intFromEnum(e_piece.nWhiteRook) + @intFromEnum(convertColorToColorPiece(turn)) - 1);
}

pub fn updateCastlingRookStatus(p_state: *Board_state, sq: u8) void {
    var target: usize = 0;
    if ((sq == 0) or (sq == 56)) {
        target = 0;
    } else {
        target = 2;
    }
    if (p_state.castleMoveCounter[@intFromEnum(p_state.turn)][target] != INVALID_POSITION) {
        return;
    }
    p_state.castleMoveCounter[@intFromEnum(p_state.turn)][target] = @intCast(p_state.turn_count);
}

pub fn updateCastlingKingStatus(p_state: *Board_state) void {
    if (p_state.castleMoveCounter[@intFromEnum(p_state.turn)][1] != INVALID_POSITION) {
        return;
    }
    p_state.castleMoveCounter[@intFromEnum(p_state.turn)][1] = @intCast(p_state.turn_count);
}
pub fn undoCastlingRookStatus(p_state: *Board_state, sq: u8) void {
    var target: usize = 0;
    if ((sq == 0) or (sq == 56)) {
        target = 0;
    } else {
        target = 2;
    }
    if (p_state.castleMoveCounter[@intFromEnum(p_state.turn)][target] < (p_state.turn_count)) {
        //std.debug.print("[DEBUG] undoCastlingRookStatus: Not clearing the status found {d} at turn: {d}\n", .{ p_state.castleMoveCounter[@intFromEnum(p_state.turn)][target], p_state.turn_count });
        return;
    }
    p_state.castleMoveCounter[@intFromEnum(p_state.turn)][target] = INVALID_POSITION;
}

pub fn undoCastlingKingStatus(p_state: *Board_state) void {
    if (p_state.castleMoveCounter[@intFromEnum(p_state.turn)][1] < (p_state.turn_count)) {
        return;
    }
    p_state.castleMoveCounter[@intFromEnum(p_state.turn)][1] = INVALID_POSITION;
}
pub inline fn convertColorToColorPiece(color: e_color) e_piece {
    return arr_color_conv[@intFromEnum(color)];
}

pub fn getEmptyBoardState() Board_state {
    var ret: Board_state = undefined;
    _ = ret.init_board() catch void;
    return ret;
}

pub const Board_state = struct {
    players: [NUMBER_PLAYER]exploration.Player = std.mem.zeroes([NUMBER_PLAYER]exploration.Player),
    pieceBB: [N_PIECES]u64 = std.mem.zeroes([N_PIECES]u64),
    enPassantBB: [NUMBER_PLAYER]u64,
    castlingBB: [NUMBER_PLAYER]u64,
    c_occupiedBB: [NUMBER_PLAYER]u64,
    occupiedBB: u64 = 0,
    turn: e_color,
    turn_count: u64 = 0,

    castleMoveCounter: [NUMBER_PLAYER][3]i8,
    // 3 index: (queenSide, king, kingSide) store
    // the turn when the piece has 'first' moved
    move_history: std.ArrayList(IMove),
    attackMask: Attack_masks,

    rngIntGenerator: std.Random.DefaultPrng,
    randInt: std.Random,
    seed: u64 = 42,
    pub fn init_board(p_self: *Board_state) !void {
        @memset(&p_self.pieceBB, 0);
        @memset(&p_self.enPassantBB, 0);
        @memset(&p_self.castlingBB, 0);
        @memset(&p_self.c_occupiedBB, 0);
        @memset(&p_self.castleMoveCounter[0], INVALID_POSITION);
        @memset(&p_self.castleMoveCounter[1], INVALID_POSITION);
        p_self.pieceBB[@intFromEnum(e_piece.nEmptySquare)] = UNIVERSE;
        p_self.turn = e_color.WHITE;
        p_self.turn_count = 0;
        p_self.occupiedBB = 0;
        p_self.move_history = try std.ArrayList(IMove).initCapacity(get_global_alloc(), 10);
        p_self.attackMask = initMaskAttacks();
        p_self.rngIntGenerator = std.Random.DefaultPrng.init(p_self.seed);
        p_self.randInt = p_self.rngIntGenerator.random();
    }
    pub fn free_board(p_self: *Board_state) void {
        p_self.move_history.deinit(get_global_alloc());
        for (0..p_self.players.len) |i| {
            exploration.freePlayer(&p_self.players[i]);
        }
    }
    pub fn initPlayers(p_self: *Board_state) !void {
        for (p_self.players) |player| {
            player.init(get_global_alloc());
        }
    }
    pub fn setPlayerType(p_self: *Board_state, color: e_color, player_type: exploration.e_playerType) void {
        p_self.players[@intFromEnum(color)].setType(player_type);
    }
    pub fn printHistory(self: Board_state) void {
        for (self.move_history.items) |move| {
            std.debug.print("{s} ", .{move.getStr()});
        }
        std.debug.print("\n", .{});
    }
    pub fn setPlayerSearchDepth(p_self: *Board_state, color: e_color, depth: u8) void {
        p_self.players[@intFromEnum(color)].setDepth(depth);
    }

    pub fn get_piece(p_self: *Board_state, sq: u8) e_piece {
        const sq_mask: u64 = (ONE << @intCast(sq));
        var ret_piece: e_piece = e_piece.nEmptySquare;
        if ((sq_mask & p_self.occupiedBB) == 0) {
            return ret_piece;
        }
        var bb: u64 = EMPTY;
        var piece_idx: u8 = undefined;
        var color_offset: u8 = @intFromEnum(e_piece.nWhite);
        if ((sq_mask & p_self.c_occupiedBB[@intFromEnum(e_color.WHITE)]) == 0) {
            color_offset = @intFromEnum(e_piece.nBlack);
        }

        for (1..(N_PIECES_TYPES + 1)) |piece_index| {
            piece_idx = color_offset;
            piece_idx += @intCast(piece_index);
            ret_piece = @enumFromInt(piece_idx);
            bb = p_self.pieceBB[piece_idx];

            if ((sq_mask & bb) != 0) {
                return ret_piece;
            }
        }
        return e_piece.nEmptySquare;
    }
    pub fn invert_turn(p_self: *Board_state) void {
        p_self.turn = invertColor(p_self.turn);
    }

    fn next_turn(p_self: *Board_state) void {
        p_self.invert_turn();
        p_self.turn_count += 1;
    }
    fn undo_turn(p_self: *Board_state) void {
        p_self.invert_turn();
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
        if (p_self.move_history.items.len == 0) {
            return false;
        }
        p_self.undo_turn();
        var pieceCastle: e_piece = undefined;
        const poped_move: IMove = p_self.move_history.pop().?;
        const toBB: u64 = ONE << @intCast((poped_move.getTo()));
        const fromBB: u64 = ONE << @intCast((poped_move.getFrom()));
        var moveBB: u64 = (toBB | fromBB);

        const pieceF: e_piece = p_self.get_piece(poped_move.getTo());
        const colorF: e_color = getColorFromPiece(pieceF);

        if (isRookPiece(pieceF)) {
            undoCastlingRookStatus(p_self, poped_move.getFrom());
        } else if (isKingPiece(pieceF)) {
            undoCastlingKingStatus(p_self);
        }
        if (poped_move.isPromotion()) {
            p_self.pieceBB[@intFromEnum(pieceF)] ^= toBB;
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
            p_self.pieceBB[@intFromEnum(poped_move.c_piece)] |= toBB;
            p_self.c_occupiedBB[@intFromEnum(invertColor(colorF))] |= toBB;
            p_self.occupiedBB |= fromBB;
        } else {
            p_self.occupiedBB ^= moveBB;
        }
        return true;
    }

    pub fn makeMove(p_self: *Board_state, move: IMove) !bool {
        var pieceCastle: e_piece = undefined;
        const toBB: u64 = ONE << @intCast(move.getTo());
        const fromBB: u64 = ONE << @intCast(move.getFrom());
        var moveBB = toBB | fromBB;
        const pieceF = p_self.get_piece(move.getFrom());
        const colorF = getColorFromPiece(pieceF);
        if (p_self.pieceBB[@intFromEnum(pieceF)] & fromBB == 0) {
            std.debug.print("[DEBUG] From makeMove: strange move found where piece not found but move formed? Move: {s} {} turn: {}\n", .{ move.getStr(), pieceF, p_self.turn });
            return debug_err.earlyReturn;
            //return false;
        }
        try p_self.move_history.append(get_global_alloc(), move.copy());

        p_self.pieceBB[@intFromEnum(pieceF)] ^= moveBB;
        p_self.c_occupiedBB[@intFromEnum(colorF)] ^= moveBB;
        if (isRookPiece(pieceF)) {
            updateCastlingRookStatus(p_self, move.getFrom());
        } else if (isKingPiece(pieceF)) {
            updateCastlingKingStatus(p_self);
        }
        if (move.isKingSideCastle()) {
            pieceCastle = getRookPiece(colorF);
            p_self.pieceBB[@intFromEnum(pieceCastle)] ^= (moveBB << 1);
            p_self.c_occupiedBB[@intFromEnum(colorF)] ^= (moveBB << 1);
            moveBB |= (moveBB << 1);
        } else if (move.isQueenSideCastle()) {
            const _castleBB: u64 = (toBB >> 2) | (toBB << 1);
            moveBB |= (_castleBB);
            pieceCastle = getRookPiece(colorF);
            p_self.pieceBB[@intFromEnum(pieceCastle)] ^= (_castleBB);
            p_self.c_occupiedBB[@intFromEnum(colorF)] ^= (_castleBB);
        }

        if (move.isCapture()) {
            p_self.pieceBB[@intFromEnum(move.c_piece)] ^= toBB;
            p_self.occupiedBB ^= fromBB;
            p_self.c_occupiedBB[@intFromEnum(invertColor(colorF))] ^= toBB;
        } else {
            p_self.occupiedBB ^= moveBB;
        }
        if (move.isPromotion()) {
            const prom_piece: e_piece = flagPromotionToPiece(move.getFlag(), p_self.turn);
            //std.debug.print("[DEBUG] From makeMove: Making a promoting move to {}\n", .{prom_piece});
            p_self.pieceBB[@intFromEnum(pieceF)] ^= toBB;
            p_self.pieceBB[@intFromEnum(prom_piece)] ^= toBB;
        }
        p_self.next_turn();
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
    pub fn soft_insert(p_self: *Board_state, move: Move) !bool {
        var movedBB: u64 = ONE << @intCast(@intFromEnum(move.to));
        const fromBB: u64 = ONE << @intCast(@intFromEnum(move.from));
        movedBB ^= fromBB;
        p_self.*.pieceBB[@intFromEnum(move.piece) + @intFromEnum(move.color)] ^= movedBB;
        p_self.*.occupiedBB ^= movedBB;
        p_self.*.c_occupiedBB[@intFromEnum(move.color)] ^= movedBB;
        try p_self.move_history.append(get_global_alloc(), move);
        return true;
    }
    pub fn getLastMove(self: Board_state) IMove {
        const n = self.move_history.items.len;
        if (n == 0) {
            return .{};
        }
        return self.move_history.items[n - 1].copy();
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
    pub fn canKingSideCastle(self: Board_state, turn: e_color) bool {
        if (!((self.castleMoveCounter[@intFromEnum(turn)][0] == INVALID_POSITION) and (self.castleMoveCounter[@intFromEnum(turn)][1] == INVALID_POSITION))) {
            return false;
        }
        var sq: e_square = .h1;
        if (turn == .BLACK) {
            sq = .h8;
        }
        return ((rankAttacks(self.occupiedBB, sq) & self.getKingBB(turn) & (self.pieceBB[@intFromEnum(getRookPiece(turn))])) != 0);
    }
    pub fn canQueenSideCastle(self: Board_state, turn: e_color) bool {
        if (!((self.castleMoveCounter[@intFromEnum(turn)][2] == INVALID_POSITION) and (self.castleMoveCounter[@intFromEnum(turn)][1] == INVALID_POSITION))) {
            return false;
        }
        var sq: e_square = .a1;
        if (turn == .BLACK) {
            sq = .a8;
        }
        return ((rankAttacks(self.occupiedBB, sq) & self.getKingBB(turn) & (self.pieceBB[@intFromEnum(getRookPiece(turn))])) != 0);
    }
    pub fn getKingSq(self: Board_state, color: e_color) i8 {
        return bitscan(self.getKingBB(color));
    }

    pub fn getPieceCount(self: Board_state, piece: e_piece) i8 {
        return l_popcount(self.pieceBB[@intFromEnum(piece)]);
    }
    pub fn getSidePieceCount(self: Board_state, color: e_color) i8 {
        return l_popcount(self.c_occupiedBB[@intFromEnum(color)]);
    }

    pub fn isLegal(p_self: *Board_state, turn: e_color) bool {
        // faster than previous _islegal going from ~100-150k nodes/s to 250-300k nodes per sec
        const king_attacks = getAllAttackMaskFromKing(p_self, turn);
        //const lastM = p_self.getLastMove();
        //const stopping = (lastM.getFrom() == @intFromEnum(e_square.d2) and lastM.getTo() == @intFromEnum(e_square.c3));
        //if (stopping) {
        //    print_bitboard(king_attacks);
        //}
        return king_attacks == 0;
    }
    pub fn _isLegal(p_self: *Board_state, turn: e_color) bool {
        const all_attack = getAllAttackMask(p_self, &p_self.attackMask, invertColor(turn));
        const king_bb = p_self.getKingBB(turn);
        if (king_bb == 0) {
            return false;
        }
        return (king_bb & all_attack) == 0;
    }

    pub fn isLegalFast(p_self: *Board_state, all_attack: u64, move: IMove, p_kingSq: *const squareInfo, p_checks: *const squarel.checkContainer, diagPieceBB: u64, linePieceBB: u64) bool {
        const kingBB = (ONE << @intCast(@intFromEnum(p_kingSq.sq)));
        const isAttacked: bool = (kingBB & all_attack) != 0;
        const to: e_square = @enumFromInt(move.getTo());
        const from: e_square = @enumFromInt(move.getFrom());
        if (from != p_kingSq.sq) {
            if (p_checks.isDoubleCheck()) {
                return false;
            }
            const pinnedBB = isPiecePinned(p_self.occupiedBB, from, kingBB, diagPieceBB, linePieceBB);
            if (pinnedBB != EMPTY) {
                const capturedPinned = (bitscan(pinnedBB) == @intFromEnum(to));
                return ((pinnedBB == isPiecePinned(p_self.occupiedBB ^ (ONE << @intCast(@intFromEnum(from))), to, kingBB, diagPieceBB, linePieceBB)) or capturedPinned);
            }

            if (!isAttacked) {
                return true;
            }
            //blocking or capturing as non king
            return ((isPiecePinned(p_self.occupiedBB, to, kingBB, diagPieceBB, linePieceBB) != EMPTY) or (p_checks.squares[0].sq == to));
        }

        const toKingBB = (ONE << @intCast(@intFromEnum(to)));
        const isNotPinned = !(isPiecePinned(p_self.occupiedBB, from, toKingBB, diagPieceBB, linePieceBB) != EMPTY);
        const isToSecure = ((all_attack & toKingBB) == 0);
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
    if (panic)
        @panic("Sanity check(s) failed");
}

pub fn print_boardstate(p_board_state: *Board_state) void {
    if (p_board_state.turn == e_color.WHITE) {
        std.debug.print("Current turn: White\n", .{});
    } else {
        std.debug.print("Current turn: Black\n", .{});
    }

    print_board(p_board_state);
    std.debug.print("Turn number: {d}, move stored: {d}\n", .{ p_board_state.turn_count, p_board_state.move_history.items.len });
    std.debug.print("Current evaluation: {d} \n", .{exploration.getEvaluation(p_board_state)});

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
        p_board_state.move_history.items[p_board_state.move_history.items.len - 1].print();
        std.debug.print("\n", .{});
    }
    std.debug.print("Castling status array: \n", .{});
    std.debug.print("{any}\n", .{p_board_state.castleMoveCounter});
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

var popCountOfByte256: [256]c_char = undefined;

pub fn initpopCountOfByte256() void {
    popCountOfByte256[0] = 0;
    for (0..256) |i| {
        popCountOfByte256[i] = popCountOfByte256[i / 2] + (i & 1);
    }
}

pub fn p_popcount(x: u64) c_int {
    return popCountOfByte256[x & 0xff] +
        popCountOfByte256[(x >> 8) & 0xff] +
        popCountOfByte256[(x >> 16) & 0xff] +
        popCountOfByte256[(x >> 24) & 0xff] +
        popCountOfByte256[(x >> 32) & 0xff] +
        popCountOfByte256[(x >> 40) & 0xff] +
        popCountOfByte256[(x >> 48) & 0xff] +
        popCountOfByte256[x >> 56];
}

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

// pre init sliding moves

var rayAttacks: [64][8]u64 = undefined;

pub fn initRayAttacks() void {
    // https://www.chessprogramming.org/On_an_empty_Board formulas used
    var nort: u64 = (0x0101010101010100);
    var sout: u64 = (0x0080808080808080);
    var _sq: u6 = 0;
    for (0..N_SQUARES) |sq| {
        _sq = @intCast(sq);
        rayAttacks[sq][@intFromEnum(e_direction.NORTH)] = nort;
        rayAttacks[63 - sq][@intFromEnum(e_direction.SOUTH)] = sout;
        // optionnal can be computed on the fly
        rayAttacks[sq][@intFromEnum(e_direction.WEST)] = (ONE << _sq) - (ONE << (_sq & 56));
        rayAttacks[sq][@intFromEnum(e_direction.EAST)] = 2 * ((ONE << (_sq | 7)) - (ONE << _sq));
        nort <<= 1;
        sout >>= 1;
    }
    initRayAttackDiag();
}
pub fn initRayAttackDiag() void {
    var delMask: u64 = undefined;
    const one: u64 = 1;

    var _sq: u6 = 0;
    var diag: u64 = undefined;
    var antidiag: u64 = undefined;

    for (0..N_SQUARES) |sq| {
        _sq = @intCast(sq);
        delMask = one << _sq;
        delMask = delMask ^ (delMask - 1);
        diag = diagonalMask(@intCast(sq));
        antidiag = antiDiagMask(@intCast(sq));

        rayAttacks[sq][@intFromEnum(e_direction.NORTHEAST)] = diag & ~delMask;
        rayAttacks[sq][@intFromEnum(e_direction.NORTHWEST)] = antidiag & ~delMask;
        rayAttacks[sq][@intFromEnum(e_direction.SOUTHEAST)] = antidiag & (delMask >> 1);
        rayAttacks[sq][@intFromEnum(e_direction.SOUTHWEST)] = diag & (delMask >> 1);
    }
}

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

pub fn initMaskAttacks() Attack_masks {
    var diagsMask: [N_SQUARES][2]u64 = undefined;
    var ret: Attack_masks = .{};
    for (0..N_SQUARES) |sq| {
        diagsMask[sq][0] = diagonalMask(@intCast(sq));
        diagsMask[sq][1] = antiDiagMask(@intCast(sq));
        ret.BishopAttack[sq] = (diagsMask[sq][0] | diagsMask[sq][1]);
        ret.QueenAttack[sq] = (diagsMask[sq][0] | diagsMask[sq][1]);

        ret.RookAttack[sq] = rayAttacks[sq][0] | rayAttacks[sq][1] | rayAttacks[sq][2] | rayAttacks[sq][3];

        ret.QueenAttack[sq] |= ret.RookAttack[sq];
        ret.SimplePawnAttack[@intFromEnum(e_color.WHITE)][sq] = simplePawnMask(@enumFromInt(sq), e_color.WHITE);
        ret.SimplePawnAttack[@intFromEnum(e_color.BLACK)][sq] = simplePawnMask(@enumFromInt(sq), e_color.BLACK);
        ret.KingAttack[sq] = kingAttacks(@intCast(sq));
    }
    return ret;
}

pub fn getAttackPositiveRay(occupied: u64, dir: e_direction, square: e_square) u64 {
    const attacks = rayAttacks[@intFromEnum(square)][@intFromEnum(dir)];
    const blocking: u64 = occupied & attacks;
    if (blocking == 0) {
        return attacks;
    }
    const sq: i8 = bitscan(blocking);
    if (sq == -1) {
        return EMPTY;
    }
    const _sq: u8 = @bitCast(sq);
    return attacks ^ rayAttacks[_sq][@intFromEnum(dir)];
}

pub fn getAttackRay(occupied: u64, dir: e_direction, square: e_square) u64 {
    const attacks = rayAttacks[@intFromEnum(square)][@intFromEnum(dir)];
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

    if (sq == -1) {
        return EMPTY;
    }
    const _sq: u8 = @bitCast(sq);
    return attacks ^ rayAttacks[_sq][@intFromEnum(dir)];
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

pub inline fn getSqRank(sq: e_square) u8 {
    return @intFromEnum(sq) / ROW_SIZE;
}

pub inline fn getSqFile(sq: e_square) u8 {
    return @intFromEnum(sq) % ROW_SIZE;
}

pub inline fn getSqDiag(sq: e_square) i8 {
    const _sq: i8 = @intCast(@intFromEnum(sq));
    return (_sq & 7) - (_sq << 3);
}

pub inline fn getSqAntiDiag(sq: e_square) i8 {
    const _sq: i8 = @intCast(@intFromEnum(sq));
    return 7 - (_sq & 7) - (_sq << 3);
}

pub fn isMoveInBB(bb: u64, move: Move) u64 {
    return bb & ((ONE << move.to));
}

pub fn _AllAttackPawnMask(bb_piece: u64, p_attack_mask: *Attack_masks, turn: e_color) u64 {
    var ret: u64 = EMPTY;
    var sq: i8 = 0;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);
        if (sq == INVALID_POSITION) {
            continue;
        }
        ret |= p_attack_mask.SimplePawnAttack[@intFromEnum(turn)][@intCast(sq)];
        _bb_piece ^= (ONE << @intCast(sq));
    }
    return ret;
}

pub fn _AllAttackKnightMask(bb_piece: u64) u64 {
    return knightAttacks(bb_piece);
    //    var ret: u64 = EMPTY;
    //    var sq: i8 = 0;
    //    var _bb_piece = bb_piece;
    //    while (_bb_piece != 0) {
    //        sq = bitscan(_bb_piece);
    //        if (sq == INVALID_POSITION) {
    //            continue;
    //        }
    //        ret |= p_attack_mask.KnightAttack[@intCast(sq)];
    //        _bb_piece ^= (ONE << @intCast(sq));
    //    }
    //    return ret;
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
        ret |= antiDiagAttacks(occ_bb, sq_e);
        ret |= diagonalAttacks(occ_bb, sq_e);
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
        ret |= fileAttacks(occ_bb, sq_e);
        ret |= rankAttacks(occ_bb, sq_e);
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
        ret |= fileAttacks(occ_bb, sq_e);
        ret |= rankAttacks(occ_bb, sq_e);
        ret |= antiDiagAttacks(occ_bb, sq_e);
        ret |= diagonalAttacks(occ_bb, sq_e);
        _bb_piece ^= (ONE << @intCast(sq));
    }
    return ret;
}

pub fn _AllAttackKingMask(bb_piece: u64, p_attack_mask: *Attack_masks) u64 {
    var ret: u64 = EMPTY;
    var sq: i8 = 0;
    var _bb_piece = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);
        if (sq == INVALID_POSITION) {
            continue;
        }
        ret |= p_attack_mask.KingAttack[@intCast(sq)];
        _bb_piece ^= (ONE << @intCast(sq));
    }
    return ret;
}

pub fn getAllAttackMask(p_board: *Board_state, p_attack_masks: *Attack_masks, turn: e_color) u64 {
    var ret: u64 = EMPTY;
    var color_offset = @intFromEnum(e_piece.nWhite) - 1;
    var other_color: e_color = e_color.BLACK;
    if (turn == e_color.BLACK) {
        color_offset = @intFromEnum(e_piece.nBlack) - 1;
        other_color = e_color.WHITE;
    }
    ret |= _AllAttackPawnMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhitePawn)], p_attack_masks, turn);
    ret |= _AllAttackKnightMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKnight)]);
    ret |= _AllAttackBishopMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteBishop)], p_board.occupiedBB);
    ret |= _AllAttackRookMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteRook)], p_board.occupiedBB);
    ret |= _AllAttackQueenMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteQueen)], p_board.occupiedBB);
    ret |= _AllAttackKingMask(p_board.pieceBB[color_offset + @intFromEnum(e_piece.nWhiteKing)], p_attack_masks);

    return ret;
}

pub fn getAllAttackMaskFromKing(p_board: *Board_state, turn: e_color) u64 {
    var ret: u64 = EMPTY;

    const kingbb = p_board.getKingBB(turn);
    if (turn == e_color.WHITE) {
        ret |= _AllAttackKnightMask(kingbb) & p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)];
        ret |= _AllAttackBishopMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
        ret |= _AllAttackRookMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);

        ret |= _AllAttackPawnMask(kingbb, &p_board.attackMask, e_color.WHITE) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)]);
    } else {
        ret |= _AllAttackKnightMask(kingbb) & p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)];
        ret |= _AllAttackBishopMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
        ret |= _AllAttackRookMask(kingbb, p_board.occupiedBB) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);

        ret |= _AllAttackPawnMask(kingbb, &p_board.attackMask, e_color.BLACK) & (p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)]);
    }
    return ret;
}

pub fn extendMoveArray(p_arr1: *std.ArrayList(Move), p_arr2: *std.ArrayList(Move)) !void {
    if (p_arr2.items.len == 0) {
        return;
    }
    for (0..p_arr2.items.len) |move_idx| {
        try p_arr1.append(get_global_alloc(), p_arr2.items[move_idx]);
    }
}

pub fn extendIMoveArray(p_arr1: *std.ArrayList(IMove), p_arr2: *std.ArrayList(IMove)) !void {
    if (p_arr2.items.len == 0) {
        return;
    }
    for (0..p_arr2.items.len) |move_idx| {
        try p_arr1.append(get_global_alloc(), p_arr2.items[move_idx]);
    }
}
pub fn _PieceMovePawnMask(p_board: *Board_state, bb_piece: u64, p_attack_mask: *Attack_masks, turn: e_color) moveContainer {
    var ret: moveContainer = .{};
    var moves: moveContainer = .{};
    var curr_pos: u64 = EMPTY;
    var curr_att: u64 = EMPTY;
    var _bb_piece: u64 = bb_piece;
    var sq: i8 = 0;
    var c_modif: i8 = 1;
    var flags: u6 = 0;
    var piece = e_piece.nWhitePawn;
    var op_color = e_color.BLACK;
    if (turn == e_color.BLACK) {
        c_modif = -1;
        piece = e_piece.nBlackPawn;
        op_color = e_color.WHITE;
    }
    while (_bb_piece != 0) {
        flags = 0;
        curr_att = 0;
        sq = bitscan(_bb_piece);
        curr_pos = (ONE << @intCast(sq));
        if (sq == INVALID_POSITION) {
            return ret;
        }
        if ((sq > 7 and sq < 16 and piece == e_piece.nBlackPawn) or (sq < 56 and sq > 47 and piece == e_piece.nWhitePawn)) {
            flags |= @intFromEnum(e_moveFlags.KNIGHTPROMO);
        }

        moves = _moveBitBoardtoIMove(p_board, curr_pos, (genShift(curr_pos, (8 * c_modif))) & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE) | flags);

        _ = ret.extend(&moves);

        moves = _moveBitBoardtoIMove(p_board, curr_pos, (p_attack_mask.SimplePawnAttack[@intFromEnum(turn)][@intCast(sq)] & p_board.c_occupiedBB[@intFromEnum(op_color)]), flags | @intFromEnum(e_moveFlags.CAPTURE));
        _ = ret.extend(&moves);

        if ((sq > 7 and sq < 16 and piece == e_piece.nWhitePawn) or (sq > 47 and sq < 56 and piece == e_piece.nBlackPawn)) {
            if ((genShift(curr_pos, 8 * c_modif) & p_board.occupiedBB) == 0) {
                moves = _moveBitBoardtoIMove(p_board, curr_pos, (genShift(ONE, sq + (16 * c_modif))) & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.DOUBLEPAWN));
                _ = ret.extend(&moves);
            }
        }

        // still need logic for enpassant moves

        _bb_piece ^= curr_pos;
    }
    return ret;
}

pub fn _PieceMoveKnightMask(p_board: *Board_state, bb_piece: u64) moveContainer {
    var ret: moveContainer = .{};
    var piece = e_piece.nWhiteKnight;
    var color = e_color.WHITE;
    if (p_board.turn == e_color.BLACK) {
        piece = e_piece.nBlackKnight;
        color = e_color.BLACK;
    }
    var _bb_piece: u64 = bb_piece;
    var sq: i8 = 0;
    var one_pos: u64 = 0;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);
        if (sq == INVALID_POSITION) {
            return ret;
        }
        one_pos = (ONE << @intCast(sq));
        _ = ret.extend(&moveBitBoardToIMove(p_board, one_pos, knightAttacks(one_pos) & ~p_board.c_occupiedBB[@intFromEnum(color)], @intFromEnum(e_moveFlags.QUIETMOVE)));
        _bb_piece ^= (ONE << @intCast(sq));
    }
    return ret;
}

pub fn _PieceMoveBishopMask(p_board: *Board_state, bb_piece: u64) moveContainer {
    var ret: moveContainer = .{};
    var curr_att: u64 = EMPTY;
    var sq: i8 = 0;
    var sq_e: e_square = e_square.a1;

    var color = e_color.WHITE;
    if (p_board.turn == e_color.BLACK) {
        color = e_color.BLACK;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);
        if (sq == INVALID_POSITION) {
            return ret;
        }
        sq_e = @enumFromInt(sq);
        curr_att = antiDiagAttacks(p_board.occupiedBB, sq_e);
        curr_att |= diagonalAttacks(p_board.occupiedBB, sq_e);
        curr_att &= ~p_board.c_occupiedBB[@intFromEnum(color)];
        _bb_piece ^= (ONE << @intCast(sq));
        _ = ret.extend(&moveBitBoardToIMove(p_board, (ONE << @intCast(sq)), curr_att, @intFromEnum(e_moveFlags.QUIETMOVE)));
    }
    return ret;
}

pub fn _PieceMoveRookMask(p_board: *Board_state, bb_piece: u64) moveContainer {
    var ret: moveContainer = .{};
    var att_mask: u64 = EMPTY;
    var sq: i8 = 0;
    var sq_e: e_square = e_square.a1;
    var piece = e_piece.nWhiteRook;
    var color = e_color.WHITE;
    if (p_board.turn == e_color.BLACK) {
        piece = e_piece.nBlackRook;
        color = e_color.BLACK;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);

        if (sq == INVALID_POSITION) {
            return ret;
        }
        sq_e = @enumFromInt(sq);
        att_mask = fileAttacks(p_board.occupiedBB, sq_e);
        att_mask |= rankAttacks(p_board.occupiedBB, sq_e);
        att_mask &= ~p_board.c_occupiedBB[@intFromEnum(color)];
        _bb_piece ^= (ONE << @intCast(sq));

        _ = ret.extend(&moveBitBoardToIMove(p_board, (ONE << @intCast(sq)), att_mask, @intFromEnum(e_moveFlags.QUIETMOVE)));
    }
    return ret;
}

pub fn _PieceMoveQueenMask(p_board: *Board_state, bb_piece: u64) moveContainer {
    var ret: moveContainer = .{};

    var att_mask: u64 = EMPTY;
    var sq: i8 = 0;
    var sq_e: e_square = e_square.a1;
    var piece = e_piece.nWhiteQueen;
    var color = e_color.WHITE;
    if (p_board.turn == e_color.BLACK) {
        piece = e_piece.nBlackQueen;
        color = e_color.BLACK;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        sq = bitscan(_bb_piece);
        if (sq == INVALID_POSITION) {
            return ret;
        }
        sq_e = @enumFromInt(sq);
        att_mask = fileAttacks(p_board.occupiedBB, sq_e);
        att_mask |= rankAttacks(p_board.occupiedBB, sq_e);
        att_mask |= antiDiagAttacks(p_board.occupiedBB, sq_e);
        att_mask |= diagonalAttacks(p_board.occupiedBB, sq_e);
        att_mask &= ~p_board.c_occupiedBB[@intFromEnum(color)];
        _bb_piece ^= (ONE << @intCast(sq));

        _ = ret.extend(&moveBitBoardToIMove(p_board, (ONE << @intCast(sq)), att_mask, @intFromEnum(e_moveFlags.QUIETMOVE)));
    }

    return ret;
}

pub fn _PieceMoveKingMask(p_board: *Board_state, bb_piece: u64, p_attack_mask: *Attack_masks) moveContainer {
    var ret: moveContainer = .{};
    var piece = e_piece.nWhiteKing;
    var color = e_color.WHITE;
    if (p_board.turn == e_color.BLACK) {
        piece = e_piece.nBlackKing;
        color = e_color.BLACK;
    }
    const sq = p_board.getKingSq(p_board.turn);
    _ = ret.extend(&moveBitBoardToIMove(p_board, bb_piece, p_attack_mask.KingAttack[@intCast(sq)] & ~p_board.c_occupiedBB[@intFromEnum(color)], @intFromEnum(e_moveFlags.QUIETMOVE)));

    if (p_board.canKingSideCastle(p_board.turn)) {
        _ = ret.extend(&moveBitBoardToIMove(p_board, bb_piece, bb_piece >> 2, @intFromEnum(e_moveFlags.KINGCASTLE)));
    }

    if (p_board.canQueenSideCastle(p_board.turn)) {
        _ = ret.extend(&moveBitBoardToIMove(p_board, bb_piece, bb_piece << 2, @intFromEnum(e_moveFlags.QUEENCASTLE)));
    }

    return ret;
}

pub fn _moveBitBoardtoIMove(p_board: *Board_state, piece_bb: u64, attack_bb: u64, flags: u6) moveContainer {
    if (flags < @intFromEnum(e_moveFlags.KNIGHTPROMO)) {
        return moveBitBoardToIMove(p_board, piece_bb, attack_bb, flags);
    }
    var ret = moveBitBoardToIMove(p_board, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.KNIGHTPROMO));
    _ = ret.extend(&moveBitBoardToIMove(p_board, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.BISHOPPROMO)));
    _ = ret.extend(&moveBitBoardToIMove(p_board, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.ROOKPROMO)));
    _ = ret.extend(&moveBitBoardToIMove(p_board, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.QUEENPROMO)));
    //std.debug.print("[DEBUG] _moveBitBoardtoIMove: Move generated: n = {d}\n", .{m3.items.len});
    return ret;
}
pub fn moveBitBoardToIMove(p_board: *Board_state, piece_bb: u64, attack_bb: u64, flags: u6) moveContainer {
    var ret: moveContainer = .{};
    const sq: i8 = bitscan(piece_bb);
    var _bb = attack_bb;
    var curr_pos: u64 = EMPTY;
    var lsb: i8 = 0;
    var _curr_move: IMove = undefined;
    var c_piece: e_piece = undefined;

    while (_bb != 0) {
        lsb = bitscan(_bb);
        if (lsb == INVALID_POSITION) {
            break;
        }
        curr_pos = (ONE << @intCast(lsb));
        if (curr_pos & p_board.occupiedBB != 0) {
            _curr_move = movel.build_move(@intCast(sq), @intCast(lsb), flags | @intFromEnum(e_moveFlags.CAPTURE));
            c_piece = p_board.get_piece(@intCast(lsb));
            _curr_move.setCapture(c_piece);
        } else {
            _curr_move = movel.build_move(@intCast(sq), @intCast(lsb), flags);
        }

        _ = ret.append(_curr_move);
        _bb ^= curr_pos;
    }
    return ret;
}
pub fn moveBitBoardToMove(p_board: *Board_state, piece_bb: u64, attack_bb: u64, piece: e_piece, turn: e_color) !std.ArrayList(Move) {
    var ret: std.ArrayList(Move) = try std.ArrayList(Move).initCapacity(get_global_alloc(), 10);
    const sq: i8 = bitscan(piece_bb);
    var _bb = attack_bb;
    var lsb: i8 = 0;
    var _curr_move: Move = undefined;
    var c_piece: e_piece = undefined;
    while (_bb != 0) {
        lsb = bitscan(_bb);
        if (lsb == INVALID_POSITION) {
            break;
        }
        c_piece = p_board.get_piece(@intCast(lsb));
        _curr_move = .{
            .piece = piece,
            .color = turn,
            .from = @enumFromInt(sq),
            .to = @enumFromInt(lsb),
            .cpiece = c_piece,
            .ccolor = getColorFromPiece(c_piece),
            .promotion = e_piece.nEmptySquare,
            .turn = @intCast(p_board.turn_count),
        };
        try ret.append(get_global_alloc(), _curr_move);
        _bb ^= (ONE << @intCast(lsb));
    }
    return ret;
}

pub fn getColorFromPiece(piece: e_piece) e_color {
    if (@intFromEnum(piece) < @intFromEnum(e_piece.nBlack)) {
        return e_color.WHITE;
    }
    return e_color.BLACK;
}

pub fn moveGeneration(p_board: *Board_state) !moveContainer {
    // Generates all the moves from the given board state

    var ret: moveContainer = .{};

    var _curr_arr: moveContainer = .{};

    var occ_bb: u64 = p_board.c_occupiedBB[@intFromEnum(e_piece.nWhite)];
    var color_offset: u8 = @intFromEnum(e_piece.nWhite);
    if (p_board.turn == e_color.BLACK) {
        color_offset = @intFromEnum(e_piece.nBlack);
        occ_bb = p_board.c_occupiedBB[@intFromEnum(e_color.BLACK)];
    }
    var bb: u64 = 0;
    var piece: e_piece = e_piece.nEmptySquare;
    var piece_idx: u8 = 0;
    // TODO Unroll the loop
    for (1..N_PIECES_TYPES + 1) |piece_index| {
        piece_idx = @intCast(piece_index + color_offset);
        piece = @enumFromInt(piece_idx);
        bb = p_board.pieceBB[piece_idx];

        if ((piece == e_piece.nWhitePawn) or (piece == e_piece.nBlackPawn)) {
            _curr_arr = _PieceMovePawnMask(p_board, bb, &p_board.attackMask, p_board.turn);
        } else if ((piece == e_piece.nWhiteKnight) or (piece == e_piece.nBlackKnight)) {
            _curr_arr = _PieceMoveKnightMask(p_board, bb);
        } else if ((piece == e_piece.nWhiteKing) or (piece == e_piece.nBlackKing)) {
            _curr_arr = _PieceMoveKingMask(p_board, bb, &p_board.attackMask);
        } else if ((piece == e_piece.nWhiteBishop) or (piece == e_piece.nBlackBishop)) {
            _curr_arr = _PieceMoveBishopMask(p_board, bb);
        } else if ((piece == e_piece.nWhiteRook) or (piece == e_piece.nBlackRook)) {
            _curr_arr = _PieceMoveRookMask(p_board, bb);
        } else if ((piece == e_piece.nWhiteQueen) or (piece == e_piece.nBlackQueen)) {
            _curr_arr = _PieceMoveQueenMask(p_board, bb);
        } else {
            @panic("Unknown piece found in move generation");
        }
        _ = ret.extend(&_curr_arr);
        //std.debug.print("[DEBUG] moveGeneration: Generated {} move(s) for piece: {}\n", .{ _curr_arr.items.len, piece });
    }
    //_ = p_board.c_occupiedBB;
    return ret;
}

pub fn isPiecePinned(occBB: u64, sq: e_square, kingBB: u64, diagPieceBB: u64, linePieceBB: u64) u64 {
    const diagatts = [_]u64{ antiDiagAttacks(occBB, sq), diagonalAttacks(occBB, sq) };

    const lineatts = [_]u64{ fileAttacks(occBB, sq), rankAttacks(occBB, sq) };

    if ((((diagatts[0] & diagPieceBB) != 0) and ((diagatts[0] & kingBB) != 0))) {
        return (diagatts[0] & diagPieceBB);
    }

    if (((diagatts[1] & diagPieceBB) != 0) and ((diagatts[1] & kingBB) != 0)) {
        return (diagatts[1] & diagPieceBB);
    }

    if (((lineatts[0] & linePieceBB) != 0) and ((lineatts[0] & kingBB) != 0)) {
        return (lineatts[0] & linePieceBB);
    }

    if (((lineatts[1] & linePieceBB) != 0) and ((lineatts[1] & kingBB) != 0)) {
        return (lineatts[1] & linePieceBB);
    }
    return EMPTY;
}

pub fn print_ray_attacks(sq: u8) void {
    std.debug.print("\n################ Ray attack state ################ \n", .{});

    std.debug.print("Ray attack north\n", .{});
    print_bitboard(rayAttacks[sq][@intFromEnum(e_direction.NORTH)]);

    std.debug.print("Ray attack north east\n", .{});
    print_bitboard(rayAttacks[sq][@intFromEnum(e_direction.NORTHEAST)]);

    std.debug.print("Ray attack north west\n", .{});
    print_bitboard(rayAttacks[sq][@intFromEnum(e_direction.NORTHWEST)]);

    std.debug.print("Ray attack south\n", .{});
    print_bitboard(rayAttacks[sq][@intFromEnum(e_direction.SOUTH)]);

    std.debug.print("Ray attack south east\n", .{});
    print_bitboard(rayAttacks[sq][@intFromEnum(e_direction.SOUTHEAST)]);

    std.debug.print("Ray attack south west\n", .{});
    print_bitboard(rayAttacks[sq][@intFromEnum(e_direction.SOUTHWEST)]);

    std.debug.print("Ray attack east\n", .{});
    print_bitboard(rayAttacks[sq][@intFromEnum(e_direction.EAST)]);

    std.debug.print("Ray attack west\n", .{});
    print_bitboard(rayAttacks[sq][@intFromEnum(e_direction.WEST)]);
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
    std.debug.print("bitscanForward testing {d}\n", .{bitScanForward(test_board)});
    print_bitboard(test_board);

    std.debug.print("DEFAULT POSITION: \n", .{});
    print_bitboard(DEFAULT_POSITION);
    print_bitboard(getAttackRay(DEFAULT_POSITION, e_direction.NORTHWEST, e_square.g2));

    print_bitboard(DEFAULT_POSITION);
    print_bitboard(getAttackRay(DEFAULT_POSITION, e_direction.SOUTHEAST, e_square.c6));

    var def_board = getDefaultBoard();
    print_board(&def_board);

    var fen_board = getBoardFromFen(DEFAULT_FEN);
    print_boardstate(&fen_board);

    const att_mask: Attack_masks = initMaskAttacks();
    std.debug.print("Chess test\n", .{});
    var test_board2: Board_state = getEmptyBoardState();
    print_bitboard(test_board2.occupiedBB);
    const move: Move = .{ .from = @enumFromInt(0), .to = @enumFromInt(18), .piece = e_piece.nWhiteBishop, .color = e_color.WHITE };
    const initBB: u64 = 1;

    test_board2.occupiedBB = initBB;
    std.debug.print("\nBefore move\n\n", .{});
    print_bitboard(test_board2.occupiedBB);
    print_bitboard(test_board2.pieceBB[@intFromEnum(e_piece.nWhiteBishop)]);

    _ = try test_board2.soft_insert(move);
    std.debug.print("After move\n", .{});
    print_bitboard(test_board2.occupiedBB);
    print_bitboard(test_board2.pieceBB[@intFromEnum(e_piece.nWhiteBishop)]);

    std.debug.print("\n\nPrinting the Bishop attack move from the 18nth square\n", .{});
    print_bitboard(att_mask.RookAttack[31]);

    const _move: Move = .{ .from = @enumFromInt(0), .to = @enumFromInt(63), .piece = e_piece.nWhiteKing, .color = e_color.WHITE };
    _ = try test_board2.soft_insert(_move);

    print_boardstate(&test_board2);
    test_board2.free_board();

    return;
}

pub fn inferFlagFromMovement(p_state: *Board_state, from: e_square, to: e_square, line_buffer: [MAX_USER_INPUT]u8) u8 {
    var ret_flag: u8 = @intFromEnum(e_moveFlags.QUIETMOVE);
    var diff: i8 = 0;
    if (p_state.get_piece(@intFromEnum(to)) != .nEmptySquare) {
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
            if (line_buffer[0] < line_buffer[2]) {
                ret_flag |= @intFromEnum(e_moveFlags.QUEENCASTLE);
            } else {
                ret_flag |= @intFromEnum(e_moveFlags.KINGCASTLE);
            }
        }
    } else if (isPawnPiece(pieceMove)) {
        diff = @intCast(line_buffer[1]);
        diff -= @intCast(line_buffer[3]);
        if (utils.absolute(diff) == 2) {
            ret_flag |= @intFromEnum(e_moveFlags.DOUBLEPAWN);
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

pub fn getUserStdinput() [MAX_USER_INPUT]u8 {
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
    return movel.build_move(@intFromEnum(from), @intFromEnum(to), flag);
}

pub fn askContinue() void {
    var stdin_buffer: [32]u8 = undefined;
    var line_buffer: [32]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&stdin_buffer);
    var w: std.io.Writer = .fixed(&line_buffer);

    _ = stdin.interface.streamDelimiterLimit(&w, '\n', .unlimited) catch void;

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

pub fn _promo_scenario() void {
    const fen_prom = "8/1P6/8/6k1/6K1/3qq3/1p6/8 w";
    var board_promo = getBoardFromFen(fen_prom);
    print_boardstate(&board_promo);
    askContinue();
    var move = movel.build_move(@intFromEnum(e_square.b7), @intFromEnum(e_square.b8), @intFromEnum(e_moveFlags.QUEENPROMO));
    _ = board_promo.makeMove(move) catch |err| {
        std.debug.print("Caught err: {}\n", .{err});
        return;
    };
    print_boardstate(&board_promo);
    askContinue();
    move = movel.build_move(@intFromEnum(e_square.b2), @intFromEnum(e_square.b1), @intFromEnum(e_moveFlags.ROOKPROMO));
    _ = board_promo.makeMove(move) catch |err| {
        std.debug.print("Caught err: {}\n", .{err});
        return;
    };

    print_boardstate(&board_promo);
    askContinue();
    //board_promo.free_board();
}

pub fn _castle_scenario() void {
    const fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w";
    var board_promo = getBoardFromFen(fen);
    print_boardstate(&board_promo);
    askContinue();
    var move = movel.build_move(@intFromEnum(e_square.e1), @intFromEnum(e_square.g1), @intFromEnum(e_moveFlags.KINGCASTLE));
    _ = board_promo.makeMove(move) catch |err| {
        std.debug.print("Caught err: {}\n", .{err});
        return;
    };
    print_boardstate(&board_promo);
    askContinue();
    _ = try board_promo.undoMove();
    print_boardstate(&board_promo);
    askContinue();

    move = movel.build_move(@intFromEnum(e_square.e1), @intFromEnum(e_square.c1), @intFromEnum(e_moveFlags.QUEENCASTLE));
    _ = board_promo.makeMove(move) catch |err| {
        std.debug.print("Caught err: {}\n", .{err});
        return;
    };
    print_boardstate(&board_promo);
    askContinue();
    _ = try board_promo.undoMove();
    print_boardstate(&board_promo);
    askContinue();
}
pub fn _default_scenarios() void {
    const fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w";
    std.debug.print("Testing fen: {s}\n", .{fen});
    var board_promo = getBoardFromFen(fen);
    print_boardstate(&board_promo);
    askContinue();
}

pub fn _mate_scenario() void {
    const fen = "k7/6r1/8/7P/7K/7P/6q1/8 b";
    var board_mate = getBoardFromFen(fen);
    print_boardstate(&board_mate);
    askContinue();
    board_mate.setPlayerType(.BLACK, .DepthBot);
    board_mate.setPlayerSearchDepth(.BLACK, 2);
    board_mate.setPlayerType(.WHITE, .Human);
    match_routine(&board_mate);

    askContinue();
}

pub fn test_scenarios() void {
    // testing promotion scenario
    //const str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w";
    //_default_scenarios();
    //utils.clear();
    //_promo_scenario();
    //utils.clear();
    //_castle_scenario();
    _mate_scenario();
    return;
}

pub fn main() !void {
    initRayAttacks();
    test_scenarios();
    return;
}
