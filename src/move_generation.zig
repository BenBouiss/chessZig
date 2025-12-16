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
        var bbMoves = moveGenBB(p_board);
        const moves = moveGenBBToMoveContainer(p_board, &bbMoves);
        //const fmoves = filterMoveLegal(p_board, &moves) catch unreachable;

        //var _moves: moveContainer = moveGeneration(p_board);
        //const _fmoves = filterMoveLegal(p_board, &_moves) catch unreachable;
        //if (_fmoves.isDifferent(moves)) {
        //    _fmoves.printDifference(moves);
        //    chess.print_boardstate(p_board);

        //    chess.print_bitboard(p_board.checkersBB);
        //    chess.askContinue();
        //}
        return moves;
    } else {
        var moves: moveContainer = moveGeneration(p_board);
        const fmoves = filterMoveLegal(p_board, &moves) catch unreachable;
        return fmoves;
    }
}
pub fn generatePseudolegalMoves(p_board: *Board_state) moveContainer {
    return moveGeneration(p_board);
}

pub fn push_promotion(from: u8, to: u8, piece: e_piece, p_out: *moveContainer) void {
    var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), piece);
    move.setFlag(@intFromEnum(e_moveFlags.KNIGHTPROMO));
    _ = p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.BISHOPPROMO));
    _ = p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.ROOKPROMO));
    _ = p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.QUEENPROMO));
    _ = p_out.append(move);
}
pub fn push_promotion_capture(from: u8, to: u8, piece: e_piece, cPiece: e_piece, p_out: *moveContainer) void {
    var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.CAPTURE), piece);
    move.setCapture(cPiece);
    move.setFlag(@intFromEnum(e_moveFlags.KNIGHTPROMOCAPTURE));
    _ = p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.BISHOPPROMOCAPTURE));
    _ = p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.ROOKPROMOCAPTURE));
    _ = p_out.append(move);
    move.setFlag(@intFromEnum(e_moveFlags.QUEENPROMOCAPTURE));
    _ = p_out.append(move);
}
pub fn moveGenBBToMoveContainer(p_board: *Board_state, p_moveBB: *moveBBState) moveContainer {
    var ret: moveContainer = .{};
    var pawnDir: i8 = 8;
    var color: e_color = .WHITE;
    var opp: e_color = .BLACK;
    var pPawn: e_piece = .nWhitePawn;
    var opPawn: e_piece = .nBlackPawn;
    var pBishop: e_piece = .nWhiteBishop;
    var pRook: e_piece = .nWhiteRook;
    var pQueen: e_piece = .nWhiteQueen;
    var pKnight: e_piece = .nWhiteKnight;
    var pKing: e_piece = .nWhiteKing;
    if (p_board.turn == .BLACK) {
        pawnDir = -8;
        opp = .WHITE;
        color = .BLACK;
        pPawn = .nBlackPawn;
        opPawn = .nWhitePawn;
        pBishop = .nBlackBishop;
        pRook = .nBlackRook;
        pQueen = .nBlackQueen;
        pKnight = .nBlackKnight;
        pKing = .nBlackKing;
    }

    const allAttacks = chess.getAllAttackMask(p_board, p_board.occupiedBB ^ p_board.pieceBB[@intFromEnum(pKing)], opp);

    const kingSq: u8 = @intCast(chess.bitscan(p_board.pieceBB[@intFromEnum(pKing)]));
    const kingSqInfo = squarel.squareInfo.init(@enumFromInt(kingSq));
    //source: https://www.codeproject.com/articles/Worlds-Fastest-Bitboard-Chess-Movegenerator
    const kingDiags = kingSqInfo.getDiagonalsBB();
    const kingLines = kingSqInfo.getHorizontalBB();
    const pinHV = p_board.pinnedBB & kingLines;
    const pinD12 = p_board.pinnedBB & kingDiags;

    const unPinnedBB = ~p_board.pinnedBB;
    const inCheck: bool = p_board.checkersBB != 0;
    const doubleCheck: bool = chess.l_popcount(p_board.checkersBB & p_board.occupiedBB) > 1;
    if (inCheck) {
        if (doubleCheck) {
            // only king moves
            const kingBB = p_moveBB.kingMoves;
            p_moveBB.resetAll();
            p_moveBB.kingMoves = kingBB;
        } else {
            // only blocking / capturing moves for non king pieces
            const kingBB = p_moveBB.kingMoves;
            p_moveBB.andEq(p_board.checkersBB);
            p_moveBB.kingMoves = kingBB;
            p_moveBB.kingSideCastlingMoves = chess.EMPTY;
            p_moveBB.queenSideCastlingMoves = chess.EMPTY;
        }
    } else {
        // move generate the pinned pieces here
        // a pinned piece cannot clear a check

        // bishop and queen
        var pinnedPiece = (p_board.pieceBB[@intFromEnum(pBishop)] | p_board.pieceBB[@intFromEnum(pQueen)]) & pinD12;
        while (pinnedPiece != chess.EMPTY) {
            const pieceSq: u8 = @intCast(chess.bitscan(pinnedPiece));
            const pieceSq_E: e_square = @enumFromInt(pieceSq);
            const piece = p_board.get_piece(pieceSq);
            pinnedPiece &= pinnedPiece - 1;
            const permittedMoves = chess.getBishopAttacks(p_board.occupiedBB, pieceSq_E) & kingDiags & (p_moveBB.bishopMoves | p_moveBB.queenMoves);
            var quietMoves = permittedMoves & (~p_board.occupiedBB);
            while (quietMoves != chess.EMPTY) {
                const to: u8 = @intCast(chess.bitscan(quietMoves));
                quietMoves &= quietMoves - 1;
                const move = movel.build_move(pieceSq, to, @intFromEnum(e_moveFlags.QUIETMOVE), piece);
                _ = ret.append(move);
            }
            var attMoves = permittedMoves & p_board.occupiedBB;
            while (attMoves != chess.EMPTY) {
                const to: u8 = @intCast(chess.bitscan(attMoves));
                const cPiece = p_board.get_piece(to);
                attMoves &= attMoves - 1;
                var move = movel.build_move(pieceSq, to, @intFromEnum(e_moveFlags.CAPTURE), piece);
                move.setCapture(cPiece);
                _ = ret.append(move);
            }
        }
        // rook and queen
        pinnedPiece = (p_board.pieceBB[@intFromEnum(pRook)] | p_board.pieceBB[@intFromEnum(pQueen)]) & pinHV;
        while (pinnedPiece != chess.EMPTY) {
            const pieceSq: u8 = @intCast(chess.bitscan(pinnedPiece));
            const pieceSq_E: e_square = @enumFromInt(pieceSq);
            const piece = p_board.get_piece(pieceSq);
            pinnedPiece &= pinnedPiece - 1;
            const permittedMoves = chess.getRookAttacks(p_board.occupiedBB, pieceSq_E) & kingLines & (p_moveBB.rookMoves | p_moveBB.queenMoves);
            var quietMoves = permittedMoves & (~p_board.occupiedBB);
            while (quietMoves != chess.EMPTY) {
                const to: u8 = @intCast(chess.bitscan(quietMoves));
                quietMoves &= quietMoves - 1;
                const move = movel.build_move(pieceSq, to, @intFromEnum(e_moveFlags.QUIETMOVE), piece);
                _ = ret.append(move);
            }
            var attMoves = permittedMoves & p_board.occupiedBB;
            while (attMoves != chess.EMPTY) {
                const to: u8 = @intCast(chess.bitscan(attMoves));
                const cPiece = p_board.get_piece(to);
                attMoves &= attMoves - 1;
                var move = movel.build_move(pieceSq, to, @intFromEnum(e_moveFlags.CAPTURE), piece);
                move.setCapture(cPiece);
                _ = ret.append(move);
            }
        }

        pinnedPiece = (p_board.pieceBB[@intFromEnum(pRook)] | p_board.pieceBB[@intFromEnum(pQueen)]) & pinHV;
        while (pinnedPiece != chess.EMPTY) {
            const pieceSq: u8 = @intCast(chess.bitscan(pinnedPiece));
            const pieceSq_E: e_square = @enumFromInt(pieceSq);
            const piece = p_board.get_piece(pieceSq);
            pinnedPiece &= pinnedPiece - 1;
            const permittedMoves = chess.getBishopAttacks(p_board.occupiedBB, pieceSq_E) & pinHV & (p_moveBB.bishopMoves | p_moveBB.queenMoves);
            var quietMoves = permittedMoves & (~p_board.occupiedBB);
            while (quietMoves != chess.EMPTY) {
                const to: u8 = @intCast(chess.bitscan(quietMoves));
                quietMoves &= quietMoves - 1;
                const move = movel.build_move(pieceSq, to, @intFromEnum(e_moveFlags.QUIETMOVE), piece);
                _ = ret.append(move);
            }
            var attMoves = permittedMoves & p_board.occupiedBB;
            while (attMoves != chess.EMPTY) {
                const to: u8 = @intCast(chess.bitscan(attMoves));
                const cPiece = p_board.get_piece(to);
                attMoves &= attMoves - 1;
                var move = movel.build_move(pieceSq, to, @intFromEnum(e_moveFlags.CAPTURE), piece);
                move.setCapture(cPiece);
                _ = ret.append(move);
            }
        }
        // pawn pin handling
        // push only possible if to in pinHV
        // capture only if to in pinD12
        // enPassant never okay
        // promotion only when capturing
        //JpinnedPiece = p_moveBB.pawnMoves & pinHV;
        pinnedPiece = (p_board.pieceBB[@intFromEnum(pPawn)] & pinHV);
        while (pinnedPiece != chess.EMPTY) {
            const from: u8 = @intCast(chess.bitscan(pinnedPiece));
            pinnedPiece &= pinnedPiece - 1;
            var to: i8 = @intCast(from);
            to += pawnDir;
            const _to: u8 = @intCast(to);
            if (chess.xToBitboard(_to) & pinHV != chess.EMPTY) {
                _ = ret.append(movel.build_move(from, _to, @intFromEnum(e_moveFlags.QUIETMOVE), pPawn));
            }
        }
        pinnedPiece = p_moveBB.doubleMoves & pinHV;
        while (pinnedPiece != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(pinnedPiece));
            pinnedPiece &= pinnedPiece - 1;
            var from: i8 = @intCast(to);
            from -= 2 * pawnDir;
            _ = ret.append(movel.build_move(@intCast(from), to, @intFromEnum(e_moveFlags.DOUBLEPAWN), pPawn));
        }

        pinnedPiece = p_board.pieceBB[@intFromEnum(pPawn)] & pinD12;
        while (pinnedPiece != chess.EMPTY) {
            const from: u8 = @intCast(chess.bitscan(pinnedPiece));
            pinnedPiece &= pinnedPiece - 1;

            const att = chess.getPawnAttacks(@enumFromInt(from), color);
            var toAtt_bb = att & kingDiags & p_board.c_occupiedBB[@intFromEnum(opp)];
            if (toAtt_bb != chess.EMPTY) {
                const to: u8 = @intCast(chess.bitscan(toAtt_bb));
                toAtt_bb &= toAtt_bb - 1;
                const cPiece = p_board.get_piece(to);
                var move = movel.build_move(@intCast(from), to, @intFromEnum(e_moveFlags.CAPTURE), pPawn);
                move.setCapture(cPiece);
                _ = ret.append(move);
            }
        }
        pinnedPiece = p_moveBB.promotionMoves & p_board.occupiedBB & pinD12;
        const validPawnAttLoc: u64 = chess.EMPTY;
        while (pinnedPiece != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(pinnedPiece));
            pinnedPiece &= pinnedPiece - 1;
            var att = chess.getPawnAttacks(@enumFromInt(to), opp) & validPawnAttLoc;
            const cPiece = p_board.get_piece(to);
            if (att != chess.EMPTY) {
                const from: u8 = @intCast(chess.bitscan(att));
                att &= att - 1;
                push_promotion_capture(from, to, pPawn, cPiece, &ret);
            }
        }
    }
    p_moveBB.kingMoves &= ~allAttacks;

    const validPawnLoc = unPinnedBB & p_board.pieceBB[@intFromEnum(pPawn)];
    var bb: u64 = p_moveBB.pawnMoves & chess.genShift(unPinnedBB, pawnDir);
    while (bb != chess.EMPTY) {
        const to: u8 = @intCast(chess.bitscan(bb));
        bb &= bb - 1;
        var from: i8 = @intCast(to);
        from -= pawnDir;
        _ = ret.append(movel.build_move(@intCast(from), to, @intFromEnum(e_moveFlags.QUIETMOVE), pPawn));
    }

    bb = p_moveBB.promotionMoves & p_board.occupiedBB;
    while (bb != chess.EMPTY) {
        const to: u8 = @intCast(chess.bitscan(bb));
        bb &= bb - 1;
        var att = chess.getPawnAttacks(@enumFromInt(to), opp) & validPawnLoc;
        const cPiece = p_board.get_piece(to);
        while (att != chess.EMPTY) {
            const from: u8 = @intCast(chess.bitscan(att));
            att &= att - 1;
            push_promotion_capture(from, to, pPawn, cPiece, &ret);
        }
    }
    bb = p_moveBB.promotionMoves & ~p_board.occupiedBB & chess.genShift(unPinnedBB, pawnDir);
    while (bb != chess.EMPTY) {
        const to: u8 = @intCast(chess.bitscan(bb));
        bb &= bb - 1;
        var from: i8 = @intCast(to);
        from -= pawnDir;
        push_promotion(@intCast(from), to, pPawn, &ret);
    }

    bb = p_moveBB.doubleMoves & chess.genShift(unPinnedBB, 2 * pawnDir);
    while (bb != chess.EMPTY) {
        const to: u8 = @intCast(chess.bitscan(bb));
        bb &= bb - 1;
        var from: i8 = @intCast(to);
        from -= (2 * pawnDir);
        _ = ret.append(movel.build_move(@intCast(from), to, @intFromEnum(e_moveFlags.DOUBLEPAWN), pPawn));
    }

    bb = p_moveBB.enPassantMoves;
    while (bb != chess.EMPTY) {
        const to: u8 = @intCast(chess.bitscan(bb));
        bb &= bb - 1;

        const att = chess.getPawnAttacks(@enumFromInt(to), opp);
        var toAtt_bb = att & validPawnLoc;
        while (toAtt_bb != chess.EMPTY) {
            const from: u8 = @intCast(chess.bitscan(toAtt_bb));
            toAtt_bb &= toAtt_bb - 1;
            var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.ENPASSANT), pPawn);
            move.setCapture(opPawn);
            _ = ret.append(move);
        }
    }

    bb = p_moveBB.pawnAttacks;
    while (bb != chess.EMPTY) {
        const to: u8 = @intCast(chess.bitscan(bb));
        const cPiece = p_board.get_piece(to);
        bb &= bb - 1;
        const att = chess.getPawnAttacks(@enumFromInt(to), opp);
        var toAtt_bb = att & validPawnLoc;
        while (toAtt_bb != chess.EMPTY) {
            const from: u8 = @intCast(chess.bitscan(toAtt_bb));
            toAtt_bb &= toAtt_bb - 1;
            var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.CAPTURE), pPawn);
            move.setCapture(cPiece);
            _ = ret.append(move);
        }
    }

    // bishop BB
    var pieceBB = p_board.pieceBB[@intFromEnum(pBishop)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = @intCast(chess.bitscan(pieceBB));
        pieceBB &= pieceBB - 1;
        const allAtt = chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(from)) & p_moveBB.bishopMoves;

        var attCapture = allAtt & p_board.occupiedBB;
        while (attCapture != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(attCapture));
            attCapture &= attCapture - 1;
            var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.CAPTURE), pBishop);
            move.setCapture(p_board.get_piece(to));
            _ = ret.append(move);
        }
        var attQuiet = allAtt & (~p_board.occupiedBB);
        while (attQuiet != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(attQuiet));
            attQuiet &= attQuiet - 1;
            const move = movel.build_move(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pBishop);
            _ = ret.append(move);
        }
    }

    // rook BB
    pieceBB = p_board.pieceBB[@intFromEnum(pRook)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = @intCast(chess.bitscan(pieceBB));
        pieceBB &= pieceBB - 1;
        const allAtt = chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(from)) & p_moveBB.rookMoves;

        var attCapture = allAtt & p_board.occupiedBB;
        while (attCapture != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(attCapture));
            attCapture &= attCapture - 1;
            var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.CAPTURE), pRook);
            move.setCapture(p_board.get_piece(to));
            _ = ret.append(move);
        }
        var attQuiet = allAtt & (~p_board.occupiedBB);
        while (attQuiet != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(attQuiet));
            attQuiet &= attQuiet - 1;
            const move = movel.build_move(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pRook);
            _ = ret.append(move);
        }
    }

    // queen BB
    pieceBB = p_board.pieceBB[@intFromEnum(pQueen)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = @intCast(chess.bitscan(pieceBB));
        pieceBB &= pieceBB - 1;
        const allAtt = (chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(from)) | chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(from))) & p_moveBB.queenMoves;

        var attCapture = allAtt & p_board.occupiedBB;
        while (attCapture != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(attCapture));
            attCapture &= attCapture - 1;
            var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.CAPTURE), pQueen);
            move.setCapture(p_board.get_piece(to));
            _ = ret.append(move);
        }
        var attQuiet = allAtt & (~p_board.occupiedBB);
        while (attQuiet != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(attQuiet));
            attQuiet &= attQuiet - 1;
            const move = movel.build_move(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pQueen);
            _ = ret.append(move);
        }
    }

    // knight BB
    pieceBB = p_board.pieceBB[@intFromEnum(pKnight)] & unPinnedBB;
    while (pieceBB != chess.EMPTY) {
        const from: u8 = @intCast(chess.bitscan(pieceBB));
        pieceBB &= pieceBB - 1;
        const fromBB = chess.xToBitboard(from);
        const allAtt = chess.knightAttacks(fromBB) & p_moveBB.knightMoves;

        var attCapture = allAtt & p_board.occupiedBB;
        while (attCapture != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(attCapture));
            attCapture &= attCapture - 1;
            var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.CAPTURE), pKnight);
            move.setCapture(p_board.get_piece(to));
            _ = ret.append(move);
        }
        var attQuiet = allAtt & (~p_board.occupiedBB);
        while (attQuiet != chess.EMPTY) {
            const to: u8 = @intCast(chess.bitscan(attQuiet));
            attQuiet &= attQuiet - 1;
            const move = movel.build_move(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pKnight);
            _ = ret.append(move);
        }
    }
    // king BB
    pieceBB = p_board.pieceBB[@intFromEnum(pKing)];

    const from: u8 = @intCast(chess.bitscan(pieceBB));

    if ((p_moveBB.kingSideCastlingMoves != chess.EMPTY) and p_board.canKingSideCastleAtt(p_board.turn, allAttacks)) {
        const move = movel.build_move(from, from + 2, @intFromEnum(e_moveFlags.KINGCASTLE), pKing);
        _ = ret.append(move);
    }
    if ((p_moveBB.queenSideCastlingMoves != chess.EMPTY) and p_board.canQueenSideCastleAtt(p_board.turn, allAttacks)) {
        const move = movel.build_move(from, from - 2, @intFromEnum(e_moveFlags.QUEENCASTLE), pKing);
        _ = ret.append(move);
    }
    const allAtt = chess.getKingAttacks(@enumFromInt(from)) & p_moveBB.kingMoves;

    var attCapture = allAtt & p_board.occupiedBB;
    while (attCapture != chess.EMPTY) {
        const to: u8 = @intCast(chess.bitscan(attCapture));
        attCapture &= attCapture - 1;
        var move = movel.build_move(from, to, @intFromEnum(e_moveFlags.CAPTURE), pKing);
        move.setCapture(p_board.get_piece(to));
        _ = ret.append(move);
    }
    var attQuiet = allAtt & (~p_board.occupiedBB);
    while (attQuiet != chess.EMPTY) {
        const to: u8 = @intCast(chess.bitscan(attQuiet));
        attQuiet &= attQuiet - 1;
        const move = movel.build_move(from, to, @intFromEnum(e_moveFlags.QUIETMOVE), pKing);
        _ = ret.append(move);
    }

    return ret;
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
    var c_piece: e_piece = .nEmptySquare;
    var enpass_capture_pawn: e_piece = e_piece.nBlackPawn;
    if (comptime turn == e_color.BLACK) {
        enpass_capture_pawn = e_piece.nWhitePawn;
    }
    while (_bb != 0) {
        const lsb = chess.bitscan(_bb);
        _bb &= _bb - 1;
        if (flags == @intFromEnum(e_moveFlags.ENPASSANT)) {
            c_piece = enpass_capture_pawn;
        } else {
            c_piece = p_board.get_piece(@intCast(lsb));
        }
        _curr_move = movel.build_move(@intCast(sq), @intCast(lsb), flags, piece);
        _curr_move.setCapture(c_piece);
        _ = p_out.append(_curr_move);
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
        _bb &= _bb - 1;
        _curr_move = movel.build_move(@intCast(sq), @intCast(lsb), flags, piece);
        c_piece = p_board.get_piece(@intCast(lsb));
        _curr_move.setCapture(c_piece);
        _ = p_out.append(_curr_move);
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
            moveBitBoardToIMove_pawn(p_board, piece, curr_pos, ((singlePushBB & freeBB) << 8) & (freeBB), @intFromEnum(e_moveFlags.DOUBLEPAWN), p_out, e_color.WHITE);
        }
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (singlePushBB & freeBB), 0, p_out, e_color.WHITE);

        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.WHITE)][@intCast(sq)] & enemyBB), @intFromEnum(e_moveFlags.CAPTURE), p_out, e_color.WHITE);

        const enPassantBB = chess.xToBitboard(p_board.enPassantIdx);
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.WHITE)][@intCast(sq)] & enPassantBB & chess.whitePawnEnpassantRank & (freeBB)), @intFromEnum(e_moveFlags.ENPASSANT), p_out, e_color.WHITE);
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

        const enPassantBB = chess.xToBitboard(p_board.enPassantIdx);
        moveBitBoardToIMove_pawn(p_board, piece, curr_pos, (cachedTables.SimplePawnAttack[@intFromEnum(e_color.BLACK)][@intCast(sq)] & enPassantBB & freeBB & chess.blackPawnEnpassantRank), @intFromEnum(e_moveFlags.ENPASSANT), p_out, e_color.BLACK);

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
        _bb_piece &= _bb_piece - 1;
        one_pos = (chess.ONE << @intCast(sq));
        const att = chess.knightAttacks(one_pos) & emptyOrEnemy;
        moveBitBoardToIMove(p_board, piece, one_pos, att & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, turn);
        moveBitBoardToIMove(p_board, piece, one_pos, att & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, turn);
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
        _bb_piece &= _bb_piece - 1;
        sq_e = @enumFromInt(sq);
        curr_att = chess.antiDiagAttacks(p_board.occupiedBB, sq_e);
        curr_att |= chess.diagonalAttacks(p_board.occupiedBB, sq_e);
        curr_att &= emptyOrEnemy;
        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), curr_att & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, turn);

        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), curr_att & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, turn);
        curr_att &= emptyOrEnemy;
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
        _bb_piece &= _bb_piece - 1;

        sq_e = @enumFromInt(sq);
        att_mask = chess.fileAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.rankAttacks(p_board.occupiedBB, sq_e);
        att_mask &= emptyOrEnemy;

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
        _bb_piece &= _bb_piece - 1;
        sq_e = @enumFromInt(sq);
        att_mask = chess.fileAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.rankAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.antiDiagAttacks(p_board.occupiedBB, sq_e);
        att_mask |= chess.diagonalAttacks(p_board.occupiedBB, sq_e);
        att_mask &= emptyOrEnemy;
        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), att_mask & (~p_board.occupiedBB), @intFromEnum(e_moveFlags.QUIETMOVE), p_out, turn);
        moveBitBoardToIMove(p_board, piece, (chess.ONE << @intCast(sq)), att_mask & p_board.occupiedBB, @intFromEnum(e_moveFlags.CAPTURE), p_out, turn);
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
    // goal compared to filterMoveLegal: try to not use the make/undo Moves methods
    var ret: moveContainer = .{};
    const turn: e_color = p_state.turn;
    const cached = getCachedAttackingPiece(p_state, turn);
    const all_attacks = chess.getAllAttackMask(p_state, p_state.occupiedBB, chess.invertColor(turn));

    const kingSqInfo = squareInfo.init(@enumFromInt(p_state.getKingSq(turn)));
    const checks: squarel.checkContainer = squarel.convertBitBoardtoCheckContainer(chess.getAllAttackMaskFromKing(p_state, turn));
    const linePieceBB = cached[0];
    const diagPieceBB = cached[1];
    for (0..move_list.len) |i| {
        if (move_list.moves[i].isCastle()) {
            if (p_state.isCastleLegalPreMove(turn, move_list.moves[i], all_attacks)) {
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
    p_out.pawnMoves = chess.EMPTY;
    p_out.pawnAttacks = chess.EMPTY;
    p_out.doubleMoves = chess.EMPTY;
    p_out.enPassantMoves = chess.EMPTY;

    const enPassantBB = chess.ONE << @intCast(p_board.enPassantIdx);
    if (comptime color == .WHITE) {
        p_out.pawnMoves |= (p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] << 8) & (~p_board.occupiedBB);
        p_out.doubleMoves |= ((p_out.pawnMoves << 8) & (~p_board.occupiedBB)) & ((p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] & chess.whitePawnDoubleRank) << 16);
        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] & chess.notAFile) << 7);
        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nWhitePawn)] & chess.notHFile) << 9);
        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.whitePawnEnpassantRank;

        p_out.pawnAttacks &= (emptyOrEnemy & p_board.occupiedBB);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.whitePawnPromoRank);
        p_out.pawnAttacks &= ~chess.whitePawnPromoRank;
        p_out.pawnMoves &= ~chess.whitePawnPromoRank;
    } else {
        p_out.pawnMoves |= (p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] >> 8) & (~p_board.occupiedBB);
        p_out.doubleMoves |= ((p_out.pawnMoves >> 8) & (~p_board.occupiedBB)) & ((p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] & chess.blackPawnDoubleRank) >> 16);

        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] & chess.notHFile) >> 7);
        p_out.pawnAttacks |= ((p_board.pieceBB[@intFromEnum(e_piece.nBlackPawn)] & chess.notAFile) >> 9);

        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.blackPawnEnpassantRank;

        p_out.pawnAttacks &= (emptyOrEnemy & p_board.occupiedBB);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.blackPawnPromoRank);
        p_out.pawnAttacks &= ~chess.blackPawnPromoRank;
        p_out.pawnMoves &= ~chess.blackPawnPromoRank;
    }
}

pub fn moveGenKnightBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.knightMoves = chess.EMPTY;
    if (comptime color == .WHITE) {
        p_out.knightMoves |= (chess.knightAttacks(p_board.pieceBB[@intFromEnum(e_piece.nWhiteKnight)])) & emptyOrEnemy;
    } else {
        p_out.knightMoves |= (chess.knightAttacks(p_board.pieceBB[@intFromEnum(e_piece.nBlackKnight)])) & emptyOrEnemy;
    }
}

pub fn moveGenKingBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.kingMoves = chess.EMPTY;
    if (comptime color == .WHITE) {
        p_out.kingMoves = cachedTables.KingAttack[@intCast(p_board.getKingSq(.WHITE))] & emptyOrEnemy;
        const kingBB = p_board.pieceBB[@intFromEnum(e_piece.nWhiteKing)];
        if (p_board.canQueenSideCastle(color)) {
            p_out.queenSideCastlingMoves |= (kingBB >> 2);
        }
        if (p_board.canKingSideCastle(color)) {
            p_out.kingSideCastlingMoves |= (kingBB << 2);
        }
    } else {
        p_out.kingMoves = cachedTables.KingAttack[@intCast(p_board.getKingSq(.BLACK))] & emptyOrEnemy;
        const kingBB = p_board.pieceBB[@intFromEnum(e_piece.nBlackKing)];
        if (p_board.canQueenSideCastle(color)) {
            p_out.queenSideCastlingMoves |= (kingBB >> 2);
        }

        if (p_board.canKingSideCastle(color)) {
            p_out.kingSideCastlingMoves |= (kingBB << 2);
        }
    }
}
pub fn moveGenBishopBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.bishopMoves = chess.EMPTY;
    if (comptime color == .WHITE) {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteBishop)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            _bb &= _bb - 1;
            p_out.bishopMoves |= chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
        }
        p_out.bishopMoves &= emptyOrEnemy;
    } else {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackBishop)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            _bb &= _bb - 1;
            p_out.bishopMoves |= chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
        }
        p_out.bishopMoves &= emptyOrEnemy;
    }
}
pub fn moveGenRookBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.rookMoves = chess.EMPTY;
    if (comptime color == .WHITE) {
        //std.debug.print("[DEBUG] moveGenRookBB: white side\n", .{});
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteRook)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            _bb &= _bb - 1;
            p_out.rookMoves |= chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(sq));
        }
        p_out.rookMoves &= emptyOrEnemy;
    } else {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackRook)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            _bb &= _bb - 1;
            p_out.rookMoves |= chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(sq));
        }
        p_out.rookMoves &= emptyOrEnemy;
    }
}

pub fn moveGenQueenBB(p_board: *Board_state, comptime color: e_color, emptyOrEnemy: u64, p_out: *moveBBState) void {
    p_out.queenMoves = chess.EMPTY;
    if (comptime color == .WHITE) {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nWhiteQueen)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            _bb &= _bb - 1;
            p_out.queenMoves |= chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(sq));
            p_out.queenMoves |= chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
        }
        p_out.queenMoves &= emptyOrEnemy;
    } else {
        var _bb = p_board.pieceBB[@intFromEnum(e_piece.nBlackQueen)];
        while (_bb != 0) {
            const sq = chess.bitscan(_bb);
            _bb &= _bb - 1;
            p_out.queenMoves |= chess.getRookAttacks(p_board.occupiedBB, @enumFromInt(sq));
            p_out.queenMoves |= chess.getBishopAttacks(p_board.occupiedBB, @enumFromInt(sq));
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
