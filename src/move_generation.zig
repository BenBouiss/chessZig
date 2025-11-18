const chess = @import("chess.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const tablel = @import("moveTables.zig");
const magicl = @import("magic.zig");
const std = @import("std");

const typedMoveContainer = movel.typedMoveContainer;
const moveContainer = movel.moveContainer;
const IMove = movel.IMove;
const moveBBState = movel.moveBBState;
const cachedTables = tablel.cachedTables;
const magicRecord = magicl.magicRecord;

const squareInfo = squarel.squareInfo;
const e_square = squarel.e_square;

const e_piece = chess.e_piece;
const e_color = chess.e_color;
const e_moveFlags = movel.e_moveFlags;
const e_moveCategory = movel.e_moveCategory;

const Board_state = chess.Board_state;

pub fn moveGeneration(p_board: *Board_state) moveContainer {
    if (p_board.turn == .WHITE) {
        return white_moveGeneration(p_board);
    }
    return black_moveGeneration(p_board);
}

pub fn white_moveGeneration(p_board: *Board_state) moveContainer {
    // Generates all the moves from the given board state

    var ret: moveContainer = .{};

    const emptyOrEnemy = ~p_board.c_occupiedBB[@intFromEnum(e_color.WHITE)];

    // TODO Unroll the loop
    white_PieceMovePawnMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)], &ret);

    _PieceMoveKnightMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)], e_color.WHITE, emptyOrEnemy, &ret);

    _PieceMoveKingMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteKing)], e_color.WHITE, emptyOrEnemy, &ret);

    _PieceMoveBishopMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)], e_color.WHITE, emptyOrEnemy, &ret);

    _PieceMoveRookMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)], e_color.WHITE, emptyOrEnemy, &ret);

    _PieceMoveQueenMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)], e_color.WHITE, emptyOrEnemy, &ret);

    //std.debug.print("[DEBUG] white_moveGeneration: \n", .{});
    //ret.print();

    return ret;
}
pub fn black_moveGeneration(p_board: *Board_state) moveContainer {
    // Generates all the moves from the given board state

    var ret: moveContainer = .{};

    const emptyOrEnemy = ~p_board.c_occupiedBB[@intFromEnum(e_color.BLACK)];

    black_PieceMovePawnMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)], &ret);

    _PieceMoveKnightMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)], e_color.BLACK, emptyOrEnemy, &ret);

    _PieceMoveKingMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackKing)], e_color.BLACK, emptyOrEnemy, &ret);

    _PieceMoveBishopMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)], e_color.BLACK, emptyOrEnemy, &ret);

    _PieceMoveRookMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)], e_color.BLACK, emptyOrEnemy, &ret);

    _PieceMoveQueenMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)], e_color.BLACK, emptyOrEnemy, &ret);
    return ret;
}
pub fn moveBitBoardToIMove_pawn(p_board: *Board_state, piece: e_piece, piece_bb: u64, attack_bb: u64, flags: u6, p_out: *moveContainer, comptime turn: e_color) void {
    if (attack_bb == 0) {
        return;
    }
    const sq: i8 = chess.bitscan(piece_bb);
    var _bb = attack_bb;
    var _curr_move: IMove = undefined;
    var c_piece: e_piece = undefined;
    var enpass_capture_pawn: e_piece = e_piece.nBlackPawn;
    if (comptime turn == e_color.BLACK) {
        enpass_capture_pawn = e_piece.nWhitePawn;
    }
    while (_bb != 0) {
        const lsb = chess.bitscan(_bb);
        const curr_pos = (chess.ONE << @intCast(lsb));
        if (flags == @intFromEnum(e_moveFlags.ENPASSANT)) {
            c_piece = enpass_capture_pawn;
        } else {
            c_piece = p_board.get_piece(@intCast(lsb));
        }
        _curr_move = movel.build_move(@intCast(sq), @intCast(lsb), flags, piece);
        _curr_move.setCapture(c_piece);
        _ = p_out.append(_curr_move);

        _bb ^= curr_pos;
    }
    return;
}
pub fn moveBitBoardToIMove(p_board: *Board_state, piece: e_piece, piece_bb: u64, attack_bb: u64, flags: u6, p_out: *moveContainer, comptime turn: e_color) void {
    const sq: i8 = chess.bitscan(piece_bb);
    var _bb = attack_bb;
    var _curr_move: IMove = undefined;
    var c_piece: e_piece = undefined;
    var enpass_capture_pawn: e_piece = e_piece.nBlackPawn;
    if (comptime turn == e_color.BLACK) {
        enpass_capture_pawn = e_piece.nWhitePawn;
    }
    while (_bb != 0) {
        const lsb = chess.bitscan(_bb);
        const curr_pos = (chess.ONE << @intCast(lsb));
        _curr_move = movel.build_move(@intCast(sq), @intCast(lsb), flags, piece);
        c_piece = p_board.get_piece(@intCast(lsb));
        _curr_move.setCapture(c_piece);
        _ = p_out.append(_curr_move);
        _bb ^= curr_pos;
    }
    return;
}

pub fn white_PieceMovePawnMask(p_board: *Board_state, bb_piece: u64, p_out: *moveContainer) void {
    var _bb_piece: u64 = bb_piece;
    const piece = e_piece.nWhitePawn;
    const op_color = e_color.BLACK;
    const freeBB = ~p_board.occupiedBB;
    const enemyBB = p_board.c_occupiedBB[@intFromEnum(op_color)];
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        const sqRank = chess.getSqIdxRank(@intCast(sq));
        const curr_pos = (chess.ONE << @intCast(sq));
        const singlePushBB = curr_pos << 8;

        if (sqRank == 6) {
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB) & (freeBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, e_color.WHITE);
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.WHITE)][@intCast(sq)] & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, e_color.WHITE);
            _bb_piece ^= curr_pos;
            continue;
        }

        if (sqRank == 1 and ((singlePushBB & freeBB)) != 0) {
            moveBitBoardToIMove_pawn(p_board, piece, curr_pos, ((singlePushBB) << 8) & (freeBB), @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, e_color.WHITE);
        }
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB & freeBB), 0, p_out, e_color.WHITE);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.WHITE)][@intCast(sq)] & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, e_color.WHITE);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.WHITE)][@intCast(sq)] & p_board.enPassantBB[@intFromEnum(op_color)] & (freeBB)), @intFromEnum(e_moveFlags.ENPASSANT), p_out, e_color.WHITE);
        _bb_piece ^= curr_pos;
    }
    return;
}

pub fn black_PieceMovePawnMask(p_board: *Board_state, bb_piece: u64, p_out: *moveContainer) void {
    var _bb_piece: u64 = bb_piece;
    const piece = e_piece.nBlackPawn;
    const op_color = e_color.WHITE;
    const freeBB = ~p_board.occupiedBB;
    const enemyBB = p_board.c_occupiedBB[@intFromEnum(op_color)];
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        const sqRank = chess.getSqIdxRank(@intCast(sq));
        const curr_pos = (chess.ONE << @intCast(sq));
        const singlePushBB = curr_pos >> 8;

        if (sqRank == 1) {
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB) & (freeBB), 0, p_out, e_color.BLACK);
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.BLACK)][@intCast(sq)] & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, e_color.BLACK);
            _bb_piece ^= curr_pos;
            continue;
        }

        if (sqRank == 6 and ((singlePushBB & freeBB)) != 0) {
            moveBitBoardToIMove_pawn(p_board, piece, curr_pos, ((singlePushBB) >> 8) & (freeBB), @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, e_color.BLACK);
        }
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB & freeBB), 0, p_out, e_color.BLACK);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.BLACK)][@intCast(sq)] & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, e_color.BLACK);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.BLACK)][@intCast(sq)] & p_board.enPassantBB[@intFromEnum(op_color)] & (freeBB)), @intFromEnum(e_moveFlags.ENPASSANT), p_out, e_color.BLACK);

        _bb_piece ^= curr_pos;
    }
    return;
}

pub fn _PieceMoveKnightMask(p_board: *Board_state, bb_piece: u64, comptime turn: e_color, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var piece = e_piece.nWhiteKnight;
    var color = e_color.WHITE;
    if (comptime turn == e_color.BLACK) {
        piece = e_piece.nBlackKnight;
        color = e_color.BLACK;
    }
    var _bb_piece: u64 = bb_piece;
    var sq: i8 = 0;
    var one_pos: u64 = 0;
    while (_bb_piece != 0) {
        sq = chess.bitscan(_bb_piece);
        one_pos = (chess.ONE << @intCast(sq));
        const att = chess.knightAttacks(one_pos) & emptyOrEnemy;
        moveBitBoardToIMove(p_board, piece, one_pos, att & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, turn);
        moveBitBoardToIMove(p_board, piece, one_pos, att & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, turn);
        _bb_piece ^= (chess.ONE << @intCast(sq));
    }
    return;
}

pub fn _PieceMoveBishopMask(p_board: *Board_state, bb_piece: u64, comptime turn: e_color, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var curr_att: u64 = chess.EMPTY;
    var sq: i8 = 0;
    var sq_e: e_square = e_square.a1;

    var color = e_color.WHITE;
    var piece = e_piece.nWhiteBishop;
    if (comptime turn == e_color.BLACK) {
        color = e_color.BLACK;
        piece = e_piece.nBlackBishop;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        sq = chess.bitscan(_bb_piece);
        sq_e = @enumFromInt(sq);
        curr_att = chess.antiDiagAttacks(p_board.occupiedBB, sq_e);
        curr_att |= chess.diagonalAttacks(p_board.occupiedBB, sq_e);
        curr_att &= emptyOrEnemy;
        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), curr_att & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, turn);

        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), curr_att & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, turn);
        curr_att &= emptyOrEnemy;
        _bb_piece ^= (chess.ONE << @intCast(sq));
    }
    return;
}

pub fn _PieceMoveRookMask(p_board: *Board_state, bb_piece: u64, comptime turn: e_color, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var att_mask: u64 = chess.EMPTY;
    var sq: i8 = 0;
    var sq_e: e_square = e_square.a1;
    var piece = e_piece.nWhiteRook;
    var color = e_color.WHITE;
    if (comptime turn == e_color.BLACK) {
        piece = e_piece.nBlackRook;
        color = e_color.BLACK;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        sq = chess.bitscan(_bb_piece);

        sq_e = @enumFromInt(sq);
        att_mask = chess.fileAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.rankAttacks(p_board.occupiedBB, sq_e);
        att_mask &= emptyOrEnemy;
        _bb_piece ^= (chess.ONE << @intCast(sq));

        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), att_mask & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, turn);
        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), att_mask & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, turn);
    }
    return;
}

pub fn _PieceMoveQueenMask(p_board: *Board_state, bb_piece: u64, comptime turn: e_color, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var att_mask: u64 = chess.EMPTY;
    var sq: i8 = 0;
    var sq_e: e_square = e_square.a1;
    var piece = e_piece.nWhiteQueen;
    var color = e_color.WHITE;
    if (comptime turn == e_color.BLACK) {
        piece = e_piece.nBlackQueen;
        color = e_color.BLACK;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        sq = chess.bitscan(_bb_piece);
        sq_e = @enumFromInt(sq);
        att_mask = chess.fileAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.rankAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.antiDiagAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.diagonalAttacks(p_board.occupiedBB, sq_e);
        att_mask &= emptyOrEnemy;
        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), att_mask & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, turn);
        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), att_mask & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, turn);

        _bb_piece ^= (chess.ONE << @intCast(sq));
    }

    return;
}

pub fn _PieceMoveKingMask(p_board: *Board_state, bb_piece: u64, comptime turn: e_color, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var piece = e_piece.nWhiteKing;
    var color = e_color.WHITE;
    if (comptime turn == e_color.BLACK) {
        piece = e_piece.nBlackKing;
        color = e_color.BLACK;
    }
    const sq = p_board.getKingSq(turn);
    const att_mask = cachedTables.KingAttack[@intCast(sq)] & emptyOrEnemy;

    moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), att_mask & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, turn);
    moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), att_mask & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, turn);

    if (p_board.canKingSideCastle(turn)) {
        moveBitBoardToIMove(p_board, piece, bb_piece, bb_piece << 2, @intFromEnum(e_moveFlags.KINGCASTLE), p_out, turn);
    }

    if (p_board.canQueenSideCastle(turn)) {
        moveBitBoardToIMove(p_board, piece, bb_piece, bb_piece >> 2, @intFromEnum(e_moveFlags.QUEENCASTLE), p_out, turn);
    }

    return;
}

pub fn _moveBitBoardToIMove_pawn(p_board: *Board_state, piece: e_piece, piece_bb: u64, attack_bb: u64, flags: u6, p_out: *moveContainer, comptime turn: e_color) void {
    moveBitBoardToIMove_pawn(p_board, piece, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.KNIGHTPROMO), p_out, turn);
    moveBitBoardToIMove_pawn(p_board, piece, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.BISHOPPROMO), p_out, turn);
    moveBitBoardToIMove_pawn(p_board, piece, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.ROOKPROMO), p_out, turn);
    moveBitBoardToIMove_pawn(p_board, piece, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.QUEENPROMO), p_out, turn);
    //std.debug.print("[DEBUG] _moveBitBoardToIMove_pawn: Move generated: n = {d}\n", .{m3.items.len});
}

pub fn filterMoveLegal(p_state: *Board_state, move_list: *moveContainer) !moveContainer {
    var ret: moveContainer = .{};
    const turn: e_color = p_state.turn;
    var status: bool = true;
    const all_attacks = chess.getAllAttackMask(p_state, chess.invertColor(turn));
    //const checks: squarel.checkContainer = squarel.convertBitBoardtoCheckContainer(all_attacks & p_state.getKingBB(turn));
    for (0..move_list.len) |i| {
        status = try p_state.makeMove(move_list.moves[i]);
        if (!status) {
            std.debug.print("[DEBUG] From filterMoveLegal: invalid status found: {}\n\n", .{move_list.moves[i]});
            chess.print_board(p_state);
        }
        if (p_state.isLegalM(turn, move_list.moves[i], all_attacks)) {
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
    const all_attacks = chess.getAllAttackMask(p_state, chess.invertColor(turn));

    const kingSqInfo = squareInfo.init(@enumFromInt(p_state.getKingSq(turn)));
    const checks: squarel.checkContainer = squarel.convertBitBoardtoCheckContainer(chess.getAllAttackMaskFromKing(p_state, turn));
    linePieceBB = cached[0];
    diagPieceBB = cached[1];
    for (0..move_list.len) |i| {
        if (move_list.moves[i].isCastle()) {
            if (chess.isCastleLegalPreMove(p_state, turn, move_list.moves[i], all_attacks)) {
                _ = ret.append(move_list.moves[i]);
            }
        } else if (p_state.isLegalFast(all_attacks, move_list.moves[i], &kingSqInfo, &checks, diagPieceBB, linePieceBB)) {
            _ = ret.append(move_list.moves[i]);
        }
    }

    return ret;
}

pub fn getCachedAttackingPiece(p_state: *Board_state, turn: e_color) [2]u64 {
    // [linePieceBB, diagPieceBB];
    var ret = [_]u64{ chess.EMPTY, chess.EMPTY };
    if (turn == e_color.WHITE) {
        ret[0] = (p_state.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
        ret[1] = (p_state.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
    } else {
        ret[0] = (p_state.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
        ret[1] = (p_state.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
    }
    return ret;
}

pub fn moveGenPawnBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime color == .WHITE) {
        p_out.pawnMoves |= (p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] << 8) & (~p_board.occupiedBB);
        p_out.doubleMoves |= ((p_out.pawnMoves << 8) & (~p_board.occupiedBB)) & ((p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] & chess.whitePawnDoubleRank) << 16);
        //std.debug.print("[DEBUG] moveGenPawnBB turn .WHITE: pawn/(2nd advance) / (check rank)\n", .{});
        //chess.print_bitboard(p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)]);
        //chess.print_bitboard(((p_out.pawnMoves << 8) & (~p_board.occupiedBB)));
        //chess.print_bitboard(((p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn) & chess.whitePawnDoubleRank]) << 16));

        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] & chess.notAFile) << 7);
        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] & chess.notHFile) << 9);
        p_out.enPassantMoves = p_out.pawnAttacks & p_board.enPassantBB[@intFromEnum(e_color.WHITE)];

        p_out.pawnAttacks &= (p_out.pawnAttacks & (emptyOrEnemy & p_board.occupiedBB));

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.whitePawnPromoRank);
        p_out.pawnAttacks &= ~chess.whitePawnPromoRank;
        p_out.pawnMoves &= ~chess.whitePawnPromoRank;
    } else {
        p_out.pawnMoves |= (p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] << 8) & (~p_board.occupiedBB);
        p_out.doubleMoves |= ((p_out.pawnMoves >> 8) & (~p_board.occupiedBB)) & ((p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] & chess.blackPawnDoubleRank) >> 16);

        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] & chess.notHFile) >> 7);
        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] & chess.notAFile) >> 9);

        p_out.enPassantMoves = p_out.pawnAttacks & p_board.enPassantBB[@intFromEnum(e_color.BLACK)];

        p_out.pawnAttacks &= (p_out.pawnAttacks & (emptyOrEnemy & p_board.occupiedBB));

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.blackPawnPromoRank);
        p_out.pawnAttacks &= ~chess.blackPawnPromoRank;
        p_out.pawnMoves &= ~chess.blackPawnPromoRank;
    }
}

pub fn moveGenKnightBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime color == .WHITE) {
        p_out.knightMoves |= (chess.knightAttacks(p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)])) & emptyOrEnemy;
    } else {
        p_out.knightMoves |= (chess.knightAttacks(p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)])) & emptyOrEnemy;
    }
}

pub fn moveGenKingBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime color == .WHITE) {
        p_out.kingMoves |= cachedTables.KingAttack[@intCast(p_board.cstgetKingSq(.WHITE))] & emptyOrEnemy;
        const kingBB = p_board.getKingBB(.WHITE);
        p_out.queenSideCastlingMoves |= p_board.castlingBB & (kingBB >> 2);
        p_out.kingSideCastlingMoves |= p_board.castlingBB & (kingBB << 2);
        // still need castling moves here
    } else {
        p_out.kingMoves |= cachedTables.KingAttack[@intCast(p_board.cstgetKingSq(.BLACK))] & emptyOrEnemy;
        const kingBB = p_board.getKingBB(.BLACK);
        p_out.queenSideCastlingMoves |= p_board.castlingBB & (kingBB >> 2);
        p_out.kingSideCastlingMoves |= p_board.castlingBB & (kingBB << 2);
    }
}
pub fn moveGenBishopBB(p_board: *Board_state, p_magicTable: *magicRecord, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime color == .WHITE) {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.bishopMoves = magicl.getBishopMoves(p_magicTable, @enumFromInt(sq), p_board.occupiedBB);
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.bishopMoves &= emptyOrEnemy;
    } else {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.bishopMoves = magicl.getBishopMoves(p_magicTable, @enumFromInt(sq), p_board.occupiedBB);
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.bishopMoves &= emptyOrEnemy;
    }
}
pub fn moveGenRookBB(p_board: *Board_state, p_magicTable: *magicRecord, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime color == .WHITE) {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.rookMoves = magicl.getRookMoves(p_magicTable, @enumFromInt(sq), p_board.occupiedBB);
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.rookMoves &= emptyOrEnemy;
    } else {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.rookMoves = magicl.getRookMoves(p_magicTable, @enumFromInt(sq), p_board.occupiedBB) & emptyOrEnemy;
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.rookMoves &= emptyOrEnemy;
    }
}

pub fn moveGenQueenBB(p_board: *Board_state, p_magicTable: *magicRecord, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime color == .WHITE) {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.queenMoves = magicl.getRookMoves(p_magicTable, @enumFromInt(sq), p_board.occupiedBB);
            p_out.queenMoves |= magicl.getBishopMoves(p_magicTable, @enumFromInt(sq), p_board.occupiedBB);
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.queenMoves &= emptyOrEnemy;
    } else {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.queenMoves = magicl.getRookMoves(p_magicTable, @enumFromInt(sq), p_board.occupiedBB);
            p_out.queenMoves |= magicl.getBishopMoves(p_magicTable, @enumFromInt(sq), p_board.occupiedBB);
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.queenMoves &= emptyOrEnemy;
    }
}

pub fn moveGenBBWhite(p_board: *Board_state, p_magicTable: *magicRecord) moveBBState {
    var ret: moveBBState = .{};
    const EmptyOrEnemy = ~p_board.c_occupiedBB[@intFromEnum(e_color.WHITE)];
    moveGenPawnBB(p_board, .WHITE, EmptyOrEnemy, &ret);
    moveGenKnightBB(p_board, .WHITE, EmptyOrEnemy, &ret);
    moveGenBishopBB(p_board, p_magicTable, .WHITE, EmptyOrEnemy, &ret);
    moveGenRookBB(p_board, p_magicTable, .WHITE, EmptyOrEnemy, &ret);
    moveGenQueenBB(p_board, p_magicTable, .WHITE, EmptyOrEnemy, &ret);
    moveGenKingBB(p_board, .WHITE, EmptyOrEnemy, &ret);
    return ret;
}

pub fn moveGenBBBlack(p_board: *Board_state, p_magicTable: *magicRecord) moveBBState {
    var ret: moveBBState = .{};
    const EmptyOrEnemy = ~p_board.c_occupiedBB[@intFromEnum(e_color.BLACK)];
    moveGenPawnBB(p_board, .BLACK, EmptyOrEnemy, &ret);
    moveGenKnightBB(p_board, .BLACK, EmptyOrEnemy, &ret);
    moveGenBishopBB(p_board, p_magicTable, .BLACK, EmptyOrEnemy, &ret);
    moveGenRookBB(p_board, p_magicTable, .BLACK, EmptyOrEnemy, &ret);
    moveGenQueenBB(p_board, p_magicTable, .BLACK, EmptyOrEnemy, &ret);
    moveGenKingBB(p_board, .BLACK, EmptyOrEnemy, &ret);
    return ret;
}

pub fn moveGenBB(p_board: *Board_state) moveBBState {
    if (p_board.turn == .WHITE) {
        return moveGenBBWhite(p_board, &magicl.magicTable);
    }
    return moveGenBBBlack(p_board, &magicl.magicTable);
}
