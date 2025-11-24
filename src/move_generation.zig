const build_options = @import("build_options");

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

const fastBitscan = build_options.fastBitscan;
const ignoreChecks = build_options.fastBitscan;
const useMagic = build_options.useMagic;
const useStaged = build_options.useStaged;

pub fn generateLegalMoves(p_board: *Board_state) moveContainer {
    if (comptime useStaged) {
        return moveGenStaged(p_board);
    } else {
        var moves: moveContainer = moveGeneration(p_board);
        const fmoves = filterMoveLegalFast(p_board, &moves) catch unreachable;
        return fmoves;
    }
}

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

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.WHITE)][@intCast(sq)] & p_board.enPassantBB & chess.whitePawnEnpassantRank & (freeBB)), @intFromEnum(e_moveFlags.ENPASSANT), p_out, e_color.WHITE);
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

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.BLACK)][@intCast(sq)] & p_board.enPassantBB & freeBB & chess.blackPawnEnpassantRank), @intFromEnum(e_moveFlags.ENPASSANT), p_out, e_color.BLACK);

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
    // goal compared to filterMoveLegal: try to not use the make/undo Moves methods
    var ret: moveContainer = .{};
    const turn: e_color = p_state.turn;
    const cached = getCachedAttackingPiece(p_state, turn);
    const all_attacks = chess.getAllAttackMask(p_state, chess.invertColor(turn));

    const kingSqInfo = squareInfo.init(@enumFromInt(p_state.getKingSq(turn)));
    const checks: squarel.checkContainer = squarel.convertBitBoardtoCheckContainer(chess.getAllAttackMaskFromKing(p_state, turn));
    const linePieceBB = cached[0];
    const diagPieceBB = cached[1];
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
        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] & chess.notAFile) << 7);
        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] & chess.notHFile) << 9);
        p_out.enPassantMoves = p_out.pawnAttacks & p_board.enPassantBB & chess.whitePawnEnpassantRank;

        p_out.pawnAttacks &= (p_out.pawnAttacks & (emptyOrEnemy & p_board.occupiedBB));

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.whitePawnPromoRank);
        p_out.pawnAttacks &= ~chess.whitePawnPromoRank;
        p_out.pawnMoves &= ~chess.whitePawnPromoRank;
    } else {
        p_out.pawnMoves |= (p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] << 8) & (~p_board.occupiedBB);
        p_out.doubleMoves |= ((p_out.pawnMoves >> 8) & (~p_board.occupiedBB)) & ((p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] & chess.blackPawnDoubleRank) >> 16);

        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] & chess.notHFile) >> 7);
        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] & chess.notAFile) >> 9);

        p_out.enPassantMoves = p_out.pawnAttacks & p_board.enPassantBB & chess.blackPawnEnpassantRank;

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
pub fn moveGenBishopBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime color == .WHITE) {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.bishopMoves = chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.bishopMoves &= emptyOrEnemy;
    } else {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.bishopMoves = chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.bishopMoves &= emptyOrEnemy;
    }
}
pub fn moveGenRookBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime color == .WHITE) {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.rookMoves = chess.getRookAttacks(p_board.occupiedBB, @intFromEnum(sq));
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.rookMoves &= emptyOrEnemy;
    } else {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.rookMoves = chess.getRookAttacks(p_board.occupiedBB, @intFromEnum(sq));
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.rookMoves &= emptyOrEnemy;
    }
}

pub fn moveGenQueenBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime color == .WHITE) {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.queenMoves = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(sq));
            p_out.queenMoves |= chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.queenMoves &= emptyOrEnemy;
    } else {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            p_out.queenMoves = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(sq));
            p_out.queenMoves |= chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
            _bb ^= (chess.ONE << @intCast(sq));
        }
        p_out.queenMoves &= emptyOrEnemy;
    }
}

pub fn moveGenBBWhite(p_board: *Board_state) moveBBState {
    var ret: moveBBState = .{};
    const EmptyOrEnemy = ~p_board.c_occupiedBB[@intFromEnum(e_color.WHITE)];
    moveGenPawnBB(p_board, .WHITE, EmptyOrEnemy, &ret);
    moveGenKnightBB(p_board, .WHITE, EmptyOrEnemy, &ret);
    moveGenBishopBB(p_board, .WHITE, EmptyOrEnemy, &ret);
    moveGenRookBB(p_board, .WHITE, EmptyOrEnemy, &ret);
    moveGenQueenBB(p_board, .WHITE, EmptyOrEnemy, &ret);
    moveGenKingBB(p_board, .WHITE, EmptyOrEnemy, &ret);
    return ret;
}

pub fn moveGenBBBlack(p_board: *Board_state) moveBBState {
    var ret: moveBBState = .{};
    const EmptyOrEnemy = ~p_board.c_occupiedBB[@intFromEnum(e_color.BLACK)];
    moveGenPawnBB(p_board, .BLACK, EmptyOrEnemy, &ret);
    moveGenKnightBB(p_board, .BLACK, EmptyOrEnemy, &ret);
    moveGenBishopBB(p_board, .BLACK, EmptyOrEnemy, &ret);
    moveGenRookBB(p_board, .BLACK, EmptyOrEnemy, &ret);
    moveGenQueenBB(p_board, .BLACK, EmptyOrEnemy, &ret);
    moveGenKingBB(p_board, .BLACK, EmptyOrEnemy, &ret);
    return ret;
}

pub fn moveGenBB(p_board: *Board_state) moveBBState {
    if (p_board.turn == .WHITE) {
        return moveGenBBWhite(p_board);
    }
    return moveGenBBBlack(p_board);
}

pub fn cstMoveGenBB(p_board: *Board_state, comptime turn: e_color) moveBBState {
    if (comptime turn == .WHITE) {
        return moveGenBBWhite(p_board);
    }
    return moveGenBBBlack(p_board);
}

pub fn filterBBStateCheckers(p_bbstate: *moveBBState, checkers: u64, turn: e_color) void {
    if (turn == .WHITE) {
        p_bbstate.enPassantMoves >>= 8;
        p_bbstate.andEq(checkers);
        p_bbstate.enPassantMoves <<= 8;
    } else {
        p_bbstate.enPassantMoves <<= 8;
        p_bbstate.andEq(checkers);
        p_bbstate.enPassantMoves >>= 8;
    }
    return;
}

pub fn moveGenStagedBB(p_board: *Board_state) moveBBState {
    // will generate a already full legal move set of BBState
    // only caveat, pinned from sq cannot be checked right now
    // this is done with the converted moveContainer afterwards

    var ret: moveBBState = moveGenBB(p_board);
    const is_checked: bool = (p_board.checkersBB != chess.EMPTY);
    const all_attacks = chess.getAllAttackMaskXrayKing(p_board, chess.invertColor(p_board.turn));
    if (is_checked) {
        if (chess.p_popcount(p_board.checkersBB & p_board.occupiedBB) > 1) {
            const kingMoveBB = ret.kingMoves;
            ret.resetAll();
            ret.kingMoves = kingMoveBB;
        } else {
            ret.kingSideCastlingMoves = chess.EMPTY;
            ret.queenSideCastlingMoves = chess.EMPTY;
            filterBBStateCheckers(&ret, p_board.checkers, all_attacks);
        }
    } else {
        checkCastlingLegality(p_board, all_attacks);
    }
    ret.kingMoves = ret.kingMoves & (~all_attacks);

    return ret;
}
pub fn checkCastlingLegality(p_board: *Board_state, p_allMovesBB: *moveBBState, all_attacks: u64) void {
    const homeRow = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(p_board.getKingSq(p_board.turn)));
    const kingBB = p_board.getKingBB(p_board.turn);
    const freeBB = ~all_attacks;
    if (p_allMovesBB.kingSideCastlingMoves != chess.EMPTY) {
        p_allMovesBB.kingSideCastlingMoves &= homeRow;
        var movingWindow = (freeBB & kingBB) << 1;
        movingWindow = (movingWindow & freeBB) << 1;
        movingWindow &= freeBB;
        p_allMovesBB.kingSideCastlingMoves &= movingWindow;
    }

    if (p_allMovesBB.queenSideCastlingMoves != chess.EMPTY) {
        p_allMovesBB.queenSideCastlingMoves &= homeRow;
        var movingWindow = (freeBB & kingBB) >> 1;
        movingWindow = (movingWindow & freeBB) >> 1;
        movingWindow &= freeBB;
        p_allMovesBB.queenSideCastlingMoves &= movingWindow;
    }
}

pub fn cmptim_moveGenStaged(p_board: *Board_state, p_allMovesBB: moveBBState, comptime turn: e_color, p_out: *moveContainer) void {
    if (comptime turn == .WHITE) {
        if (p_allMovesBB.pawnMoves != chess.EMPTY) {
            moveBBStateToIMove_pawn(p_board, p_allMovesBB, .WHITE, .QUIET, p_out);
            moveBBStateToIMove_pawn(p_board, p_allMovesBB, .WHITE, .CAPTURE, p_out);
        }
        if (p_allMovesBB.bishopMoves != chess.EMPTY) {
            moveBBStateToIMove_bishop(p_board, p_allMovesBB.bishopMoves, .WHITE, .QUIET, p_out);
            moveBBStateToIMove_bishop(p_board, p_allMovesBB.bishopMoves, .WHITE, .CAPTURE, p_out);
        }
        if (p_allMovesBB.knightMoves != chess.EMPTY) {
            moveBBStateToIMove_knight(p_board, p_allMovesBB.knightMoves, .WHITE, .QUIET, p_out);
            moveBBStateToIMove_knight(p_board, p_allMovesBB.knightMoves, .WHITE, .CAPTURE, p_out);
        }
        if (p_allMovesBB.rookMoves != chess.EMPTY) {
            moveBBStateToIMove_rook(p_board, p_allMovesBB.rookMoves, .WHITE, .QUIET, p_out);
            moveBBStateToIMove_rook(p_board, p_allMovesBB.rookMoves, .WHITE, .CAPTURE, p_out);
        }
        if (p_allMovesBB.queenMoves != chess.EMPTY) {
            moveBBStateToIMove_queen(p_board, p_allMovesBB.queenMoves, .WHITE, .QUIET, p_out);
            moveBBStateToIMove_queen(p_board, p_allMovesBB.queenMoves, .WHITE, .CAPTURE, p_out);
        }
        if (p_allMovesBB.kingMoves != chess.EMPTY) {
            moveBBStateToIMove_king(p_board, p_allMovesBB.bishopMoves, .WHITE, .QUIET, p_out);
            moveBBStateToIMove_king(p_board, p_allMovesBB.bishopMoves, .WHITE, .CAPTURE, p_out);
        }
    } else {
        if (p_allMovesBB.pawnMoves != chess.EMPTY) {
            moveBBStateToIMove_pawn(p_board, p_allMovesBB, .BLACK, .QUIET, p_out);
            moveBBStateToIMove_pawn(p_board, p_allMovesBB, .BLACK, .CAPTURE, p_out);
        }
        if (p_allMovesBB.bishopMoves != chess.EMPTY) {
            moveBBStateToIMove_bishop(p_board, p_allMovesBB.bishopMoves, .BLACK, .QUIET, p_out);
            moveBBStateToIMove_bishop(p_board, p_allMovesBB.bishopMoves, .BLACK, .CAPTURE, p_out);
        }
        if (p_allMovesBB.knightMoves != chess.EMPTY) {
            moveBBStateToIMove_knight(p_board, p_allMovesBB.knightMoves, .BLACK, .QUIET, p_out);
            moveBBStateToIMove_knight(p_board, p_allMovesBB.knightMoves, .BLACK, .CAPTURE, p_out);
        }
        if (p_allMovesBB.rookMoves != chess.EMPTY) {
            moveBBStateToIMove_rook(p_board, p_allMovesBB.rookMoves, .BLACK, .QUIET, p_out);
            moveBBStateToIMove_rook(p_board, p_allMovesBB.rookMoves, .BLACK, .CAPTURE, p_out);
        }
        if (p_allMovesBB.queenMoves != chess.EMPTY) {
            moveBBStateToIMove_queen(p_board, p_allMovesBB.queenMoves, .BLACK, .QUIET, p_out);
            moveBBStateToIMove_queen(p_board, p_allMovesBB.queenMoves, .BLACK, .CAPTURE, p_out);
        }
        if (p_allMovesBB.kingMoves != chess.EMPTY) {
            moveBBStateToIMove_king(p_board, p_allMovesBB.bishopMoves, .BLACK, .QUIET, p_out);
            moveBBStateToIMove_king(p_board, p_allMovesBB.bishopMoves, .BLACK, .CAPTURE, p_out);
        }
    }
}

pub fn moveGenStaged(p_board: *Board_state) moveContainer {
    const allMovesBB = moveGenStagedBB(p_board);
    if (p_board.turn == .WHITE) {
        const retContainer: moveContainer = .{};
        cmptim_moveGenStaged(p_board, &allMovesBB, .WHITE, &retContainer);
        //const kingSqInfo: squareInfo = squareInfo.init(p_board.getKingSq(.WHITE));

        // filter for pin
        return filterPinnedMoveContainer(p_board, .WHITE, &retContainer);
    } else {
        const retContainer: moveContainer = .{};
        cmptim_moveGenStaged(p_board, &allMovesBB, .BLACK, &retContainer);
        //const kingSqInfo: squareInfo = squareInfo.init(p_board.getKingSq(.BLACK));

        // filter for pin
        return filterPinnedMoveContainer(p_board, .BLACK, &retContainer);
    }
}

pub fn filterPinnedMoveContainer(p_board: *Board_state, comptime turn: e_color, p_container: *moveContainer) moveContainer {
    var ret: moveContainer = .{};
    var kingSqInfo: squareInfo = undefined;
    if (comptime turn == .WHITE) {
        kingSqInfo = squareInfo.init(p_board.getKingSq(.WHITE));
    } else {
        kingSqInfo = squareInfo.init(p_board.getKingSq(.BLACK));
    }
    const kingThreatSquare = kingSqInfo.visibilitySquares();
    for (0..p_container.len) |i| {
        const move: IMove = p_container.moves[i];
        const from = move.getFrom();
        const from_E: e_square = @enumFromInt(from);
        const fromInfo: squareInfo = squareInfo.init(from_E);
        const fromBB = chess.ONE << @intCast(from);
        const toBB = chess.ONE << @intCast(move.getTo());
        const newOcc = (p_board.occupiedBB ^ fromBB) | toBB;
        const overlap = kingThreatSquare & fromInfo.visibilitySquares();
        var relevantAtt: u64 = undefined;
        if (comptime turn == .WHITE) {
            relevantAtt = chess.getRookAttacks(newOcc, from_E) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
            relevantAtt |= chess.getBishopAttacks(newOcc, from_E) & (p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
        } else {
            relevantAtt = chess.getRookAttacks(newOcc, from_E) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
            relevantAtt |= chess.getBishopAttacks(newOcc, from_E) & (p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
        }
        relevantAtt &= overlap;
        if (relevantAtt == chess.EMPTY) {
            ret.append(move);
        }
    }
    return ret;
}

pub fn moveBBStateToIMove_pawn(p_board: *Board_state, p_state: *moveBBState, comptime turn: e_color, comptime flag: e_moveCategory, p_out: *moveContainer) void {
    if (comptime flag == .QUIET) {
        moveBBStateToIMove_QuietPawn(p_state.pawnMoves, turn, p_out);
        moveBBStateToIMove_Doublepawn(p_state.doubleMoves, turn, p_out);
        moveBBStateToIMove_PromotionPawn(p_state.promotionMoves & (~p_board.occupiedBB), turn, .QUIETMOVE, p_out);
        return;
    } else if (comptime flag == .CAPTURE) {
        moveBBStateToIMove_CapturePawn(p_board, p_state.pawnAttacks, turn, p_out);
        moveBBStateToIMove_PromotionPawn(p_state.promotionMoves & (p_board.occupiedBB), turn, .CAPTURE, p_out);
        moveBBStateToIMove_Enpassantpawn(p_board, p_state.enPassantMoves, turn, p_out);
        return;
    } else {
        @panic("Only .QUIETMOVE and .CAPTURE are allowed");
    }
}

pub fn moveBBStateToIMove_Enpassantpawn(p_board: *Board_state, bb: u64, comptime turn: e_color, p_out: *moveContainer) void {
    if (bb == chess.EMPTY) {
        return;
    }
    var fromBB: u64 = undefined;
    var fromPiece: e_piece = undefined;
    var toPiece: e_piece = undefined;
    if (comptime turn == .WHITE) {
        fromBB = (bb >> 7 | bb >> 9) & p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)];
        fromPiece = .nWhitePawn;
        toPiece = .nBlackPawn;
    } else {
        fromBB = (bb << 7 | bb << 9) & p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)];
        fromPiece = .nBlackPawn;
        toPiece = .nWhitePawn;
    }
    const toSq = chess.bitscan(bb);
    while (fromBB != chess.EMPTY) {
        const fromSq = chess.Bitscan(fromBB);
        fromBB ^= chess.ONE << @intCast(fromSq);
        const move = movel.build_move(@intCast(fromSq), @intCast(toSq), e_moveFlags.ENPASSANT, fromPiece);
        move.setCapture(toPiece);
        p_out.append(move);
    }
}
pub fn moveBBStateToIMove_Doublepawn(bb: u64, comptime turn: e_color, p_out: *moveContainer) void {
    if (bb == chess.EMPTY) {
        return;
    }
    var _bb: u64 = bb;
    if (comptime turn == .WHITE) {
        while (_bb != chess.EMPTY) {
            const toSq = chess.Bitscan(_bb);
            const fromSq = toSq - 16;
            _bb ^= chess.ONE << @intCast(fromSq);
            const move = movel.build_move(@intCast(fromSq), @intCast(toSq), e_moveFlags.DOUBLEPAWN, .nWhitePawn);
            move.setCapture(.nBlackPawn);
            p_out.append(move);
        }
    } else {
        while (_bb != chess.EMPTY) {
            const toSq = chess.Bitscan(_bb);
            const fromSq = toSq + 16;
            _bb ^= toSq;
            const move = movel.build_move(@intCast(fromSq), @intCast(toSq), e_moveFlags.DOUBLEPAWN, .nWhitePawn);
            move.setCapture(.nBlackPawn);
            p_out.append(move);
        }
    }
}
pub fn moveBBStateToIMove_QuietPawn(bb: u64, comptime turn: e_color, p_out: *moveContainer) void {
    if (bb == chess.EMPTY) {
        return;
    }
    var _bb: u64 = bb;
    if (comptime turn == .WHITE) {
        while (_bb != chess.EMPTY) {
            const toSq = chess.Bitscan(_bb);
            _bb ^= chess.ONE << @intCast(toSq);
            const fromSq = toSq - 8;
            const move = movel.build_move(@intCast(fromSq), @intCast(toSq), e_moveFlags.QUIETMOVE, .nWhitePawn);
            p_out.append(move);
        }
    } else {
        while (_bb != chess.EMPTY) {
            const toSq = chess.Bitscan(_bb);
            _bb ^= chess.ONE << @intCast(toSq);
            const fromSq = toSq + 8;
            const move = movel.build_move(@intCast(fromSq), @intCast(toSq), e_moveFlags.QUIETMOVE, .nWhitePawn);
            p_out.append(move);
        }
    }
}

pub fn moveBBStateToIMove_CapturePawn(p_board: *Board_state, bb: u64, comptime turn: e_color, p_out: *moveContainer) void {
    if (bb == chess.EMPTY) {
        return;
    }
    if (comptime turn == .WHITE) {
        var fromBB = p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)];
        while (fromBB != chess.EMPTY) {
            const _currentSq = chess.Bitscan(fromBB);
            const _currentBB = chess.ONE << @intCast(_currentSq);
            fromBB ^= _currentBB;
            genericCaptureMoveBBToIMove(p_board, _currentSq, bb & ((_currentBB << 7) | (_currentBB << 9)), .CAPTURE, .nWhitePawn, p_out);
        }
    } else {
        var fromBB = p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)];
        while (fromBB != chess.EMPTY) {
            const _currentSq = chess.Bitscan(fromBB);
            const _currentBB = chess.ONE << @intCast(_currentSq);
            fromBB ^= _currentBB;
            genericCaptureMoveBBToIMove(p_board, _currentSq, bb & ((_currentBB >> 7) | (_currentBB >> 9)), .CAPTURE, .nBlackPawn, p_out);
        }
    }
}

pub fn moveBBStateToIMove_PromotionPawn(p_board: *Board_state, bb: u64, comptime turn: e_color, comptime flag: e_moveFlags, p_out: *moveContainer) void {
    if (bb == chess.EMPTY) {
        return;
    }
    if (comptime turn == .WHITE) {
        var fromBB = p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)];
        while (fromBB != chess.EMPTY) {
            const _currentSq = chess.Bitscan(fromBB);
            const _currentBB = chess.ONE << @intCast(_currentSq);
            fromBB ^= _currentBB;
            if (comptime flag == .CAPTURE) {
                capturePromoMoveBBToIMove(p_board, _currentSq, bb & ((_currentBB << 7) | (_currentBB << 9)), .nWhitePawn, p_out);
            } else {
                quietPromoMoveBBToIMove(_currentSq, bb & (_currentBB << 8), .nWhitePawn, p_out);
            }
        }
    } else {
        var fromBB = p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)];
        while (fromBB != chess.EMPTY) {
            const _currentSq = chess.Bitscan(fromBB);
            const _currentBB = chess.ONE << @intCast(_currentSq);
            fromBB ^= _currentBB;
            if (comptime flag == .CAPTURE) {
                capturePromoMoveBBToIMove(p_board, _currentSq, bb & ((_currentBB >> 7) | (_currentBB >> 9)), .nBlackPawn, p_out);
            } else {
                quietPromoMoveBBToIMove(_currentSq, bb & (_currentBB >> 8), .nBlackPawn, p_out);
            }
        }
    }
}
pub fn moveBBStateToIMove_bishop(p_board: *Board_state, moveBB: u64, comptime turn: e_color, comptime flag: e_moveCategory, p_out: *moveContainer) void {
    var piece: e_piece = .nWhiteBishop;
    if (comptime turn == .BLACK) {
        piece = .nBlackBishop;
    }
    var fromBB = p_board.pieceBB[@intFromEnum(piece)];
    while (fromBB != chess.EMPTY) {
        const currentSq = chess.bitscan(fromBB);
        fromBB ^= (chess.ONE << @intCast(currentSq));
        const curr_movesBB = chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(currentSq));
        if (comptime flag == .QUIET) {
            genericQuietMoveBBToIMove(@intCast(currentSq), moveBB & curr_movesBB, piece, p_out);
        } else {
            genericCaptureMoveBBToIMove(p_board, @intCast(currentSq), moveBB & curr_movesBB, .CAPTURE, piece, p_out);
        }
    }
}

pub fn moveBBStateToIMove_rook(p_board: *Board_state, moveBB: u64, comptime turn: e_color, comptime flag: e_moveCategory, p_out: *moveContainer) void {
    var piece: e_piece = .nWhiteRook;
    if (comptime turn == .BLACK) {
        piece = .nBlackRook;
    }
    var fromBB = p_board.pieceBB[@intFromEnum(piece)];
    while (fromBB != chess.EMPTY) {
        const currentSq = chess.bitscan(fromBB);
        fromBB ^= (chess.ONE << @intCast(currentSq));
        const curr_movesBB = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(currentSq));
        if (comptime flag == .QUIET) {
            genericQuietMoveBBToIMove(@intCast(currentSq), moveBB & curr_movesBB, piece, p_out);
        } else {
            genericCaptureMoveBBToIMove(p_board, @intCast(currentSq), moveBB & curr_movesBB, .CAPTURE, piece, p_out);
        }
    }
}

pub fn moveBBStateToIMove_knight(p_board: *Board_state, moveBB: u64, comptime turn: e_color, comptime flag: e_moveCategory, p_out: *moveContainer) void {
    var piece: e_piece = .nWhiteKnigh;
    if (comptime turn == .BLACK) {
        piece = .nBlackKnigh;
    }
    var fromBB = p_board.pieceBB[@intFromEnum(piece)];
    while (fromBB != chess.EMPTY) {
        const currentSq = chess.bitscan(fromBB);
        const knightBB = (chess.ONE << @intCast(currentSq));
        fromBB ^= knightBB;
        const curr_movesBB = chess.knightAttacks(knightBB);

        if (comptime flag == .QUIET) {
            genericQuietMoveBBToIMove(@intCast(currentSq), moveBB & curr_movesBB, piece, p_out);
        } else {
            genericCaptureMoveBBToIMove(p_board, @intCast(currentSq), moveBB & curr_movesBB, .CAPTURE, piece, p_out);
        }
    }
}
pub fn moveBBStateToIMove_queen(p_board: *Board_state, moveBB: u64, comptime turn: e_color, comptime flag: e_moveCategory, p_out: *moveContainer) void {
    var piece: e_piece = .nWhiteQueen;
    if (comptime turn == .BLACK) {
        piece = .nBlackQueen;
    }
    var fromBB = p_board.pieceBB[@intFromEnum(piece)];
    while (fromBB != chess.EMPTY) {
        const currentSq = chess.bitscan(fromBB);
        fromBB ^= (chess.ONE << @intCast(currentSq));
        var curr_movesBB = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(currentSq));
        curr_movesBB |= chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(currentSq));

        if (comptime flag == .QUIET) {
            genericQuietMoveBBToIMove(@intCast(currentSq), moveBB & curr_movesBB, piece, p_out);
        } else {
            genericCaptureMoveBBToIMove(p_board, @intCast(currentSq), moveBB & curr_movesBB, .CAPTURE, piece, p_out);
        }
    }
}

pub fn moveBBStateToIMove_king(p_board: *Board_state, moveBB: u64, comptime turn: e_color, comptime flag: e_moveCategory, p_out: *moveContainer) void {
    var piece: e_piece = .nWhiteKing;
    if (comptime turn == .BLACK) {
        piece = .nBlackKing;
    }
    const fromBB = p_board.pieceBB[@intFromEnum(piece)];
    const currentSq = chess.bitscan(fromBB);
    const curr_movesBB = chess.getKingAttacks(@enumFromInt(currentSq));

    if (comptime flag == .QUIET) {
        genericQuietMoveBBToIMove(@intCast(currentSq), moveBB & curr_movesBB, piece, p_out);
    } else {
        genericCaptureMoveBBToIMove(p_board, @intCast(currentSq), moveBB & curr_movesBB, .CAPTURE, piece, p_out);
    }
}
pub fn genericQuietMoveBBToIMove(fromSq: u8, moveBB: u64, flag: e_moveFlags, piece: e_piece, p_out: moveContainer) void {
    var _moveBB: u64 = moveBB;
    while (_moveBB != chess.EMPTY) {
        const toSq = chess.bitscan;
        _moveBB ^= chess.ONE << @intCast(toSq);
        p_out.append(movel.build_move(fromSq, @intCast(toSq), flag, piece));
    }
}

pub fn genericCaptureMoveBBToIMove(p_board: *Board_state, fromSq: u8, moveBB: u64, flag: e_moveFlags, piece: e_piece, p_out: moveContainer) void {
    var _moveBB: u64 = moveBB;
    while (_moveBB != chess.EMPTY) {
        const toSq = chess.bitscan;
        _moveBB ^= chess.ONE << @intCast(toSq);
        const move = movel.build_move(fromSq, @intCast(toSq), flag, piece);
        move.setCapture(p_board.get_piece(@intCast(toSq)));
        p_out.append(move);
    }
}

pub fn capturePromoMoveBBToIMove(p_board: *Board_state, fromSq: u8, moveBB: u64, piece: e_piece, p_out: moveContainer) void {
    var _moveBB: u64 = moveBB;
    while (_moveBB != chess.EMPTY) {
        const toSq = chess.bitscan;
        _moveBB ^= chess.ONE << @intCast(toSq);
        const cpiece = p_board.get_piece(@intCast(toSq));
        const move = movel.build_move(fromSq, @intCast(toSq), @intFromEnum(e_moveFlags.KNIGHTPROMOCAPTURE), piece);
        move.setCapture(cpiece);
        p_out.append(move);

        move.setFlag(@intFromEnum(e_moveFlags.BISHOPPROMOCAPTURE));
        p_out.append(move);

        move.setFlag(@intFromEnum(e_moveFlags.ROOKPROMOCAPTURE));
        p_out.append(move);

        move.setFlag(@intFromEnum(e_moveFlags.QUEENPROMOCAPTURE));
        p_out.append(move);
    }
}

pub fn quietPromoMoveBBToIMove(fromSq: u8, moveBB: u64, piece: e_piece, p_out: moveContainer) void {
    var _moveBB: u64 = moveBB;
    while (_moveBB != chess.EMPTY) {
        const toSq = chess.bitscan;
        _moveBB ^= chess.ONE << @intCast(toSq);
        const move = movel.build_move(fromSq, @intCast(toSq), @intFromEnum(e_moveFlags.KNIGHTPROMO), piece);
        p_out.append(move);

        move.setFlag(@intFromEnum(e_moveFlags.BISHOPPROMO));
        p_out.append(move);

        move.setFlag(@intFromEnum(e_moveFlags.ROOKPROMO));
        p_out.append(move);

        move.setFlag(@intFromEnum(e_moveFlags.QUEENPROMO));
        p_out.append(move);
    }
}
// Kogge-stone algo section
// source: https://www.chessprogramming.org/Kogge-Stone_Algorithm

pub fn northOccl(pieceBB: u64, free: u64) u64 {
    var gen: u64 = pieceBB;
    var pro: u64 = free;
    gen |= pro & (gen << 8);
    pro &= pro << 8;
    gen |= pro & (gen << 16);
    pro &= pro << 16;
    gen |= pro & (gen << 32);
    return gen;
}
pub fn northOne(bb: u64) u64 {
    return bb | (bb << 8);
}
pub fn southOccl(pieceBB: u64, free: u64) u64 {
    var gen: u64 = pieceBB;
    var pro: u64 = free;
    gen |= pro & (gen >> 8);
    pro &= pro >> 8;
    gen |= pro & (gen >> 16);
    pro &= pro >> 16;
    gen |= pro & (gen >> 32);
    return gen;
}

pub fn southOne(bb: u64) u64 {
    return bb | (bb >> 8);
}

pub fn eastOccl(pieceBB: u64, free: u64) u64 {
    var gen: u64 = pieceBB;
    var pro: u64 = free & chess.notHFile;

    gen |= pro & (gen << 1);
    pro &= pro << 1;
    gen |= pro & (gen << 2);
    pro &= pro << 2;
    gen |= pro & (gen << 4);
    return gen;
}
pub fn eastOne(bb: u64) u64 {
    return (bb | ((bb & chess.notHFile) << 1));
}

pub fn westOccl(pieceBB: u64, free: u64) u64 {
    var gen: u64 = pieceBB;
    var pro: u64 = free & chess.notAFile;

    gen |= pro & (gen >> 1);
    pro &= pro >> 1;
    gen |= pro & (gen >> 2);
    pro &= pro >> 2;
    gen |= pro & (gen >> 4);
    return gen;
}
pub fn westOne(bb: u64) u64 {
    return (bb | ((bb & chess.notAFile) >> 1));
}

pub fn northEastOccl(pieceBB: u64, free: u64) u64 {
    var gen: u64 = pieceBB;
    var pro: u64 = free & chess.notHFile;

    gen |= pro & (gen << 9);
    pro &= pro << 9;
    gen |= pro & (gen << 18);
    pro &= pro << 18;
    gen |= pro & (gen << 36);
    return gen;
}
pub fn northEastOne(bb: u64) u64 {
    return (bb | ((bb & chess.notHFile) << 9));
}

pub fn northWestOccl(pieceBB: u64, free: u64) u64 {
    var gen: u64 = pieceBB;
    var pro: u64 = free & chess.notHFile;

    gen |= pro & (gen << 7);
    pro &= pro << 7;
    gen |= pro & (gen << 14);
    pro &= pro << 14;
    gen |= pro & (gen << 28);
    return gen;
}
pub fn northWestOne(bb: u64) u64 {
    return (bb | ((bb & chess.notHFile) << 7));
}

pub fn southEastOccl(pieceBB: u64, free: u64) u64 {
    var gen: u64 = pieceBB;
    var pro: u64 = free & chess.notAFile;

    gen |= pro & (gen >> 7);
    pro &= pro >> 7;
    gen |= pro & (gen >> 14);
    pro &= pro >> 14;
    gen |= pro & (gen >> 28);
    return gen;
}
pub fn southEastOne(bb: u64) u64 {
    return (bb | ((bb & chess.notAFile) >> 7));
}

pub fn southWestOccl(pieceBB: u64, free: u64) u64 {
    var gen: u64 = pieceBB;
    var pro: u64 = free & chess.notHFile;

    gen |= pro & (gen >> 9);
    pro &= pro >> 9;
    gen |= pro & (gen >> 18);
    pro &= pro >> 18;
    gen |= pro & (gen >> 36);
    return gen;
}
pub fn southWestOne(bb: u64) u64 {
    return (bb | ((bb & chess.notHFile) >> 9));
}

pub fn diagPinned(attBB: u64, kingBB: u64, free: u64) u64 {
    const _free = free ^ kingBB;
    var intersect = northEastOne(northEastOccl(attBB, _free)) & southWestOne(southWestOccl(kingBB, _free));

    intersect |= northWestOne(northWestOccl(attBB, _free)) & southEastOne(southEastOccl(kingBB, _free));

    intersect |= southEastOne(southEastOccl(attBB, _free)) & northWestOne(northWestOccl(kingBB, _free));

    intersect |= southWestOne(southWestOccl(attBB, _free)) & northEastOne(northEastOccl(kingBB, _free));
    return intersect;
}
pub fn linePinned(attBB: u64, kingBB: u64, free: u64) u64 {
    const _free = free ^ kingBB;
    var intersect = northOne(northOccl(attBB, _free)) & southOne(southOccl(kingBB, _free));
    intersect |= southOne(southOccl(attBB, _free)) & northOne(northOccl(kingBB, _free));

    intersect |= eastOne(eastOccl(attBB, _free)) & westOne(westOccl(kingBB, _free));

    intersect |= westOne(westOccl(attBB, _free)) & eastOne(eastOccl(kingBB, _free));
    return intersect;
}
