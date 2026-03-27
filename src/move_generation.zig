const build_options = @import("build_options");

const chess = @import("chess.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const tablel = @import("moveTables.zig");
const magicl = @import("magic.zig");
const utilsl = @import("utils.zig");

const std = @import("std");

const moveContainer = movel.moveContainer;
const IMove = movel.IMove;
const moveBBState = movel.moveBBState;
const magicRecord = magicl.magicRecord;

const squareInfo = squarel.squareInfo;
const e_square = squarel.e_square;

const e_piece = chess.e_piece;
const e_moveFlags = movel.e_moveFlags;
const e_moveCategory = movel.e_moveCategory;

const Board_state = chess.Board_state;

const fastBitscan = build_options.fastBitscan;
const ignoreChecks = build_options.fastBitscan;
const useMagic = build_options.useMagic;
const useStaged = build_options.useStaged;
const useDebug = build_options.useDebug;

pub inline fn generateLegalMoves(p_board: *const Board_state) moveContainer {
    if (comptime useStaged) {
        var bbMoves = moveGenBB(p_board);
        var moves: moveContainer = undefined;
        moves.len = 0;
        moveGenBBToMoveContainer(p_board, &bbMoves, &moves);
        //if (comptime useDebug) {
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
        return moveGenBBToMoveContainer(p_board, &bbMoves, p_out);
    } else {
        @panic("Not implemented");
    }
}

pub fn generateMoveCountLegalMoves(p_board: *const Board_state, white: bool) usize {
    if (white) {
        var moves = white_moveGeneration(p_board);
        return filterCountMoveLegal(p_board, &moves, white);
    } else {
        var moves = black_moveGeneration(p_board);
        return filterCountMoveLegal(p_board, &moves, white);
    }
}

pub fn push_promotion(from: u8, to: u8, piece: e_piece, p_out: *moveContainer) void {
    var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), piece);
    move.setFlag(@intFromEnum(e_moveFlags.KNIGHTPROMO));
    p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.BISHOPPROMO));
    p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.ROOKPROMO));
    p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.QUEENPROMO));
    p_out.append(move);
}

pub fn push_promotion_capture(from: u8, to: u8, piece: e_piece, cPiece: e_piece, p_out: *moveContainer) void {
    var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.CAPTURE), piece);
    move.setCapture(cPiece);
    move.setFlag(@intFromEnum(e_moveFlags.KNIGHTPROMOCAPTURE));
    p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.BISHOPPROMOCAPTURE));
    p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.ROOKPROMOCAPTURE));
    p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.QUEENPROMOCAPTURE));
    p_out.append(move);
}

pub inline fn moveGenBBToMoveContainer(p_board: *const Board_state, p_moveBB: *moveBBState, p_out: *moveContainer) void {
    if (p_board.whiteToMove()) {
        return cst_moveGenBBToMoveContainer(p_board, p_moveBB, true, p_out);
    }
    return cst_moveGenBBToMoveContainer(p_board, p_moveBB, false, p_out);
}
pub fn cst_moveGenBBToMoveContainer(p_board: *const Board_state, p_moveBB: *moveBBState, comptime white: bool, p_out: *moveContainer) void {
    var pawnDir: i8 = 8;
    var pPawn: e_piece = .nWhitePawn;
    var opPawn: e_piece = .nBlackPawn;
    var pBishop: e_piece = .nWhiteBishop;
    var pRook: e_piece = .nWhiteRook;
    var pQueen: e_piece = .nWhiteQueen;
    var pKnight: e_piece = .nWhiteKnight;
    var pKing: e_piece = .nWhiteKing;
    var kingSq = p_board.wKingSq;
    var emptyOrEnem: u64 = ~p_board.c_occupiedBB[@intFromBool(true)];
    const opp = !white;
    if (comptime !white) {
        pawnDir = -8;
        pPawn = .nBlackPawn;
        opPawn = .nWhitePawn;
        pBishop = .nBlackBishop;
        pRook = .nBlackRook;
        pQueen = .nBlackQueen;
        pKnight = .nBlackKnight;
        pKing = .nBlackKing;
        kingSq = p_board.bKingSq;
        emptyOrEnem = ~p_board.c_occupiedBB[@intFromBool(false)];
    }

    const allAttacks = chess.getAllAttackMask(p_board, p_board.occupiedBB ^ p_board.pieceBB[@intFromEnum(pKing)], opp);

    const kingSqInfo = squarel.squareInfo.init(kingSq);

    //source: https://www.codeproject.com/articles/Worlds-Fastest-Bitboard-Chess-Movegenerator
    const kingDiags = kingSqInfo.getDiagonalsBB();
    const kingLines = kingSqInfo.getHorizontalBB();
    const pinHV = p_board.pinnedBB & kingLines;
    const pinD12 = p_board.pinnedBB & kingDiags;

    const unPinnedBB = ~p_board.pinnedBB;
    const inCheck: bool = p_board.checkersBB != 0;
    if (inCheck) {
        const doubleCheck: bool = chess.l_popcount(p_board.checkersBB & p_board.occupiedBB) > 1;
        if (doubleCheck) {
            // only king moves
            const kingBB = p_moveBB.kingMoves;
            p_moveBB.resetAll();
            p_moveBB.kingMoves = kingBB;
        } else {
            // only blocking / capturing moves for non king pieces
            const kingBB = p_moveBB.kingMoves;
            if (comptime white) {
                p_moveBB.enPassantMoves = p_moveBB.enPassantMoves >> 8;
                p_moveBB.andEq(p_board.checkersBB);
                p_moveBB.enPassantMoves = p_moveBB.enPassantMoves << 8;
            } else {
                p_moveBB.enPassantMoves = p_moveBB.enPassantMoves << 8;
                p_moveBB.andEq(p_board.checkersBB);
                p_moveBB.enPassantMoves = p_moveBB.enPassantMoves >> 8;
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
            const pieceSq: u8 = chess.bitscan(pinnedPiece);
            const pieceSq_E: e_square = @enumFromInt(pieceSq);
            const piece = p_board.get_piece(pieceSq);
            pinnedPiece &= pinnedPiece - 1;
            const permittedMoves = chess.getBishopAttacks(p_board.occupiedBB, pieceSq_E) & kingDiags & emptyOrEnem;
            var quietMoves = permittedMoves & (~p_board.occupiedBB);
            while (quietMoves != chess.EMPTY) {
                const to: u8 = chess.bitscan(quietMoves);
                quietMoves &= quietMoves - 1;
                _ = movel.build_move_in(pieceSq, to, @intFromEnum(e_moveFlags.QUIETMOVE), piece, p_out);
            }
            var attMoves = permittedMoves & p_board.occupiedBB;
            while (attMoves != chess.EMPTY) {
                const to: u8 = chess.bitscan(attMoves);
                const cPiece = p_board.get_piece(to);
                attMoves &= attMoves - 1;
                var pMove = movel.build_move_in(pieceSq, to, @intFromEnum(e_moveFlags.CAPTURE), piece, p_out);
                pMove.setCapture(cPiece);
            }
        }
        // rook and queen
        pinnedPiece = (p_board.pieceBB[@intFromEnum(pRook)] | p_board.pieceBB[@intFromEnum(pQueen)]) & pinHV;
        while (pinnedPiece != chess.EMPTY) {
            const pieceSq: u8 = chess.bitscan(pinnedPiece);
            const pieceSq_E: e_square = @enumFromInt(pieceSq);
            const piece = p_board.get_piece(pieceSq);
            pinnedPiece &= pinnedPiece - 1;
            const permittedMoves = chess.getRookAttacks(p_board.occupiedBB, pieceSq_E) & kingLines & emptyOrEnem;
            var quietMoves = permittedMoves & (~p_board.occupiedBB);
            while (quietMoves != chess.EMPTY) {
                const to: u8 = chess.bitscan(quietMoves);
                quietMoves &= quietMoves - 1;
                _ = movel.build_move_in(pieceSq, to, @intFromEnum(e_moveFlags.QUIETMOVE), piece, p_out);
            }
            var attMoves = permittedMoves & p_board.occupiedBB;
            while (attMoves != chess.EMPTY) {
                const to: u8 = chess.bitscan(attMoves);
                const cPiece = p_board.get_piece(to);
                attMoves &= attMoves - 1;
                var pMove = movel.build_move_in(pieceSq, to, @intFromEnum(e_moveFlags.CAPTURE), piece, p_out);
                pMove.setCapture(cPiece);
            }
        }

        // pawn pin handling
        // push only possible if to in pinHV
        // capture only if to in pinD12
        // enPassant never okay
        // promotion only when capturing
        // pinnedPiece = p_moveBB.pawnMoves & pinHV;
        pinnedPiece = (p_board.pieceBB[@intFromEnum(pPawn)] & pinHV);
        while (pinnedPiece != chess.EMPTY) {
            const from: u8 = chess.bitscan(pinnedPiece);
            pinnedPiece &= pinnedPiece - 1;
            const to: i8 = @as(i8, @intCast(from)) + pawnDir;
            const _to: u8 = @intCast(to);
            if (chess.xToBitboard(_to) & pinHV != chess.EMPTY) {
                _ = movel.build_move_in(from, _to, @intFromEnum(e_moveFlags.QUIETMOVE), pPawn, p_out);
            }
        }
        pinnedPiece = p_moveBB.doubleMoves & pinHV;
        while (pinnedPiece != chess.EMPTY) {
            const to: u8 = chess.bitscan(pinnedPiece);
            pinnedPiece &= pinnedPiece - 1;
            const from: i8 = @as(i8, @intCast(to)) - (pawnDir << 1);
            _ = movel.build_move_in(@intCast(from), to, @intFromEnum(e_moveFlags.DOUBLEPAWN), pPawn, p_out);
        }

        pinnedPiece = p_board.pieceBB[@intFromEnum(pPawn)] & pinD12;
        while (pinnedPiece != chess.EMPTY) {
            const from: u8 = chess.bitscan(pinnedPiece);
            pinnedPiece &= pinnedPiece - 1;

            const att = chess.getPawnAttacks(@enumFromInt(from), white);
            var toAtt_bb = att & kingDiags & p_board.c_occupiedBB[@intFromBool(!white)];
            if (toAtt_bb != chess.EMPTY) {
                const to: u8 = chess.bitscan(toAtt_bb);
                toAtt_bb &= toAtt_bb - 1;
                const cPiece = p_board.get_piece(to);
                var pMove = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.CAPTURE), pPawn, p_out);
                pMove.setCapture(cPiece);
            }
        }
        pinnedPiece = p_moveBB.promotionMoves & p_board.occupiedBB & pinD12;
        const validPawnAttLoc: u64 = chess.EMPTY;
        while (pinnedPiece != chess.EMPTY) {
            const to: u8 = chess.bitscan(pinnedPiece);
            pinnedPiece &= pinnedPiece - 1;
            var att = chess.getPawnAttacks(@enumFromInt(to), opp) & validPawnAttLoc;
            const cPiece = p_board.get_piece(to);
            if (att != chess.EMPTY) {
                const from: u8 = chess.bitscan(att);
                att &= att - 1;
                push_promotion_capture(from, to, pPawn, cPiece, p_out);
            }
        }
    }

    const validPawnLoc = unPinnedBB & p_board.pieceBB[@intFromEnum(pPawn)];
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
        _ = movel.build_move_in(@intCast(from), to, @intFromEnum(e_moveFlags.QUIETMOVE), pPawn, p_out);
    }

    bb = p_moveBB.promotionMoves & p_board.occupiedBB;
    while (bb != chess.EMPTY) {
        const to: u8 = chess.bitscan(bb);
        bb &= bb - 1;
        var att = chess.getPawnAttacks(@enumFromInt(to), opp) & validPawnLoc;
        const cPiece = p_board.get_piece(to);
        while (att != chess.EMPTY) {
            const from: u8 = chess.bitscan(att);
            att &= att - 1;
            push_promotion_capture(from, to, pPawn, cPiece, p_out);
        }
    }
    if (comptime white) {
        bb = (p_moveBB.promotionMoves & ~p_board.occupiedBB & (unPinnedBB << 8));
    } else {
        bb = (p_moveBB.promotionMoves & ~p_board.occupiedBB & (unPinnedBB >> 8));
    }
    while (bb != chess.EMPTY) {
        const to: u8 = chess.bitscan(bb);
        const from: i8 = @as(i8, @intCast(to)) - pawnDir;
        bb &= bb - 1;
        push_promotion(@intCast(from), to, pPawn, p_out);
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
        _ = movel.build_move_in(@intCast(from), to, @intFromEnum(e_moveFlags.DOUBLEPAWN), pPawn, p_out);
    }

    bb = p_moveBB.enPassantMoves;
    while (bb != chess.EMPTY) {
        const to: u8 = chess.bitscan(bb);
        bb &= bb - 1;

        const att = chess.getPawnAttacks(@enumFromInt(to), opp);
        var toAtt_bb = att & validPawnLoc;
        while (toAtt_bb != chess.EMPTY) {
            const from: u8 = chess.bitscan(toAtt_bb);
            toAtt_bb &= toAtt_bb - 1;
            var pMove = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.ENPASSANT), pPawn, p_out);
            pMove.setCapture(opPawn);
        }
    }

    bb = p_moveBB.pawnAttacks;
    while (bb != chess.EMPTY) {
        const to: u8 = chess.bitscan(bb);
        const cPiece = p_board.get_piece(to);
        bb &= bb - 1;
        const att = chess.getPawnAttacks(@enumFromInt(to), opp);
        var toAtt_bb = att & validPawnLoc;
        while (toAtt_bb != chess.EMPTY) {
            const from: u8 = chess.bitscan(toAtt_bb);
            toAtt_bb &= toAtt_bb - 1;
            var pMove = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.CAPTURE), pPawn, p_out);
            pMove.setCapture(cPiece);
        }
    }

    // bishop BB
    var pieceBB = p_board.pieceBB[@intFromEnum(pBishop)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const allAtt = chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(from)) & p_moveBB.bishopMoves;

        var attCapture = allAtt & p_board.occupiedBB;
        while (attCapture != chess.EMPTY) {
            const to: u8 = chess.bitscan(attCapture);
            attCapture &= attCapture - 1;
            var pMove = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.CAPTURE), pBishop, p_out);
            pMove.setCapture(p_board.get_piece(to));
        }
        var attQuiet = allAtt & (~p_board.occupiedBB);
        while (attQuiet != chess.EMPTY) {
            const to: u8 = chess.bitscan(attQuiet);
            attQuiet &= attQuiet - 1;
            _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pBishop, p_out);
        }
    }

    // rook BB
    pieceBB = p_board.pieceBB[@intFromEnum(pRook)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const allAtt = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(from)) & p_moveBB.rookMoves;

        var attCapture = allAtt & p_board.occupiedBB;
        while (attCapture != chess.EMPTY) {
            const to: u8 = chess.bitscan(attCapture);
            attCapture &= attCapture - 1;
            var pMove = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.CAPTURE), pRook, p_out);
            pMove.setCapture(p_board.get_piece(to));
        }
        var attQuiet = allAtt & (~p_board.occupiedBB);
        while (attQuiet != chess.EMPTY) {
            const to: u8 = chess.bitscan(attQuiet);
            attQuiet &= attQuiet - 1;
            _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pRook, p_out);
        }
    }

    // queen BB
    pieceBB = p_board.pieceBB[@intFromEnum(pQueen)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const allAtt = (chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(from)) | chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(from))) & p_moveBB.queenMoves;

        var attCapture = allAtt & p_board.occupiedBB;
        while (attCapture != chess.EMPTY) {
            const to: u8 = chess.bitscan(attCapture);
            attCapture &= attCapture - 1;
            var pMove = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.CAPTURE), pQueen, p_out);
            pMove.setCapture(p_board.get_piece(to));
        }
        var attQuiet = allAtt & (~p_board.occupiedBB);
        while (attQuiet != chess.EMPTY) {
            const to: u8 = chess.bitscan(attQuiet);
            attQuiet &= attQuiet - 1;
            _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pQueen, p_out);
        }
    }

    // knight BB
    pieceBB = p_board.pieceBB[@intFromEnum(pKnight)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = chess.bitscan(pieceBB);
        pieceBB &= pieceBB - 1;
        const fromBB = chess.xToBitboard(from);
        const allAtt = chess.knightAttacks(fromBB) & p_moveBB.knightMoves;

        var attCapture = allAtt & p_board.occupiedBB;
        while (attCapture != chess.EMPTY) {
            const to: u8 = chess.bitscan(attCapture);
            attCapture &= attCapture - 1;
            var pMove = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.CAPTURE), pKnight, p_out);
            pMove.setCapture(p_board.get_piece(to));
        }
        var attQuiet = allAtt & (~p_board.occupiedBB);
        while (attQuiet != chess.EMPTY) {
            const to: u8 = chess.bitscan(attQuiet);
            attQuiet &= attQuiet - 1;
            _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pKnight, p_out);
        }
    }
    // king BB
    p_moveBB.kingMoves &= ~allAttacks;
    pieceBB = p_board.pieceBB[@intFromEnum(pKing)];

    const from: u8 = chess.bitscan(pieceBB);

    if ((p_moveBB.kingSideCastlingMoves != chess.EMPTY) and p_board.canKingSideCastleAtt(white, allAttacks)) {
        _ = movel.build_move_in(from, from + 2, @intFromEnum(e_moveFlags.KINGCASTLE), pKing, p_out);
    }
    if ((p_moveBB.queenSideCastlingMoves != chess.EMPTY) and p_board.canQueenSideCastleAtt(white, allAttacks)) {
        _ = movel.build_move_in(from, from - 2, @intFromEnum(e_moveFlags.QUEENCASTLE), pKing, p_out);
    }

    //const allAtt = chess.getKingAttacks(@enumFromInt(from)) & p_moveBB.kingMoves;

    var attCapture = p_moveBB.kingMoves & p_board.occupiedBB;
    while (attCapture != chess.EMPTY) {
        const to: u8 = chess.bitscan(attCapture);
        attCapture &= attCapture - 1;
        var pMove = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.CAPTURE), pKing, p_out);
        pMove.setCapture(p_board.get_piece(to));
    }
    var attQuiet = p_moveBB.kingMoves & (~p_board.occupiedBB);
    while (attQuiet != chess.EMPTY) {
        const to: u8 = chess.bitscan(attQuiet);
        attQuiet &= attQuiet - 1;
        _ = movel.build_move_in(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pKing, p_out);
    }
}

pub inline fn moveGeneration(p_board: *const Board_state) moveContainer {
    if (p_board.whiteToMove()) {
        return white_moveGeneration(p_board);
    }
    return black_moveGeneration(p_board);
}

pub fn white_moveGeneration(p_board: *const Board_state) moveContainer {
    // Generates all the moves from the given board state

    var ret: moveContainer = .{};

    const emptyOrEnemy = ~p_board.c_occupiedBB[@intFromBool(true)];

    white_PieceMovePawnMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)], &ret);

    _PieceMoveKnightMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)], true, emptyOrEnemy, &ret);

    _PieceMoveKingMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteKing)], true, emptyOrEnemy, &ret);

    _PieceMoveBishopMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)], true, emptyOrEnemy, &ret);

    _PieceMoveRookMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)], true, emptyOrEnemy, &ret);

    _PieceMoveQueenMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)], true, emptyOrEnemy, &ret);

    return ret;
}
pub fn black_moveGeneration(p_board: *const Board_state) moveContainer {
    // Generates all the moves from the given board state

    var ret: moveContainer = .{};

    const emptyOrEnemy = ~p_board.c_occupiedBB[@intFromBool(false)];

    black_PieceMovePawnMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)], &ret);

    _PieceMoveKnightMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)], false, emptyOrEnemy, &ret);

    _PieceMoveKingMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackKing)], false, emptyOrEnemy, &ret);

    _PieceMoveBishopMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)], false, emptyOrEnemy, &ret);

    _PieceMoveRookMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)], false, emptyOrEnemy, &ret);

    _PieceMoveQueenMask(p_board, p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)], false, emptyOrEnemy, &ret);
    return ret;
}
pub fn moveBitBoardToIMove_pawn(p_board: *const Board_state, piece: e_piece, piece_bb: u64, attack_bb: u64, flags: u6, p_out: *moveContainer, comptime white: bool) void {
    if (attack_bb == 0) {
        return;
    }
    const sq: u8 = chess.bitscan(piece_bb);
    var _bb = attack_bb;
    var _curr_move: IMove = undefined;
    var c_piece: e_piece = .nEmptySquare;
    var enpass_capture_pawn: e_piece = e_piece.nBlackPawn;
    if (comptime !white) {
        enpass_capture_pawn = e_piece.nWhitePawn;
    }
    while (_bb != 0) {
        const lsb: u8 = chess.bitscan(_bb);
        _bb &= _bb - 1;
        if (flags == @intFromEnum(e_moveFlags.ENPASSANT)) {
            c_piece = enpass_capture_pawn;
        } else {
            c_piece = p_board.get_piece(lsb);
        }
        _curr_move = movel.build_move(sq, lsb, flags, piece);
        _curr_move.setCapture(c_piece);
        p_out.append(_curr_move);
    }
    return;
}
pub fn moveBitBoardToIMove(p_board: *const Board_state, piece: e_piece, piece_bb: u64, attack_bb: u64, flags: u6, p_out: *moveContainer, comptime white: bool) void {
    if (attack_bb == 0) {
        return;
    }
    _ = white;
    const sq: u8 = chess.bitscan(piece_bb);
    var _bb = attack_bb;
    var _curr_move: IMove = undefined;
    var c_piece: e_piece = undefined;
    while (_bb != 0) {
        const lsb: u8 = chess.bitscan(_bb);
        _bb &= _bb - 1;
        _curr_move = movel.build_move(sq, lsb, flags, piece);
        c_piece = p_board.get_piece(lsb);
        _curr_move.setCapture(c_piece);
        p_out.append(_curr_move);
    }
    return;
}

pub fn white_PieceMovePawnMask(p_board: *const Board_state, bb_piece: u64, p_out: *moveContainer) void {
    var _bb_piece: u64 = bb_piece;
    const piece = e_piece.nWhitePawn;
    const freeBB = ~p_board.occupiedBB;
    const enemyBB = p_board.c_occupiedBB[@intFromBool(false)];
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        const sqRank = chess.getSqIdxRank(sq);
        const curr_pos = chess.xToBitboard(sq);
        const singlePushBB = curr_pos << 8;

        if (sqRank == 6) {
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB) & (freeBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, true);
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), true) & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, true);
            continue;
        }

        if (sqRank == 1 and ((singlePushBB & freeBB)) != 0) {
            moveBitBoardToIMove_pawn(p_board, piece, curr_pos, ((singlePushBB & freeBB) << 8) & (freeBB), @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, true);
        }
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB & freeBB), 0, p_out, true);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), true) & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, true);

        const enPassantBB = chess.xToBitboard(p_board.enPassantIdx);
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), true) & enPassantBB & chess.whitePawnEnpassantRank & (freeBB)), @intFromEnum(e_moveFlags.ENPASSANT), p_out, true);
    }
    return;
}

pub fn black_PieceMovePawnMask(p_board: *const Board_state, bb_piece: u64, p_out: *moveContainer) void {
    var _bb_piece: u64 = bb_piece;
    const piece = e_piece.nBlackPawn;
    const freeBB = ~p_board.occupiedBB;
    const enemyBB = p_board.c_occupiedBB[@intFromBool(true)];
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        const sqRank = chess.getSqIdxRank(sq);
        const curr_pos = chess.xToBitboard(sq);
        const singlePushBB = curr_pos >> 8;

        if (sqRank == 1) {
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB) & (freeBB), 0, p_out, false);
            _moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), false) & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, false);
            continue;
        }

        if (sqRank == 6 and ((singlePushBB & freeBB)) != 0) {
            moveBitBoardToIMove_pawn(p_board, piece, curr_pos, ((singlePushBB) >> 8) & (freeBB), @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, false);
        }
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB & freeBB), 0, p_out, false);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), false) & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, false);

        const enPassantBB = chess.xToBitboard(p_board.enPassantIdx);
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (chess.getPawnAttacks(@enumFromInt(sq), false) & enPassantBB & freeBB & chess.blackPawnEnpassantRank), @intFromEnum(e_moveFlags.ENPASSANT), p_out, false);
    }
    return;
}

pub fn _PieceMoveKnightMask(p_board: *const Board_state, bb_piece: u64, comptime white: bool, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var piece = e_piece.nWhiteKnight;
    if (comptime !white) {
        piece = e_piece.nBlackKnight;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        const one_pos = chess.xToBitboard(sq);
        const att = chess.knightAttacks(one_pos) & emptyOrEnemy;
        moveBitBoardToIMove(p_board, piece, one_pos, att & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, white);
        moveBitBoardToIMove(p_board, piece, one_pos, att & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, white);
    }
    return;
}

pub fn _PieceMoveBishopMask(p_board: *const Board_state, bb_piece: u64, comptime white: bool, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var curr_att: u64 = chess.EMPTY;

    var piece = e_piece.nWhiteBishop;
    if (comptime !white) {
        piece = e_piece.nBlackBishop;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;
        const sq_e: e_square = @enumFromInt(sq);
        const bb_pos = chess.xToBitboard(sq);
        curr_att = chess.antiDiagAttacks(p_board.occupiedBB, sq_e);
        curr_att |= chess.diagonalAttacks(p_board.occupiedBB, sq_e);
        curr_att &= emptyOrEnemy;
        moveBitBoardToIMove(p_board, piece, bb_pos, curr_att & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, white);

        moveBitBoardToIMove(p_board, piece, bb_pos, curr_att & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, white);
    }
    return;
}

pub fn _PieceMoveRookMask(p_board: *const Board_state, bb_piece: u64, comptime white: bool, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var att_mask: u64 = chess.EMPTY;
    var piece = e_piece.nWhiteRook;
    if (comptime !white) {
        piece = e_piece.nBlackRook;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        const sq = chess.bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;

        const bb_pos = chess.xToBitboard(sq);
        const sq_e: e_square = @enumFromInt(sq);
        att_mask = chess.fileAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.rankAttacks(p_board.occupiedBB, sq_e);
        att_mask &= emptyOrEnemy;

        moveBitBoardToIMove(p_board, piece, bb_pos, att_mask & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, white);
        moveBitBoardToIMove(p_board, piece, bb_pos, att_mask & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, white);
    }
    return;
}

pub fn _PieceMoveQueenMask(p_board: *const Board_state, bb_piece: u64, comptime white: bool, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var att_mask: u64 = chess.EMPTY;
    var piece = e_piece.nWhiteQueen;
    if (comptime !white) {
        piece = e_piece.nBlackQueen;
    }
    var _bb_piece: u64 = bb_piece;
    while (_bb_piece != 0) {
        const sq: u8 = chess.bitscan(_bb_piece);
        _bb_piece &= _bb_piece - 1;

        const bb_pos = chess.xToBitboard(sq);
        const sq_e: e_square = @enumFromInt(sq);

        att_mask = chess.fileAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.rankAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.antiDiagAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.diagonalAttacks(p_board.occupiedBB, sq_e);
        att_mask &= emptyOrEnemy;
        moveBitBoardToIMove(p_board, piece, bb_pos, att_mask & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, white);
        moveBitBoardToIMove(p_board, piece, bb_pos, att_mask & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, white);
    }

    return;
}

pub fn _PieceMoveKingMask(p_board: *const Board_state, bb_piece: u64, comptime white: bool, emptyOrEnemy: u64, p_out: *moveContainer) void {
    var piece = e_piece.nBlackKing;
    if (comptime white) {
        piece = e_piece.nWhiteKing;
    }
    const sq = p_board.getKingSq(white);
    const bb_pos = chess.sqToBitboard(sq);
    const att_mask = chess.getKingAttacks(sq) & emptyOrEnemy;

    moveBitBoardToIMove(p_board, piece, bb_pos, att_mask & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, white);
    moveBitBoardToIMove(p_board, piece, bb_pos, att_mask & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, white);
    if (p_board.canKingSideCastle(white)) {
        moveBitBoardToIMove(p_board, piece, bb_piece, bb_piece << 2, @intFromEnum(e_moveFlags.KINGCASTLE), p_out, white);
    }

    if (p_board.canQueenSideCastle(white)) {
        moveBitBoardToIMove(p_board, piece, bb_piece, bb_piece >> 2, @intFromEnum(e_moveFlags.QUEENCASTLE), p_out, white);
    }
    return;
}

pub fn _moveBitBoardToIMove_pawn(p_board: *const Board_state, piece: e_piece, piece_bb: u64, attack_bb: u64, flags: u6, p_out: *moveContainer, comptime white: bool) void {
    moveBitBoardToIMove_pawn(p_board, piece, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.KNIGHTPROMO), p_out, white);
    moveBitBoardToIMove_pawn(p_board, piece, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.BISHOPPROMO), p_out, white);
    moveBitBoardToIMove_pawn(p_board, piece, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.ROOKPROMO), p_out, white);
    moveBitBoardToIMove_pawn(p_board, piece, piece_bb, attack_bb, flags | @intFromEnum(e_moveFlags.QUEENPROMO), p_out, white);
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
pub fn filterCountMoveLegal(p_state: *const Board_state, move_list: *moveContainer, white: bool) usize {
    const cached = getCachedAttackingPiece(p_state, white);
    const all_attacks = chess.getAllAttackMask(p_state, p_state.occupiedBB, !white);

    const kingSqInfo = squareInfo.init(p_state.getKingSq(white));
    const checks: squarel.checkContainer = squarel.convertBitBoardtoCheckContainer(chess.getAllAttackerFromKing(p_state, white));
    const linePieceBB = cached[0];
    const diagPieceBB = cached[1];
    var ret: usize = 0;
    for (0..move_list.len) |i| {
        if (move_list.moves[i].isCastle()) {
            if (p_state.isCastleLegalPreMove(white, move_list.moves[i], all_attacks)) {
                ret += 1;
            }
        } else if (p_state.isLegalFast(all_attacks, move_list.moves[i], &kingSqInfo, &checks, diagPieceBB, linePieceBB)) {
            ret += 1;
        }
    }

    return ret;
}

pub fn getCachedAttackingPiece(p_state: *const Board_state, white: bool) [2]u64 {
    // [linePieceBB, diagPieceBB];
    var ret = [_]u64{ chess.EMPTY, chess.EMPTY };
    if (white) {
        ret[0] = (p_state.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
        ret[1] = (p_state.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)]);
    } else {
        ret[0] = (p_state.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
        ret[1] = (p_state.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]);
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
        p_out.pawnAttacks |= ((p_board.pieceBB[piece_idx] & chess.notAFile) << 7);
        p_out.pawnAttacks |= ((p_board.pieceBB[piece_idx] & chess.notHFile) << 9);
        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.whitePawnEnpassantRank;

        p_out.pawnAttacks &= (emptyOrEnemy & p_board.occupiedBB);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.whitePawnPromoRank);
        p_out.pawnAttacks &= ~chess.whitePawnPromoRank;
        p_out.pawnMoves &= ~chess.whitePawnPromoRank;
    } else {
        const piece_idx: u8 = @intFromEnum(e_piece.nBlackPawn);
        p_out.pawnMoves |= (p_board.pieceBB[piece_idx] >> 8) & (~p_board.occupiedBB);
        p_out.doubleMoves |= ((p_out.pawnMoves >> 8) & (~p_board.occupiedBB)) & ((p_board.pieceBB[piece_idx] & chess.blackPawnDoubleRank) >> 16);

        p_out.pawnAttacks |= ((p_board.pieceBB[piece_idx] & chess.notHFile) >> 7);
        p_out.pawnAttacks |= ((p_board.pieceBB[piece_idx] & chess.notAFile) >> 9);

        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.blackPawnEnpassantRank;

        p_out.pawnAttacks &= (emptyOrEnemy & p_board.occupiedBB);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.blackPawnPromoRank);
        p_out.pawnAttacks &= ~chess.blackPawnPromoRank;
        p_out.pawnMoves &= ~chess.blackPawnPromoRank;
    }
}

pub inline fn moveGenKnightBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.knightMoves = (chess.knightAttacks(p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)])) & emptyOrEnemy;
    } else {
        p_out.knightMoves = (chess.knightAttacks(p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)])) & emptyOrEnemy;
    }
}

pub fn moveGenKingBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    if (comptime white) {
        p_out.kingMoves = chess.getKingAttacks(p_board.wKingSq) & emptyOrEnemy;
        const kingBB = p_board.pieceBB[@intFromEnum(e_piece.nWhiteKing)];
        if (p_board.canQueenSideCastle(white)) {
            p_out.queenSideCastlingMoves |= (kingBB >> 2);
        }
        if (p_board.canKingSideCastle(white)) {
            p_out.kingSideCastlingMoves |= (kingBB << 2);
        }
    } else {
        p_out.kingMoves = chess.getKingAttacks(p_board.bKingSq) & emptyOrEnemy;
        const kingBB = p_board.pieceBB[@intFromEnum(e_piece.nBlackKing)];
        if (p_board.canQueenSideCastle(white)) {
            p_out.queenSideCastlingMoves |= (kingBB >> 2);
        }
        if (p_board.canKingSideCastle(white)) {
            p_out.kingSideCastlingMoves |= (kingBB << 2);
        }
    }
}
pub inline fn moveGenBishopBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.bishopMoves = chess.EMPTY;
    var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)];
    if (comptime white) {
        _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)];
    }
    while (_bb != 0) {
        const sq = chess.bitscan(_bb);
        _bb &= _bb - 1;
        p_out.bishopMoves |= chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
    }
    p_out.bishopMoves &= emptyOrEnemy;
}
pub inline fn moveGenRookBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.rookMoves = chess.EMPTY;
    var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)];
    if (comptime white) {
        _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)];
    }
    while (_bb != 0) {
        const sq = chess.bitscan(_bb);
        _bb &= _bb - 1;
        p_out.rookMoves |= chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(sq));
    }
    p_out.rookMoves &= emptyOrEnemy;
}

pub inline fn moveGenQueenBB(p_board: *const Board_state, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.queenMoves = chess.EMPTY;
    var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)];
    if (comptime white) {
        _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
    }
    while (_bb != 0) {
        const sq = chess.bitscan(_bb);
        _bb &= _bb - 1;
        p_out.queenMoves |= chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(sq));
        p_out.queenMoves |= chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
    }
    p_out.queenMoves &= emptyOrEnemy;
}

pub const generationModifiers = enum { NORMAL, QUIETMOVE, CAPTURES, ALL };
pub fn cst_moveGenBB_extra(p_board: *const Board_state, comptime white: bool, comptime extra: generationModifiers) moveBBState {
    var ret: moveBBState = .{};
    var EmptyOrEnemy: u64 = 0;
    switch (extra) {
        .NORMAL => {
            EmptyOrEnemy = ~p_board.c_occupiedBB[@intFromBool(white)];
        },
        .QUIETMOVE => {
            EmptyOrEnemy = ~p_board.occupiedBB;
        },
        .CAPTURES => {
            EmptyOrEnemy = p_board.c_occupiedBB[@intFromBool(!white)];
        },
        .ALL => {
            EmptyOrEnemy = chess.UNIVERSE;
        },
    }
    moveGenPawnBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenKnightBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenBishopBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenRookBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenQueenBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenKingBB(p_board, white, EmptyOrEnemy, &ret);
    return ret;
}

pub inline fn moveGenBB(p_board: *const Board_state) moveBBState {
    if (p_board.whiteToMove()) {
        return cst_moveGenBB(p_board, true);
    }
    return cst_moveGenBB(p_board, false);
}
pub fn cst_moveGenBB(p_board: *const Board_state, comptime white: bool) moveBBState {
    var ret: moveBBState = .{};
    const EmptyOrEnemy = ~p_board.c_occupiedBB[@intFromBool(white)];
    moveGenPawnBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenKnightBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenBishopBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenRookBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenQueenBB(p_board, white, EmptyOrEnemy, &ret);
    moveGenKingBB(p_board, white, EmptyOrEnemy, &ret);
    return ret;
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
        const rq = p_state.pieceBB[@intFromEnum(e_piece.nWhiteRook)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
        const bq = p_state.pieceBB[@intFromEnum(e_piece.nWhiteBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
        const pieceQBB: qbb = .{ .bb = [4]u64{ rq, rq, bq, bq } };
        const free = ~p_state.occupiedBB;
        var posBB = east_nort_noWe_noEa_Attacks(pieceQBB, free);
        const negBB = west_sout_soEa_soWe_Attacks(pieceQBB, free);
        return posBB.bbOr(negBB);
    } else {
        const rq = p_state.pieceBB[@intFromEnum(e_piece.nBlackRook)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)];
        const bq = p_state.pieceBB[@intFromEnum(e_piece.nBlackBishop)] | p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)];
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
        const k = p_state.pieceBB[@intFromEnum(e_piece.nWhiteKing)];
        const k_qbb = qbb.init(k);
        var attackers = avx2DumbFill(p_state, false);
        free ^= (attackers.collapse() & p_state.c_occupiedBB[@intFromBool(true)]);
        var kingBB = east_nort_noWe_noEa_Attacks(k_qbb, free);
        var negBB = west_sout_soEa_soWe_Attacks(k_qbb, free);
        kingBB.bbOr_eq(&negBB);
        kingBB.bbAnd_eq(&attackers);
        return kingBB.collapse();
    } else {
        const k = p_state.pieceBB[@intFromEnum(e_piece.nBlackKing)];
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
// move ordering section?
pub fn generateLegalMoves_ordered(p_board: *const Board_state, captureOnly: bool) moveContainer {
    //
    if (captureOnly) {
        return _generateLegalMoves_ordered(p_board, true);
    }
    return _generateLegalMoves_ordered(p_board, false);
}
pub inline fn _generateLegalMoves_ordered(p_board: *const Board_state, comptime captureOnly: bool) moveContainer {
    //
    if (p_board.whiteToMove()) {
        return cst_generateLegalMoves_ordered(p_board, captureOnly, true);
    }
    return cst_generateLegalMoves_ordered(p_board, captureOnly, false);
}
pub fn cst_generateLegalMoves_ordered(p_board: *const Board_state, comptime captureOnly: bool, comptime white: bool) moveContainer {
    //
    var ret: moveBBState = .{};
    if (comptime white) {
        var EmptyOrEnemy = ~p_board.c_occupiedBB[@intFromBool(true)];
        if (comptime captureOnly) {
            EmptyOrEnemy = p_board.c_occupiedBB[@intFromBool(false)];
        }
        moveGenPawnBB(p_board, true, EmptyOrEnemy, &ret);
        moveGenKnightBB(p_board, true, EmptyOrEnemy, &ret);
        moveGenBishopBB(p_board, true, EmptyOrEnemy, &ret);
        moveGenRookBB(p_board, true, EmptyOrEnemy, &ret);
        moveGenQueenBB(p_board, true, EmptyOrEnemy, &ret);
        moveGenKingBB(p_board, true, EmptyOrEnemy, &ret);
    } else {
        var EmptyOrEnemy = ~p_board.c_occupiedBB[@intFromBool(false)];
        if (comptime captureOnly) {
            EmptyOrEnemy = p_board.c_occupiedBB[@intFromBool(true)];
        }
        moveGenPawnBB(p_board, false, EmptyOrEnemy, &ret);
        moveGenKnightBB(p_board, false, EmptyOrEnemy, &ret);
        moveGenBishopBB(p_board, false, EmptyOrEnemy, &ret);
        moveGenRookBB(p_board, false, EmptyOrEnemy, &ret);
        moveGenQueenBB(p_board, false, EmptyOrEnemy, &ret);
        moveGenKingBB(p_board, false, EmptyOrEnemy, &ret);
    }
    var moves: moveContainer = undefined;
    moves.len = 0;

    moveGenBBToMoveContainer(p_board, &ret, &moves);
    return moves;
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

pub fn southOne(bb: u64) u64 {
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
pub fn eastOne(bb: u64) u64 {
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
pub fn westOne(bb: u64) u64 {
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
pub fn northEastOne(bb: u64) u64 {
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
pub fn northWestOne(bb: u64) u64 {
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
pub fn southEastOne(bb: u64) u64 {
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
pub fn southWestOne(bb: u64) u64 {
    return ((bb & chess.notHFile) >> 9);
}
