const chess = @import("chess.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");

const std = @import("std");

const typedMoveContainer = movel.typedMoveContainer;
const moveContainer = movel.moveContainer;
const IMove = movel.IMove;

const squareInfo = squarel.squareInfo;
const e_square = squarel.e_square;

const e_piece = chess.e_piece;
const e_color = chess.e_color;
const e_moveFlags = movel.e_moveFlags;
const e_moveCategory = movel.e_moveCategory;

const Board_state = chess.Board_state;

//pub fn moveGeneration(p_board: *Board_state) !moveContainer {
//    // Generates all the moves from the given board state
//
//    var ret: moveContainer = .{};
//
//    var color_offset: u8 = @intFromEnum(e_piece.nWhite);
//    if (p_board.turn == e_color.BLACK) {
//        color_offset = @intFromEnum(e_piece.nBlack);
//    }
//    var bb: u64 = 0;
//    var piece: e_piece = e_piece.nEmptySquare;
//    var piece_idx: u8 = 0;
//    // TODO Unroll the loop
//    for (1..chess.N_PIECES_TYPES + 1) |piece_index| {
//        piece_idx = @intCast(piece_index + color_offset);
//        piece = @enumFromInt(piece_idx);
//        bb = p_board.pieceBB[piece_idx];
//
//        if ((piece == e_piece.nWhitePawn) or (piece == e_piece.nBlackPawn)) {
//            _PieceMovePawnMask(p_board, bb, &p_board.attackMask, p_board.turn, &ret);
//        } else if ((piece == e_piece.nWhiteKnight) or (piece == e_piece.nBlackKnight)) {
//            _PieceMoveKnightMask(p_board, bb, &ret);
//        } else if ((piece == e_piece.nWhiteKing) or (piece == e_piece.nBlackKing)) {
//            _PieceMoveKingMask(p_board, bb, &p_board.attackMask, &ret);
//        } else if ((piece == e_piece.nWhiteBishop) or (piece == e_piece.nBlackBishop)) {
//            _PieceMoveBishopMask(p_board, bb, &ret);
//        } else if ((piece == e_piece.nWhiteRook) or (piece == e_piece.nBlackRook)) {
//            _PieceMoveRookMask(p_board, bb, &ret);
//        } else if ((piece == e_piece.nWhiteQueen) or (piece == e_piece.nBlackQueen)) {
//            _PieceMoveQueenMask(p_board, bb, &ret);
//        } else {
//            @panic("Unknown piece found in move generation");
//        }
//        //std.debug.print("[DEBUG] moveGeneration: Generated {} move(s) for piece: {}\n", .{ _curr_arr.items.len, piece });
//    }
//    //_ = p_board.c_occupiedBB;
//    return ret;
//}

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
    white_PieceMovePawnMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)], &p_board.attackMask, &ret);

    _PieceMoveKnightMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)], &ret, e_color.WHITE, emptyOrEnemy);

    _PieceMoveKingMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteKing)], &p_board.attackMask, &ret, e_color.WHITE, emptyOrEnemy);

    _PieceMoveBishopMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)], &ret, e_color.WHITE, emptyOrEnemy);

    _PieceMoveRookMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)], &ret, e_color.WHITE, emptyOrEnemy);

    _PieceMoveQueenMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)], &ret, e_color.WHITE, emptyOrEnemy);

    //std.debug.print("[DEBUG] white_moveGeneration: \n", .{});
    //ret.print();

    return ret;
}
pub fn black_moveGeneration(p_board: *Board_state) moveContainer {
    // Generates all the moves from the given board state

    var ret: moveContainer = .{};

    const emptyOrEnemy = ~p_board.c_occupiedBB[@intFromEnum(e_color.BLACK)];

    black_PieceMovePawnMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)], &p_board.attackMask, &ret);

    _PieceMoveKnightMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)], &ret, e_color.BLACK, emptyOrEnemy);

    _PieceMoveKingMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackKing)], &p_board.attackMask, &ret, e_color.BLACK, emptyOrEnemy);

    _PieceMoveBishopMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)], &ret, e_color.BLACK, emptyOrEnemy);

    _PieceMoveRookMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)], &ret, e_color.BLACK, emptyOrEnemy);

    _PieceMoveQueenMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)], &ret, e_color.BLACK, emptyOrEnemy);
    return ret;
}
pub fn moveBitBoardToIMove_pawn(p_board: *Board_state, piece: e_piece, piece_bb: u64, attack_bb: u64, flags: u6, p_out: *moveContainer, comptime turn: e_color) void {
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

pub fn white_PieceMovePawnMask(p_board: *Board_state, bb_piece: u64, p_attack_mask: *chess.Attack_masks, p_out: *moveContainer) void {
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
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (p_attack_mask.SimplePawnAttack[@intFromEnum(e_color.WHITE)][@intCast(sq)] & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, e_color.WHITE);
            _bb_piece ^= curr_pos;
            continue;
        }

        if (sqRank == 1 and ((singlePushBB & freeBB)) != 0) {
            moveBitBoardToIMove_pawn(p_board, piece, curr_pos, ((singlePushBB) << 8) & (freeBB), @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, e_color.WHITE);
        }
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB & freeBB), 0, p_out, e_color.WHITE);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (p_attack_mask.SimplePawnAttack[@intFromEnum(e_color.WHITE)][@intCast(sq)] & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, e_color.WHITE);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (p_attack_mask.SimplePawnAttack[@intFromEnum(e_color.WHITE)][@intCast(sq)] & p_board.enPassantBB[@intFromEnum(op_color)] & (freeBB)), @intFromEnum(e_moveFlags.ENPASSANT), p_out, e_color.WHITE);
        _bb_piece ^= curr_pos;
    }
    return;
}

pub fn black_PieceMovePawnMask(p_board: *Board_state, bb_piece: u64, p_attack_mask: *chess.Attack_masks, p_out: *moveContainer) void {
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
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (p_attack_mask.SimplePawnAttack[@intFromEnum(e_color.BLACK)][@intCast(sq)] & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, e_color.BLACK);
            _bb_piece ^= curr_pos;
            continue;
        }

        if (sqRank == 6 and ((singlePushBB & freeBB)) != 0) {
            moveBitBoardToIMove_pawn(p_board, piece, curr_pos, ((singlePushBB) >> 8) & (freeBB), @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, e_color.BLACK);
        }
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB & freeBB), 0, p_out, e_color.BLACK);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (p_attack_mask.SimplePawnAttack[@intFromEnum(e_color.BLACK)][@intCast(sq)] & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, e_color.BLACK);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (p_attack_mask.SimplePawnAttack[@intFromEnum(e_color.BLACK)][@intCast(sq)] & p_board.enPassantBB[@intFromEnum(op_color)] & (freeBB)), @intFromEnum(e_moveFlags.ENPASSANT), p_out, e_color.BLACK);

        _bb_piece ^= curr_pos;
    }
    return;
}

pub fn _PieceMoveKnightMask(p_board: *Board_state, bb_piece: u64, p_out: *moveContainer, comptime turn: e_color, emptyOrEnemy: u64) void {
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

pub fn _PieceMoveBishopMask(p_board: *Board_state, bb_piece: u64, p_out: *moveContainer, comptime turn: e_color, emptyOrEnemy: u64) void {
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

pub fn _PieceMoveRookMask(p_board: *Board_state, bb_piece: u64, p_out: *moveContainer, comptime turn: e_color, emptyOrEnemy: u64) void {
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

pub fn _PieceMoveQueenMask(p_board: *Board_state, bb_piece: u64, p_out: *moveContainer, comptime turn: e_color, emptyOrEnemy: u64) void {
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

pub fn _PieceMoveKingMask(p_board: *Board_state, bb_piece: u64, p_attack_mask: *chess.Attack_masks, p_out: *moveContainer, comptime turn: e_color, emptyOrEnemy: u64) void {
    var piece = e_piece.nWhiteKing;
    var color = e_color.WHITE;
    if (comptime turn == e_color.BLACK) {
        piece = e_piece.nBlackKing;
        color = e_color.BLACK;
    }
    const sq = p_board.getKingSq(turn);
    const att_mask = p_attack_mask.KingAttack[@intCast(sq)] & emptyOrEnemy;

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
    const all_attacks = chess.getAllAttackMask(p_state, &p_state.attackMask, chess.invertColor(turn));
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
    const all_attacks = chess.getAllAttackMask(p_state, &p_state.attackMask, chess.invertColor(turn));
    //const allAttackingChecks = chess.getAllAttackingChecksMask(p_state, &p_state.attackMask, chess.invertColor(turn));
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
