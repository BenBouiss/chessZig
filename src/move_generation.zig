const std = @import("std");
const build_options = @import("build_options");
const useStaged = build_options.useStaged;

const chess = @import("chess.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const boardl = @import("board.zig");
const typel = @import("type.zig");

const moveContainer = movel.moveContainer;
const moveBBState = movel.moveBBState;

const e_square = typel.e_square;
const e_piece = typel.e_piece;
const e_moveFlags = typel.e_moveFlags;

const squareInfo = squarel.squareInfo;
const boardState = boardl.boardState;

pub const generationModifiers = enum { NONE, QUIETMOVE, CAPTURES, ALL };

// move ordering section?
pub fn generateLegalMoves_capture(p_board: *const boardState) moveContainer {
    var bbMoves = moveGenBB(p_board);
    var moves: moveContainer = undefined;
    moves.len = 0;
    moveGenBBToMoveContainer(p_board, &bbMoves, &moves, .CAPTURES);
    return moves;
}

pub inline fn generateLegalMoves(p_board: *const boardState) moveContainer {
    if (comptime useStaged) {
        var bbMoves = moveGenBB(p_board);
        var moves: moveContainer = undefined;
        moves.len = 0;
        moveGenBBToMoveContainer(p_board, &bbMoves, &moves, .ALL);
        //keeping for debug purposes
        //if (true) {
        //    var otherMove: moveContainer = moveGeneration(p_board);
        //    const f_otherMove = filterMoveLegal(p_board, &otherMove, p_board.whiteToMove());
        //    if (f_otherMove.isDifferent(moves)) {
        //        chess.print_board(p_board);
        //        f_otherMove.printDifference(moves);
        //        //chess.print_bitboard(chess.canMove(.e8, .b8, self.occupiedBB));
        //        chess.print_bitboard(bbMoves.rookMoves);
        //        @panic("");
        //    }
        //}
        return moves;
    } else {
        var moves: moveContainer = moveGeneration(p_board);
        const fmoves = filterMoveLegal(p_board, &moves, p_board.whiteToMove());
        return fmoves;
    }
}

pub fn moveGenBBToMoveContainer(p_board: *const boardState, p_moveBB: *moveBBState, p_out: *moveContainer, comptime extra: generationModifiers) void {
    if (p_board.whiteToMove()) {
        return cst_moveGenBBToMoveContainer_ordered(p_board, p_moveBB, true, p_out, extra);
    }
    return cst_moveGenBBToMoveContainer_ordered(p_board, p_moveBB, false, p_out, extra);
}

pub fn cst_moveGenBBToMoveContainer_ordered(p_board: *const boardState, p_moveBB: *moveBBState, comptime white: bool, p_out: *moveContainer, comptime extra: generationModifiers) void {
    const pawnDir: i8 = if (comptime white) 8 else -8;
    const pPawn: e_piece = if (comptime white) .nWhitePawn else .nBlackPawn;
    //const opPawn: e_piece = if (comptime white) .nBlackPawn else .nWhitePawn;
    const pBishop: e_piece = if (comptime white) .nWhiteBishop else .nBlackBishop;
    const pRook: e_piece = if (comptime white) .nWhiteRook else .nBlackRook;
    const pQueen: e_piece = if (comptime white) .nWhiteQueen else .nBlackQueen;
    const pKnight: e_piece = if (comptime white) .nWhiteKnight else .nBlackKnight;
    const pKing: e_piece = if (comptime white) .nWhiteKing else .nBlackKing;
    const kingSq = if (comptime white) p_board.b.wKingSq else p_board.b.bKingSq;
    const emptyOrEnem: u64 = ~p_board.b.c_occupiedBB[@intFromBool(white)];
    const opp = !white;
    const occ = p_board.b.occupiedBB();

    // similar behavior to bishop/rook magic bug here if replacing the pieceBB to getPieceBB, high memcpy usage and huge performance degradation
    const allAttacks = chess.getAllAttackMask(p_board, occ ^ p_board.getPieceBB(pKing), opp);

    const kingSqInfo = squarel.squareInfo.init(kingSq);

    //source: https://www.codeproject.com/articles/Worlds-Fastest-Bitboard-Chess-Movegenerator
    const kingDiags = kingSqInfo.getDiagonalsBB();
    const kingLines = kingSqInfo.getHorizontalBB();
    const pinHV = p_board.frame.pinnedBB & kingLines;
    const pinD12 = p_board.frame.pinnedBB & kingDiags;

    const unPinnedBB = ~p_board.frame.pinnedBB;
    const inCheck: bool = p_board.frame.checkersBB != 0;
    const generateCapture = comptime (extra == .CAPTURES or extra == .ALL);
    const generateQuiet = comptime (extra == .QUIETMOVE or extra == .ALL);
    if (inCheck) {
        const doubleCheck: bool = chess.popcount(p_board.frame.checkersBB & occ) > 1;
        if (doubleCheck) {
            // only king moves
            const kingBB = p_moveBB.kingMoves;
            p_moveBB.resetAll();
            p_moveBB.kingMoves = kingBB;
        } else {
            // only blocking / capturing moves for non king pieces
            const kingBB = p_moveBB.kingMoves;

            if (generateCapture) {
                if (comptime white) {
                    p_moveBB.enPassantMoves = p_moveBB.enPassantMoves >> 8;
                    p_moveBB.andEq(p_board.frame.checkersBB);
                    p_moveBB.enPassantMoves = p_moveBB.enPassantMoves << 8;
                } else {
                    p_moveBB.enPassantMoves = p_moveBB.enPassantMoves << 8;
                    p_moveBB.andEq(p_board.frame.checkersBB);
                    p_moveBB.enPassantMoves = p_moveBB.enPassantMoves >> 8;
                }
            }

            p_moveBB.kingMoves = kingBB;
            // if in check no castling allowed
            p_moveBB.kingSideCastlingMoves = chess.EMPTY;
            p_moveBB.queenSideCastlingMoves = chess.EMPTY;
        }
    } else {
        // move generate the pinned pieces here
        // a pinned piece cannot clear a check

        // bishop and queen
        var pinnedPiece = (p_board.getPieceBB(pBishop) | p_board.getPieceBB(pQueen)) & pinD12;
        while (pinnedPiece != chess.EMPTY) {
            const from: u8 = chess.bitscan(pinnedPiece);
            pinnedPiece &= pinnedPiece - 1;
            const permittedMoves = chess.getBishopAttacks(occ, @enumFromInt(from)) & kingDiags & emptyOrEnem;

            if (comptime generateQuiet) {
                genericStagedMovePushQuiet(p_out, permittedMoves & (~occ), from);
            }
            if (comptime generateCapture) {
                genericStagedMovePushCapture(p_out, permittedMoves & occ, from);
            }
        }
        // rook and queen
        pinnedPiece = (p_board.getPieceBB(pRook) | p_board.getPieceBB(pQueen)) & pinHV;
        while (pinnedPiece != chess.EMPTY) {
            const from: u8 = chess.bitscan(pinnedPiece);
            pinnedPiece &= pinnedPiece - 1;
            const permittedMoves = chess.getRookAttacks(occ, @enumFromInt(from)) & kingLines & emptyOrEnem;

            if (comptime generateQuiet) {
                genericStagedMovePushQuiet(p_out, permittedMoves & (~occ), from);
            }
            if (comptime generateCapture) {
                genericStagedMovePushCapture(p_out, permittedMoves & occ, from);
            }
        }

        // pawn pin handling
        // push only possible if to in pinHV
        // capture only if to in pinD12
        // enPassant never okay
        // promotion only when capturing
        // pinnedPiece = p_moveBB.pawnMoves & pinHV;
        if (comptime generateQuiet) {
            pinnedPiece = (p_board.getPieceBB(pPawn) & pinHV);
            while (pinnedPiece != chess.EMPTY) {
                const from: u8 = chess.bitscan(pinnedPiece);
                pinnedPiece &= pinnedPiece - 1;
                const to: i8 = @as(i8, @intCast(from)) + pawnDir;
                const _to: u8 = @intCast(to);
                if (chess.xToBitboard(_to) & pinHV != chess.EMPTY) {
                    _ = movel.build_move_in(from, _to, @intFromEnum(e_moveFlags.QUIETMOVE), p_out);
                }
            }
            pinnedPiece = p_moveBB.doubleMoves & pinHV;
            while (pinnedPiece != chess.EMPTY) {
                const to: u8 = chess.bitscan(pinnedPiece);
                pinnedPiece &= pinnedPiece - 1;
                const from: i8 = @as(i8, @intCast(to)) - (pawnDir << 1);
                _ = movel.build_move_in(@intCast(from), to, @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out);
            }
        }
        if (comptime generateCapture) {
            pinnedPiece = p_board.getPieceBB(pPawn) & pinD12;
            while (pinnedPiece != chess.EMPTY) {
                const from: u8 = chess.bitscan(pinnedPiece);
                pinnedPiece &= pinnedPiece - 1;

                const att = chess.getPawnAttacks(@enumFromInt(from), white);
                const toAtt_bb = att & kingDiags & p_board.b.c_occupiedBB[@intFromBool(!white)];
                genericStagedMovePushCapture(p_out, toAtt_bb, from);
            }
            pinnedPiece = p_moveBB.promotionMoves & occ & pinD12;
            const validPawnAttLoc: u64 = chess.EMPTY;
            while (pinnedPiece != chess.EMPTY) {
                const to: u8 = chess.bitscan(pinnedPiece);
                pinnedPiece &= pinnedPiece - 1;
                var att = chess.getPawnAttacks(@enumFromInt(to), opp) & validPawnAttLoc;
                if (att != chess.EMPTY) {
                    const from: u8 = chess.bitscan(att);
                    att &= att - 1;
                    push_promotion_capture(from, to, p_out);
                }
            }
        }
    }

    const validPawnLoc = unPinnedBB & p_board.getPieceBB(pPawn);
    if (comptime generateQuiet) {
        var bb: u64 = undefined;
        if (comptime white) {
            bb = (p_moveBB.pawnMoves & (unPinnedBB << 8));
        } else {
            bb = (p_moveBB.pawnMoves & (unPinnedBB >> 8));
        }
        while (bb != chess.EMPTY) {
            const to: u8 = chess.bitscan(bb);
            bb &= bb - 1;
            const from: i8 = @as(i8, @intCast(to)) - pawnDir;
            _ = movel.build_move_in(@intCast(from), to, @intFromEnum(e_moveFlags.QUIETMOVE), p_out);
        }
    }

    if (comptime generateCapture) {
        var bb = p_moveBB.promotionMoves & occ;
        while (bb != chess.EMPTY) {
            const to: u8 = chess.bitscan(bb);
            bb &= bb - 1;
            var att = chess.getPawnAttacks(@enumFromInt(to), opp) & validPawnLoc;
            while (att != chess.EMPTY) {
                const from: u8 = chess.bitscan(att);
                att &= att - 1;
                push_promotion_capture(from, to, p_out);
            }
        }
    }

    if (comptime generateQuiet) {
        var bb: u64 = 0;
        if (comptime white) {
            bb = (p_moveBB.promotionMoves & ~occ & (unPinnedBB << 8));
        } else {
            bb = (p_moveBB.promotionMoves & ~occ & (unPinnedBB >> 8));
        }
        while (bb != chess.EMPTY) {
            const to: u8 = chess.bitscan(bb);
            const from: i8 = @as(i8, @intCast(to)) - pawnDir;
            bb &= bb - 1;
            push_promotion(@intCast(from), to, p_out);
        }

        if (comptime white) {
            bb = (p_moveBB.doubleMoves & (unPinnedBB << 16));
        } else {
            bb = (p_moveBB.doubleMoves & (unPinnedBB >> 16));
        }
        while (bb != chess.EMPTY) {
            const to: u8 = chess.bitscan(bb);
            const from: i8 = @as(i8, @intCast(to)) - (pawnDir << 1);
            bb &= bb - 1;
            _ = movel.build_move_in(@intCast(from), to, @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out);
        }
    }

    if (comptime generateCapture) {
        const validPawnAtt = chess.getPawnAttacksFromBB(validPawnLoc, white);
        var bb = p_moveBB.enPassantMoves & validPawnAtt;
        if (bb != chess.EMPTY) {
            const to: u8 = chess.bitscan(bb);
            bb &= bb - 1;

            const att = chess.getPawnAttacks(@enumFromInt(to), opp);
            var toAtt_bb = att & validPawnLoc;
            if (toAtt_bb != chess.EMPTY) {
                const from: u8 = chess.bitscan(toAtt_bb);
                toAtt_bb &= toAtt_bb - 1;
                const moveBB = chess.xToBitboard(from) | if (comptime white) (chess.xToBitboard(to) >> 8) else (chess.xToBitboard(to) << 8);
                const rankAttack = chess.getQueenAttacks(occ ^ moveBB, kingSq) & kingSqInfo.getRankBB();
                const offender: u64 = if (comptime white) (p_board.getPieceBB(.nBlackRook) | p_board.getPieceBB(.nBlackQueen)) else (p_board.getPieceBB(.nWhiteRook) | p_board.getPieceBB(.nWhiteQueen));
                //std.debug.print("[DEBUG] move gen: offender, att from king \n", .{});
                //chess.print_bitboard(offender);
                //chess.print_bitboard(rankAttack);
                // check that a pP or Pp on the board does not block a sliding piece
                if ((offender & rankAttack) == 0) {
                    _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.ENPASSANT), p_out);
                }
            }
        }

        bb = p_moveBB.pawnAttacks & validPawnAtt;
        while (bb != chess.EMPTY) {
            const to: u8 = chess.bitscan(bb);
            bb &= bb - 1;
            const att = chess.getPawnAttacks(@enumFromInt(to), opp);
            var toAtt_bb = att & validPawnLoc;

            while (toAtt_bb != chess.EMPTY) {
                const from: u8 = chess.bitscan(toAtt_bb);
                toAtt_bb &= toAtt_bb - 1;
                _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.CAPTURE), p_out);
            }
        }
    }

    // bishop BB
    var pieceBB = p_board.getPieceBB(pBishop) & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const allAtt = chess.getBishopAttacks(occ, @enumFromInt(from)) & p_moveBB.bishopMoves;

        if (comptime generateCapture) {
            genericStagedMovePushCapture(p_out, allAtt & occ, from);
        }
        if (comptime generateQuiet) {
            genericStagedMovePushQuiet(p_out, allAtt & (~occ), from);
        }
    }

    // rook BB
    pieceBB = p_board.getPieceBB(pRook) & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const allAtt = chess.getRookAttacks(occ, @enumFromInt(from)) & p_moveBB.rookMoves;
        if (comptime generateCapture) {
            genericStagedMovePushCapture(p_out, allAtt & occ, from);
        }
        if (comptime generateQuiet) {
            genericStagedMovePushQuiet(p_out, allAtt & (~occ), from);
        }
    }

    // queen BB
    pieceBB = p_board.getPieceBB(pQueen) & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const allAtt = (chess.getRookAttacks(occ, @enumFromInt(from)) | chess.getBishopAttacks(occ, @enumFromInt(from))) & p_moveBB.queenMoves;
        if (comptime generateCapture) {
            genericStagedMovePushCapture(p_out, allAtt & occ, from);
        }
        if (comptime generateQuiet) {
            genericStagedMovePushQuiet(p_out, allAtt & (~occ), from);
        }
    }

    // knight BB
    pieceBB = p_board.getPieceBB(pKnight) & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const fromBB = chess.xToBitboard(from);
        const allAtt = chess.knightAttacks(fromBB) & p_moveBB.knightMoves;

        if (comptime generateCapture) {
            genericStagedMovePushCapture(p_out, allAtt & occ, from);
        }
        if (comptime generateQuiet) {
            genericStagedMovePushQuiet(p_out, allAtt & (~occ), from);
        }
    }
    // king BB
    p_moveBB.kingMoves &= ~allAttacks;
    pieceBB = p_board.getPieceBB(pKing);

    const from: u8 = chess.bitscan(pieceBB);

    if (comptime generateCapture) {
        genericStagedMovePushCapture(p_out, p_moveBB.kingMoves & occ, from);
    }
    if (comptime generateQuiet) {
        genericStagedMovePushQuiet(p_out, p_moveBB.kingMoves & (~occ), from);
        if ((p_moveBB.kingSideCastlingMoves != chess.EMPTY) and p_board.canKingSideCastleAtt(white, allAttacks)) {
            _ = movel.build_move_in(from, from + 2, @intFromEnum(e_moveFlags.KINGCASTLE), p_out);
        }
        if ((p_moveBB.queenSideCastlingMoves != chess.EMPTY) and p_board.canQueenSideCastleAtt(white, allAttacks)) {
            _ = movel.build_move_in(from, from - 2, @intFromEnum(e_moveFlags.QUEENCASTLE), p_out);
        }
    }
}
pub fn genericStagedMovePushQuiet(p_out: *moveContainer, iterBB: u64, from: u8) void {
    var _iter = iterBB;
    while (_iter != chess.EMPTY) {
        const to: u8 = chess.bitscan(_iter);
        _iter &= _iter - 1;
        _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), p_out);
    }
}
pub fn genericStagedMovePushCapture(p_out: *moveContainer, iterBB: u64, from: u8) void {
    var _iter = iterBB;
    while (_iter != chess.EMPTY) {
        const to: u8 = chess.bitscan(_iter);
        _iter &= _iter - 1;
        _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.CAPTURE), p_out);
    }
}

pub fn push_promotion(from: u8, to: u8, p_out: *moveContainer) void {
    const move = movel.build_move(from, to, @intFromEnum(e_moveFlags.QUIETMOVE));
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.KNIGHTPROMO)) << 12) });
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.BISHOPPROMO)) << 12) });
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.ROOKPROMO)) << 12) });
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.QUEENPROMO)) << 12) });
}

pub fn push_promotion_capture(from: u8, to: u8, p_out: *moveContainer) void {
    const move = movel.build_move(from, to, @intFromEnum(e_moveFlags.QUIETMOVE));
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.KNIGHTPROMOCAPTURE)) << 12) });
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.BISHOPPROMOCAPTURE)) << 12) });
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.ROOKPROMOCAPTURE)) << 12) });
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.QUEENPROMOCAPTURE)) << 12) });
}

pub inline fn moveGeneration(p_board: *const boardState) moveContainer {
    if (p_board.whiteToMove()) {
        return cst_moveGeneration(p_board, true, .ALL);
    }
    return cst_moveGeneration(p_board, false, .ALL);
}

pub fn cst_moveGeneration(p_board: *const boardState, comptime white: bool, comptime extra: generationModifiers) moveContainer {
    // Generates all the moves from the given board state

    var ret: moveContainer = .{};

    const emptyOrEnemy = ~p_board.b.c_occupiedBB[@intFromBool(white)];

    t_PieceMovePawnMask(p_board, white, extra, &ret);
    t_PieceMoveMask(p_board, white, extra, .KNIGHT, emptyOrEnemy, &ret);
    t_PieceMoveMask(p_board, white, extra, .BISHOP, emptyOrEnemy, &ret);
    t_PieceMoveMask(p_board, white, extra, .ROOK, emptyOrEnemy, &ret);
    t_PieceMoveMask(p_board, white, extra, .QUEEN, emptyOrEnemy, &ret);
    _PieceMoveKingMask(p_board, white, extra, emptyOrEnemy, &ret);
    return ret;
}

pub fn moveBitBoardToIMove_pawn(piece_bb: u64, attack_bb: u64, flags: u8, p_out: *moveContainer) void {
    if (attack_bb == 0) {
        return;
    }
    const sq: u8 = chess.bitscan(piece_bb);
    var _bb = attack_bb;
    while (_bb != 0) {
        const lsb: u8 = chess.bitscan(_bb);
        _bb &= _bb - 1;
        const _curr_move = movel.build_move(sq, lsb, flags);
        p_out.append(_curr_move);
    }
    return;
}

pub fn t_PieceMovePawnMask(p_board: *const boardState, comptime white: bool, extra: generationModifiers, p_out: *moveContainer) void {
    var _bb_piece: u64 = p_board.getPieceBB(if (comptime white) .nWhitePawn else .nBlackPawn);
    const freeBB = ~p_board.b.occupiedBB();
    const enemyBB = p_board.b.c_occupiedBB[@intFromBool(!white)];
    const rankPromo: u8 = if (comptime white) 6 else 1;
    const doublePawn: u8 = if (comptime white) 1 else 6;
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        const sqRank = chess.getSqIdxRank(sq);
        const curr_pos = chess.xToBitboard(sq);
        const singlePushBB = if (comptime white) (curr_pos << 8) else ((curr_pos >> 8));

        if (sqRank == rankPromo) {
            if (extra == .ALL or extra == .QUIETMOVE) {
                _moveBitBoardToIMove_pawn(curr_pos, (singlePushBB) & (freeBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, white);
            }
            if (extra == .ALL or extra == .CAPTURES) {
                _moveBitBoardToIMove_pawn(curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), white) & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, white);
            }
            continue;
        }

        if (sqRank == doublePawn and ((singlePushBB & freeBB)) != 0) {
            const bb = if (comptime white) ((singlePushBB & freeBB) << 8) else ((singlePushBB & freeBB) >> 8);
            moveBitBoardToIMove_pawn(curr_pos, bb & freeBB, @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, white);
        }
        if (extra == .ALL or extra == .QUIETMOVE) {
            genericStagedMovePushQuiet(p_out, (singlePushBB & freeBB), sq);
        }
        if (extra == .ALL or extra == .CAPTURES) {
            genericStagedMovePushCapture(p_out, (chess.getPawnAttacks(@enumFromInt(sq), white) & enemyBB), sq);
        }

        const enPassantBB = chess.xToBitboard(p_board.frame.enPassantIdx);
        moveBitBoardToIMove_pawn(curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), true) & enPassantBB & (if (comptime white) (chess.blackPawnEnpassantRank) else (chess.whitePawnEnpassantRank)) & (freeBB)), @intFromEnum(e_moveFlags.ENPASSANT), p_out, white);
    }
}

pub fn t_PieceMoveMask(p_board: *const boardState, comptime white: bool, comptime piece: typel.e_pieceType, comptime extra: generationModifiers, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var _piece: u8 = @intFromEnum(piece);
    if (comptime !white) {
        _piece += chess.N_PIECES_TYPES;
    }
    var bb_piece = p_board.getPieceBB(@enumFromInt(_piece));
    var att: u64 = 0;
    const occ = p_board.b.occupiedBB();
    while (bb_piece != 0) {
        const sq = chess.bitscan(bb_piece);
        bb_piece &= bb_piece - 1;
        if (comptime piece == .KNIGHT) {
            att = chess.knightAttacks(chess.xToBitboard(sq)) & emptyOrEnemy;
        } else if (comptime piece == .BISHOP) {
            att = chess.getBishopAttacks(occ, @enumFromInt(sq)) & emptyOrEnemy;
        } else if (comptime piece == .ROOK) {
            att = chess.getRookAttacks(occ, @enumFromInt(sq)) & emptyOrEnemy;
        } else if (comptime piece == .QUEEN) {
            att = chess.getQueenAttacks(occ, @enumFromInt(sq)) & emptyOrEnemy;
        }
        if (comptime extra == .ALL or extra == .CAPTURES) {
            genericStagedMovePushCapture(p_out, att & occ, sq);
        }
        if (comptime extra == .ALL or extra == .QUIETMOVE) {
            genericStagedMovePushQuiet(p_out, att & ~occ, sq);
        }
    }
    return;
}

pub fn _PieceMoveKingMask(p_board: *const boardState, comptime white: bool, comptime extra: generationModifiers, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var piece = e_piece.nBlackKing;
    if (comptime white) {
        piece = e_piece.nWhiteKing;
    }
    const sq = p_board.getKingSq(white);
    const att = chess.getKingAttacks(sq) & emptyOrEnemy;

    if (comptime extra == .ALL or extra == .CAPTURES) {
        genericStagedMovePushCapture(p_out, att & p_board.b.occupiedBB(), @intFromEnum(sq));
    }
    if (comptime extra == .ALL or extra == .QUIETMOVES) {
        genericStagedMovePushQuiet(p_out, att & ~p_board.b.occupiedBB(), @intFromEnum(sq));
        if (p_board.canKingSideCastle(white)) {
            _ = movel.build_move_in(@intFromEnum(sq), @intFromEnum(sq) + 2, @intFromEnum(e_moveFlags.KINGCASTLE), p_out);
        }

        if (p_board.canQueenSideCastle(white)) {
            _ = movel.build_move_in(@intFromEnum(sq), @intFromEnum(sq) - 2, @intFromEnum(e_moveFlags.QUEENCASTLE), p_out);
        }
    }
}

pub fn _moveBitBoardToIMove_pawn(piece_bb: u64, attack_bb: u64, flags: u8, p_out: *moveContainer, comptime white: bool) void {
    moveBitBoardToIMove_pawn(piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.KNIGHTPROMO), p_out, white);
    moveBitBoardToIMove_pawn(piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.BISHOPPROMO), p_out, white);
    moveBitBoardToIMove_pawn(piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.ROOKPROMO), p_out, white);
    moveBitBoardToIMove_pawn(piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.QUEENPROMO), p_out, white);
}

pub fn filterMoveLegal(p_state: *const boardState, move_list: *moveContainer, white: bool) moveContainer {
    // goal compared to filterMoveLegal: try to not use the make/undo Moves methods
    var ret: moveContainer = .{};
    const cached = getCachedAttackingPiece(p_state, white);
    const all_attacks = chess.getAllAttackMask(p_state, p_state.b.occupiedBB(), !white);

    const kingSqInfo = squareInfo.init(p_state.getKingSq(white));
    const checks: squarel.checkContainer = squarel.convertBitBoardtoCheckContainer(chess.getAllAttackerFromKing(p_state, white));
    const linePieceBB = cached[0];
    const diagPieceBB = cached[1];
    for (0..move_list.len) |i| {
        if (move_list.moves[i].isCastle()) {
            if (p_state.isCastleLegalPreMove(white, move_list.moves[i], all_attacks)) {
                ret.append(move_list.moves[i]);
            }
        } else if (p_state.isLegalFast(all_attacks, move_list.moves[i], &kingSqInfo, &checks, diagPieceBB, linePieceBB)) {
            ret.append(move_list.moves[i]);
        }
    }

    return ret;
}

pub fn getCachedAttackingPiece(p_state: *const boardState, white: bool) [2]u64 {
    // [linePieceBB, diagPieceBB];
    var ret = [_]u64{ chess.EMPTY, chess.EMPTY };
    if (white) {
        ret[0] = (p_state.getPieceBB(.nBlackRook) | p_state.getPieceBB(.nBlackQueen));
        ret[1] = (p_state.getPieceBB(.nBlackBishop) | p_state.getPieceBB(.nBlackQueen));
    } else {
        ret[0] = (p_state.getPieceBB(.nWhiteRook) | p_state.getPieceBB(.nWhiteQueen));
        ret[1] = (p_state.getPieceBB(.nWhiteBishop) | p_state.getPieceBB(.nWhiteQueen));
    }
    return ret;
}

pub fn moveGenPawnBB(p_board: *const boardState, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.pawnMoves = chess.EMPTY;
    p_out.pawnAttacks = chess.EMPTY;
    p_out.doubleMoves = chess.EMPTY;
    p_out.enPassantMoves = chess.EMPTY;
    const occ = p_board.b.occupiedBB();

    const enPassantBB = chess.xToBitboard(p_board.frame.enPassantIdx);
    if (comptime white) {
        const piece_idx: u8 = @intFromEnum(e_piece.nWhitePawn);
        const pBB = p_board.getPieceBB(@enumFromInt(piece_idx));
        p_out.pawnMoves |= (pBB << 8) & (~occ);
        p_out.doubleMoves |= ((p_out.pawnMoves << 8) & (~occ)) & ((p_board.getPieceBB(@enumFromInt(piece_idx)) & chess.whitePawnDoubleRank) << 16);

        p_out.pawnAttacks |= chess.getPawnAttacksFromBB(pBB, true);

        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.whitePawnEnpassantRank;

        p_out.pawnAttacks &= (emptyOrEnemy & occ);
        //p_out.pawnAttacks &= (p_board.b.c_occupiedBB[@intFromBool(false)]);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.whitePawnPromoRank);
        p_out.pawnAttacks &= ~chess.whitePawnPromoRank;
        p_out.pawnMoves &= ~chess.whitePawnPromoRank;
    } else {
        const piece_idx: u8 = @intFromEnum(e_piece.nBlackPawn);
        const pBB = p_board.getPieceBB(@enumFromInt(piece_idx));
        p_out.pawnMoves |= (pBB >> 8) & (~occ);
        p_out.doubleMoves |= ((p_out.pawnMoves >> 8) & (~occ)) & ((pBB & chess.blackPawnDoubleRank) >> 16);

        p_out.pawnAttacks |= chess.getPawnAttacksFromBB(pBB, false);

        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.blackPawnEnpassantRank;

        //p_out.pawnAttacks &= (p_board.b.c_occupiedBB[@intFromBool(true)]);
        p_out.pawnAttacks &= (emptyOrEnemy & occ);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.blackPawnPromoRank);
        p_out.pawnAttacks &= ~chess.blackPawnPromoRank;
        p_out.pawnMoves &= ~chess.blackPawnPromoRank;
    }
}

pub inline fn moveGenKnightBB(p_board: *const boardState, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.knightMoves = (chess.knightAttacks(p_board.getPieceBB(.nWhiteKnight))) & emptyOrEnemy;
    } else {
        p_out.knightMoves = (chess.knightAttacks(p_board.getPieceBB(.nBlackKnight))) & emptyOrEnemy;
    }
}

pub fn moveGenKingBB(p_board: *const boardState, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.kingMoves = chess.getKingAttacks(p_board.b.wKingSq) & emptyOrEnemy;
        const kingBB = p_board.getPieceBB(.nWhiteKing);
        if (p_board.canQueenSideCastle(white)) {
            p_out.queenSideCastlingMoves |= (kingBB >> 2);
        }
        if (p_board.canKingSideCastle(white)) {
            p_out.kingSideCastlingMoves |= (kingBB << 2);
        }
    } else {
        p_out.kingMoves = chess.getKingAttacks(p_board.b.bKingSq) & emptyOrEnemy;
        const kingBB = p_board.getPieceBB(.nBlackKing);
        if (p_board.canQueenSideCastle(white)) {
            p_out.queenSideCastlingMoves |= (kingBB >> 2);
        }
        if (p_board.canKingSideCastle(white)) {
            p_out.kingSideCastlingMoves |= (kingBB << 2);
        }
    }
}
pub inline fn moveGenBishopBB(p_board: *const boardState, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.bishopMoves = chess._AllAttackBishopMask(p_board.getPieceBB(.nWhiteBishop), p_board.b.occupiedBB()) & emptyOrEnemy;
    } else {
        p_out.bishopMoves = chess._AllAttackBishopMask(p_board.getPieceBB(.nBlackBishop), p_board.b.occupiedBB()) & emptyOrEnemy;
    }
}
pub inline fn moveGenRookBB(p_board: *const boardState, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.rookMoves = chess._AllAttackRookMask(p_board.getPieceBB(.nWhiteRook), p_board.b.occupiedBB()) & emptyOrEnemy;
    } else {
        p_out.rookMoves = chess._AllAttackRookMask(p_board.getPieceBB(.nBlackRook), p_board.b.occupiedBB()) & emptyOrEnemy;
    }
}

pub inline fn moveGenQueenBB(p_board: *const boardState, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.queenMoves = chess._AllAttackQueenMask(p_board.getPieceBB(.nWhiteQueen), p_board.b.occupiedBB()) & emptyOrEnemy;
    } else {
        p_out.queenMoves = chess._AllAttackQueenMask(p_board.getPieceBB(.nBlackQueen), p_board.b.occupiedBB()) & emptyOrEnemy;
    }
}

pub inline fn moveGenBB(p_board: *const boardState) moveBBState {
    var ret: moveBBState = .{};
    if (p_board.whiteToMove()) {
        cst_moveGenBB(p_board, true, &ret);
        return ret;
    }
    cst_moveGenBB(p_board, false, &ret);
    return ret;
}
pub inline fn _cst_moveGenBB(p_board: *const boardState, comptime white: bool) moveBBState {
    var ret: moveBBState = .{};
    cst_moveGenBB(p_board, white, &ret);
    return ret;
}
pub fn cst_moveGenBB(p_board: *const boardState, comptime white: bool, p_out: *moveBBState) void {
    const EmptyOrEnemy = ~p_board.b.c_occupiedBB[@intFromBool(white)];
    moveGenPawnBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenKnightBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenBishopBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenRookBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenQueenBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenKingBB(p_board, white, EmptyOrEnemy, p_out);
}
pub inline fn _cst_moveGenBB_all(p_board: *const boardState, comptime white: bool) moveBBState {
    var ret: moveBBState = .{};
    cst_moveGenBB_all(p_board, white, &ret);
    return ret;
}
pub fn cst_moveGenBB_all(p_board: *const boardState, comptime white: bool, p_out: *moveBBState) void {
    const EmptyOrEnemy = chess.UNIVERSE;
    moveGenPawnBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenKnightBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenBishopBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenRookBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenQueenBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenKingBB(p_board, white, EmptyOrEnemy, p_out);
}

pub const qbb = struct {
    bb: @Vector(4, u64),
    pub inline fn init(bb: u64) qbb {
        return .{ .bb = [4]u64{ bb, bb, bb, bb } };
    }
    pub inline fn lShift(self: qbb, other: qbb) qbb {
        return .{ .bb = self.bb << other.bb };
    }
    pub inline fn lShift_eq(self: *qbb, other: *qbb) void {
        self.bb = self.bb << other.bb;
    }
    pub inline fn rShift(self: qbb, other: qbb) qbb {
        return .{ .bb = self.bb >> other.bb };
    }
    pub fn rShift_eq(self: *qbb, other: *qbb) void {
        self.bb >>= other.bb;
    }

    pub fn bbAnd(self: qbb, other: qbb) qbb {
        return .{ .bb = self.bb & other.bb };
    }
    pub fn bbAnd_eq(self: *qbb, other: *qbb) void {
        self.bb = self.bb & other.bb;
    }
    pub fn bbOr(self: qbb, other: qbb) qbb {
        return .{ .bb = self.bb | other.bb };
    }
    pub fn bbOr_eq(self: *qbb, other: *qbb) void {
        self.bb |= other.bb;
    }
    pub fn collapse(self: qbb) u64 {
        return self.bb[0] | self.bb[1] | self.bb[2] | self.bb[3];
    }
};

// source: https://www.chessprogramming.org/AVX2#Dumb7Fill
pub fn east_nort_noWe_noEa_Attacks(qsliders: qbb, free: u64) qbb {
    var qmask: qbb = .{ .bb = .{ chess.notAFile, chess.UNIVERSE, chess.notHFile, chess.notAFile } };
    const qshift: qbb = .{ .bb = .{ 1, 8, 7, 9 } };
    var qfree = qbb.init(free);
    qfree.bbAnd_eq(&qmask);
    var _qsliders = qsliders;
    var qflood = qsliders;
    _qsliders.bb = ((_qsliders.bb << qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    _qsliders.bb = ((_qsliders.bb << qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    _qsliders.bb = ((_qsliders.bb << qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    _qsliders.bb = ((_qsliders.bb << qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    _qsliders.bb = ((_qsliders.bb << qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    qflood.bb |= ((_qsliders.bb << qshift.bb) & qfree.bb);
    return .{ .bb = (qflood.bb << qshift.bb) & qmask.bb };
}
pub fn west_sout_soEa_soWe_Attacks(qsliders: qbb, free: u64) qbb {
    var qmask: qbb = .{ .bb = .{ chess.notHFile, chess.UNIVERSE, chess.notAFile, chess.notHFile } };
    const qshift: qbb = .{ .bb = .{ 1, 8, 7, 9 } };
    var qfree = qbb.init(free);
    qfree.bbAnd_eq(&qmask);
    var _qsliders = qsliders;
    var qflood = qsliders;
    _qsliders.bb = ((_qsliders.bb >> qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    _qsliders.bb = ((_qsliders.bb >> qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    _qsliders.bb = ((_qsliders.bb >> qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    _qsliders.bb = ((_qsliders.bb >> qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    _qsliders.bb = ((_qsliders.bb >> qshift.bb) & qfree.bb);
    qflood.bb |= _qsliders.bb;

    qflood.bb |= ((_qsliders.bb >> qshift.bb) & qfree.bb);
    return .{ .bb = (qflood.bb >> qshift.bb) & qmask.bb };
}
pub fn avx2DumbFill(p_state: *const boardState, comptime white: bool) qbb {
    if (comptime white) {
        const rq = p_state.getPieceBB(.nWhiteRook) | p_state.getPieceBB(.nWhiteQueen);
        const bq = p_state.getPieceBB(.nWhiteBishop) | p_state.getPieceBB(.nWhiteQueen);
        const pieceQBB: qbb = .{ .bb = [4]u64{ rq, rq, bq, bq } };
        const free = ~p_state.b.occupiedBB();
        var posBB = east_nort_noWe_noEa_Attacks(pieceQBB, free);
        const negBB = west_sout_soEa_soWe_Attacks(pieceQBB, free);
        return posBB.bbOr(negBB);
    } else {
        const rq = p_state.getPieceBB(.nBlackRook) | p_state.getPieceBB(.nBlackQueen);
        const bq = p_state.getPieceBB(.nBlackBishop) | p_state.getPieceBB(.nBlackQueen);
        const pieceQBB: qbb = .{ .bb = [4]u64{ rq, rq, bq, bq } };
        const free = ~p_state.b.occupiedBB();
        var posBB = east_nort_noWe_noEa_Attacks(pieceQBB, free);
        const negBB = west_sout_soEa_soWe_Attacks(pieceQBB, free);
        return posBB.bbOr(negBB);
    }
}
pub fn getPinned_avx2(p_state: *const boardState, comptime white: bool) u64 {
    var free = ~p_state.b.occupiedBB();
    if (comptime white) {
        const k = p_state.getPieceBB(.nWhiteKing);
        const k_qbb = qbb.init(k);
        var attackers = avx2DumbFill(p_state, false);
        free ^= (attackers.collapse() & p_state.b.c_occupiedBB[@intFromBool(true)]);
        var kingBB = east_nort_noWe_noEa_Attacks(k_qbb, free);
        var negBB = west_sout_soEa_soWe_Attacks(k_qbb, free);
        kingBB.bbOr_eq(&negBB);
        kingBB.bbAnd_eq(&attackers);
        return kingBB.collapse();
    } else {
        const k = p_state.getPieceBB(.nBlackKing);
        const k_qbb = qbb.init(k);
        var attackers = avx2DumbFill(p_state, true);
        free ^= (attackers.collapse() & p_state.b.c_occupiedBB[@intFromBool(false)]);
        var kingBB = east_nort_noWe_noEa_Attacks(k_qbb, free);
        var negBB = west_sout_soEa_soWe_Attacks(k_qbb, free);
        kingBB.bbOr_eq(&negBB);
        kingBB.bbAnd_eq(&attackers);
        return kingBB.collapse();
    }
}

pub fn getPinned_(p_state: *const boardState, comptime white: bool, king_E: e_square, rq: u64, bq: u64) u64 {
    var pinned: u64 = 0;
    var pinner = chess.xrayRookAttacks(p_state.b.occupiedBB(), p_state.b.c_occupiedBB[@intFromBool(white)], king_E) & rq;
    while (pinner != chess.EMPTY) {
        const pinsq = chess.bitscan(pinner);
        pinner &= pinner - 1;
        pinned |= chess.inBetween(@enumFromInt(pinsq), king_E);
    }

    pinner = chess.xrayBishopAttacks(p_state.b.occupiedBB(), p_state.b.c_occupiedBB[@intFromBool(white)], king_E) & bq;
    while (pinner != chess.EMPTY) {
        const pinsq = chess.bitscan(pinner);
        pinner &= pinner - 1;
        pinned |= chess.inBetween(@enumFromInt(pinsq), king_E);
    }
    return pinned;
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
pub inline fn northOne(bb: u64) u64 {
    return (bb << 8);
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

pub inline fn southOne(bb: u64) u64 {
    return (bb >> 8);
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
pub inline fn eastOne(bb: u64) u64 {
    return ((bb & chess.notHFile) << 1);
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
pub inline fn westOne(bb: u64) u64 {
    return ((bb & chess.notAFile) >> 1);
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
pub inline fn northEastOne(bb: u64) u64 {
    return (bb & chess.notHFile) << 9;
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
pub inline fn northWestOne(bb: u64) u64 {
    return (bb & chess.notHFile) << 7;
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
pub inline fn southEastOne(bb: u64) u64 {
    return ((bb & chess.notAFile) >> 7);
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
pub inline fn southWestOne(bb: u64) u64 {
    return ((bb & chess.notHFile) >> 9);
}

pub fn moveDeliverCheck(p_state: *const boardState, move: movel.IMove) bool {
    const white: bool = p_state.whiteToMove();
    const from = move.getFrom();
    const fromBB = chess.xToBitboard(from);
    const otherKing: u8 = @intFromEnum(p_state.getKingSq(!white));
    var piece = p_state.getPiece(from);
    if ((p_state.frame.pinnedBB & fromBB) != 0) {
        //const to = move.getTo();
        //if ((chess.inBetweenX(from, to) & (chess.inBetweenX(from, otherKing) | fromBB)) == 0) {
        //    return true;
        //}
        // a pawn or king can move along a pin (given by same piece color ie: white queen behind white king) without delivering check however any other piece will induce a check
        return !chess.isPawnPiece(piece) and !chess.isKingPiece(piece);
    }
    const toSq = move.getTo();
    if (move.isPromotion()) {
        piece = chess.flagPromotionToPiece(move.getFlag(), white);
    }
    if (chess.isKingPiece(piece)) {
        if (move.isCastle()) {
            const castleSq: e_square = if (move.isQueenSideCastle()) (@enumFromInt(toSq + 1)) else (@enumFromInt(toSq - 1));
            return (chess.getRookAttacks(p_state.b.occupiedBB() ^ fromBB, castleSq) & chess.xToBitboard(otherKing)) != 0;
        } else {
            return false;
        }
    }
    const att = chess.getRelevantAttacks(piece, @enumFromInt(toSq), p_state.b.occupiedBB() ^ fromBB) catch {
        chess.sanityCheckBoardState(p_state);
        @panic("???");
    };
    return (att & chess.xToBitboard(otherKing)) != 0;
}
pub const moveGene = struct {
    // generates pseudo legal moves
    _moves: moveContainer = .{},
    idx: u8 = 0,

    pub fn next(self: *moveGene) ?movel.IMove {
        if (self.idx == self._moves.len) {
            return null;
        }
        self.idx += 1;
        return self._moves[self.idx];
    }
    pub inline fn generateMove(self: *moveGene, comptime t: typel.e_moveGenFlag, p_state: *const boardState) void {
        self._moves.len = 0;
        generateMoveT(&self._moves, t, p_state);
    }
    pub inline fn generateAll(self: *moveGene, p_state: *const boardState) void {
        self._moves.len = 0;
        generateMoveT(&self._moves, .ALL, p_state);
    }
    pub fn getMoveCounts(self: *moveGene, p_state: *const boardState) moveTypeCount {
        var ret: moveTypeCount = .{};
        self.generateMove(.QUIET, p_state);
        ret.quiet = self._moves.len;

        self.generateMove(.CAPTURE, p_state);
        ret.capture = self._moves.len;

        self.generateMove(.PROMO, p_state);
        ret.promo = self._moves.len;

        self.generateMove(.EVASION, p_state);
        ret.evasion = self._moves.len;
        return ret;
    }
};
pub fn generateMoveT(out: *moveContainer, comptime t: typel.e_moveGenFlag, p_state: *const boardState) void {
    if (p_state.whiteToMove()) {
        return _generateMoveT(out, t, true, p_state);
    }
    return _generateMoveT(out, t, false, p_state);
}
pub fn _generateMoveT(out: *moveContainer, comptime t: typel.e_moveGenFlag, comptime white: bool, p_state: *const boardState) void {
    const emptyOrEnemy = if (comptime t == .EVASION) (p_state.frame.checkersBB) else (~p_state.b.c_occupiedBB[@intFromBool(white)]);
    const occ = p_state.b.occupiedBB();

    if (comptime t == .EVASION) {
        const doubleCheck = if (p_state.isChecked()) (p_state.frame.checkersBB & (p_state.frame.checkersBB - 1) != 0) else false;
        if (doubleCheck) {
            return generatePieceMove(out, t, white, .KING, p_state, occ, emptyOrEnemy);
        }
    }

    generatePieceMove(out, t, white, .PAWN, p_state, occ, emptyOrEnemy);
    if (comptime t != .PROMO) {
        generatePieceMove(out, t, white, .BISHOP, p_state, occ, emptyOrEnemy);
        generatePieceMove(out, t, white, .KNIGHT, p_state, occ, emptyOrEnemy);
        generatePieceMove(out, t, white, .ROOK, p_state, occ, emptyOrEnemy);
        generatePieceMove(out, t, white, .QUEEN, p_state, occ, emptyOrEnemy);
        generatePieceMove(out, t, white, .KING, p_state, occ, emptyOrEnemy);
    }
}
pub fn generatePieceMove(out: *moveContainer, comptime t: typel.e_moveGenFlag, comptime white: bool, comptime p: typel.e_pieceType, p_state: *const boardState, occ: u64, emptyOrEnemy: u64) void {
    if (comptime p == .PAWN) {
        return generatePawnt(out, white, t, p_state, occ, emptyOrEnemy);
    } else if (comptime p == .BISHOP or p == .ROOK or p == .QUEEN or p == .KNIGHT) {
        return t_GeneratePiece(out, white, t, p, p_state, occ, emptyOrEnemy);
    } else if (comptime p == .KING) {
        const sq = if (comptime white) p_state.b.wKingSq else p_state.b.bKingSq;
        const sqX: u8 = @intFromEnum(sq);
        const att = chess.getKingAttacks(sq);
        if (comptime t == .CAPTURE or t == .ALL or t == .EVASION) {
            genericStagedMovePushCapture(out, att & emptyOrEnemy & occ, @intFromEnum(sq));
        }
        if (comptime t == .QUIET or t == .ALL or t == .EVASION) {
            genericStagedMovePushQuiet(out, att & emptyOrEnemy & (~occ), @intFromEnum(sq));
        }
        if (comptime t == .QUIET or t == .ALL) {
            if (p_state.canKingSideCastle(white)) {
                _ = movel.build_move_in(sqX, sqX + 2, @intFromEnum(e_moveFlags.KINGCASTLE), out);
            }

            if (p_state.canQueenSideCastle(white)) {
                _ = movel.build_move_in(sqX, sqX - 2, @intFromEnum(e_moveFlags.QUEENCASTLE), out);
            }
        }
    }
}

pub fn t_GeneratePiece(out: *moveContainer, comptime white: bool, comptime t: typel.e_moveGenFlag, comptime p: typel.e_pieceType, p_state: *const boardState, occ: u64, emptyOrEnemy: u64) void {
    const piece: e_piece = @enumFromInt(@as(u8, @intFromEnum(p)) + if (comptime white) 0 else chess.N_PIECES_TYPES);
    var bb = p_state.getPieceBB(piece);
    while (bb != 0) {
        const sq = chess.bitscan(bb);
        bb &= bb - 1;
        const att = if (comptime p == .BISHOP) (chess.getBishopAttacks(occ, @enumFromInt(sq))) else if (comptime p == .ROOK) (chess.getRookAttacks(occ, @enumFromInt(sq))) else if (comptime p == .KNIGHT) (chess.knightAttacks(chess.xToBitboard(sq))) else (chess.getQueenAttacks(occ, @enumFromInt(sq)));
        if (t == .CAPTURE or t == .ALL) {
            genericStagedMovePushCapture(out, att & emptyOrEnemy & occ, sq);
        }
        if (t == .QUIET or t == .ALL) {
            genericStagedMovePushQuiet(out, att & emptyOrEnemy & (~occ), sq);
        }
    }
    return;
}

pub fn generatePawnt(out: *moveContainer, comptime white: bool, comptime t: typel.e_moveGenFlag, p_state: *const boardState, occ: u64, emptyOrEnemy: u64) void {
    const p = if (comptime white) (p_state.b.pieceBB[@intFromEnum(e_piece.nWhitePawn)]) else (p_state.b.pieceBB[@intFromEnum(e_piece.nBlackPawn)]);
    const empty = (~occ) & emptyOrEnemy;

    if (comptime t == .QUIET or t == .ALL or t == .PROMO) {
        var bbProm = p & chess.maskOutPawnQuietMove(white, empty) & if (comptime white) chess.blackPawnDoubleRank else chess.whitePawnDoubleRank;
        while (bbProm != 0) {
            const sq = chess.bitscan(bbProm);
            bbProm &= bbProm - 1;
            push_promotion(sq, if (comptime white) (sq + 8) else (sq - 8), out);
        }
        if (t != .PROMO) {
            var bb: u64 = p & chess.maskOutPawnQuietMove(white, empty) & if (comptime white) ~chess.blackPawnDoubleRank else ~chess.whitePawnDoubleRank;
            while (bb != 0) {
                const sq = chess.bitscan(bb);
                bb &= bb - 1;
                _ = movel.build_move_in(sq, if (comptime white) (sq + 8) else (sq - 8), @intFromEnum(e_moveFlags.QUIETMOVE), out);
            }

            bb = p & chess.maskOutPawnDoublePush(white, empty);
            while (bb != 0) {
                const sq = chess.bitscan(bb);
                bb &= bb - 1;
                _ = movel.build_move_in(sq, if (comptime white) (sq + 16) else (sq - 16), @intFromEnum(e_moveFlags.DOUBLEPAWN), out);
            }
        }
    }
    if (comptime t == .CAPTURE or t == .ALL or t == .PROMO) {
        var bbProm = p & if (comptime white) chess.blackPawnDoubleRank else chess.whitePawnDoubleRank;
        while (bbProm != 0) {
            const sq = chess.bitscan(bbProm);
            bbProm &= bbProm - 1;
            var att = chess.getPawnAttacks(@enumFromInt(sq), white) & emptyOrEnemy & occ;
            while (att != 0) {
                const victim = chess.bitscan(att);
                att &= att - 1;
                push_promotion_capture(sq, victim, out);
            }
        }
        if (t == .PROMO) {
            return;
        }

        var bb: u64 = p & chess.maskOutPawnQuietMove(white, empty) & if (comptime white) ~chess.blackPawnDoubleRank else ~chess.whitePawnDoubleRank;
        while (bb != 0) {
            const sq = chess.bitscan(bb);
            bb &= bb - 1;
            const att = chess.getPawnAttacks(@enumFromInt(sq), white) & emptyOrEnemy & occ;
            genericStagedMovePushCapture(out, att, sq);
        }
        if (comptime t != .EVASION) {
            if (p_state.frame.enPassantIdx != 0) {
                var validPs = chess.getPawnAttacks(@enumFromInt(p_state.frame.enPassantIdx), !white) & p;
                while (validPs != 0) {
                    const sq = chess.bitscan(validPs);
                    validPs &= validPs - 1;
                    _ = movel.build_move_in(sq, p_state.frame.enPassantIdx, @intFromEnum(e_moveFlags.ENPASSANT), out);
                }
            }
        }
    }
}
pub const genError = error{ quietMoveErr, captureMoveErr, promoMoveErr, evasionMoveErr, allMoveErr };
pub const moveTypeCount = struct {
    quiet: u8 = 0,
    capture: u8 = 0,
    promo: u8 = 0,
    evasion: u8 = 0,
    pub fn all(self: moveTypeCount) u8 {
        return self.quiet + self.capture + self.promo + self.evasion;
    }
    pub fn compare(self: moveTypeCount, other: moveTypeCount) genError!bool {
        if (self.quiet != other.quiet) {
            std.debug.print("quiet move difference self {d} other {d}\n", .{ self.quiet, other.quiet });
            return genError.quietMoveErr;
        }
        if (self.capture != other.capture) {
            std.debug.print("capture move difference self {d} other {d}\n", .{ self.capture, other.capture });
            return genError.captureMoveErr;
        }
        if (self.promo != other.promo) {
            std.debug.print("promotion move difference self {d} other {d}\n", .{ self.promo, other.promo });
            return genError.promoMoveErr;
        }
        if (self.evasion != other.evasion) {
            std.debug.print("evasion move difference self {d} other {d}\n", .{ self.evasion, other.evasion });
            return genError.evasionMoveErr;
        }
        return true;
    }
};
pub fn genTypeCountFromState(p_state: *const boardState) moveTypeCount {
    var ret: moveTypeCount = .{};
    const fmoves = generateLegalMoves(p_state);
    for (0..fmoves.len) |i| {
        const move = fmoves.moves[i];
        if (move.isCapture()) {
            ret.capture += 1;
        } else {
            ret.quiet += 1;
        }
        if (move.isPromotion()) {
            ret.promo += 1;
        }
        if (p_state.isChecked() and chess.isKingPiece(p_state.getPiece(move.getFrom()))) {
            ret.evasion += 1;
        }
    }
    return ret;
}
