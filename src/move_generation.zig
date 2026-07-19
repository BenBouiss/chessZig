const std = @import("std");
const build_options = @import("build_options");
const useStaged = build_options.useStaged;

const chess = @import("chess.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const boardl = @import("board.zig");
const typel = @import("type.zig");
const heuristicl = @import("heuristic.zig");
const configl = @import("config.zig");
const weightl = @import("weights.zig");
const historyl = @import("history.zig");
const magicl = @import("magic.zig");

const moveContainer = movel.moveContainer;
const moveBBState = movel.moveBBState;
const IMove = movel.IMove;

const e_square = typel.e_square;
const e_piece = typel.e_piece;
const e_pieceType = typel.e_pieceType;
const e_moveFlags = typel.e_moveFlags;
const scoreType = typel.scoreType;

const e_moveGenFlag = typel.e_moveGenFlag;

const squareInfo = squarel.squareInfo;
const boardState = boardl.boardState;

//pub const generationModifiers = enum { STD, NONE, QUIETMOVES, CAPTURES, ALL };

pub inline fn generateLegalMoves(p_board: *const boardState) moveContainer {
    if (comptime useStaged) {
        var bbMoves = moveGenBB(p_board);
        //bbMoves.print();
        var moves: moveContainer = undefined;
        moves.len = 0;
        moveGenBBToMoveContainer(p_board, &bbMoves, &moves, .ALL);
        return moves;
    }
}

pub fn moveGenBBToMoveContainer(p_board: *const boardState, p_moveBB: *moveBBState, p_out: *moveContainer, comptime extra: e_moveGenFlag) void {
    if (p_board.whiteToMove()) {
        return cst_moveGenBBToMoveContainer_ordered(p_board, p_moveBB, true, p_out, extra);
    }
    return cst_moveGenBBToMoveContainer_ordered(p_board, p_moveBB, false, p_out, extra);
}

pub fn cst_moveGenBBToMoveContainer_ordered(p_board: *const boardState, p_moveBB: *moveBBState, comptime white: bool, p_out: *moveContainer, comptime extra: e_moveGenFlag) void {
    const pawnDir: i8 = if (comptime white) 8 else -8;
    const pPawn: e_piece = if (comptime white) .nWhitePawn else .nBlackPawn;
    const pBishop: e_piece = if (comptime white) .nWhiteBishop else .nBlackBishop;
    const pRook: e_piece = if (comptime white) .nWhiteRook else .nBlackRook;
    const pQueen: e_piece = if (comptime white) .nWhiteQueen else .nBlackQueen;
    const pKnight: e_piece = if (comptime white) .nWhiteKnight else .nBlackKnight;
    const pKing: e_piece = if (comptime white) .nWhiteKing else .nBlackKing;
    const kingSq = if (comptime white) p_board.b.wKingSq else p_board.b.bKingSq;
    const emptyOrEnem: u64 = ~p_board.b.c_occupiedBB[chess.whiteBoolToInt(white)];
    const opp = !white;
    const occ = p_board.b.occupiedBB();
    const wOcc = p_board.b.c_occupiedBB[chess.whiteBoolToInt(white)];

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
    const generateCapture = comptime (extra == .CAPTURE or extra == .ALL);
    const generateQuiet = comptime (extra == .QUIET or extra == .ALL);
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
        var pinnedPiece = (p_board.getPieceBB_t(.BISHOP) | p_board.getPieceBB_t(.QUEEN)) & pinD12 & wOcc;
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
        pinnedPiece = (p_board.getPieceBB_t(.ROOK) | p_board.getPieceBB_t(.QUEEN)) & pinHV & wOcc;
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
            pinnedPiece = p_moveBB.doubleMoves & pinHV & kingSqInfo.getFileBB();
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
                const toAtt_bb = att & kingDiags & p_board.b.c_occupiedBB[chess.whiteBoolToInt(!white)];
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
            while (toAtt_bb != 0) {
                const from: u8 = chess.bitscan(toAtt_bb);
                toAtt_bb &= toAtt_bb - 1;
                const moveBB = chess.xToBitboard(from) | if (comptime white) (chess.xToBitboard(to) >> 8) else (chess.xToBitboard(to) << 8);
                const rankAttack = chess.getQueenAttacks(occ ^ moveBB, kingSq) & kingSqInfo.getRankBB();
                const offender: u64 = (p_board.getPieceBB_t(.ROOK) | p_board.getPieceBB_t(.QUEEN)) & emptyOrEnem;
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
    const from: u8 = @intFromEnum(p_board.getKingSq(white));

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
        _ = movel.build_move_in(from, to, 0, p_out);
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
    const move = movel.build_move(from, to, 0);
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.KNIGHTPROMOCAPTURE)) << 12) });
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.BISHOPPROMOCAPTURE)) << 12) });
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.ROOKPROMOCAPTURE)) << 12) });
    p_out.append(.{ .m_move = move.m_move | (@as(u16, @intFromEnum(e_moveFlags.QUEENPROMOCAPTURE)) << 12) });
}

pub fn moveGenPawnBB(p_board: *const boardState, comptime white: bool, emptyOrEnemy: u64, extra: e_moveGenFlag, p_out: *moveBBState) void {
    p_out.pawnMoves = chess.EMPTY;
    p_out.pawnAttacks = chess.EMPTY;
    p_out.doubleMoves = chess.EMPTY;
    p_out.enPassantMoves = chess.EMPTY;
    const occ = if (extra == .ALL) chess.UNIVERSE else p_board.b.occupiedBB();

    const pBB = p_board.getPieceBB_t(.PAWN) & p_board.b.c_occupiedBB[chess.whiteBoolToInt(white)];

    const enPassantBB = chess.xToBitboard(p_board.frame.enPassantIdx);
    if (comptime white) {
        p_out.pawnMoves |= (pBB << 8) & (~occ);
        p_out.doubleMoves |= ((p_out.pawnMoves << 8) & (~occ)) & ((pBB & chess.whitePawnDoubleRank) << 16);

        p_out.pawnAttacks |= chess.getPawnAttacksFromBB(pBB, true);

        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.whitePawnEnpassantRank;

        p_out.pawnAttacks &= (emptyOrEnemy & occ);
        //p_out.pawnAttacks &= (p_board.b.c_occupiedBB[chess.whiteBoolToInt(false)]);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.whitePawnPromoRank);
        p_out.pawnAttacks &= ~chess.whitePawnPromoRank;
        p_out.pawnMoves &= ~chess.whitePawnPromoRank;
    } else {
        p_out.pawnMoves |= (pBB >> 8) & (~occ);
        p_out.doubleMoves |= ((p_out.pawnMoves >> 8) & (~occ)) & ((pBB & chess.blackPawnDoubleRank) >> 16);

        p_out.pawnAttacks |= chess.getPawnAttacksFromBB(pBB, false);

        p_out.enPassantMoves |= p_out.pawnAttacks & enPassantBB & chess.blackPawnEnpassantRank;

        //p_out.pawnAttacks &= (p_board.b.c_occupiedBB[chess.whiteBoolToInt(true)]);
        p_out.pawnAttacks &= (emptyOrEnemy & occ);

        p_out.promotionMoves |= ((p_out.pawnMoves | p_out.pawnAttacks) & chess.blackPawnPromoRank);
        p_out.pawnAttacks &= ~chess.blackPawnPromoRank;
        p_out.pawnMoves &= ~chess.blackPawnPromoRank;
    }
}

pub fn moveGenKingBB(p_board: *const boardState, comptime white: bool, emptyOrEnemy: u64, p_out: *moveBBState) void {
    const sq = if (comptime white) p_board.b.wKingSq else p_board.b.bKingSq;
    p_out.kingMoves = chess.getKingAttacks(sq) & emptyOrEnemy;
    const kingBB = chess.sqToBitboard(sq);
    if (p_board.canQueenSideCastle(white)) {
        p_out.queenSideCastlingMoves |= (kingBB >> 2);
    }
    if (p_board.canKingSideCastle(white)) {
        p_out.kingSideCastlingMoves |= (kingBB << 2);
    }
}

pub inline fn moveGenBB(p_board: *const boardState) moveBBState {
    var ret: moveBBState = .{};
    if (p_board.whiteToMove()) {
        cst_moveGenBB(p_board, true, &ret, .NONE);
        return ret;
    }
    cst_moveGenBB(p_board, false, &ret, .NONE);
    return ret;
}

pub fn cst_moveGenBB(p_board: *const boardState, comptime white: bool, p_out: *moveBBState, comptime extra: e_moveGenFlag) void {
    const EmptyOrEnemy = if (comptime extra == .ALL) (chess.UNIVERSE) else ~p_board.b.c_occupiedBB[chess.whiteBoolToInt(white)];
    const slidingOcc = p_board.b.occupiedBB() ^ p_board.getPieceBB_t(.KING);
    moveGenPawnBB(p_board, white, EmptyOrEnemy, extra, p_out);

    p_out.knightMoves = (chess.knightAttacks(p_board.getPieceBB_t(.KNIGHT) & p_board.b.c_occupiedBB[chess.whiteBoolToInt(white)])) & EmptyOrEnemy;

    p_out.bishopMoves = chess._AllAttackBishopMask(p_board.getPieceBB_t(.BISHOP) & p_board.b.c_occupiedBB[chess.whiteBoolToInt(white)], slidingOcc) & EmptyOrEnemy;

    p_out.rookMoves = chess._AllAttackRookMask(p_board.getPieceBB_t(.ROOK) & p_board.b.c_occupiedBB[chess.whiteBoolToInt(white)], slidingOcc) & EmptyOrEnemy;

    p_out.queenMoves = chess._AllAttackQueenMask(p_board.getPieceBB_t(.QUEEN) & p_board.b.c_occupiedBB[chess.whiteBoolToInt(white)], slidingOcc) & EmptyOrEnemy;

    moveGenKingBB(p_board, white, EmptyOrEnemy, p_out);
}
pub inline fn _cst_moveGenBB_all(p_board: *const boardState, comptime white: bool) moveBBState {
    var ret: moveBBState = .{};
    cst_moveGenBB(p_board, white, &ret, .ALL);
    return ret;
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
        free ^= (attackers.collapse() & p_state.b.c_occupiedBB[chess.whiteBoolToInt(true)]);
        var kingBB = east_nort_noWe_noEa_Attacks(k_qbb, free);
        var negBB = west_sout_soEa_soWe_Attacks(k_qbb, free);
        kingBB.bbOr_eq(&negBB);
        kingBB.bbAnd_eq(&attackers);
        return kingBB.collapse();
    } else {
        const k = p_state.getPieceBB(.nBlackKing);
        const k_qbb = qbb.init(k);
        var attackers = avx2DumbFill(p_state, true);
        free ^= (attackers.collapse() & p_state.b.c_occupiedBB[chess.whiteBoolToInt(false)]);
        var kingBB = east_nort_noWe_noEa_Attacks(k_qbb, free);
        var negBB = west_sout_soEa_soWe_Attacks(k_qbb, free);
        kingBB.bbOr_eq(&negBB);
        kingBB.bbAnd_eq(&attackers);
        return kingBB.collapse();
    }
}

pub fn getPinned_(p_state: *const boardState, comptime white: bool, king_E: e_square, rq: u64, bq: u64) u64 {
    var pinned: u64 = 0;
    var pinner = chess.xrayRookAttacks(p_state.b.occupiedBB(), p_state.b.c_occupiedBB[chess.whiteBoolToInt(white)], king_E) & rq;
    while (pinner != chess.EMPTY) {
        const pinsq = chess.bitscan(pinner);
        pinner &= pinner - 1;
        pinned |= chess.inBetween(@enumFromInt(pinsq), king_E);
    }

    pinner = chess.xrayBishopAttacks(p_state.b.occupiedBB(), p_state.b.c_occupiedBB[chess.whiteBoolToInt(white)], king_E) & bq;
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
    var pro: u64 = free & chess.notAFile;

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
    var pro: u64 = free & chess.notHFile;

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
    var pro: u64 = free & chess.notAFile;

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
    return (bb & chess.notAFile) << 7;
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
    return ((bb & chess.notHFile) >> 7);
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
    return ((bb & chess.notAFile) >> 9);
}

pub fn moveDeliverCheck(p_state: *const boardState, move: movel.IMove, isHashMove: bool) bool {
    const white: bool = p_state.whiteToMove();
    const from = move.getFrom();
    const to = move.getTo();
    const fromBB = chess.xToBitboard(from);
    const otherKing: u8 = @intFromEnum(p_state.getKingSq(!white));
    const otherKingBB = chess.xToBitboard(otherKing);
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
            return (chess.getRookAttacks(p_state.b.occupiedBB() ^ fromBB, castleSq) & otherKingBB) != 0;
        } else {
            return false;
        }
    }
    const occ = p_state.b.occupiedBB();
    const _occ = occ ^ fromBB;
    const att = chess.getRelevantAttacks(piece, @enumFromInt(toSq), _occ) catch {
        std.debug.print("[PANIC] panic with move {s} is hash move {}\n", .{ move.getStr(), isHashMove });
        chess.print_boardstate(p_state);
        chess.sanityCheckBoardState(p_state);
        @panic("???");
    };
    if ((att & otherKingBB) != 0) {
        return true;
    }

    return (chess.slider_getAllAttackerFromSq(p_state, occ ^ chess.xToBitboard(from) ^ chess.xToBitboard(to), white, @enumFromInt(otherKing))) != 0;
}
pub const typeMoveGenerator = struct {
    // generates pseudo legal moves
    //_moves: movesScores = undefined,

    captures: movesScores = undefined,
    computedCapt: bool = false,
    quiets: movesScores = undefined,
    computedQuiet: bool = false,
    badCaptures: movesScores = undefined,
    idx: u8 = 0,
    phase: typel.e_moveGenFlag = .NONE,

    pub fn init() typeMoveGenerator {
        var ret: typeMoveGenerator = undefined;
        ret.idx = 0;
        ret.phase = .NONE;
        //ret._moves.moves.len = 0;
        ret.captures.moves.len = 0;
        ret.computedCapt = false;
        ret.quiets.moves.len = 0;
        ret.computedQuiet = false;
        ret.badCaptures.moves.len = 0;
        return ret;
    }
    pub fn reset(p_self: *typeMoveGenerator) void {
        p_self.phase = .NONE;
        p_self.idx = 0;
    }

    pub fn pickNext(p_self: *typeMoveGenerator, state: *const boardl.boardState, ply: typel.depthT, hashMove: IMove, prevLineMove: IMove, seeThreshold: scoreType, skipQuiet: bool) ?struct { movel.IMove, scoreType } {
        const white = state.whiteToMove();
        const _ply: usize = @intCast(ply);
        if (p_self.phase == .NONE) {
            p_self.phase = .TTMOVE;
            if (hashMove.isValid() and !(hashMove.isQuietMove() and skipQuiet)) {
                p_self.idx = 1;
                return .{ hashMove, configl.ORDERING_LINE_VALUE + 1 };
            }
        }
        if (p_self.phase == .TTMOVE) {
            if (!p_self.computedCapt) {
                p_self.generateMove(.CAPTURE, state);
                //heuristicl.evalMoveScore(state, ply, hashMove, prevLineMove, useMVA, &p_self.captures);
                for (0..p_self.captures.moves.len) |i| {
                    const move = p_self.captures.moves.moves[i];

                    if (move.equal(prevLineMove)) {
                        p_self.captures.scores[i] = configl.ORDERING_LINE_VALUE;
                    } else {
                        //p_self.captures.scores[i] = heuristicl.SEE(state, move);

                        const to = move.getTo();
                        const cPiece: u8 = if (move.isEnpassant()) (if (white) @intFromEnum(e_piece.nBlackPawn) else @intFromEnum(e_piece.nWhitePawn)) else @intFromEnum(state.getPiece(to));
                        const fpiece: u8 = @intFromEnum(state.getFromPiece(move));
                        p_self.captures.scores[i] = historyl.captureHistory[fpiece][cPiece][to] + (heuristicl.SEE_values[cPiece] - heuristicl.SEE_values[fpiece]);
                    }
                }
            }
            p_self.phase = .CAPTURE;
        }
        if (p_self.phase == .CAPTURE) {
            while (p_self.idx < p_self.captures.moves.len) {
                const ret = p_self.captures.getNext(p_self.idx);
                p_self.idx += 1;
                if (ret.@"0".equal(hashMove)) {
                    continue;
                }

                //if (ret.@"1" > seeThreshold) {
                //    return ret;
                //} else {
                //    p_self.badCaptures.scores[p_self.badCaptures.moves.len] = ret.@"1";
                //    p_self.badCaptures.moves.append(ret.@"0");
                //}
                if (heuristicl.SEE_threshold(state, ret.@"0", seeThreshold)) {
                    return ret;
                } else {
                    p_self.badCaptures.scores[p_self.badCaptures.moves.len] = ret.@"1";
                    p_self.badCaptures.moves.append(ret.@"0");
                }
            }
        }
        if (p_self.phase == .CAPTURE) {
            if (!p_self.computedQuiet and !skipQuiet) {
                p_self.generateMove(.QUIET, state);
                //heuristicl.evalMoveScore(state, ply, hashMove, capturesprevLineMove, useMVA, &p_self.quiets);
                for (0..p_self.quiets.moves.len) |i| {
                    const move = p_self.quiets.moves.moves[i];
                    const to = move.getTo();
                    const from = move.getFrom();

                    if (move.equal(prevLineMove)) {
                        p_self.quiets.scores[i] = configl.ORDERING_LINE_VALUE;
                    } else if (move.equal(historyl.killerMoves[_ply][0])) {
                        p_self.quiets.scores[i] = configl.KILLER_0_HEURISTIC_VALUE;
                    } else if (move.equal(historyl.killerMoves[_ply][1])) {
                        p_self.quiets.scores[i] = configl.KILLER_1_HEURISTIC_VALUE;
                    } else if (move.isPromotion() and move.getFlag() == @intFromEnum(typel.e_moveFlags.QUEENPROMO)) {
                        p_self.quiets.scores[i] = configl.ORDERING_PROMOTIONS;
                    } else {
                        const offset = chess.whiteBoolToInt(white);
                        p_self.quiets.scores[i] = historyl.historyHeuristic[offset][from][to];
                    }
                }
            }
            p_self.phase = .QUIET;
        }
        if (p_self.phase == .QUIET and !skipQuiet) {
            while (p_self.idx < p_self.quiets.moves.len) {
                const ret = p_self.quiets.getNext(p_self.idx);
                p_self.idx += 1;
                if (ret.@"0".equal(hashMove)) {
                    continue;
                }
                return ret;
            }
            p_self.idx = 0;
            p_self.phase = .BADCAPTURE;
        }
        if (p_self.phase == .BADCAPTURE) {
            if (p_self.idx < p_self.badCaptures.moves.len) {
                const ret = .{ p_self.badCaptures.moves.moves[p_self.idx], p_self.badCaptures.scores[p_self.idx] };
                p_self.idx += 1;
                return ret;
            }
        }
        return null;
    }
    pub inline fn generateMove(self: *typeMoveGenerator, comptime t: typel.e_moveGenFlag, p_state: *const boardState) void {
        self.idx = 0;
        if (comptime t == .CAPTURE or t == .QUIET) {
            if (comptime t == .CAPTURE) {
                self.computedCapt = true;
                self.captures.moves.len = 0;
                generateMoveT(&self.captures.moves, t, p_state);
            }
            if (comptime t == .QUIET) {
                self.computedQuiet = true;
                self.quiets.moves.len = 0;
                generateMoveT(&self.quiets.moves, t, p_state);
            }
            return;
        }
        //if (comptime t == .CAPTURELEGAL) {
        //    generateMoveT(&self._moves.moves, .CAPTURE, p_state);
        //} else if (comptime t == .QUIETLEGAL) {
        //    generateMoveT(&self._moves.moves, .QUIET, p_state);
        //} else if (t == .ALLLEGAL) {
        //    generateMoveT(&self._moves.moves, .ALL, p_state);
        //}
        //var skips: usize = 0;
        //for (0..self._moves.moves.len) |i| {
        //    const move = self._moves.moves.moves[i];
        //    if (p_state.legal(move)) {
        //        self._moves.moves.moves[i - skips] = move;
        //    } else {
        //        skips += 1;
        //    }
        //}
        //self._moves.moves.len -= @intCast(skips);
    }
    pub inline fn generateAll(self: *typeMoveGenerator, p_state: *const boardState) void {
        self.idx = 0;
        self._moves.moves.len = 0;
        generateMoveT(&self._moves.moves, .ALL, p_state);
    }
    pub fn getMoveCounts(self: *typeMoveGenerator, p_state: *const boardState) moveTypeCount {
        var ret: moveTypeCount = .{};
        self.generateMove(.QUIET, p_state);
        ret.quiet = self.quiets.moves.len;

        self.generateMove(.CAPTURE, p_state);
        ret.capture = self.captures.moves.len;

        return ret;
    }
};
pub inline fn generateMoveT(out: *moveContainer, comptime t: typel.e_moveGenFlag, p_state: *const boardState) void {
    if (p_state.whiteToMove()) {
        return _generateMoveT(out, t, true, p_state);
    }
    return _generateMoveT(out, t, false, p_state);
}
pub fn _generateMoveT(out: *moveContainer, comptime t: typel.e_moveGenFlag, comptime white: bool, p_state: *const boardState) void {
    const isCheck = p_state.isChecked();
    const own = p_state.b.c_occupiedBB[chess.whiteBoolToInt(white)];
    const _emptyOrEnemy = ~own;
    const occ = p_state.b.occupiedBB();
    const targets = if (comptime t == .QUIET) (if (isCheck) (p_state.frame.checkersBB & (~occ)) else (_emptyOrEnemy & (~occ))) else if (comptime t == .CAPTURE) (if (isCheck) (p_state.frame.checkersBB & occ) else (_emptyOrEnemy & occ)) else if (comptime t == .ALL) (if (isCheck) (p_state.frame.checkersBB) else (_emptyOrEnemy));

    if (isCheck) {
        const checkers = p_state.frame.checkersBB & occ;
        if (checkers & (checkers - 1) != 0) {
            if (comptime t == .QUIET) {
                return king_generatePieceMove(out, t, white, p_state, ~checkers & ~occ);
            } else if (comptime t == .CAPTURE) {
                return king_generatePieceMove(out, t, white, p_state, _emptyOrEnemy & occ);
            }
        }
        if (comptime t == .QUIET) {
            king_generatePieceMove(out, t, white, p_state, ~checkers & ~occ);
        } else if (comptime t == .CAPTURE) {
            king_generatePieceMove(out, t, white, p_state, _emptyOrEnemy & occ);
        }
    } else {
        king_generatePieceMove(out, t, white, p_state, targets);
    }

    generatePawnt(out, white, t, p_state, occ, targets);

    // horiz
    var bb = p_state.getPieceBB_t(.QUEEN) | p_state.getPieceBB_t(.ROOK) & own;
    while (bb != 0) {
        const sq = chess.bitscan(bb);
        bb &= bb - 1;
        const att = chess.getRookAttacks(occ, @enumFromInt(sq));
        if (comptime t == .CAPTURE or t == .ALL) {
            genericStagedMovePushCapture(out, att & targets, sq);
        }
        if (comptime t == .QUIET or t == .ALL) {
            genericStagedMovePushQuiet(out, att & targets, sq);
        }
    }
    bb = p_state.getPieceBB_t(.QUEEN) | p_state.getPieceBB_t(.BISHOP) & own;
    while (bb != 0) {
        const sq = chess.bitscan(bb);
        bb &= bb - 1;
        const att = chess.getBishopAttacks(occ, @enumFromInt(sq));
        if (comptime t == .CAPTURE or t == .ALL) {
            genericStagedMovePushCapture(out, att & targets, sq);
        }
        if (comptime t == .QUIET or t == .ALL) {
            genericStagedMovePushQuiet(out, att & targets, sq);
        }
    }
    bb = p_state.getPieceBB_t(.KNIGHT) & own;
    while (bb != 0) {
        const sq = chess.bitscan(bb);
        bb &= bb - 1;
        const att = chess.knightAttacks(chess.xToBitboard(sq));
        if (comptime t == .CAPTURE or t == .ALL) {
            genericStagedMovePushCapture(out, att & targets, sq);
        }
        if (comptime t == .QUIET or t == .ALL) {
            genericStagedMovePushQuiet(out, att & targets, sq);
        }
    }
    //if (p_state.getLastMove().equal(movel.build_move(@intFromEnum(e_square.b5), @intFromEnum(e_square.c7), @intFromEnum(e_moveFlags.CAPTURE)))) {
    //    std.debug.print("move gen for type {} is checked {} \n", .{ t, isCheck });
    //    out.print();
    //}
    //const badMove = movel.build_move(@intFromEnum(e_square.c8), @intFromEnum(e_square.d7), @intFromEnum(e_moveFlags.QUIETMOVE));
    //if (badMove.isIn(out.*)) {
    //    std.debug.print("bad move found in out t {} is checked {} \n", .{ t, isCheck });
    //    chess.print_boardstate(p_state);
    //    out.print();
    //}
}
pub fn king_generatePieceMove(out: *moveContainer, comptime t: typel.e_moveGenFlag, comptime white: bool, p_state: *const boardState, targets: u64) void {
    const sq = if (comptime white) p_state.b.wKingSq else p_state.b.bKingSq;
    const sqX: u8 = @intFromEnum(sq);
    const att = chess.getKingAttacks(sq);
    if (comptime t == .CAPTURE or t == .ALL) {
        genericStagedMovePushCapture(out, att & targets, @intFromEnum(sq));
    }
    if (comptime t == .QUIET or t == .ALL) {
        genericStagedMovePushQuiet(out, att & targets, @intFromEnum(sq));
        if (!p_state.isChecked()) {
            if (p_state.canKingSideCastle(white)) {
                _ = movel.build_move_in(sqX, sqX + 2, @intFromEnum(e_moveFlags.KINGCASTLE), out);
            }
            if (p_state.canQueenSideCastle(white)) {
                _ = movel.build_move_in(sqX, sqX - 2, @intFromEnum(e_moveFlags.QUEENCASTLE), out);
            }
        }
    }
}

pub fn generatePawnt(out: *moveContainer, comptime white: bool, comptime t: typel.e_moveGenFlag, p_state: *const boardState, occ: u64, targets: u64) void {
    const p = p_state.getPieceBB_t(.PAWN) & p_state.b.c_occupiedBB[chess.whiteBoolToInt(white)];
    const realEmpty = ~occ;
    //const empty = realEmpty & emptyOrEnemy;

    if (comptime t == .QUIET or t == .ALL) {
        var bbProm = p & chess.maskOutPawnQuietMove(white, targets) & if (comptime white) chess.blackPawnDoubleRank else chess.whitePawnDoubleRank;
        while (bbProm != 0) {
            const sq = chess.bitscan(bbProm);
            bbProm &= bbProm - 1;
            push_promotion(sq, if (comptime white) (sq + 8) else (sq - 8), out);
        }
        var bb: u64 = p & chess.maskOutPawnQuietMove(white, targets) & if (comptime white) ~chess.blackPawnDoubleRank else ~chess.whitePawnDoubleRank;
        while (bb != 0) {
            const sq = chess.bitscan(bb);
            bb &= bb - 1;
            _ = movel.build_move_in(sq, if (comptime white) (sq + 8) else (sq - 8), @intFromEnum(e_moveFlags.QUIETMOVE), out);
        }

        //std.debug.print("generatePawnt double pawn occ emptyorenemy empty\n", .{});
        //chess.print_bitboard(occ);
        //chess.print_bitboard(emptyOrEnemy);
        //chess.print_bitboard(empty);
        bb = p & chess.maskOutPawnDoublePush(white, realEmpty);
        while (bb != 0) {
            const sq = chess.bitscan(bb);
            const dest = if (comptime white) (sq + 16) else (sq - 16);
            bb &= bb - 1;
            if (chess.xToBitboard(dest) & targets != 0) {
                _ = movel.build_move_in(sq, dest, @intFromEnum(e_moveFlags.DOUBLEPAWN), out);
            }
        }
    }
    if (comptime t == .CAPTURE or t == .ALL) {
        var bbProm = p & if (comptime white) chess.blackPawnDoubleRank else chess.whitePawnDoubleRank;
        while (bbProm != 0) {
            const sq = chess.bitscan(bbProm);
            bbProm &= bbProm - 1;
            var att = chess.getPawnAttacks(@enumFromInt(sq), white) & targets;
            while (att != 0) {
                const victim = chess.bitscan(att);
                att &= att - 1;
                push_promotion_capture(sq, victim, out);
            }
        }

        var bb: u64 = p & if (comptime white) ~chess.blackPawnDoubleRank else ~chess.whitePawnDoubleRank;
        while (bb != 0) {
            const sq = chess.bitscan(bb);
            bb &= bb - 1;
            const att = chess.getPawnAttacks(@enumFromInt(sq), white) & targets;
            genericStagedMovePushCapture(out, att, sq);
        }
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
pub const genError = error{ quietMoveErr, captureMoveErr, evasionMoveErr, allMoveErr };
pub const moveTypeCount = struct {
    quiet: u8 = 0,
    capture: u8 = 0,
    evasion: u8 = 0,
    pub fn all(self: moveTypeCount) u8 {
        return self.quiet + self.capture + self.evasion;
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

        if (p_state.isChecked() and chess.isKingPiece(p_state.getPiece(move.getFrom()))) {
            ret.evasion += 1;
        }
    }
    return ret;
}
pub const movesScores = struct {
    moves: moveContainer = undefined,
    scores: [chess.MAX_POSSIBLE_MOVE]scoreType = undefined,
    pub fn getNext(self: *movesScores, idx: usize) struct { movel.IMove, scoreType } {
        var bestScore = self.scores[idx];
        var bestId: usize = idx;
        for (idx + 1..self.moves.len) |i| {
            if (self.scores[i] > bestScore) {
                bestScore = self.scores[i];
                bestId = i;
            }
        }

        // see Patricia
        std.mem.swap(IMove, &self.moves.moves[idx], &self.moves.moves[bestId]);
        std.mem.swap(scoreType, &self.scores[idx], &self.scores[bestId]);
        return .{ self.moves.moves[idx], bestScore };
    }
};

pub const moveOrdering = struct {
    indexes: [chess.MAX_POSSIBLE_MOVE]u8 = undefined,
    scores: [chess.MAX_POSSIBLE_MOVE]scoreType = undefined,
    len: u8 = 0,
};

pub fn main() !void {
    //const state = try chess.getBoardFromFen("r7/p1pp1QB1/qn6/3p4/4n3/7p/PPP2PPP/R3K2R b HA - 0 17");

    magicl._initMagic(&magicl.magicTable, false);
    //const state = try chess.getBoardFromFen("8/q7/8/3K4/8/8/2pN3p/8 b - - 3 113");
    const state = try chess.getBoardFromFen("8/8/4b1kp/8/6r1/1p3K2/8/8 b - - 3 110");
    const badMoveQ = movel.build_move(@intFromEnum(e_square.g4), @intFromEnum(e_square.f3), @intFromEnum(typel.e_moveFlags.QUIETMOVE));
    const badMoveC = movel.build_move(@intFromEnum(e_square.g4), @intFromEnum(e_square.f3), @intFromEnum(typel.e_moveFlags.CAPTURE));
    std.debug.print("{} {} \n", .{ state.isMovePseudoLegal(badMoveQ), state.isMovePseudoLegal(badMoveC) });

    chess.print_boardstate(&state);
    var gen: typeMoveGenerator = .init();
    gen.generateMove(.CAPTURE, &state);
    gen.captures.moves.print();

    gen.generateMove(.QUIET, &state);
    gen.quiets.moves.print();
}
