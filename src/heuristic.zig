const chess = @import("chess.zig");
const moveGenl = @import("move_generation.zig");
const filel = @import("file.zig");
const stringl = @import("string.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const statusl = @import("board_status.zig");
const boardl = @import("board.zig");
const weightl = @import("weights.zig");
const squarel = @import("square.zig");
const mainl = @import("main.zig");
const movel = @import("move.zig");
const typel = @import("type.zig");
const alphaBetal = @import("search/alphaBeta.zig");
const threadingl = @import("search/threading.zig");
const historyl = @import("history.zig");
const hashl = @import("hashTable.zig");

const std = @import("std");

const e_piece = chess.e_piece;
const e_pieceType = chess.e_pieceType;
const e_turn = statusl.e_turn;

const string = stringl.string;
const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const moveBBState = movel.moveBBState;
const scoreType: type = typel.scoreType;
pub const scoreVect: type = @Vector(2, scoreType);
const milliDepth: type = typel.milliDepth;

pub const texel_err = error{board_err};

pub fn evaluate(p_state: *const boardl.boardState) scoreType {
    const allwhiteMoveBB = moveGenl._cst_moveGenBB_all(p_state, true);
    const allblackMoveBB = moveGenl._cst_moveGenBB_all(p_state, false);
    const whiteMoveBB = allwhiteMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromBool(true)]);
    const blackMoveBB = allblackMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromBool(false)]);
    const white = p_state.whiteToMove();

    const phase: scoreType = p_state.getPhase();

    var ret = evaluate_mobility(p_state, &allwhiteMoveBB, &allblackMoveBB, white);

    ret += evaluate_material(p_state);
    ret += evaluate_safety(p_state, &whiteMoveBB, &blackMoveBB);
    ret += evaluate_structure(p_state, &allwhiteMoveBB, &allblackMoveBB);
    ret += evaluate_tempo(p_state, &allwhiteMoveBB, &allblackMoveBB, white);
    ret += evaluate_pawnStructure(p_state);
    ret += evaluate_king(p_state, (ret[0] + ret[1]) > 0, white);

    return computeTaperedV(ret, phase) + p_state.frame.psqtEval;
}

pub inline fn c_evaluate(p_state: *const boardl.boardState, white: bool) scoreType {
    const ret = evaluate(p_state);
    if (white) return ret - p_state.frame.halfMoveClock;
    return (-ret) - p_state.frame.halfMoveClock;
}

pub const heuristicComponents = struct {
    PSQT: scoreType = 0,
    Mobility: scoreType = 0,
    PawnStruct: scoreType = 0,
    Safety: scoreType = 0,
    Material: scoreType = 0,
    Structure: scoreType = 0,
    Tempo: scoreType = 0,
    King: scoreType = 0,
    pub fn total(self: *const heuristicComponents) scoreType {
        return self.PSQT + self.Mobility + self.PawnStruct + self.Safety + self.Structure + self.Tempo + self.King + self.Material;
    }
    pub fn print(self: *const heuristicComponents) void {
        std.debug.print("Score: PSQT = {d}, Mobility = {d}, PawnStruct = {d}, Safety = {d}, Material = {d}, Structure = {d}, Tempo = {d}, King = {d}, Total = {d}\n", .{ self.PSQT, self.Mobility, self.PawnStruct, self.Safety, self.Material, self.Structure, self.Tempo, self.King, self.total() });
    }
};
pub fn evaluate_debug(p_state: *const boardl.boardState) heuristicComponents {
    const allwhiteMoveBB = moveGenl._cst_moveGenBB_all(p_state, true);
    const allblackMoveBB = moveGenl._cst_moveGenBB_all(p_state, false);
    const whiteMoveBB = allwhiteMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromBool(true)]);
    const blackMoveBB = allblackMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromBool(false)]);

    const phase: scoreType = p_state.getPhase();
    const white = p_state.whiteToMove();
    //const phase: scoreType = @divFloor((p_state.getPhase() >> 8) + (typel.totalPhase >> 1), typel.totalPhase);

    const ret: heuristicComponents = .{
        //.PSQT = evaluate_PSQT(p_state, values, _phase),
        .PSQT = p_state.frame.psqtEval,
        .Mobility = computeTaperedV(evaluate_mobility(p_state, &allwhiteMoveBB, &allblackMoveBB, white), phase),
        .King = computeTaperedV(evaluate_king(p_state, p_state.frame.psqtEval > 0, white), phase),
        .Material = computeTaperedV(evaluate_material(p_state), phase),
        .Safety = computeTaperedV(evaluate_safety(p_state, &whiteMoveBB, &blackMoveBB), phase),
        .Structure = computeTaperedV(evaluate_structure(p_state, &allwhiteMoveBB, &allblackMoveBB), phase),
        .PawnStruct = computeTaperedV(evaluate_pawnStructure(p_state), phase),
        .Tempo = computeTaperedV(evaluate_tempo(p_state, &allwhiteMoveBB, &allblackMoveBB, white), phase),
    };
    return ret;
}
pub inline fn computeTapered(score_mg: scoreType, score_eg: scoreType, phase: scoreType) scoreType {
    return @divFloor((score_mg * (256 - phase)) + score_eg * phase, 256);
}
pub inline fn computeTaperedV(s: scoreVect, phase: scoreType) scoreType {
    return @divFloor((s[0] * (256 - phase)) + s[1] * phase, 256);
}

pub fn evaluate_PSQT(p_state: *const boardl.boardState, _phase: scoreType) scoreType {
    var score_count: scoreType = 0;
    var score_mg: scoreType = 0;
    var score_eg: scoreType = 0;
    var _bb = p_state.b.occupiedBB();

    while (_bb != 0) {
        const sq = chess.bitscan(_bb);
        _bb &= _bb - 1;
        const piece = p_state.getPiece(@intCast(sq));
        switch (piece) {
            .nEmptySquare, .nWhite, .nBlack => {},
            .nWhitePawn => {
                score_count += weightl.global_PawnValue;
                score_mg += weightl.global_Pawn_PSQT[MG][sq];
                score_eg += weightl.global_Pawn_PSQT[EG][sq];
            },
            .nWhiteBishop => {
                score_count += weightl.global_BishopValue;
                score_mg += weightl.global_Bishop_PSQT[MG][sq];
                score_eg += weightl.global_Bishop_PSQT[EG][sq];
            },
            .nWhiteKnight => {
                score_count += weightl.global_KnightValue;
                score_mg += weightl.global_Knight_PSQT[MG][sq];
                score_eg += weightl.global_Knight_PSQT[EG][sq];
            },
            .nWhiteRook => {
                score_count += weightl.global_RookValue;
                score_mg += weightl.global_Rook_PSQT[MG][sq];
                score_eg += weightl.global_Rook_PSQT[EG][sq];
            },
            .nWhiteQueen => {
                score_count += weightl.global_QueenValue;
                score_mg += weightl.global_Queen_PSQT[MG][sq];
                score_eg += weightl.global_Queen_PSQT[EG][sq];
            },
            .nWhiteKing => {
                score_mg += weightl.global_King_PSQT[MG][sq];
                score_eg += weightl.global_King_PSQT[EG][sq];
            },

            .nBlackPawn => {
                score_count -= weightl.global_PawnValue;
                score_mg -= weightl.global_Pawn_PSQT[MG][chess.flipSq(sq)];
                score_eg -= weightl.global_Pawn_PSQT[EG][chess.flipSq(sq)];
            },
            .nBlackBishop => {
                score_count -= weightl.global_BishopValue;
                score_mg -= weightl.global_Bishop_PSQT[MG][chess.flipSq(sq)];
                score_eg -= weightl.global_Bishop_PSQT[EG][chess.flipSq(sq)];
            },
            .nBlackKnight => {
                score_count -= weightl.global_KnightValue;
                score_mg -= weightl.global_Knight_PSQT[MG][chess.flipSq(sq)];
                score_eg -= weightl.global_Knight_PSQT[EG][chess.flipSq(sq)];
            },
            .nBlackRook => {
                score_count -= weightl.global_RookValue;
                score_mg -= weightl.global_Rook_PSQT[MG][chess.flipSq(sq)];
                score_eg -= weightl.global_Rook_PSQT[EG][chess.flipSq(sq)];
            },
            .nBlackQueen => {
                score_count -= weightl.global_QueenValue;
                score_mg -= weightl.global_Queen_PSQT[MG][chess.flipSq(sq)];
                score_eg -= weightl.global_Queen_PSQT[EG][chess.flipSq(sq)];
            },
            .nBlackKing => {
                score_mg -= weightl.global_King_PSQT[MG][chess.flipSq(sq)];
                score_eg -= weightl.global_King_PSQT[EG][chess.flipSq(sq)];
            },
        }
    }

    return score_count + computeTapered(score_mg, score_eg, _phase);
}

pub fn evaluate_pawnStructure(p_state: *const boardl.boardState) scoreVect {
    const wp = p_state.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] & p_state.b.c_occupiedBB[1];
    const bp = p_state.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] & p_state.b.c_occupiedBB[0];
    // in an effort to have the weights all positive I swapped the diff, (nBlackIsolated - nWhiteIsolated) * (w>0) means that white is advantaged (s>0) if (nBlackIsolated > nWhiteIsolated) and black is advantaged(s<0) if (nBlackIsolated < nWhiteIsolated)
    // same for doubled as doubled and isolated are seen as negative attributes hence why I chose negative weights to penalize the respective sides.

    const nWhiteIsolated: i8 = @intCast(chess.popcount(chess.isolatedPawns(wp)));
    const nBlackIsolated: i8 = @intCast(chess.popcount(chess.isolatedPawns(bp)));
    const isoS: scoreType = @intCast(nBlackIsolated - nWhiteIsolated);

    const nWhiteDoubled: i8 = @intCast(chess.popcount(chess.stackedPawns(wp)));
    const nBlackDoubled: i8 = @intCast(chess.popcount(chess.stackedPawns(bp)));
    const doS: scoreType = @intCast(nBlackDoubled - nWhiteDoubled);

    const nWhitePassed: i8 = @intCast(chess.popcount(chess.passedPawns(wp, bp)));
    const nBlackPassed: i8 = @intCast(chess.popcount(chess.passedPawns(bp, wp)));
    const paS: scoreType = @intCast(nWhitePassed - nBlackPassed);

    const nWhiteDuo: i8 = @intCast(chess.popcount(chess.duoPhalanx(wp)));
    const nBlackDuo: i8 = @intCast(chess.popcount(chess.duoPhalanx(bp)));
    const duoS: scoreType = @intCast(nWhiteDuo - nBlackDuo);

    const nWhiteConn: i8 = @intCast(chess.popcount(wp & chess.getPawnAttacksFromBB(wp, true)));
    const nBlackConn: i8 = @intCast(chess.popcount(bp & chess.getPawnAttacksFromBB(bp, false)));
    const connectS: scoreType = @intCast(nWhiteConn - nBlackConn);

    return .{ (isoS * weightl.global_IsolatedPawnValue[MG]) + (doS * weightl.global_StackedPawnValue[MG]) + (paS * weightl.global_PassedPawnValue[MG]) + (duoS * weightl.global_phalanxDuoPawnValue[MG]) + (connectS * weightl.global_connectionPawnValue[MG]), (isoS * weightl.global_IsolatedPawnValue[EG]) + (doS * weightl.global_StackedPawnValue[EG]) + (paS * weightl.global_PassedPawnValue[EG]) + (duoS * weightl.global_phalanxDuoPawnValue[EG]) + (connectS * weightl.global_connectionPawnValue[EG]) };
}
pub fn evaluate_mobility(p_state: *const boardl.boardState, p_whiteMoveBB: *const moveBBState, p_blackMoveBB: *const moveBBState, white: bool) scoreVect {
    _ = white;
    // going to use "raw" mobility only taking board coverage
    const moveW: i64 = @intCast(p_whiteMoveBB.count());
    const moveB: i64 = @intCast(p_blackMoveBB.count());
    const v = @as(scoreType, @intCast(moveW - moveB));
    const moveAmountScore: scoreVect = .{ weightl.global_MobilityValue[MG] * v, weightl.global_MobilityValue[EG] * v };
    const wkingBB = chess.sqToBitboard(p_state.b.wKingSq);
    const bkingBB = chess.sqToBitboard(p_state.b.bKingSq);

    const bAttacks = (p_blackMoveBB.getAttackedMask(chess.UNIVERSE));
    const wAttacks = (p_whiteMoveBB.getAttackedMask(chess.UNIVERSE));
    const kingMoveW = p_whiteMoveBB.kingMoves & (~bAttacks) & ~p_state.b.c_occupiedBB[@intFromBool(true)];
    const kingMoveB = p_blackMoveBB.kingMoves & (~wAttacks) & ~p_state.b.c_occupiedBB[@intFromBool(false)];
    const nw: scoreType = @intCast(chess.ipopcount(kingMoveW));
    const nb: scoreType = @intCast(chess.ipopcount(kingMoveB));
    const v2 = (nw - nb);
    var kingMoveScore: scoreVect = .{ weightl.global_KingMobilityValue[MG] * v2, weightl.global_KingMobilityValue[EG] * v2 };

    if (nw == 0 and (wkingBB & bAttacks) != 0) {
        kingMoveScore -= .{ weightl.global_weakCheckmate[MG], weightl.global_weakCheckmate[EG] };
    }
    if (nb == 0 and (bkingBB & wAttacks) != 0) {
        kingMoveScore += .{ weightl.global_weakCheckmate[MG], weightl.global_weakCheckmate[EG] };
    }
    const nOpenRookW: scoreType = @intCast(chess.popcount(chess.openFileRooks(p_state.getPieceBB_t(.ROOK) & p_state.b.c_occupiedBB[@intFromBool(true)], p_state.getPieceBB_t(.PAWN) & p_state.b.c_occupiedBB[@intFromBool(true)], true)));
    const nOpenRookB: scoreType = @intCast(chess.popcount(chess.openFileRooks(p_state.getPieceBB_t(.ROOK) & p_state.b.c_occupiedBB[@intFromBool(false)], p_state.getPieceBB_t(.PAWN) & p_state.b.c_occupiedBB[@intFromBool(false)], false)));
    const deltaOpenRook = nOpenRookW - nOpenRookB;
    const pieceMobility: scoreVect = .{ weightl.global_OpenFileRookValue[MG] * deltaOpenRook, weightl.global_OpenFileRookValue[EG] * deltaOpenRook };
    return moveAmountScore + kingMoveScore + pieceMobility;
}
pub fn evaluate_king(p_state: *const boardl.boardState, whiteWinning: bool, whiteToMove: bool) scoreVect {
    _ = whiteToMove;
    if (p_state.isEndGame()) {
        const distance: scoreType = squarel.computeMHDistance(p_state.b.wKingSq, p_state.b.bKingSq);
        const bonus = 2 * (squarel.maxBenDistance - distance) + 5 * if (whiteWinning) squarel.computeMHDistance(p_state.b.bKingSq, squarel.centerSq) else -squarel.computeMHDistance(p_state.b.wKingSq, squarel.centerSq);
        return .{ bonus * weightl.global_KingProximityValue[MG], bonus * weightl.global_KingProximityValue[EG] };
    } else {
        return .{ 0, 0 };
    }
}
pub fn evaluate_material(p_state: *const boardl.boardState) scoreVect {
    // counting negative for white as the best safety is not attackers => 0 heuristic
    const nPairs: scoreType = @as(scoreType, @intFromBool(p_state.b.pieceCount[@intFromEnum(e_piece.nWhiteBishop)] == 2)) - @as(scoreType, @intFromBool(p_state.b.pieceCount[@intFromEnum(e_piece.nBlackBishop)] == 2));
    const bishopPair: scoreVect = .{ nPairs * weightl.global_materialBishopPair[MG], nPairs * weightl.global_materialBishopPair[EG] };
    return bishopPair;
}

pub fn evaluate_safety(p_state: *const boardl.boardState, p_whiteMoveBB: *const moveBBState, p_blackMoveBB: *const moveBBState) scoreVect {
    // counting negative for white as the best safety is not attackers => 0 heuristic
    const kingWSafety = chess.safetyArea(p_state.b.wKingSq);
    const kingBSafety = chess.safetyArea(p_state.b.bKingSq);

    const wKnight: scoreType = @intCast(chess.ipopcount(kingBSafety & p_whiteMoveBB.knightMoves));
    const bKnight: scoreType = @intCast(chess.ipopcount(kingWSafety & p_blackMoveBB.knightMoves));
    const Knight: scoreType = wKnight - bKnight;

    const wBishop: scoreType = @intCast(chess.ipopcount(kingBSafety & p_whiteMoveBB.bishopMoves));
    const bBishop: scoreType = @intCast(chess.ipopcount(kingWSafety & p_blackMoveBB.bishopMoves));
    const Bishop: scoreType = wBishop - bBishop;

    const wRook: scoreType = @intCast(chess.ipopcount(kingBSafety & p_whiteMoveBB.rookMoves));
    const bRook: scoreType = @intCast(chess.ipopcount(kingWSafety & p_blackMoveBB.rookMoves));
    const Rook: scoreType = wRook - bRook;

    const wQueen: scoreType = @intCast(chess.ipopcount(kingBSafety & p_whiteMoveBB.queenMoves));
    const bQueen: scoreType = @intCast(chess.ipopcount(kingWSafety & p_blackMoveBB.queenMoves));
    const Queen: scoreType = wQueen - bQueen;

    // white is advantaged from a high safety_arr index, more =wPieceAtt are present in the black king vicinity thus it should be counted as positive
    const saf: scoreType = SAFETY_ARR[@intCast(@min(SAFETY_ARR.len - 1, wKnight + wBishop + wRook + wQueen))] - SAFETY_ARR[@intCast(@min(SAFETY_ARR.len - 1, bKnight + bBishop + bRook + bQueen))];
    const v: scoreVect = .{ saf + (weightl.global_SafetyKnightValue[MG] * Knight) + (weightl.global_SafetyBishopValue[MG] * Bishop) + (weightl.global_SafetyRookValue[MG] * Rook) + (weightl.global_SafetyQueenValue[MG] * Queen), saf + (weightl.global_SafetyKnightValue[EG] * Knight) + (weightl.global_SafetyBishopValue[EG] * Bishop) + (weightl.global_SafetyRookValue[EG] * Rook) + weightl.global_SafetyQueenValue[EG] * Queen };
    return v;
}
pub fn evaluate_structure(p_state: *const boardl.boardState, p_whiteMoveBB: *const moveBBState, p_blackMoveBB: *const moveBBState) scoreVect {
    // structure protection,
    // use the c_moveBBstate & c_occupied, this returns the safety of each individual pieces against capture
    const w_pieceProtect = p_whiteMoveBB.andFn(p_state.b.c_occupiedBB[@intFromBool(true)] ^ chess.sqToBitboard(p_state.b.wKingSq));
    const b_pieceProtect = p_blackMoveBB.andFn(p_state.b.c_occupiedBB[@intFromBool(false)] ^ chess.sqToBitboard(p_state.b.bKingSq));
    const s = @as(scoreType, @intCast(w_pieceProtect.count())) - @as(scoreType, @intCast(b_pieceProtect.count()));

    const w_pieceCenterProt = p_whiteMoveBB.andFn(typel.centerBB).collapse();
    const b_pieceCenterProt = p_blackMoveBB.andFn(typel.centerBB).collapse();
    const s2 = @as(scoreType, @intCast(chess.popcount(w_pieceCenterProt))) - @as(scoreType, @intCast(chess.popcount(b_pieceCenterProt)));
    return .{ weightl.global_StructureProtectionValue[MG] * s + weightl.global_centerProtectionValue[MG] * s2, weightl.global_StructureProtectionValue[EG] * s + weightl.global_centerProtectionValue[EG] * s2 };
}
pub fn evaluate_tempo(p_state: *const boardl.boardState, p_whiteMoveBB: *const moveBBState, p_blackMoveBB: *const moveBBState, white: bool) scoreVect {
    const nonPawns = ~p_state.getPieceBB_t(.PAWN);
    const wThreats = p_whiteMoveBB.andFn(p_state.b.c_occupiedBB[@intFromBool(false)] & nonPawns);
    const bThreats = p_blackMoveBB.andFn(p_state.b.c_occupiedBB[@intFromBool(true)] & nonPawns);
    const deltaThreat: scoreType = @as(scoreType, (@intCast(wThreats.count()))) - @as(scoreType, (@intCast(bThreats.count())));

    var ret: scoreVect = .{ weightl.global_pieceThreatScore[MG] * deltaThreat, weightl.global_pieceThreatScore[EG] * deltaThreat };
    if (p_state.isChecked()) {
        if (white) {
            ret -= .{ weightl.global_tempoChecksScore[MG], weightl.global_tempoChecksScore[EG] };
        } else {
            ret += .{ weightl.global_tempoChecksScore[MG], weightl.global_tempoChecksScore[EG] };
        }
    }
    return ret;
}

pub fn e_pieceToHeuristic(piece: e_piece) scoreType {
    switch (piece) {
        .nEmptySquare, .nWhite, .nBlack => {
            return 0;
        },
        .nWhiteKing, .nBlackKing => {
            return weightl.global_QueenValue << 2;
        },
        .nWhitePawn, .nBlackPawn => {
            return weightl.global_PawnValue;
        },
        .nWhiteBishop, .nBlackBishop => {
            return weightl.global_BishopValue;
        },
        .nWhiteKnight, .nBlackKnight => {
            return weightl.global_KnightValue;
        },
        .nWhiteRook, .nBlackRook => {
            return weightl.global_RookValue;
        },
        .nWhiteQueen, .nBlackQueen => {
            return weightl.global_QueenValue;
        },
    }
}
pub fn updatePSQTOnMove(comptime white: bool, comptime isCapture: bool, move: IMove, isPromo: bool, isCastle: bool, toPiece: e_piece, phase: scoreType, info: *const boardl.boardFrame) scoreType {
    var fromPiece = toPiece;
    const from = move.getFrom();
    const to = move.getTo();
    var sV: @Vector(3, scoreType) = getPieceInfos(fromPiece, @enumFromInt(to));
    if (isPromo) {
        fromPiece = if (comptime white) .nWhitePawn else .nBlackPawn;
    }
    sV -= getPieceInfos(fromPiece, @enumFromInt(from));

    if (comptime !isCapture) {
        if (isCastle) {
            const toBis: u8 = if (comptime white) to else (chess.flipSq(to));
            if (move.isQueenSideCastle()) {
                const prev: @Vector(3, scoreType) = getPieceInfos_cst(.ROOK, toBis - 2);
                const next: @Vector(3, scoreType) = getPieceInfos_cst(.ROOK, toBis + 1);
                sV = sV + next - prev;
            } else {
                const prev: @Vector(3, scoreType) = getPieceInfos_cst(.ROOK, toBis + 1);
                const next: @Vector(3, scoreType) = getPieceInfos_cst(.ROOK, toBis - 1);
                sV = sV + next - prev;
            }
        }
    } else {
        // is capture
        const victimSq: typel.e_square = if (move.isEnpassant()) chess.enPassantVictimSq(from, to) else (@enumFromInt(to));
        const victimScs: @Vector(3, scoreType) = getPieceInfos(info.victim, victimSq);
        sV += victimScs;
    }

    const ret = sV[0] + computeTapered(sV[1], sV[2], phase);
    if (comptime white) {
        return ret;
    }
    return -ret;
}

pub fn materialImbalance(p_state: *const boardl.boardState) scoreType {
    const wPiece: @Vector(5, scoreType) = .{p_state.b.pieceCount[0..5]};
    const bPiece: @Vector(5, scoreType) = .{p_state.b.pieceCount[6..11]};
    const scores = (wPiece - bPiece) * .{ weightl.global_PawnValue, weightl.simpleBishopScore, weightl.global_KnightValue, weightl.global_RookValue, weightl.global_QueenValue };
    return scores[0] + scores[1] + scores[2] + scores[3] + scores[4];
}
pub inline fn c_materialImbalance(p_state: *const boardl.boardState, white: bool) scoreType {
    const ret = materialImbalance(p_state);
    if (white) return ret;
    return -ret;
}

pub fn getMaskFromBB(bb: u64) [chess.N_SQUARES]scoreType {
    var ret: [chess.N_SQUARES]scoreType = std.mem.zeroes([chess.N_SQUARES]scoreType);
    for (0..chess.N_SQUARES) |i| {
        const val: u64 = (bb >> @intCast(i)) & chess.ONE;
        ret[i] = @intCast(val);
    }
    return ret;
}
pub fn modifyHeuristicWeight(alloc: std.mem.Allocator, path: []const u8, debug: bool) !void {
    // format
    var tokens = try filel.getTokensFromFile(alloc, path, ';');
    defer stringl.freeArrayList_string(alloc, &tokens);
    for (0..tokens.items.len) |j| {
        var s = tokens.items[j];
        if (s.containsE("[", .ignoreCase)) {
            modifyHeuristicWeight_array(alloc, &s, debug) catch {
                continue;
            };
        } else {
            modifyHeuristicWeight_number(alloc, &s, debug);
        }
    }
}
pub fn modifyHeuristicWeight_array(alloc: std.mem.Allocator, s: *string, debug: bool) !void {
    const valuesStr: []const u8 = s.extractFromBounds("[", "]") catch {
        return;
    };

    var tmp = try string.initFromSlice(alloc, valuesStr);
    defer tmp.free(alloc);

    var values = try tmp.split(alloc, ',');
    defer values.deinit(alloc);
    if (values.items.len != chess.N_SQUARES) {
        return;
    }
    var buffer: [chess.N_SQUARES]scoreType = undefined;
    for (0..chess.N_SQUARES) |i| {
        buffer[i] = std.fmt.parseInt(scoreType, utilsl.stripStr(values.items[i]), 10) catch {
            std.debug.print("[ERROR] modifyHeuristicWeight: invalid conversion continuing ({s}) {s}\n", .{ utilsl.stripStr(values.items[i]), values.items[i] });
            continue;
        };
    }
    if (debug) {
        std.debug.print("[DEBUG] modifyHeuristicWeight: modifying buffer with following values: \n[", .{});
        for (0..chess.N_SQUARES - 1) |i| {
            const val: scoreType = buffer[i];
            std.debug.print("{d}, ", .{val});
        }
        std.debug.print("{d}]\n", .{buffer[chess.N_SQUARES - 1]});
    }
    var dest: *[N_PHASES][chess.N_SQUARES]scoreType = undefined;
    if (s.containsE("pawn", .ignoreCase)) {
        dest = &weightl.global_Pawn_PSQT;
    } else if (s.containsE("knight", .ignoreCase)) {
        dest = &weightl.global_Knight_PSQT;
    } else if (s.containsE("bishop", .ignoreCase)) {
        dest = &weightl.global_Bishop_PSQT;
    } else if (s.containsE("rook", .ignoreCase)) {
        dest = &weightl.global_Rook_PSQT;
    } else if (s.containsE("queen", .ignoreCase)) {
        dest = &weightl.global_Queen_PSQT;
    } else if (s.containsE("king", .ignoreCase)) {
        dest = &weightl.global_King_PSQT;
    } else {
        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: unknown token \n[", .{});
        }
        return;
    }
    if (s.containsE("_MG", .ignoreCase)) {
        dest.*[MG] = buffer;
        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: successfully set MG\n", .{});
        }
    } else if (s.containsE("_EG", .ignoreCase)) {
        dest.*[EG] = buffer;

        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: successfully set EG\n", .{});
        }
    } else {
        dest.* = .{ buffer, buffer };
        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: successfully set both\n", .{});
        }
    }
}
pub fn modifyHeuristicWeight_number(alloc: std.mem.Allocator, s: *string, debug: bool) void {
    const equalIdx = s.findE('=') catch {
        std.debug.print("[ERROR] modifyHeuristicWeight: could not find = from '{s}'\n", .{s._slice()});
        return;
    };
    const valuesStr = s._slice()[(equalIdx + 1)..];
    _ = alloc;

    const val = std.fmt.parseFloat(f32, utilsl.stripStr(valuesStr)) catch |err| {
        std.debug.print("[ERROR] modifyHeuristicWeight {}: invalid conversion continuing ({s}){any} ({s}){any}\n", .{ err, utilsl.stripStr(valuesStr), utilsl.stripStr(valuesStr), valuesStr, valuesStr });
        return;
    };
    const _val: scoreType = @intFromFloat(val);

    if (debug) {
        std.debug.print("[DEBUG] modifyHeuristicWeight: modifying buffer with following value {d} \n[", .{_val});
    }

    var dest: *[N_PHASES]scoreType = undefined;
    if (s.containsE("isolatedPawn", .ignoreCase)) {
        dest = &weightl.global_IsolatedPawnValue;
    } else if (s.containsE("mobilityScore", .ignoreCase)) {
        dest = &weightl.global_MobilityValue;
    } else if (s.containsE("mobilityKingScore", .ignoreCase)) {
        dest = &weightl.global_KingMobilityValue;
    } else if (s.containsE("stackedPawn", .ignoreCase)) {
        dest = &weightl.global_StackedPawnValue;
    } else if (s.containsE("passedPawn", .ignoreCase)) {
        dest = &weightl.global_PassedPawnValue;
    } else if (s.containsE("tempoChecksScore", .ignoreCase)) {
        dest = &weightl.global_tempoChecksScore;
    } else if (s.containsE("pieceThreatScore", .ignoreCase)) {
        dest = &weightl.global_pieceThreatScore;
    } else if (s.containsE("safetyKnight", .ignoreCase)) {
        dest = &weightl.global_SafetyKnightValue;
    } else if (s.containsE("safetyBishop", .ignoreCase)) {
        dest = &weightl.global_SafetyBishopValue;
    } else if (s.containsE("safetyRook", .ignoreCase)) {
        dest = &weightl.global_SafetyRookValue;
    } else if (s.containsE("safetyQueen", .ignoreCase)) {
        dest = &weightl.global_SafetyQueenValue;
    } else if (s.containsE("structureProtection", .ignoreCase)) {
        dest = &weightl.global_StructureProtectionValue;
    } else if (s.containsE("centerProtection", .ignoreCase)) {
        dest = &weightl.global_centerProtectionValue;
    } else if (s.containsE("kingProximity", .ignoreCase)) {
        dest = &weightl.global_KingProximityValue;
    } else {
        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: unknown token {s}\n", .{s._slice()});
        }
        return;
    }
    if (s.containsE("_MG", .ignoreCase)) {
        dest.*[MG] = _val;
        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: successfully set MG\n", .{});
        }
    } else if (s.containsE("_EG", .ignoreCase)) {
        dest.*[EG] = _val;
        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: successfully set EG\n", .{});
        }
    } else {
        dest.* = .{ _val, _val };
        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: successfully set both\n", .{});
        }
    }
}

pub const heuristicValues = struct {
    // container storing every heuristics/ weights to evaluate a given board
    PawnValue: scoreType = weightl.simplePawnScore,
    BishopValue: scoreType = weightl.simpleBishopScore,
    KnightValue: scoreType = weightl.simpleKnightScore,
    RookValue: scoreType = weightl.simpleRookScore,
    QueenValue: scoreType = weightl.simpleQueenScore,

    MobilityValue: [N_PHASES]scoreType = .{ weightl.simpleMobilityScore, weightl.simpleMobilityScore },
    KingMobilityValue: [N_PHASES]scoreType = .{ weightl.simpleKingMobilityScore, weightl.simpleKingMobilityScore },
    weakCheckmate: [N_PHASES]scoreType = .{ weightl.simpleWeakCheckMateScore, weightl.simpleWeakCheckMateScore },

    tempoChecksScore: [N_PHASES]scoreType = .{ weightl.simpleTempoChecksScore, weightl.simpleTempoChecksScore },
    pieceThreatScore: [N_PHASES]scoreType = .{ weightl.simplePieceThreatScore, weightl.simplePieceThreatScore },

    IsolatedPawnValue: [N_PHASES]scoreType = .{ weightl.simpleIsolatedPawnScore, weightl.simpleIsolatedPawnScore },
    StackedPawnValue: [N_PHASES]scoreType = .{ weightl.simpleStackedPawnScore, weightl.simpleStackedPawnScore },
    PassedPawnValue: [N_PHASES]scoreType = .{ weightl.simplePassedPawnScore, weightl.simplePassedPawnScore },

    SafetyBishopValue: [N_PHASES]scoreType = .{ weightl.simpleSafetyBishopScore, weightl.simpleSafetyBishopScore },
    SafetyKnightValue: [N_PHASES]scoreType = .{ weightl.simpleSafetyKnightScore, weightl.simpleSafetyKnightScore },
    SafetyRookValue: [N_PHASES]scoreType = .{ weightl.simpleSafetyRookScore, weightl.simpleSafetyRookScore },
    SafetyQueenValue: [N_PHASES]scoreType = .{ weightl.simpleSafetyQueenScore, weightl.simpleSafetyQueenScore },

    StructureProtectionValue: [N_PHASES]scoreType = .{ weightl.simpleStructureProtectionScore, weightl.simpleStructureProtectionScore },

    KingProximityValue: [N_PHASES]scoreType = .{ weightl.simpleKingProximity, weightl.simpleKingProximity },

    Pawn_PSQT: [N_PHASES][chess.N_SQUARES]scoreType = .{ weightl.pawnScoreArr, weightl.pawnScoreArr },
    Bishop_PSQT: [N_PHASES][chess.N_SQUARES]scoreType = .{ weightl.bishopScoreArr, weightl.bishopScoreArr },
    Knight_PSQT: [N_PHASES][chess.N_SQUARES]scoreType = .{ weightl.knightScoreArr, weightl.knightScoreArr },
    Rook_PSQT: [N_PHASES][chess.N_SQUARES]scoreType = .{ weightl.rookScoreArr, weightl.rookScoreArr },
    Queen_PSQT: [N_PHASES][chess.N_SQUARES]scoreType = .{ weightl.queenScoreArr, weightl.queenScoreArr },
    King_PSQT: [N_PHASES][chess.N_SQUARES]scoreType = .{ weightl.kingScoreArr, weightl.kingScoreArr_EG },

    pub inline fn getPieceCountValues(self: *const heuristicValues) [chess.N_PIECES]scoreType {
        return .{ self.PawnValue, self.BishopValue, self.KnightValue, self.RookValue, self.QueenValue, 0 };
    }
    // other more complex values may be inserted below
    pub fn getPieceInfos(self: *const heuristicValues, piece: e_piece, sq: typel.e_square) [3]typel.scoreType {
        switch (piece) {
            .nEmptySquare, .nWhite, .nBlack => {
                return .{ 0, 0, 0 };
            },
            .nWhitePawn => {
                return self.getPieceInfos_cst(.PAWN, @intFromEnum(sq));
            },
            .nBlackPawn => {
                return self.getPieceInfos_cst(.PAWN, @intFromEnum(chess.flipSq(sq)));
            },
            .nWhiteBishop => {
                return self.getPieceInfos_cst(.BISHOP, @intFromEnum(sq));
            },
            .nBlackBishop => {
                return self.getPieceInfos_cst(.BISHOP, @intFromEnum(chess.flipSq(sq)));
            },
            .nWhiteKnight => {
                return self.getPieceInfos_cst(.KNIGHT, @intFromEnum(sq));
            },
            .nBlackKnight => {
                return self.getPieceInfos_cst(.KNIGHT, @intFromEnum(chess.flipSq(sq)));
            },
            .nWhiteRook => {
                return self.getPieceInfos_cst(.ROOK, @intFromEnum(sq));
            },
            .nBlackRook => {
                return self.getPieceInfos_cst(.ROOK, @intFromEnum(chess.flipSq(sq)));
            },
            .nWhiteQueen => {
                return self.getPieceInfos_cst(.QUEEN, @intFromEnum(sq));
            },
            .nBlackQueen => {
                return self.getPieceInfos_cst(.QUEEN, @intFromEnum(chess.flipSq(sq)));
            },
            .nWhiteKing => {
                return self.getPieceInfos_cst(.KING, @intFromEnum(sq));
            },
            .nBlackKing => {
                return self.getPieceInfos_cst(.KING, @intFromEnum(chess.flipSq(sq)));
            },
        }
    }
    pub inline fn getPieceInfos_cst(self: *const heuristicValues, comptime piece: typel.e_pieceType, sq: u8) [3]typel.scoreType {
        switch (piece) {
            .PAWN => {
                return .{ self.PawnValue, self.Pawn_PSQT[MG][sq], self.Pawn_PSQT[EG][sq] };
            },
            .BISHOP => {
                return .{ self.BishopValue, self.Bishop_PSQT[MG][sq], self.Bishop_PSQT[EG][sq] };
            },
            .KNIGHT => {
                return .{ self.KnightValue, self.Knight_PSQT[MG][sq], self.Knight_PSQT[EG][sq] };
            },
            .ROOK => {
                return .{ self.RookValue, self.Rook_PSQT[MG][sq], self.Rook_PSQT[EG][sq] };
            },
            .QUEEN => {
                return .{ self.QueenValue, self.Queen_PSQT[MG][sq], self.Queen_PSQT[EG][sq] };
            },
            .KING => {
                return .{ 0, self.King_PSQT[MG][sq], self.King_PSQT[EG][sq] };
            },
        }
    }
    pub fn modifyGlobals(self: *const heuristicValues) void {
        weightl.global_PawnValue = self.PawnValue;
        weightl.global_BishopValue = self.BishopValue;
        weightl.global_KnightValue = self.KnightValue;
        weightl.global_RookValue = self.RookValue;
        weightl.global_QueenValue = self.QueenValue;

        weightl.global_MobilityValue = self.MobilityValue;
        weightl.global_KingMobilityValue = self.KingMobilityValue;
        weightl.global_weakCheckmate = self.weakCheckmate;

        weightl.global_tempoChecksScore = self.tempoChecksScore;
        weightl.global_pieceThreatScore = self.pieceThreatScore;

        weightl.global_IsolatedPawnValue = self.IsolatedPawnValue;
        weightl.global_StackedPawnValue = self.StackedPawnValue;
        weightl.global_PassedPawnValue = self.PassedPawnValue;

        weightl.global_SafetyBishopValue = self.SafetyBishopValue;
        weightl.global_SafetyKnightValue = self.SafetyKnightValue;
        weightl.global_SafetyRookValue = self.SafetyRookValue;
        weightl.global_SafetyQueenValue = self.SafetyQueenValue;

        weightl.global_StructureProtectionValue = self.StructureProtectionValue;

        weightl.global_KingProximityValue = self.KingProximityValue;

        weightl.global_Pawn_PSQT = self.Pawn_PSQT;
        weightl.global_Bishop_PSQT = self.Bishop_PSQT;
        weightl.global_Knight_PSQT = self.Knight_PSQT;
        weightl.global_Rook_PSQT = self.Rook_PSQT;
        weightl.global_Queen_PSQT = self.Queen_PSQT;
        weightl.global_King_PSQT = self.King_PSQT;
    }
};

pub inline fn getPieceCountValues() [chess.N_PIECES]scoreType {
    return .{ weightl.global_PawnValue, weightl.global_BishopValue, weightl.global_KnightValue, weightl.global_RookValue, weightl.global_QueenValue, 0 };
}
// other more complex values may be inserted below
pub fn getPieceInfos(piece: e_piece, sq: typel.e_square) [3]typel.scoreType {
    switch (piece) {
        .nEmptySquare, .nWhite, .nBlack => {
            return .{ 0, 0, 0 };
        },
        .nWhitePawn => {
            return getPieceInfos_cst(.PAWN, @intFromEnum(sq));
        },
        .nBlackPawn => {
            return getPieceInfos_cst(.PAWN, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteBishop => {
            return getPieceInfos_cst(.BISHOP, @intFromEnum(sq));
        },
        .nBlackBishop => {
            return getPieceInfos_cst(.BISHOP, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteKnight => {
            return getPieceInfos_cst(.KNIGHT, @intFromEnum(sq));
        },
        .nBlackKnight => {
            return getPieceInfos_cst(.KNIGHT, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteRook => {
            return getPieceInfos_cst(.ROOK, @intFromEnum(sq));
        },
        .nBlackRook => {
            return getPieceInfos_cst(.ROOK, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteQueen => {
            return getPieceInfos_cst(.QUEEN, @intFromEnum(sq));
        },
        .nBlackQueen => {
            return getPieceInfos_cst(.QUEEN, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteKing => {
            return getPieceInfos_cst(.KING, @intFromEnum(sq));
        },
        .nBlackKing => {
            return getPieceInfos_cst(.KING, chess.flipSq(@intFromEnum(sq)));
        },
    }
}
pub inline fn getPieceInfos_cst(comptime piece: typel.e_pieceType, sq: u8) [3]typel.scoreType {
    switch (piece) {
        .PAWN => {
            return .{ weightl.global_PawnValue, weightl.global_Pawn_PSQT[MG][sq], weightl.global_Pawn_PSQT[EG][sq] };
        },
        .BISHOP => {
            return .{ weightl.global_BishopValue, weightl.global_Bishop_PSQT[MG][sq], weightl.global_Bishop_PSQT[EG][sq] };
        },
        .KNIGHT => {
            return .{ weightl.global_KnightValue, weightl.global_Knight_PSQT[MG][sq], weightl.global_Knight_PSQT[EG][sq] };
        },
        .ROOK => {
            return .{ weightl.global_RookValue, weightl.global_Rook_PSQT[MG][sq], weightl.global_Rook_PSQT[EG][sq] };
        },
        .QUEEN => {
            return .{ weightl.global_QueenValue, weightl.global_Queen_PSQT[MG][sq], weightl.global_Queen_PSQT[EG][sq] };
        },
        .KING => {
            return .{ 0, weightl.global_King_PSQT[MG][sq], weightl.global_King_PSQT[EG][sq] };
        },
    }
}

// source: https://www.chessprogramming.org/King_Safety
const SAFETY_ARR: [8]scoreType = [8]scoreType{ 0, 0, 50, 75, 88, 94, 97, 99 };

const N_PHASES: usize = 2;
const N_WEIGHTS: usize = 256;
const NTERMS: usize = 1024;

pub const MG: usize = 0;
pub const EG: usize = 1;

pub fn computePhase(p_board: *const boardl.boardState) scoreType {
    const phase: i32 = 24 - 4 * (p_board.getPieceCount(.nWhiteQueen) + p_board.getPieceCount(.nBlackQueen)) - 2 * (p_board.getPieceCount(.nWhiteRook) + p_board.getPieceCount(.nBlackRook)) - (p_board.getPieceCount(.nWhiteBishop) + p_board.getPieceCount(.nBlackBishop)) - (p_board.getPieceCount(.nWhiteKnight) + p_board.getPieceCount(.nBlackKnight));
    const _phase: scoreType = @intCast(phase);
    return @divFloor(256 * (24 - _phase) + 12, 24);
}
pub fn isBoardTexelValid(p_board: *boardl.boardState) bool {
    //https://github.com/maksimKorzh/wukongJS/blob/main/docs/TEXEL'S_TUNING.MD
    const fmoves = moveGenl.generateLegalMoves(p_board);
    if (fmoves.len == 0) {
        return false;
    }

    const color_mask: scoreType = if (p_board.whiteToMove()) 1 else -1;
    const stat = color_mask * evaluate(p_board);
    var info: threadingl.threadInfo = .{ .alive = true, .working = true };

    const alpha: scoreType = -weightl.simpleCheckMateScore;
    const beta: scoreType = weightl.simpleCheckMateScore;
    var ss: alphaBetal.searchStack = .{};
    const isChecked = p_board.isChecked();
    if (isChecked) return false;
    const quiesc = alphaBetal.quiescenceSearch(p_board, &info, undefined, configl.MAX_QUIESC_DEPTH + 2, alpha, beta, 1, isChecked, false, &ss, .NonPV);
    if (stat != quiesc) {
        return false;
    }
    return true;
}
pub const texelEntry = struct {
    //
    //seval: i32 = 0,
    // phase value describing how far the game progressed
    phase: scoreType = 0.0,
    // turn of the extracted fen
    turn: bool = true,

    eval: i32 = 0,
    // 0.0 black win, 0.5 draw, 1.0 white win
    result: f32 = -1,
    //

    // coeffs provided by the board reading the fen
    // C vects from the eq with L the weight
    // E = L . (Cw - Cb)
    tuples: coeffVector = .{},
    valid: bool = true,
    pub fn initFromBoard(p_state: *boardl.boardState) texelEntry {
        var ret: texelEntry = .{};
        ret.phase = computePhase(p_state);
        ret.turn = p_state.whiteToMove();
        try getCoeffsFromBoard(p_state, &ret.tuples);
        return ret;
    }
    pub fn initFromBoardFast(p_state: *boardl.boardState) texelEntry {
        var ret: texelEntry = .{};
        ret.phase = computePhase(p_state);
        return ret;
    }

    pub fn set_fen(p_self: *texelEntry, alloc: std.mem.Allocator, fen: []const u8, result: f32) !void {
        p_self.tuples = .{};
        p_self.result = result;
        var board = chess.getBoardFromFen(fen) catch {
            std.debug.print("[ERROR] set_fen: error while using the fen: '{s}'\n", .{fen});
            @panic("");
        };
        defer board.free(alloc);
        p_self.phase = (board.getPhase());
        p_self.turn = board.whiteToMove();
        p_self.valid = isBoardTexelValid(&board);
        if (!p_self.valid) {
            return texel_err.board_err;
        }
        try getCoeffsFromBoard(&board, &p_self.tuples);
    }
    pub fn print(p_self: *texelEntry) void {
        //
        std.debug.print("Printing texelEntry: \n", .{});
        std.debug.print("Res: {d}\n", .{p_self.result});
        //std.debug.print("Res: {d}, seval: {d}\n", .{ p_self.result, p_self.seval });
        std.debug.print("Coefficients array: ", .{});
        p_self.tuples.print();
    }
};

pub fn getCoeffsFromBoard(p_state: *boardl.boardState, p_out: *coeffVector) !void {
    // Normal:
    var idx: usize = 0;
    if (configl.TUNE_NORMAL) {
        // piece counts
        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhitePawn)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackPawn)) });
        std.debug.assert(idx == configl.TEXEL_PAWN_COUNT_IDX);
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhiteBishop)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackBishop)) });
        std.debug.assert(idx == configl.TEXEL_BISHOP_COUNT_IDX);
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhiteKnight)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackKnight)) });
        std.debug.assert(idx == configl.TEXEL_KNIGHT_COUNT_IDX);
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhiteRook)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackRook)) });
        std.debug.assert(idx == configl.TEXEL_ROOK_COUNT_IDX);
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhiteQueen)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackQueen)) });
        std.debug.assert(idx == configl.TEXEL_QUEEN_COUNT_IDX);
        idx += 1;

        const allwhiteMoveBB = moveGenl._cst_moveGenBB_all(p_state, true);
        const allblackMoveBB = moveGenl._cst_moveGenBB_all(p_state, false);
        //const whiteMoveBB = allwhiteMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromBool(true)]);
        //const blackMoveBB = allblackMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromBool(false)]);
        // mobility
        const moveW: scoreType = @intCast(allwhiteMoveBB.count());
        const moveB: scoreType = @intCast(allblackMoveBB.count());

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = moveW, .bcoeff = moveB });
        std.debug.assert(idx == configl.TEXEL_MOVE_COUNT_IDX);
        idx += 1;

        const bAttacks = (allblackMoveBB.getAttackedMask(chess.UNIVERSE));
        const wAttacks = (allwhiteMoveBB.getAttackedMask(chess.UNIVERSE));
        //const kingMoveW = allwhiteMoveBB.kingMoves & (~allblackMoveBB.getAttackedMask(chess.UNIVERSE));
        //const kingMoveB = allblackMoveBB.kingMoves & (~allwhiteMoveBB.getAttackedMask(chess.UNIVERSE));
        const kingMoveW = allwhiteMoveBB.kingMoves & (~bAttacks) & ~p_state.b.c_occupiedBB[@intFromBool(true)];
        const kingMoveB = allblackMoveBB.kingMoves & (~wAttacks) & ~p_state.b.c_occupiedBB[@intFromBool(false)];

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.popcount(kingMoveW)), .bcoeff = @intCast(chess.popcount(kingMoveB)) });
        std.debug.assert(idx == configl.TEXEL_KINGMOVE_COUNT_IDX);
        idx += 1;

        // structure protection
        const w_pieceProtect = allwhiteMoveBB.andFn(p_state.b.c_occupiedBB[@intFromBool(true)] ^ chess.sqToBitboard(p_state.b.wKingSq));
        const b_pieceProtect = allblackMoveBB.andFn(p_state.b.c_occupiedBB[@intFromBool(false)] ^ chess.sqToBitboard(p_state.b.bKingSq));

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(w_pieceProtect.count()), .bcoeff = @intCast(b_pieceProtect.count()) });
        std.debug.assert(idx == configl.TEXEL_PROTECTION_COUNT_IDX);
        idx += 1;

        // pawn structure
        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.ipopcount(chess.isolatedPawns(p_state.getPieceBB(e_piece.nWhitePawn)))), .bcoeff = @intCast(chess.ipopcount(chess.isolatedPawns(p_state.getPieceBB(e_piece.nBlackPawn)))) });
        std.debug.assert(idx == configl.TEXEL_PAWN_ISOL_IDX);
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.ipopcount(chess.stackedPawns(p_state.getPieceBB(e_piece.nWhitePawn)))), .bcoeff = @intCast(chess.ipopcount(chess.stackedPawns(p_state.getPieceBB(e_piece.nBlackPawn)))) });
        std.debug.assert(idx == configl.TEXEL_PAWN_STACKED_IDX);
        idx += 1;

        const wp = p_state.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] & p_state.b.c_occupiedBB[1];
        const bp = p_state.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] & p_state.b.c_occupiedBB[0];
        const nWhitePassed: i8 = @intCast(chess.popcount(chess.passedPawns(wp, bp)));
        const nBlackPassed: i8 = @intCast(chess.popcount(chess.passedPawns(bp, wp)));

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(nWhitePassed), .bcoeff = @intCast(nBlackPassed) });
        std.debug.assert(idx == configl.TEXEL_PAWN_PASSED_IDX);
        idx += 1;

        // tempo
        if (p_state.whiteToMove()) {
            p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = 0, .bcoeff = @intCast(@intFromBool(p_state.isChecked())) });
        } else {
            p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(@intFromBool(p_state.isChecked())), .bcoeff = 0 });
        }
        std.debug.assert(idx == configl.TEXEL_TEMPO_CHECKS_IDX);
        idx += 1;
    }
    if (comptime (configl.TUNE_SAFETY)) {
        const maskW = chess.safetyArea(p_state.b.wKingSq);
        const maskB = chess.safetyArea(p_state.b.bKingSq);

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackPawn))), .bcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhitePawn))) });
        std.debug.assert(idx == configl.TEXEL_SAFETY_PAWN_PROX_IDX);
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackBishop))), .bcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhiteBishop))) });
        std.debug.assert(idx == configl.TEXEL_SAFETY_BISHOP_PROX_IDX);
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackKnight))), .bcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhiteKnight))) });
        std.debug.assert(idx == configl.TEXEL_SAFETY_KNIGHT_PROX_IDX);
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackRook))), .bcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhiteRook))) });
        std.debug.assert(idx == configl.TEXEL_SAFETY_ROOK_PROX_IDX);
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackQueen))), .bcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhiteQueen))) });
        std.debug.assert(idx == configl.TEXEL_SAFETY_QUEEN_PROX_IDX);
        idx += 1;

        const wKing = squarel.squareInfo.init(p_state.b.wKingSq);
        const bKing = squarel.squareInfo.init(p_state.b.bKingSq);
        const distance: scoreType = squarel.maxBenDistance - @as(scoreType, @intCast(wKing.computeMHDistance(bKing)));

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = distance, .bcoeff = distance });
        std.debug.assert(idx == configl.TEXEL_KING_PROXIMITY_IDX);
        idx += 1;
    }

    if (configl.TUNE_COMPLEXITY) {}
    if (comptime (configl.TUNE_PSQT)) {
        // piece psqt
        std.debug.assert(idx == configl.TEXEL_PAWN_PSQT_IDX);
        p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhitePawn)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackPawn))), &idx);

        std.debug.assert(idx == configl.TEXEL_BISHOP_PSQT_IDX);
        p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteBishop)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackBishop))), &idx);

        std.debug.assert(idx == configl.TEXEL_KNIGHT_PSQT_IDX);
        p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteKnight)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackKnight))), &idx);

        std.debug.assert(idx == configl.TEXEL_ROOK_PSQT_IDX);
        p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteRook)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackRook))), &idx);

        std.debug.assert(idx == configl.TEXEL_QUEEN_PSQT_IDX);
        p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteQueen)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackQueen))), &idx);

        std.debug.assert(idx == configl.TEXEL_KING_PSQT_IDX);
        p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteKing)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackKing))), &idx);
    }
    return;
}

pub const NVector = struct {
    val: [configl.N_TERMS]scoreType = std.mem.zeroes([configl.N_TERMS]scoreType),
    pub fn copy(p_self: NVector) NVector {
        var ret: NVector = .{};
        @memcpy(&ret.val, &p_self.val);
        return ret;
    }
    pub fn format(self: NVector, writer: *std.Io.Writer) !void {
        // fmt idea { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }
        //try writer.print("{{", .{});
        for (0..self.val.len) |i| {
            if (i != (self.val.len - 1)) {
                try writer.print(" {d},", .{self.val[i]});
            } else {
                try writer.print(" {d}", .{self.val[i]});
            }
        }
        //try writer.writeAll(" }");
        return;
    }
    pub fn dotProduct(p_self: *const NVector, p_other: *const NVector) scoreType {
        var acc: scoreType = 0;
        for (p_self.val, p_other.val) |x1, x2| {
            acc += x1 * x2;
        }
        return acc;
    }
    pub fn substractVectEq(p_self: *NVector, p_other: *const NVector) void {
        for (0..p_self.val.len) |i| {
            p_self.val[i] -= p_other.val[i];
        }
    }
    pub fn substractVect(p_self: *const NVector, p_other: *const NVector) NVector {
        var ret: NVector = .{};
        for (0..p_self.val.len) |i| {
            ret.val[i] = p_self.val[i] - p_other.val[i];
        }
        return ret;
    }
    pub fn addVectEq(p_self: *NVector, p_other: *const NVector) void {
        for (0..p_self.val.len) |i| {
            p_self.val[i] += p_other.val[i];
        }
    }
    pub fn addVect(p_self: *const NVector, p_other: *const NVector) NVector {
        var ret: NVector = .{};
        for (0..p_self.val.len) |i| {
            ret.val[i] = p_self.val[i] + p_other.val[i];
        }
        return ret;
    }
    pub fn substract(p_self: *const NVector, val: scoreType) NVector {
        var ret: NVector = .{};
        for (0..p_self.val.len) |i| {
            ret.val[i] = p_self.val[i] - val;
        }
        return ret;
    }
    pub fn addEq(p_self: *NVector, val: scoreType) void {
        for (0..p_self.val.len) |i| {
            p_self.val[i] += val;
        }
    }
    pub fn add(p_self: *const NVector, val: scoreType) NVector {
        var ret: NVector = .{};
        for (0..p_self.val.len) |i| {
            ret.val[i] = p_self.val[i] + val;
        }
        return ret;
    }
    pub fn multiplyEq(p_self: *NVector, val: scoreType) void {
        for (0..p_self.val.len) |i| {
            p_self.val[i] *= val;
        }
    }
    pub fn multiply(p_self: *const NVector, val: scoreType) NVector {
        var ret: NVector = .{};
        for (0..p_self.val.len) |i| {
            ret.val[i] = p_self.val[i] * val;
        }
        return ret;
    }
    pub fn divide(p_self: *const NVector, val: scoreType) NVector {
        std.debug.assert(val != 0);
        var ret: NVector = .{};
        for (0..p_self.val.len) |i| {
            ret.val[i] = p_self.val[i] / val;
        }
        return ret;
    }
    pub fn print(p_self: *NVector) void {
        std.debug.print("( ", .{});
        for (0..p_self.val.len) |i| {
            std.debug.print(" {d} ", .{p_self.val[i]});
        }
        std.debug.print(")\n", .{});
    }
};

pub const coeffTuple = struct {
    val: [N_PHASES]NVector = std.mem.zeroes([N_PHASES]NVector),
    pub fn init(seed: u64, usePastPSQT: bool) coeffTuple {
        var rngIntGenerator = std.Random.DefaultPrng.init(seed);
        const randGen = rngIntGenerator.random();
        var ret: coeffTuple = .{};
        for (0..N_PHASES) |p| {
            for (0..NTERMS) |i| {
                const r: scoreType = @intCast(randGen.intRangeAtMost(i64, configl.WEIGHT_MIN, configl.WEIGHT_MAX));
                ret.val[p].val[i] = r;
            }
        }
        if (usePastPSQT) {
            ret.load_prev();
        }
        return ret;
    }
    pub fn load_prev(p_self: *coeffTuple) void {
        std.debug.print("[DEBUG] load_prev: Loading previous PSQT values\n", .{});
        for (0..chess.N_SQUARES) |sq| {
            p_self.val[MG].val[configl.TEXEL_PAWN_PSQT_IDX + sq] = weightl.pawnScoreArr[sq];
            p_self.val[EG].val[configl.TEXEL_PAWN_PSQT_IDX + sq] = weightl.pawnScoreArr[sq];

            p_self.val[MG].val[configl.TEXEL_BISHOP_PSQT_IDX + sq] = weightl.bishopScoreArr[sq];
            p_self.val[EG].val[configl.TEXEL_BISHOP_PSQT_IDX + sq] = weightl.bishopScoreArr[sq];

            p_self.val[MG].val[configl.TEXEL_KNIGHT_PSQT_IDX + sq] = weightl.knightScoreArr[sq];
            p_self.val[EG].val[configl.TEXEL_KNIGHT_PSQT_IDX + sq] = weightl.knightScoreArr[sq];

            p_self.val[MG].val[configl.TEXEL_ROOK_PSQT_IDX + sq] = weightl.rookScoreArr[sq];
            p_self.val[EG].val[configl.TEXEL_ROOK_PSQT_IDX + sq] = weightl.rookScoreArr[sq];

            p_self.val[MG].val[configl.TEXEL_QUEEN_PSQT_IDX + sq] = weightl.queenScoreArr[sq];
            p_self.val[EG].val[configl.TEXEL_QUEEN_PSQT_IDX + sq] = weightl.queenScoreArr[sq];

            p_self.val[MG].val[configl.TEXEL_KING_PSQT_IDX + sq] = weightl.kingScoreArr[sq];
            p_self.val[EG].val[configl.TEXEL_KING_PSQT_IDX + sq] = weightl.kingScoreArr[sq];
        }
    }
    pub fn print(p_self: *const coeffTuple) void {
        for (0..NTERMS) |i| {
            std.debug.print("(MG: {d}, EG: {d})\n", .{ p_self.val[MG].val[i], p_self.val[EG].val[i] });
        }
    }
    pub fn copy(p_self: *const coeffTuple) coeffTuple {
        var ret: coeffTuple = .{};
        @memcpy(&ret.val[MG].val, &p_self.val[MG].val);
        @memcpy(&ret.val[EG].val, &p_self.val[EG].val);
        return ret;
    }
    pub fn saveToFile(p_self: *const coeffTuple, alloc: std.mem.Allocator, path: []const u8) !void {
        const mg_str = try std.fmt.allocPrint(alloc, "mg: {f}\n", .{p_self.val[MG]});
        defer alloc.free(mg_str);

        const eg_str = try std.fmt.allocPrint(alloc, "eg: {f}\n", .{p_self.val[EG]});
        defer alloc.free(eg_str);

        const file = try std.fs.cwd().createFile(path, .{ .read = true });
        defer file.close(mainl.getGlobalIo());
        _ = try file.write(mg_str);
        _ = try file.write(eg_str);
    }
};

pub const coeffs = struct {
    index: i32 = -1,
    wcoeff: scoreType = 0,
    bcoeff: scoreType = 0,
};

pub const coeffVector = struct {
    items: [chess.NUMBER_PLAYER]NVector = std.mem.zeroes([chess.NUMBER_PLAYER]NVector),
    len: usize = 0,
    capacity: usize = configl.N_TERMS,
    pub fn init(alloc: std.mem.Allocator, totalSize: usize) !coeffVector {
        var ret: coeffVector = undefined;
        ret.len = 0;
        ret.capacity = totalSize;
        ret.items = {};
        _ = alloc;
        return ret;
    }
    pub fn appendCoeff(p_self: *coeffVector, item: coeffs) void {
        std.debug.assert(p_self.len < p_self.capacity);
        p_self.items[@intFromEnum(e_turn.WHITE)].val[p_self.len] = item.wcoeff;
        p_self.items[@intFromEnum(e_turn.BLACK)].val[p_self.len] = item.bcoeff;
        p_self.len += 1;
    }

    pub fn add1DCoeff(p_self: *coeffVector, w: []const scoreType, b: []const scoreType, idx: *usize) void {
        std.debug.assert(w.len == b.len);
        for (0..w.len) |i| {
            const item: coeffs = .{ .index = @intCast(idx.*), .wcoeff = w[i], .bcoeff = b[i] };
            p_self.appendCoeff(item);
            idx.* += 1;
        }
    }
    pub fn print(p_self: *coeffVector) void {
        std.debug.print("\n", .{});
        for (0..p_self.len) |i| {
            const tuple = p_self.items[i];
            std.debug.print("(w: {d}, b: {d})\n", .{ tuple.wcoeff, tuple.bcoeff });
        }
    }
};

pub fn getEntriesFromFile(alloc: std.mem.Allocator, path: string, nSkips: usize) ![]texelEntry {
    var tokens = try filel.getTokensFromFileAlloc(alloc, path._slice(), '\n', configl.N_POSITIONS, nSkips);
    var entries: []texelEntry = try alloc.alloc(texelEntry, configl.N_POSITIONS);

    for (0..tokens.items.len) |i| {
        var s = tokens.items[i];
        var tok = try s.split(alloc, ' ');
        defer tok.deinit(alloc);
        //const fen = tok.items[0];
        //const outcome = tok.items[1];
        const outcome = try s.extractFromBounds("[", "]");
        var foutcome: f32 = 0;
        if (utilsl.contains(outcome, "0.5", .ignoreCase)) {
            foutcome = 0.5;
        } else if (utilsl.contains(outcome, "1.0", .ignoreCase)) {
            foutcome = 1;
        }
        entries[i].set_fen(alloc, s._slice(), foutcome) catch {
            continue;
        };
    }
    defer stringl.freeArrayList_string(alloc, &tokens);
    return entries;
}

pub const csvHeader = struct {
    n_params: usize,
    pub fn format(self: csvHeader, writer: *std.Io.Writer) !void {
        for (0..self.n_params) |i| {
            try writer.print("Delta_{d},", .{i});
        }

        try writer.print("Phase,Outcome", .{});
    }
};
pub const csvBody = struct {
    entry: *texelEntry = undefined,
    pub fn format(self: csvBody, writer: *std.Io.Writer) !void {
        const tuple = self.entry.tuples;
        for (0..tuple.len) |i| {
            try writer.print("{d},", .{tuple.items[@intFromEnum(e_turn.WHITE)].val[i] - tuple.items[@intFromEnum(e_turn.BLACK)].val[i]});
        }

        try writer.print("{d},{d}", .{ self.entry.phase, self.entry.result });
    }
};
pub fn createEmptyFile(alloc: std.mem.Allocator, path: string) !void {
    // format
    // Coeff_1_w, Coeff_1_b, ...., Coeff_n_w, Coeff_n_b, phase, outcome)
    // <--comma separated values--->
    //const file = try std.fs.cwd().createFile(path._slice(), .{ .read = true });
    const file = try std.Io.Dir.createFile(.cwd(), mainl.getGlobalIo(), path._slice(), .{ .read = true });
    defer file.close(mainl.getGlobalIo());

    // save header
    const headerTemplate: csvHeader = .{ .n_params = configl.N_TERMS };

    const header_str = try std.fmt.allocPrint(alloc, "{f}\n", .{headerTemplate});
    defer alloc.free(header_str);
    _ = file.writeStreamingAll(mainl.getGlobalIo(), header_str) catch unreachable;
}
pub fn saveCoefficientToFile(alloc: std.mem.Allocator, entries: []texelEntry, path: string) !void {
    // <--comma separated values--->
    //const file = try std.fs.cwd().openFile(path._slice(), .{ .mode = .write_only });
    const file = try std.Io.Dir.openFile(.cwd(), mainl.getGlobalIo(), path._slice(), .{ .mode = .write_only });
    defer file.close(mainl.getGlobalIo());

    const print_freq: usize = 10000;
    for (0..entries.len) |i| {
        if (i % print_freq == 0) {
            std.debug.print("{d} / {d} \r", .{ i, entries.len });
        }
        if (!entries[i].valid) {
            continue;
        }
        const body: csvBody = .{ .entry = &entries[i] };
        const body_str = try std.fmt.allocPrint(alloc, "{f}\n", .{body});
        defer alloc.free(body_str);
        //_ = file.writerStreaming(mainl.getGlobalIo(), body_str);
        _ = file.writePositionalAll(mainl.getGlobalIo(), body_str[0..body_str.len], file.length(mainl.getGlobalIo()) catch unreachable) catch unreachable;
    }
}

pub fn printEntriesInfo(entries: []const texelEntry) void {
    var buffer: [3]usize = .{ 0, 0, 0 };
    var validBuffer: [2]usize = .{ 0, 0 };
    for (0..entries.len) |i| {
        buffer[@intFromFloat(entries[i].result * 2)] += 1;
        validBuffer[@intFromBool(entries[i].valid)] += 1;
    }
    std.debug.print("[DEBUG] printEntriesInfo: Breakdown of entries found 0: {d}, 0.5: {d}, 1: {d}\n valid: {d} non valid: {d}\n\n", .{ buffer[0], buffer[1], buffer[2], validBuffer[1], validBuffer[0] });
}

pub fn test_save(alloc: std.mem.Allocator, dataPath: string, savePath: string) !void {
    //
    const allEntries = try filel.getFileLineSize(alloc, dataPath._slice());
    var remainingEntries = allEntries;
    std.debug.print("[DEBUG] test_save: number of lines found: {d}\n", .{allEntries});

    try createEmptyFile(alloc, savePath);
    var skips: usize = 0;
    while (remainingEntries != 0) {
        std.debug.print("Remaining entries: {d} \n", .{remainingEntries});
        remainingEntries = remainingEntries -| configl.N_POSITIONS;
        const entries = try getEntriesFromFile(alloc, dataPath, skips);

        printEntriesInfo(entries);
        defer alloc.free(entries);
        try saveCoefficientToFile(alloc, entries, savePath);
        skips += configl.N_POSITIONS;
    }
}
//https://www.talkchess.com/forum3/viewtopic.php?f=7&t=74403
// test for first futility implem
pub const futilityMargin: [4]scoreType = .{ 0, 200, 300, 500 };
pub const probCutMoveCount: [6]scoreType = .{ 8, 10, 14, 20, 20, 40 };
//pub const futilityMargin: scoreType = 400;
pub const dFutilityMargin: scoreType = 300;

// move heuristic "sections"
// https://github.com/maksimKorzh/chess_programming MVA_lva table
pub const mvv_lva: [12][12]scoreType = .{ .{ 105, 205, 305, 405, 505, 605, 105, 205, 305, 405, 505, 605 }, .{ 104, 204, 304, 404, 504, 604, 104, 204, 304, 404, 504, 604 }, .{ 103, 203, 303, 403, 503, 603, 103, 203, 303, 403, 503, 603 }, .{ 102, 202, 302, 402, 502, 602, 102, 202, 302, 402, 502, 602 }, .{ 101, 201, 301, 401, 501, 601, 101, 201, 301, 401, 501, 601 }, .{ 100, 200, 300, 400, 500, 600, 100, 200, 300, 400, 500, 600 }, .{ 105, 205, 305, 405, 505, 605, 105, 205, 305, 405, 505, 605 }, .{ 104, 204, 304, 404, 504, 604, 104, 204, 304, 404, 504, 604 }, .{ 103, 203, 303, 403, 503, 603, 103, 203, 303, 403, 503, 603 }, .{ 102, 202, 302, 402, 502, 602, 102, 202, 302, 402, 502, 602 }, .{ 101, 201, 301, 401, 501, 601, 101, 201, 301, 401, 501, 601 }, .{ 100, 200, 300, 400, 500, 600, 100, 200, 300, 400, 500, 600 } };

pub fn eval_move_heuristic_line(p_state: *const boardl.boardState, move: IMove, ply: u16, hashMove: IMove, prevLineMove: IMove, comptime mva: bool, white: bool) scoreType {
    if (move.equal(hashMove)) {
        return configl.ORDERING_LINE_VALUE + 1;
    }
    if (move.equal(prevLineMove)) {
        // previous best move at that ply
        return configl.ORDERING_LINE_VALUE;
    }
    const fpiece = p_state.getFromPiece(move);
    const from = move.getFrom();
    const to = move.getTo();

    if (move.isCapture()) {
        const cPiece: e_piece = if (move.isEnpassant()) (e_piece.nWhitePawn) else (p_state.getPiece(to));
        // done for pseudo legal move stuff
        if (chess.isKingPiece(cPiece)) {
            return configl.ORDERING_LINE_VALUE + 2;
        }
        if (comptime mva) {
            return historyl.captureHistory[@intFromEnum(fpiece)][@intFromEnum(cPiece)][to] + mvv_lva[@intFromEnum(fpiece)][@intFromEnum(cPiece)];
            //return mvv_lva[@intFromEnum(fpiece)][@intFromEnum(cPiece)];
        } else {
            return SEE(p_state, move);
        }
    } else {
        //
        if (move.isPromotion()) {
            return configl.ORDERING_PROMOTIONS;
        }
        if (move.equal(historyl.killerMoves[ply][0])) {
            return configl.KILLER_0_HEURISTIC_VALUE;
        } else if (move.equal(historyl.killerMoves[ply][1])) {
            return configl.KILLER_1_HEURISTIC_VALUE;
            //} else if (move.equal(historyl.counterMoves[from][to])) {
            //    return configl.COUNTERMOVE_HEURISTIC_VALUE;
        } else {
            //return historyl.historyHeuristic[@intFromBool(white)][from][to] + continuations[0][@intFromEnum(fpiece)][to] + continuations[1][@intFromEnum(fpiece)][to];
            return historyl.historyHeuristic[@intFromBool(white)][from][to];
        }
        //return historyl.historyHeuristic[@intFromBool(white)][from][to] + continuations[0][@intFromEnum(fpiece)][to] + continuations[1][@intFromEnum(fpiece)][to];
    }
    return 0;
}

//https://www.chessprogramming.org/History_Heuristic#Update
pub inline fn computeHistoryBonus(depth: u16) scoreType {
    return @intCast(30 * depth - 25);
}
pub fn cmp_eval_move(context: []const scoreType, a: u8, b: u8) bool {
    return context[a] > context[b];
}
pub fn eval_move_sorting_mask(p_state: *const boardl.boardState, p_moves: *const movel.moveContainer, ply: u16, hashMove: IMove, depth: u16, prevLineMove: IMove, comptime mva: bool) moveOrdering {
    _ = depth;
    var ret: moveOrdering = undefined;
    var scores: [chess.MAX_POSSIBLE_MOVE]scoreType = undefined;
    const w: bool = p_state.whiteToMove();

    for (0..p_moves.len) |i| {
        ret.indexes[i] = @intCast(i);
        scores[i] = eval_move_heuristic_line(p_state, p_moves.moves[i], ply, hashMove, prevLineMove, mva, w);
    }
    ret.len = p_moves.len;

    std.mem.sort(u8, ret.indexes[0..p_moves.len], scores[0..p_moves.len], cmp_eval_move);

    for (0..ret.len) |idx| {
        ret.scores[idx] = scores[ret.indexes[idx]];
    }
    return ret;
}

pub inline fn depthToMilliDepth(d: i32) milliDepth {
    return @intCast(d << 10);
}
pub inline fn milliDepthToDepth(md: milliDepth) i32 {
    return @intCast(md >> 10);
}
pub inline fn lmrFDepth(md: milliDepth) milliDepth {
    return @divFloor(md, 3); // base reduction of 1/3
}
pub inline fn plyModif(ply: u16) u16 {
    return @intCast(std.math.log(u16, 3, ply + 1));
}

pub const moveReductionAmount = 4;
// hashmove + line move + 2 killer moves (?)

pub fn losingCapture(p_state: *const boardl.boardState, move: IMove) bool {
    const otherKingSq = p_state.getKingSq(!p_state.whiteToMove());
    const safetyArea = chess.safetyArea(otherKingSq);
    const to = move.getTo();
    if ((to & safetyArea) != 0 or moveGenl.moveDeliverCheck(p_state, move)) {
        return false;
    }
    return SEE(p_state, move) < 0;
}
pub const score = struct {
    s: scoreType = 0,
    t: typel.e_scoreType = .NONE,
    pub inline fn isTerminal(self: score) bool {
        return self.t == .DRAW or self.t == .MATE;
    }
    pub inline fn getScore(self: score) scoreType {
        return self.s;
    }
    pub inline fn invert(self: score) score {
        return .{ .s = -self.s, .t = self.t };
    }
};

pub const moveOrdering = struct {
    indexes: [chess.MAX_POSSIBLE_MOVE]u8 = undefined,
    scores: [chess.MAX_POSSIBLE_MOVE]scoreType = undefined,
    len: u8 = 0,
};
pub const moveGenerator = struct {
    moves: moveContainer = undefined,
    bbState: moveBBState = undefined,
    bbStateGenerated: bool = false,
    extra: moveGenl.generationModifiers = .NONE,
    idx: usize = 0,

    pub fn init() moveGenerator {
        var ret: moveGenerator = .{};
        ret.moves.len = 0;
        ret.idx = 0;
        ret.extra = .NONE;
        return ret;
    }
    pub fn generateCapture(p_self: *moveGenerator, p_state: *const boardl.boardState) void {
        if (!p_self.bbStateGenerated) {
            p_self.bbState = moveGenl.moveGenBB(p_state);
            p_self.bbStateGenerated = true;
        }
        moveGenl.moveGenBBToMoveContainer(p_state, &p_self.bbState, &p_self.moves, .CAPTURES);
    }
    pub fn generateQuiet(p_self: *moveGenerator, p_state: *const boardl.boardState) void {
        if (!p_self.bbStateGenerated) {
            p_self.bbState = moveGenl.moveGenBB(p_state);
            p_self.bbStateGenerated = true;
        }
        moveGenl.moveGenBBToMoveContainer(p_state, &p_self.bbState, &p_self.moves, .QUIETMOVE);
    }
    pub fn fetchNext(p_self: *moveGenerator, p_state: *const boardl.boardState) void {
        p_self.idx = 0;
        p_self.moves.len = 0;
        if (p_self.extra == .NONE) {
            p_self.generateCapture(p_state);
            p_self.extra = .CAPTURES;
        } else if (p_self.extra == .CAPTURES) {
            p_self.generateQuiet(p_state);
            p_self.extra = .QUIETMOVE;
        } else {
            std.debug.print("[PANIC] fetchNext: found invalid extra {}\n", .{p_self.extra});
            @panic("");
        }
    }
    pub fn pickNext(p_self: *moveGenerator, order: *const moveOrdering) ?IMove {
        // fetchNext need to be called atleast once
        if (p_self.idx >= p_self.moves.len) {
            return null;
        }
        const idx = order.indexes[p_self.idx];
        const ret: IMove = p_self.moves.moves[idx];
        p_self.idx += 1;
        return ret;
    }
};
pub fn mat_gain(p_state: *const boardl.boardState, move: IMove) scoreType {
    if (!move.isCapture()) return 0;
    const piece = p_state.getCapturePiece(move);
    return e_pieceToHeuristic(piece);
}

pub fn SEE(p_state: *const boardl.boardState, move: IMove) scoreType {
    if (!move.isCapture()) {
        return 0;
    }
    const to = move.getTo();
    const from = move.getFrom();
    return _SEE_recalc(p_state, @enumFromInt(to), @enumFromInt(from), p_state.whiteToMove());
}
pub const SEE_context = struct {
    attadef: u64 = 0,
    diagPiece: u64 = 0,
    horizPiece: u64 = 0,
    pub fn init(p_board: *const boardl.boardState, toSq: squarel.e_square, white: bool) SEE_context {
        var ret: SEE_context = undefined;
        ret.horizPiece = (p_board.b.pieceBB[@intFromEnum(e_pieceType.ROOK)] |
            p_board.b.pieceBB[@intFromEnum(e_pieceType.QUEEN)]);

        ret.diagPiece = (p_board.b.pieceBB[@intFromEnum(e_pieceType.BISHOP)] |
            p_board.b.pieceBB[@intFromEnum(e_pieceType.QUEEN)]);

        const attacker = chess.getAllAttackerFromSq(p_board, !white, toSq);
        const defender = chess.getAllAttackerFromSq(p_board, white, toSq);
        ret.attadef = attacker | defender;
        return ret;
    }
};

// source: https://www.chessprogramming.org/SEE_-_The_Swap_Algorithm
pub inline fn _SEE_recalc(p_state: *const boardl.boardState, toSq: squarel.e_square, fromSq: squarel.e_square, white: bool) scoreType {
    const ctx: SEE_context = SEE_context.init(p_state, toSq, white);
    return _SEE_loop(p_state, toSq, fromSq, white, ctx.attadef, ctx.diagPiece, ctx.horizPiece);
}
pub fn _SEE_loop(p_state: *const boardl.boardState, toSq: squarel.e_square, fromSq: squarel.e_square, white: bool, attadef: u64, diagPiece: u64, horizPiece: u64) scoreType {
    var fromSet = chess.sqToBitboard(fromSq);
    const mayXray = diagPiece | horizPiece;
    var _attadef = attadef;

    const toSqInfo = squarel.squareInfo.init(toSq);
    const toSqDiags = toSqInfo.getDiagonalsBB();

    var occ = p_state.b.occupiedBB();

    var gain: [32]scoreType = undefined;
    var d: usize = 0;

    const target = p_state.getPiece(@intFromEnum(toSq));
    const aPiece = p_state.getPiece(@intFromEnum(fromSq));
    gain[d] = e_pieceToHeuristic(target);
    var turn = white;
    var _aPiece = aPiece;
    while (fromSet != 0) {
        d += 1;
        turn = !turn;
        gain[d] = e_pieceToHeuristic(_aPiece) - gain[d - 1];
        _attadef ^= fromSet;
        occ ^= fromSet;
        if ((fromSet & mayXray) != 0) {
            // update the attadef due to movement
            _attadef |= considerXrays(occ, toSq, toSqDiags, fromSet, diagPiece, horizPiece);
        }
        const low = lowestAttackDefPiece(p_state, _attadef, turn);
        if (low.sq == .invalid) {
            fromSet = 0;
            continue;
        }
        fromSet = chess.sqToBitboard(low.sq);
        _aPiece = low.piece;
    }
    d -= 1;
    while (d != 0) : (d -= 1) {
        gain[d - 1] = -@max(-gain[d - 1], gain[d]);
    }
    return gain[0];
}
pub fn considerXrays(occ: u64, fromSq: squarel.e_square, fromDiags: u64, movingBB: u64, diagPiece: u64, horizPiece: u64) u64 {
    if (fromDiags & movingBB == 0) {
        // then horizontal or vertical
        const ret = chess.getRookAttacks(occ, fromSq) & horizPiece & occ;
        return ret;
    }
    const ret = chess.getBishopAttacks(occ, fromSq) & diagPiece & occ;
    return ret;
}

pub const piecePosition = struct {
    piece: e_piece = .nEmptySquare,
    sq: squarel.e_square = .invalid,
};

pub fn lowestAttackDefPiece(p_state: *const boardl.boardState, attDef: u64, white: bool) piecePosition {
    var ret: piecePosition = .{};
    var retHeur: scoreType = weightl.simpleCheckMateScore;
    var allAttack = attDef & p_state.b.c_occupiedBB[@intFromBool(white)];
    while (allAttack != 0) {
        const targetSq = chess.bitscan(allAttack);
        allAttack &= allAttack - 1;
        const piece = p_state.getPiece(targetSq);
        const pieceH = e_pieceToHeuristic(piece);
        if (pieceH < retHeur) {
            retHeur = pieceH;
            ret.piece = piece;
            ret.sq = @enumFromInt(targetSq);
        }
    }
    return ret;
}

pub fn main(alloc: std.mem.Allocator) !void {
    //try sanityCheck();
    //try test_main();
    mainl.initAll(alloc, false);
    var path: string = try string.initFromSlice(alloc, "opening/E12.33-1M-D12-Resolved.book");
    var savePath: string = try string.initFromSlice(alloc, "out/csv/tmp.csv");

    defer path.free(alloc);
    defer savePath.free(alloc);

    try test_save(alloc, path, savePath);
    //try mainTexel(alloc, path);
}
