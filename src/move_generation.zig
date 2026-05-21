const std = @import("std");
const build_options = @import("build_options");
const useStaged = build_options.useStaged;

const chess = @import("chess.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");

const moveContainer = movel.moveContainer;
const moveBBState = movel.moveBBState;

const e_square = squarel.e_square;
const e_piece = chess.e_piece;
const e_moveFlags = movel.e_moveFlags;

const squareInfo = squarel.squareInfo;
const Board_state = chess.Board_state;

pub const generationModifiers = enum { NONE, NORMAL, QUIETMOVE, CAPTURES, ALL };

// move ordering section?
pub fn generateLegalMoves_capture(p_board: *const Board_state) moveContainer {
    var bbMoves = moveGenBB(p_board);
    var moves: moveContainer = undefined;
    moves.len = 0;
    moveGenBBToMoveContainer(p_board, &bbMoves, &moves, .CAPTURES);
    return moves;
}

pub inline fn generateLegalMoves(p_board: *const Board_state) moveContainer {
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
pub inline fn generateLegalMovesCut(p_board: *const Board_state, p_out: *moveContainer) void {
    if (comptime useStaged) {
        var bbMoves = moveGenBB(p_board);
        return moveGenBBToMoveContainer(p_board, &bbMoves, p_out, .ALL);
    } else {
        @panic("Not implemented");
    }
}

pub fn moveGenBBToMoveContainer(p_board: *const Board_state, p_moveBB: *moveBBState, p_out: *moveContainer, comptime extra: generationModifiers) void {
    if (p_board.whiteToMove()) {
        return cst_moveGenBBToMoveContainer_ordered(p_board, p_moveBB, true, p_out, extra);
    }
    return cst_moveGenBBToMoveContainer_ordered(p_board, p_moveBB, false, p_out, extra);
}

pub fn cst_moveGenBBToMoveContainer_ordered(p_board: *const Board_state, p_moveBB: *moveBBState, comptime white: bool, p_out: *moveContainer, comptime extra: generationModifiers) void {
    const pawnDir: i8 = if (comptime white) 8 else -8;
    const pPawn: e_piece = if (comptime white) .nWhitePawn else .nBlackPawn;
    //const opPawn: e_piece = if (comptime white) .nBlackPawn else .nWhitePawn;
    const pBishop: e_piece = if (comptime white) .nWhiteBishop else .nBlackBishop;
    const pRook: e_piece = if (comptime white) .nWhiteRook else .nBlackRook;
    const pQueen: e_piece = if (comptime white) .nWhiteQueen else .nBlackQueen;
    const pKnight: e_piece = if (comptime white) .nWhiteKnight else .nBlackKnight;
    const pKing: e_piece = if (comptime white) .nWhiteKing else .nBlackKing;
    const kingSq = if (comptime white) p_board.wKingSq else p_board.bKingSq;
    const emptyOrEnem: u64 = ~p_board.c_occupiedBB[@intFromBool(white)];
    const opp = !white;

    // similar behavior to bishop/rook magic bug here if replacing the pieceBB to getPieceBB, high memcpy usage and huge performance degradation
    const allAttacks = chess.getAllAttackMask(p_board, p_board.occupiedBB ^ p_board.pieceBB[@intFromEnum(pKing)], opp);

    const kingSqInfo = squarel.squareInfo.init(kingSq);

    //source: https://www.codeproject.com/articles/Worlds-Fastest-Bitboard-Chess-Movegenerator
    const kingDiags = kingSqInfo.getDiagonalsBB();
    const kingLines = kingSqInfo.getHorizontalBB();
    const pinHV = p_board.pinnedBB & kingLines;
    const pinD12 = p_board.pinnedBB & kingDiags;

    const unPinnedBB = ~p_board.pinnedBB;
    const inCheck: bool = p_board.checkersBB != 0;
    const generateCapture = comptime (extra == .CAPTURES or extra == .ALL);
    const generateQuiet = comptime (extra == .QUIETMOVE or extra == .ALL);
    if (inCheck) {
        const doubleCheck: bool = chess.popcount(p_board.checkersBB & p_board.occupiedBB) > 1;
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
                    p_moveBB.andEq(p_board.checkersBB);
                    p_moveBB.enPassantMoves = p_moveBB.enPassantMoves << 8;
                } else {
                    p_moveBB.enPassantMoves = p_moveBB.enPassantMoves << 8;
                    p_moveBB.andEq(p_board.checkersBB);
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
        var pinnedPiece = (p_board.pieceBB[@intFromEnum(pBishop)] | p_board.pieceBB[@intFromEnum(pQueen)]) & pinD12;
        while (pinnedPiece != chess.EMPTY) {
            const from: u8 = chess.bitscan(pinnedPiece);
            pinnedPiece &= pinnedPiece - 1;
            const permittedMoves = chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(from)) & kingDiags & emptyOrEnem;

            if (comptime generateQuiet) {
                genericStagedMovePushQuiet(p_out, permittedMoves & (~p_board.occupiedBB), from);
            }
            if (comptime generateCapture) {
                genericStagedMovePushCapture(p_out, permittedMoves & p_board.occupiedBB, from);
            }
        }
        // rook and queen
        pinnedPiece = (p_board.pieceBB[@intFromEnum(pRook)] | p_board.pieceBB[@intFromEnum(pQueen)]) & pinHV;
        while (pinnedPiece != chess.EMPTY) {
            const from: u8 = chess.bitscan(pinnedPiece);
            pinnedPiece &= pinnedPiece - 1;
            const permittedMoves = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(from)) & kingLines & emptyOrEnem;

            if (comptime generateQuiet) {
                genericStagedMovePushQuiet(p_out, permittedMoves & (~p_board.occupiedBB), from);
            }
            if (comptime generateCapture) {
                genericStagedMovePushCapture(p_out, permittedMoves & p_board.occupiedBB, from);
            }
        }

        // pawn pin handling
        // push only possible if to in pinHV
        // capture only if to in pinD12
        // enPassant never okay
        // promotion only when capturing
        // pinnedPiece = p_moveBB.pawnMoves & pinHV;
        if (comptime generateQuiet) {
            pinnedPiece = (p_board.pieceBB[@intFromEnum(pPawn)] & pinHV);
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
            pinnedPiece = p_board.pieceBB[@intFromEnum(pPawn)] & pinD12;
            while (pinnedPiece != chess.EMPTY) {
                const from: u8 = chess.bitscan(pinnedPiece);
                pinnedPiece &= pinnedPiece - 1;

                const att = chess.getPawnAttacks(@enumFromInt(from), white);
                const toAtt_bb = att & kingDiags & p_board.c_occupiedBB[@intFromBool(!white)];
                genericStagedMovePushCapture(p_out, toAtt_bb, from);
            }
            pinnedPiece = p_moveBB.promotionMoves & p_board.occupiedBB & pinD12;
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

    const validPawnLoc = unPinnedBB & p_board.pieceBB[@intFromEnum(pPawn)];
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
        var bb = p_moveBB.promotionMoves & p_board.occupiedBB;
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
            bb = (p_moveBB.promotionMoves & ~p_board.occupiedBB & (unPinnedBB << 8));
        } else {
            bb = (p_moveBB.promotionMoves & ~p_board.occupiedBB & (unPinnedBB >> 8));
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
        while (bb != chess.EMPTY) {
            const to: u8 = chess.bitscan(bb);
            bb &= bb - 1;

            const att = chess.getPawnAttacks(@enumFromInt(to), opp);
            var toAtt_bb = att & validPawnLoc;
            while (toAtt_bb != chess.EMPTY) {
                const from: u8 = chess.bitscan(toAtt_bb);
                toAtt_bb &= toAtt_bb - 1;
                _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.ENPASSANT), p_out);
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
    var pieceBB = p_board.pieceBB[@intFromEnum(pBishop)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const allAtt = chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(from)) & p_moveBB.bishopMoves;

        if (comptime generateCapture) {
            genericStagedMovePushCapture(p_out, allAtt & p_board.occupiedBB, from);
        }
        if (comptime generateQuiet) {
            genericStagedMovePushQuiet(p_out, allAtt & (~p_board.occupiedBB), from);
        }
    }

    // rook BB
    pieceBB = p_board.pieceBB[@intFromEnum(pRook)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const allAtt = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(from)) & p_moveBB.rookMoves;
        if (comptime generateCapture) {
            genericStagedMovePushCapture(p_out, allAtt & p_board.occupiedBB, from);
        }
        if (comptime generateQuiet) {
            genericStagedMovePushQuiet(p_out, allAtt & (~p_board.occupiedBB), from);
        }
    }

    // queen BB
    pieceBB = p_board.pieceBB[@intFromEnum(pQueen)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const allAtt = (chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(from)) | chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(from))) & p_moveBB.queenMoves;
        if (comptime generateCapture) {
            genericStagedMovePushCapture(p_out, allAtt & p_board.occupiedBB, from);
        }
        if (comptime generateQuiet) {
            genericStagedMovePushQuiet(p_out, allAtt & (~p_board.occupiedBB), from);
        }
    }

    // knight BB
    pieceBB = p_board.pieceBB[@intFromEnum(pKnight)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const fromBB = chess.xToBitboard(from);
        const allAtt = chess.knightAttacks(fromBB) & p_moveBB.knightMoves;

        if (comptime generateCapture) {
            genericStagedMovePushCapture(p_out, allAtt & p_board.occupiedBB, from);
        }
        if (comptime generateQuiet) {
            genericStagedMovePushQuiet(p_out, allAtt & (~p_board.occupiedBB), from);
        }
    }
    // king BB
    p_moveBB.kingMoves &= ~allAttacks;
    pieceBB = p_board.pieceBB[@intFromEnum(pKing)];

    const from: u8 = chess.bitscan(pieceBB);

    if (comptime generateCapture) {
        genericStagedMovePushCapture(p_out, p_moveBB.kingMoves & p_board.occupiedBB, from);
    }
    if (comptime generateQuiet) {
        genericStagedMovePushQuiet(p_out, p_moveBB.kingMoves & (~p_board.occupiedBB), from);
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

pub inline fn moveGeneration(p_board: *const Board_state) moveContainer {
    if (p_board.whiteToMove()) {
        return cst_moveGeneration(p_board, true);
    }
    return cst_moveGeneration(p_board, false);
}

pub fn cst_moveGeneration(p_board: *const Board_state, comptime white: bool) moveContainer {
    // Generates all the moves from the given board state

    var ret: moveContainer = .{};

    const emptyOrEnemy = ~p_board.c_occupiedBB[@intFromBool(white)];

    if (comptime white) {
        white_PieceMovePawnMask(p_board, &ret);
    } else {
        black_PieceMovePawnMask(p_board, &ret);
    }

    t_PieceMoveMask(p_board, white, .nWhiteKnight, emptyOrEnemy, &ret);
    t_PieceMoveMask(p_board, white, .nWhiteBishop, emptyOrEnemy, &ret);
    t_PieceMoveMask(p_board, white, .nWhiteRook, emptyOrEnemy, &ret);
    t_PieceMoveMask(p_board, white, .nWhiteQueen, emptyOrEnemy, &ret);
    _PieceMoveKingMask(p_board, white, emptyOrEnemy, &ret);
    return ret;
}

pub fn moveBitBoardToIMove_pawn(piece_bb: u64, attack_bb: u64, flags: u6, p_out: *moveContainer, comptime white: bool) void {
    if (attack_bb == 0) {
        return;
    }
    const sq: u8 = chess.bitscan(piece_bb);
    var _bb = attack_bb;
    var enpass_capture_pawn: e_piece = e_piece.nBlackPawn;
    if (comptime !white) {
        enpass_capture_pawn = e_piece.nWhitePawn;
    }
    while (_bb != 0) {
        const lsb: u8 = chess.bitscan(_bb);
        _bb &= _bb - 1;
        const _curr_move = movel.build_move(sq, lsb, flags);
        p_out.append(_curr_move);
    }
    return;
}

pub fn white_PieceMovePawnMask(p_board: *const Board_state, p_out: *moveContainer) void {
    var _bb_piece: u64 = p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)];
    const freeBB = ~p_board.occupiedBB;
    const enemyBB = p_board.c_occupiedBB[@intFromBool(false)];
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        const sqRank = chess.getSqIdxRank(sq);
        const curr_pos = chess.xToBitboard(sq);
        const singlePushBB = curr_pos << 8;

        if (sqRank == 6) {
            _moveBitBoardToIMove_pawn(curr_pos, (singlePushBB) & (freeBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, true);
            _moveBitBoardToIMove_pawn(curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), true) & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, true);
            continue;
        }

        if (sqRank == 1 and ((singlePushBB & freeBB)) != 0) {
            moveBitBoardToIMove_pawn(curr_pos, ((singlePushBB & freeBB) << 8) & (freeBB), @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, true);
        }
        genericStagedMovePushQuiet(p_out, (singlePushBB & freeBB), sq);
        genericStagedMovePushCapture(p_out, (chess.getPawnAttacks(@enumFromInt(sq), true) & enemyBB), sq);

        const enPassantBB = chess.xToBitboard(p_board.enPassantIdx);
        moveBitBoardToIMove_pawn(curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), true) & enPassantBB & chess.whitePawnEnpassantRank & (freeBB)), @intFromEnum(e_moveFlags.ENPASSANT), p_out, true);
    }
    return;
}

pub fn black_PieceMovePawnMask(p_board: *const Board_state, p_out: *moveContainer) void {
    var _bb_piece: u64 = p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)];
    const freeBB = ~p_board.occupiedBB;
    const enemyBB = p_board.c_occupiedBB[@intFromBool(true)];
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        const sqRank = chess.getSqIdxRank(sq);
        const curr_pos = chess.xToBitboard(sq);
        const singlePushBB = curr_pos >> 8;

        if (sqRank == 1) {
            _moveBitBoardToIMove_pawn(curr_pos, (singlePushBB) & (freeBB), 0, p_out, false);
            _moveBitBoardToIMove_pawn(curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), false) & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, false);
            continue;
        }

        if (sqRank == 6 and ((singlePushBB & freeBB)) != 0) {
            moveBitBoardToIMove_pawn(curr_pos, ((singlePushBB) >> 8) & (freeBB), @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, false);
        }
        genericStagedMovePushQuiet(p_out, (singlePushBB & freeBB), sq);
        genericStagedMovePushCapture(p_out, (chess.getPawnAttacks(@enumFromInt(sq), false) & enemyBB), sq);

        const enPassantBB = chess.xToBitboard(p_board.enPassantIdx);
        moveBitBoardToIMove_pawn(curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), false) & enPassantBB & freeBB & chess.blackPawnEnpassantRank), @intFromEnum(e_moveFlags.ENPASSANT), p_out, false);
    }
    return;
}
pub fn t_PieceMoveMask(p_board: *const Board_state, comptime white: bool, comptime piece: e_piece, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var _piece: u8 = @intFromEnum(piece);
    if (comptime !white) {
        _piece += chess.N_PIECES_TYPES;
    }
    var bb_piece = p_board.pieceBB[_piece];
    var att: u64 = 0;
    while (bb_piece != 0) {
        const sq = chess.bitscan(bb_piece);
        bb_piece &= bb_piece - 1;
        if (comptime piece == .nWhiteKnight) {
            att = chess.knightAttacks(chess.xToBitboard(sq)) & emptyOrEnemy;
        } else if (comptime piece == .nWhiteBishop) {
            att = chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq)) & emptyOrEnemy;
        } else if (comptime piece == .nWhiteRook) {
            att = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(sq)) & emptyOrEnemy;
        } else if (comptime piece == .nWhiteQueen) {
            att = chess.getQueenAttacks(p_board.occupiedBB, @enumFromInt(sq)) & emptyOrEnemy;
        }
        genericStagedMovePushCapture(p_out, att & p_board.occupiedBB, sq);
        genericStagedMovePushQuiet(p_out, att & ~p_board.occupiedBB, sq);
    }
    return;
}

pub fn _PieceMoveKingMask(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var piece = e_piece.nBlackKing;
    if (comptime white) {
        piece = e_piece.nWhiteKing;
    }
    const sq = p_board.getKingSq(white);
    const att = chess.getKingAttacks(sq) & emptyOrEnemy;

    genericStagedMovePushCapture(p_out, att & p_board.occupiedBB, @intFromEnum(sq));
    genericStagedMovePushQuiet(p_out, att & ~p_board.occupiedBB, @intFromEnum(sq));
    if (p_board.canKingSideCastle(white)) {
        _ = movel.build_move_in(@intFromEnum(sq), @intFromEnum(sq) + 2, @intFromEnum(e_moveFlags.KINGCASTLE), p_out);
    }

    if (p_board.canQueenSideCastle(white)) {
        _ = movel.build_move_in(@intFromEnum(sq), @intFromEnum(sq) - 2, @intFromEnum(e_moveFlags.QUEENCASTLE), p_out);
    }
    return;
}

pub fn _moveBitBoardToIMove_pawn(piece_bb: u64, attack_bb: u64, flags: u6, p_out: *moveContainer, comptime white: bool) void {
    moveBitBoardToIMove_pawn(piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.KNIGHTPROMO), p_out, white);
    moveBitBoardToIMove_pawn(piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.BISHOPPROMO), p_out, white);
    moveBitBoardToIMove_pawn(piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.ROOKPROMO), p_out, white);
    moveBitBoardToIMove_pawn(piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.QUEENPROMO), p_out, white);
}

pub fn filterMoveLegal(p_state: *const Board_state, move_list: *moveContainer, white: bool) moveContainer {
    // goal compared to filterMoveLegal: try to not use the make/undo Moves methods
    var ret: moveContainer = .{};
    const cached = getCachedAttackingPiece(p_state, white);
    const all_attacks = chess.getAllAttackMask(p_state, p_state.occupiedBB, !white);

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

pub fn getCachedAttackingPiece(p_state: *const Board_state, white: bool) [2]u64 {
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

pub fn moveGenPawnBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.pawnMoves = chess.EMPTY;
    p_out.pawnAttacks = chess.EMPTY;
    p_out.doubleMoves = chess.EMPTY;
    p_out.enPassantMoves = chess.EMPTY;

    const enPassantBB = chess.xToBitboard(p_board.enPassantIdx);
    if (comptime white) {
        const piece_idx: u8 = @intFromEnum(e_piece.nWhitePawn);
        p_out.pawnMoves |= (p_board.pieceBB[piece_idx] << 8) & (~p_board.occupiedBB);
        p_out.doubleMoves |= ((p_out.pawnMoves << 8) & (~p_board.occupiedBB)) & ((p_board.pieceBB[piece_idx] & chess.whitePawnDoubleRank) << 16);

        p_out.pawnAttacks |= chess.getPawnAttacksFromBB(p_board.pieceBB[piece_idx], true);

        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.whitePawnEnpassantRank;

        p_out.pawnAttacks &= (emptyOrEnemy & p_board.occupiedBB);
        //p_out.pawnAttacks &= (p_board.c_occupiedBB[@intFromBool(false)]);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.whitePawnPromoRank);
        p_out.pawnAttacks &= ~chess.whitePawnPromoRank;
        p_out.pawnMoves &= ~chess.whitePawnPromoRank;
    } else {
        const piece_idx: u8 = @intFromEnum(e_piece.nBlackPawn);
        p_out.pawnMoves |= (p_board.pieceBB[piece_idx] >> 8) & (~p_board.occupiedBB);
        p_out.doubleMoves |= ((p_out.pawnMoves >> 8) & (~p_board.occupiedBB)) & ((p_board.pieceBB[piece_idx] & chess.blackPawnDoubleRank) >> 16);

        p_out.pawnAttacks |= chess.getPawnAttacksFromBB(p_board.pieceBB[piece_idx], false);

        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.blackPawnEnpassantRank;

        //p_out.pawnAttacks &= (p_board.c_occupiedBB[@intFromBool(true)]);
        p_out.pawnAttacks &= (emptyOrEnemy & p_board.occupiedBB);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.blackPawnPromoRank);
        p_out.pawnAttacks &= ~chess.blackPawnPromoRank;
        p_out.pawnMoves &= ~chess.blackPawnPromoRank;
    }
}

pub inline fn moveGenKnightBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.knightMoves = (chess.knightAttacks(p_board.getPieceBB(.nWhiteKnight))) & emptyOrEnemy;
    } else {
        p_out.knightMoves = (chess.knightAttacks(p_board.getPieceBB(.nBlackKnight))) & emptyOrEnemy;
    }
}

pub fn moveGenKingBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.kingMoves = chess.getKingAttacks(p_board.wKingSq) & emptyOrEnemy;
        const kingBB = p_board.getPieceBB(.nWhiteKing);
        if (p_board.canQueenSideCastle(white)) {
            p_out.queenSideCastlingMoves |= (kingBB >> 2);
        }
        if (p_board.canKingSideCastle(white)) {
            p_out.kingSideCastlingMoves |= (kingBB << 2);
        }
    } else {
        p_out.kingMoves = chess.getKingAttacks(p_board.bKingSq) & emptyOrEnemy;
        const kingBB = p_board.getPieceBB(.nBlackKing);
        if (p_board.canQueenSideCastle(white)) {
            p_out.queenSideCastlingMoves |= (kingBB >> 2);
        }
        if (p_board.canKingSideCastle(white)) {
            p_out.kingSideCastlingMoves |= (kingBB << 2);
        }
    }
}
pub inline fn moveGenBishopBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.bishopMoves = chess._AllAttackBishopMask(p_board.getPieceBB(.nWhiteBishop), p_board.occupiedBB) & emptyOrEnemy;
    } else {
        p_out.bishopMoves = chess._AllAttackBishopMask(p_board.getPieceBB(.nBlackBishop), p_board.occupiedBB) & emptyOrEnemy;
    }
}
pub inline fn moveGenRookBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.rookMoves = chess._AllAttackRookMask(p_board.getPieceBB(.nWhiteRook), p_board.occupiedBB) & emptyOrEnemy;
    } else {
        p_out.rookMoves = chess._AllAttackRookMask(p_board.getPieceBB(.nBlackRook), p_board.occupiedBB) & emptyOrEnemy;
    }
}

pub inline fn moveGenQueenBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.queenMoves = chess._AllAttackQueenMask(p_board.getPieceBB(.nWhiteQueen), p_board.occupiedBB) & emptyOrEnemy;
    } else {
        p_out.queenMoves = chess._AllAttackQueenMask(p_board.getPieceBB(.nBlackQueen), p_board.occupiedBB) & emptyOrEnemy;
    }
}

pub inline fn moveGenBB(p_board: *const Board_state) moveBBState {
    var ret: moveBBState = .{};
    if (p_board.whiteToMove()) {
        cst_moveGenBB(p_board, true, &ret);
        return ret;
    }
    cst_moveGenBB(p_board, false, &ret);
    return ret;
}
pub inline fn _cst_moveGenBB(p_board: *const Board_state, comptime white: bool) moveBBState {
    var ret: moveBBState = .{};
    cst_moveGenBB(p_board, white, &ret);
    return ret;
}
pub fn cst_moveGenBB(p_board: *const Board_state, comptime white: bool, p_out: *moveBBState) void {
    const EmptyOrEnemy = ~p_board.c_occupiedBB[@intFromBool(white)];
    moveGenPawnBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenKnightBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenBishopBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenRookBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenQueenBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenKingBB(p_board, white, EmptyOrEnemy, p_out);
}
pub inline fn _cst_moveGenBB_all(p_board: *const Board_state, comptime white: bool) moveBBState {
    var ret: moveBBState = .{};
    cst_moveGenBB_all(p_board, white, &ret);
    return ret;
}
pub fn cst_moveGenBB_all(p_board: *const Board_state, comptime white: bool, p_out: *moveBBState) void {
    const EmptyOrEnemy = chess.UNIVERSE;
    moveGenPawnBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenKnightBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenBishopBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenRookBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenQueenBB(p_board, white, EmptyOrEnemy, p_out);
    moveGenKingBB(p_board, white, EmptyOrEnemy, p_out);
}

pub const qbb = struct {
    bb: [4]u64,
    pub fn init(bb: u64) qbb {
        return .{ .bb = [_]u64{ bb, bb, bb, bb } };
    }
    pub fn lShift(self: qbb, other: qbb) qbb {
        return .{ .bb = [_]u64{
            self.bb[0] << @intCast(other.bb[0]),
            self.bb[1] << @intCast(other.bb[1]),
            self.bb[2] << @intCast(other.bb[2]),
            self.bb[3] << @intCast(other.bb[3]),
        } };
    }
    pub fn lShift_eq(self: *qbb, other: *qbb) void {
        self.bb[0] <<= @intCast(other.bb[0]);
        self.bb[1] <<= @intCast(other.bb[1]);
        self.bb[2] <<= @intCast(other.bb[2]);
        self.bb[3] <<= @intCast(other.bb[3]);
    }
    pub fn rShift(self: qbb, other: qbb) qbb {
        return .{ .bb = [_]u64{
            self.bb[0] >> @intCast(other.bb[0]),
            self.bb[1] >> @intCast(other.bb[1]),
            self.bb[2] >> @intCast(other.bb[2]),
            self.bb[3] >> @intCast(other.bb[3]),
        } };
    }
    pub fn rShift_eq(self: *qbb, other: *qbb) void {
        self.bb[0] >>= @intCast(other.bb[0]);
        self.bb[1] >>= @intCast(other.bb[1]);
        self.bb[2] >>= @intCast(other.bb[2]);
        self.bb[3] >>= @intCast(other.bb[3]);
    }

    pub fn bbAnd(self: qbb, other: qbb) qbb {
        return .{ .bb = [_]u64{
            self.bb[0] & other.bb[0],
            self.bb[1] & other.bb[1],
            self.bb[2] & other.bb[2],
            self.bb[3] & other.bb[3],
        } };
    }
    pub fn bbAnd_eq(self: *qbb, other: *qbb) void {
        self.bb[0] &= other.bb[0];
        self.bb[1] &= other.bb[1];
        self.bb[2] &= other.bb[2];
        self.bb[3] &= other.bb[3];
    }
    pub fn bbOr(self: qbb, other: qbb) qbb {
        return .{ .bb = [_]u64{
            self.bb[0] | other.bb[0],
            self.bb[1] | other.bb[1],
            self.bb[2] | other.bb[2],
            self.bb[3] | other.bb[3],
        } };
    }
    pub fn bbOr_eq(self: *qbb, other: *qbb) void {
        self.bb[0] |= other.bb[0];
        self.bb[1] |= other.bb[1];
        self.bb[2] |= other.bb[2];
        self.bb[3] |= other.bb[3];
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
    _qsliders = (_qsliders.lShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.lShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.lShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.lShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.lShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.rShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);
    return (qflood.lShift(qshift)).bbAnd(qmask);
}
pub fn west_sout_soEa_soWe_Attacks(qsliders: qbb, free: u64) qbb {
    var qmask: qbb = .{ .bb = .{ chess.notHFile, chess.UNIVERSE, chess.notAFile, chess.notHFile } };
    const qshift: qbb = .{ .bb = .{ 1, 8, 7, 9 } };
    var qfree = qbb.init(free);
    qfree.bbAnd_eq(&qmask);
    var _qsliders = qsliders;
    var qflood = qsliders;
    _qsliders = (_qsliders.rShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.rShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.rShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.rShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.rShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    _qsliders = (_qsliders.rShift(qshift)).bbAnd(qfree);
    qflood.bbOr_eq(&_qsliders);

    return (qflood.rShift(qshift)).bbAnd(qmask);
}
pub fn avx2DumbFill(p_state: *const Board_state, comptime white: bool) qbb {
    if (comptime white) {
        const rq = p_state.getPieceBB(.nWhiteRook) | p_state.getPieceBB(.nWhiteQueen);
        const bq = p_state.getPieceBB(.nWhiteBishop) | p_state.getPieceBB(.nWhiteQueen);
        const pieceQBB: qbb = .{ .bb = [4]u64{ rq, rq, bq, bq } };
        const free = ~p_state.occupiedBB;
        var posBB = east_nort_noWe_noEa_Attacks(pieceQBB, free);
        const negBB = west_sout_soEa_soWe_Attacks(pieceQBB, free);
        return posBB.bbOr(negBB);
    } else {
        const rq = p_state.getPieceBB(.nBlackRook) | p_state.getPieceBB(.nBlackQueen);
        const bq = p_state.getPieceBB(.nBlackBishop) | p_state.getPieceBB(.nBlackQueen);
        const pieceQBB: qbb = .{ .bb = [4]u64{ rq, rq, bq, bq } };
        const free = ~p_state.occupiedBB;
        var posBB = east_nort_noWe_noEa_Attacks(pieceQBB, free);
        const negBB = west_sout_soEa_soWe_Attacks(pieceQBB, free);
        return posBB.bbOr(negBB);
    }
}
pub fn getPinned_avx2(p_state: *const Board_state, comptime white: bool) u64 {
    var free = ~p_state.occupiedBB;
    if (comptime white) {
        const k = p_state.getPieceBB(.nWhiteKing);
        const k_qbb = qbb.init(k);
        var attackers = avx2DumbFill(p_state, false);
        free ^= (attackers.collapse() & p_state.c_occupiedBB[@intFromBool(true)]);
        var kingBB = east_nort_noWe_noEa_Attacks(k_qbb, free);
        var negBB = west_sout_soEa_soWe_Attacks(k_qbb, free);
        kingBB.bbOr_eq(&negBB);
        kingBB.bbAnd_eq(&attackers);
        return kingBB.collapse();
    } else {
        const k = p_state.getPieceBB(.nBlackKing);
        const k_qbb = qbb.init(k);
        var attackers = avx2DumbFill(p_state, true);
        free ^= (attackers.collapse() & p_state.c_occupiedBB[@intFromBool(false)]);
        var kingBB = east_nort_noWe_noEa_Attacks(k_qbb, free);
        var negBB = west_sout_soEa_soWe_Attacks(k_qbb, free);
        kingBB.bbOr_eq(&negBB);
        kingBB.bbAnd_eq(&attackers);
        return kingBB.collapse();
    }
}

pub fn getPinned_(p_state: *const Board_state, comptime white: bool, king_E: e_square, rq: u64, bq: u64) u64 {
    var pinned: u64 = 0;
    var pinner = chess.xrayRookAttacks(p_state.occupiedBB, p_state.c_occupiedBB[@intFromBool(white)], king_E) & rq;
    while (pinner != chess.EMPTY) {
        const pinsq = chess.bitscan(pinner);
        pinner &= pinner - 1;
        pinned |= chess.inBetween(@enumFromInt(pinsq), king_E);
    }

    pinner = chess.xrayBishopAttacks(p_state.occupiedBB, p_state.c_occupiedBB[@intFromBool(white)], king_E) & bq;
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

pub fn moveDeliverCheck(p_state: *const chess.Board_state, move: movel.IMove) bool {
    const white: bool = p_state.whiteToMove();
    const fromSq = move.getFrom();
    const fromBB = chess.xToBitboard(fromSq);
    if ((p_state.pinnedBB & fromBB) != 0) {
        return true;
    }
    var piece = p_state.get_piece(fromSq);
    const toSq = move.getTo();
    if (move.isPromotion()) {
        piece = chess.flagPromotionToPiece(move.getFlag(), white);
    }
    // TODO: get castling checks in here
    if (chess.isKingPiece(piece)) {
        return false;
    }
    const att = chess.getRelevantAttacks(piece, @enumFromInt(toSq), p_state.occupiedBB ^ fromBB);
    return (att & p_state.getKingBB(!white)) != 0;
}
