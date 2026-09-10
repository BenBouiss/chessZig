const chess = @import("chess.zig");
const moveGenl = @import("move_generation.zig");
const filel = @import("file.zig");
const stringl = @import("string.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const boardl = @import("board.zig");
const weightl = @import("weights.zig");
const squarel = @import("square.zig");
const movel = @import("move.zig");
const typel = @import("type.zig");
const alphaBetal = @import("alphaBeta.zig");
const threadingl = @import("threading.zig");
const logl = @import("log.zig");
const nnuel = @import("nnue.zig");

const std = @import("std");

const e_piece = typel.e_piece;
const e_pieceType = typel.e_pieceType;
const e_color = typel.e_color;

const string = stringl.string;
const IMove = movel.IMove;
const moveBBState = movel.moveBBState;
const scoreType: type = typel.scoreType;
pub const scoreVect: type = @Vector(2, scoreType);
pub const psqtVect: type = @Vector(2, scoreType);
const milliDepth: type = typel.milliDepth;

pub const texel_err = error{board_err};

pub fn evaluate(p_state: *const boardl.boardState) scoreType {
    const allwhiteMoveBB = moveGenl._cst_moveGenBB_all(p_state, true);
    const allblackMoveBB = moveGenl._cst_moveGenBB_all(p_state, false);

    const whiteMoveBB = allwhiteMoveBB.andFn(~p_state.occupiedBB_col(.WHITE));
    const blackMoveBB = allblackMoveBB.andFn(~p_state.occupiedBB_col(.BLACK));
    const white = p_state.whiteToMove();

    const phase: scoreType = p_state.getPhase();

    var ret = evaluate_mobility(p_state, &allwhiteMoveBB, &allblackMoveBB, white);

    ret += evaluate_material(p_state);
    ret += evaluate_safety(p_state, &whiteMoveBB, &blackMoveBB);
    ret += evaluate_structure(p_state, &allwhiteMoveBB, &allblackMoveBB);
    ret += evaluate_tempo(p_state, white);
    ret += evaluate_pawnStructure(p_state);
    ret += evaluate_king(p_state, (computeTaperedV(ret, phase) + p_state.frame.psqtEval) > 0, white);

    return computeTaperedV(ret, phase) + p_state.frame.psqtEval;
}

pub inline fn c_evaluate(p_state: *const boardl.boardState, white: bool) scoreType {
    if (comptime configl.USE_NNUE) {
        const eval = nnuel.evaluate(white, &p_state.frame.nnueAccumul);
        return @divFloor(eval * (200 - p_state.frame.halfMoveClock), 200);
    } else {
        const eval = evaluate(p_state);
        const ret: scoreType = @divFloor(eval * (200 - p_state.frame.halfMoveClock), 200);
        return if (white) ret else -ret;
    }
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
    nnueW: scoreType = 0,
    nnueB: scoreType = 0,
    pub fn total(self: *const heuristicComponents) scoreType {
        return self.PSQT + self.Mobility + self.PawnStruct + self.Safety + self.Structure + self.Tempo + self.King + self.Material;
    }
    pub fn print(self: *const heuristicComponents) void {
        if (configl.USE_NNUE) {
            std.debug.print("Score: PSQT = {d}, Mobility = {d}, PawnStruct = {d}, Safety = {d}, Material = {d}, Structure = {d}, Tempo = {d}, King = {d}, Total = {d} NNUE-W = {d} NNUE-B = {d}\n", .{ self.PSQT, self.Mobility, self.PawnStruct, self.Safety, self.Material, self.Structure, self.Tempo, self.King, self.total(), self.nnueW, self.nnueB });
        } else {
            std.debug.print("Score: PSQT = {d}, Mobility = {d}, PawnStruct = {d}, Safety = {d}, Material = {d}, Structure = {d}, Tempo = {d}, King = {d}, Total = {d}\n", .{ self.PSQT, self.Mobility, self.PawnStruct, self.Safety, self.Material, self.Structure, self.Tempo, self.King, self.total() });
        }
    }
};
pub fn evaluate_debug(p_state: *const boardl.boardState) heuristicComponents {
    const allwhiteMoveBB = moveGenl._cst_moveGenBB_all(p_state, true);
    const allblackMoveBB = moveGenl._cst_moveGenBB_all(p_state, false);
    const whiteMoveBB = allwhiteMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromEnum(e_color.WHITE)]);
    const blackMoveBB = allblackMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromEnum(e_color.BLACK)]);

    const phase: scoreType = p_state.getPhase();
    const white = p_state.whiteToMove();

    var ret: heuristicComponents = .{
        //.PSQT = evaluate_PSQT(p_state, values, _phase),
        .PSQT = p_state.frame.psqtEval,
        .Mobility = computeTaperedV(evaluate_mobility(p_state, &allwhiteMoveBB, &allblackMoveBB, white), phase),
        .King = computeTaperedV(evaluate_king(p_state, p_state.frame.psqtEval > 0, white), phase),
        .Material = computeTaperedV(evaluate_material(p_state), phase),
        .Safety = computeTaperedV(evaluate_safety(p_state, &whiteMoveBB, &blackMoveBB), phase),
        .Structure = computeTaperedV(evaluate_structure(p_state, &allwhiteMoveBB, &allblackMoveBB), phase),
        .PawnStruct = computeTaperedV(evaluate_pawnStructure(p_state), phase),
        .Tempo = computeTaperedV(evaluate_tempo(p_state, white), phase),
    };
    if (configl.USE_NNUE) {
        // always from white perspective?
        const acc = nnuel.computeAccPair(&nnuel.nnueNet.net, p_state);
        ret.nnueW = nnuel.evaluate(true, &acc);
        ret.nnueB = nnuel.evaluate(false, &acc);
    }
    return ret;
}
pub inline fn computeTapered(score_mg: scoreType, score_eg: scoreType, phase: scoreType) scoreType {
    return @divFloor((score_mg * (256 - phase)) + score_eg * phase, 256);
}
pub inline fn computeTaperedV(s: scoreVect, phase: scoreType) scoreType {
    return @divFloor((s[0] * (256 - phase)) + s[1] * phase, 256);
}

pub fn evaluate_PSQT(p_state: *const boardl.boardState, _phase: scoreType) scoreType {
    var score_mg: scoreType = 0;
    var score_eg: scoreType = 0;
    var _bb = p_state.b.occupiedBB();

    //var score_count: scoreType = 0;
    while (_bb != 0) {
        const sq = chess.bitscan(_bb);
        _bb &= _bb - 1;
        const piece = p_state.getPiece(@intCast(sq));

        const sV: psqtVect = getPieceInfos(piece, @enumFromInt(sq));

        //score_count += sV[0];
        //score_mg += sV[1];
        //score_eg += sV[2];

        score_mg += sV[0];
        score_eg += sV[1];
    }

    //return score_count + computeTapered(score_mg, score_eg, _phase);
    return computeTapered(score_mg, score_eg, _phase);
}

pub fn evaluate_pawnStructure(p_state: *const boardl.boardState) scoreVect {
    const wp = p_state.getPieceBB_t(.PAWN) & p_state.occupiedBB_col(.WHITE);
    const bp = p_state.getPieceBB_t(.PAWN) & p_state.occupiedBB_col(.BLACK);
    // in an effort to have the weights all positive I swapped the diff, (nBlackIsolated - nWhiteIsolated) * (w>0) means that white is advantaged (s>0) if (nBlackIsolated > nWhiteIsolated) and black is advantaged(s<0) if (nBlackIsolated < nWhiteIsolated)
    // same for doubled as doubled and isolated are seen as negative attributes hence why I chose negative weights to penalize the respective sides.

    const nWhiteIsolated: i8 = chess.ipopcount(chess.isolatedPawns(wp));
    const nBlackIsolated: i8 = chess.ipopcount(chess.isolatedPawns(bp));
    const isoS: scoreType = @intCast(nBlackIsolated - nWhiteIsolated);

    const nWhiteDoubled: i8 = chess.ipopcount(chess.stackedPawns(wp));
    const nBlackDoubled: i8 = chess.ipopcount(chess.stackedPawns(bp));
    const doS: scoreType = @intCast(nBlackDoubled - nWhiteDoubled);

    const nWhitePassed: i8 = chess.ipopcount(chess.passedPawns(wp, bp));
    const nBlackPassed: i8 = chess.ipopcount(chess.passedPawns(bp, wp));
    const paS: scoreType = @intCast(nWhitePassed - nBlackPassed);

    const nWhiteDuo: i8 = chess.ipopcount(chess.duoPhalanx(wp));
    const nBlackDuo: i8 = chess.ipopcount(chess.duoPhalanx(bp));
    const duoS: scoreType = @intCast(nWhiteDuo - nBlackDuo);

    const nWhiteConn: i8 = chess.ipopcount(wp & chess.getPawnAttacksFromBB(wp, true));
    const nBlackConn: i8 = chess.ipopcount(bp & chess.getPawnAttacksFromBB(bp, false));
    const connectS: scoreType = @intCast(nWhiteConn - nBlackConn);

    return .{ (isoS * weightl.global_IsolatedPawnVal[MG]) + (doS * weightl.global_StackedPawnVal[MG]) + (paS * weightl.global_PassedPawnVal[MG]) + (duoS * weightl.global_phalanxDuoPawnVal[MG]) + (connectS * weightl.global_connectionPawnVal[MG]), (isoS * weightl.global_IsolatedPawnVal[EG]) + (doS * weightl.global_StackedPawnVal[EG]) + (paS * weightl.global_PassedPawnVal[EG]) + (duoS * weightl.global_phalanxDuoPawnVal[EG]) + (connectS * weightl.global_connectionPawnVal[EG]) };
}
pub fn evaluate_mobility(p_state: *const boardl.boardState, p_whiteMoveBB: *const moveBBState, p_blackMoveBB: *const moveBBState, white: bool) scoreVect {
    _ = white;
    // going to use "raw" mobility only taking board coverage
    const moveW: i64 = @intCast(p_whiteMoveBB.count());
    const moveB: i64 = @intCast(p_blackMoveBB.count());
    const v = @as(scoreType, @intCast(moveW - moveB));
    const moveAmountScore: scoreVect = .{ weightl.global_MobilityVal[MG] * v, weightl.global_MobilityVal[EG] * v };
    //const wkingBB = chess.sqToBitboard(p_state.b.wKingSq);
    //const bkingBB = chess.sqToBitboard(p_state.b.bKingSq);
    const wAttacks = (p_whiteMoveBB.getAttackedMask(chess.UNIVERSE));
    const bAttacks = (p_blackMoveBB.getAttackedMask(chess.UNIVERSE));

    const wTabouAttacks = p_whiteMoveBB.getAttackedMaskTabou(chess.UNIVERSE, bAttacks);
    const bTabouAttacks = p_blackMoveBB.getAttackedMaskTabou(chess.UNIVERSE, wAttacks);

    const kingMoveW = p_whiteMoveBB.kingMoves & (~bAttacks) & ~p_state.occupiedBB_col(.WHITE);
    const kingMoveB = p_blackMoveBB.kingMoves & (~wAttacks) & ~p_state.occupiedBB_col(.BLACK);

    var kingMoveScore: scoreVect = @splat(0);
    if (p_state.isChecked()) {
        if (p_state.whiteToMove()) {
            if (kingMoveW == 0 and (wTabouAttacks & p_state.frame.checkersBB) == 0) {
                kingMoveScore -= .{ weightl.global_weakCheckmate[MG], weightl.global_weakCheckmate[EG] };
            }
        } else {
            if (kingMoveB == 0 and (bTabouAttacks & p_state.frame.checkersBB) == 0) {
                kingMoveScore += .{ weightl.global_weakCheckmate[MG], weightl.global_weakCheckmate[EG] };
            }
        }
    }
    const nOpenRookW: scoreType = @intCast(chess.ipopcount(chess.openFileRooks(p_state.getPieceBB_t(.ROOK) & p_state.occupiedBB_col(.WHITE), p_state.getPieceBB_t(.PAWN) & p_state.occupiedBB_col(.WHITE), true)));
    const nOpenRookB: scoreType = @intCast(chess.ipopcount(chess.openFileRooks(p_state.getPieceBB_t(.ROOK) & p_state.occupiedBB_col(.BLACK), p_state.getPieceBB_t(.PAWN) & p_state.occupiedBB_col(.BLACK), false)));
    const deltaOpenRook = nOpenRookW - nOpenRookB;
    const pieceMobility: scoreVect = .{ weightl.global_OpenFileRookVal[MG] * deltaOpenRook, weightl.global_OpenFileRookVal[EG] * deltaOpenRook };
    return moveAmountScore + kingMoveScore + pieceMobility;
    //return moveAmountScore + pieceMobility;
}
pub fn evaluate_king(p_state: *const boardl.boardState, whiteWinning: bool, whiteToMove: bool) scoreVect {
    _ = whiteToMove;
    if (p_state.isEndGame()) {
        const wKing = squarel.squareInfo.init(p_state.b.wKingSq);
        const bKing = squarel.squareInfo.init(p_state.b.bKingSq);

        const distance = wKing.computeMHDistance(bKing);
        const bonus = 2 * (squarel.maxBenDistance - distance) + 5 * if (whiteWinning) distance else -distance;
        return .{ bonus * weightl.global_KingProximityVal[MG], bonus * weightl.global_KingProximityVal[EG] };
    } else {
        return .{ 0, 0 };
    }
}
pub inline fn evaluate_material(p_state: *const boardl.boardState) scoreVect {
    // counting negative for white as the best safety is not attackers => 0 heuristic
    const nPairs: scoreType = @as(scoreType, @intFromBool(p_state.b.pieceCount[@intFromEnum(e_piece.nWhiteBishop)] == 2)) - @as(scoreType, @intFromBool(p_state.b.pieceCount[@intFromEnum(e_piece.nBlackBishop)] == 2));
    return .{ nPairs * weightl.global_materialBishopPair[MG], nPairs * weightl.global_materialBishopPair[EG] };
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
    const saf: scoreType = weightl.SAFETY_ARR[@intCast(@min(weightl.SAFETY_ARR.len - 1, wKnight + wBishop + wRook + wQueen))] - weightl.SAFETY_ARR[@intCast(@min(weightl.SAFETY_ARR.len - 1, bKnight + bBishop + bRook + bQueen))];
    const v: scoreVect = .{ saf + (weightl.global_SafetyKnightVal[MG] * Knight) + (weightl.global_SafetyBishopVal[MG] * Bishop) + (weightl.global_SafetyRookVal[MG] * Rook) + (weightl.global_SafetyQueenVal[MG] * Queen), saf + (weightl.global_SafetyKnightVal[EG] * Knight) + (weightl.global_SafetyBishopVal[EG] * Bishop) + (weightl.global_SafetyRookVal[EG] * Rook) + weightl.global_SafetyQueenVal[EG] * Queen };
    return v;
}
pub fn evaluate_structure(p_state: *const boardl.boardState, p_whiteMoveBB: *const moveBBState, p_blackMoveBB: *const moveBBState) scoreVect {
    // structure protection,
    // use the c_moveBBstate & c_occupied, this returns the safety of each individual pieces against capture
    const w_pieceProtect = p_whiteMoveBB.andFn(p_state.occupiedBB_col(.WHITE));
    const b_pieceProtect = p_blackMoveBB.andFn(p_state.occupiedBB_col(.BLACK));
    const s = @as(scoreType, @intCast(w_pieceProtect.count())) - @as(scoreType, @intCast(b_pieceProtect.count()));

    const w_pieceCenterProt = p_whiteMoveBB.collapse() & (chess.centerBB);
    const b_pieceCenterProt = p_blackMoveBB.collapse() & (chess.centerBB);
    const s2 = @as(scoreType, @intCast(chess.ipopcount(w_pieceCenterProt) - chess.ipopcount(b_pieceCenterProt)));
    const wAttack = p_whiteMoveBB.getAttackedMask(chess.UNIVERSE);
    const bAttack = p_blackMoveBB.getAttackedMask(chess.UNIVERSE);
    const wHanging = p_state.occupiedBB_col(.WHITE) & (~wAttack) & (bAttack);
    const bHanging = p_state.occupiedBB_col(.BLACK) & (~bAttack) & (wAttack);
    const s3: scoreType = @intCast(chess.ipopcount(bHanging) - chess.ipopcount(wHanging));

    const nonPawns = ~p_state.getPieceBB_t(.PAWN);
    const wBigThreat = p_state.occupiedBB_col(.BLACK) & (wAttack) & nonPawns;
    const bBigThreat = p_state.occupiedBB_col(.WHITE) & (bAttack) & nonPawns;
    const deltaThreat: scoreType = @intCast(chess.ipopcount(wBigThreat) - chess.ipopcount(bBigThreat));
    //const wRooksAtt = p_whiteMoveBB.rookMoves | p_whiteMoveBB.queenMoves

    //return .{ weightl.global_StructureProtectionVal[MG] * s + weightl.global_centerProtectionVal[MG] * s2, weightl.global_StructureProtectionVal[EG] * s + weightl.global_centerProtectionVal[EG] * s2 };
    return .{ weightl.global_StructureProtectionVal[MG] * s + weightl.global_centerProtectionVal[MG] * s2 + weightl.global_HangingVal[MG] * s3 + weightl.global_pieceThreatScore[MG] * deltaThreat, weightl.global_StructureProtectionVal[EG] * s + weightl.global_HangingVal[EG] * s3 + weightl.global_pieceThreatScore[EG] * deltaThreat };
}
pub fn evaluate_tempo(p_state: *const boardl.boardState, white: bool) scoreVect {
    var ret: scoreVect = @splat(0);
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
            return weightl.simpleQueenScore * 4;
        },
        .nWhitePawn, .nBlackPawn => {
            return weightl.simplePawnScore;
        },
        .nWhiteBishop, .nBlackBishop => {
            return weightl.simpleBishopScore;
        },
        .nWhiteKnight, .nBlackKnight => {
            return weightl.simpleKnightScore;
        },
        .nWhiteRook, .nBlackRook => {
            return weightl.simpleRookScore;
        },
        .nWhiteQueen, .nBlackQueen => {
            return weightl.simpleQueenScore;
        },
    }
}
pub fn updatePSQTOnMove(comptime white: bool, comptime isCapture: bool, move: IMove, isPromo: bool, isCastle: bool, toPiece: e_piece, phase: scoreType, info: *const boardl.boardFrame) scoreType {
    var fromPiece = toPiece;
    const from = move.getFrom();
    const to = move.getTo();
    var sV: psqtVect = getPieceInfos(fromPiece, @enumFromInt(to));
    if (isPromo) {
        fromPiece = if (comptime white) .nWhitePawn else .nBlackPawn;
    }
    sV -= getPieceInfos(fromPiece, @enumFromInt(from));

    if (comptime !isCapture) {
        if (isCastle) {
            const toBis: u8 = if (comptime white) to else (chess.flipSq(to));
            if (move.isQueenSideCastle()) {
                const prev: psqtVect = getPieceInfos_cst(.ROOK, toBis - 2);
                const next: psqtVect = getPieceInfos_cst(.ROOK, toBis + 1);
                //sV = if (comptime white) (sV + next - prev) else (sV + prev - next);
                sV = (sV + next - prev);
            } else {
                const prev: psqtVect = getPieceInfos_cst(.ROOK, toBis + 1);
                const next: psqtVect = getPieceInfos_cst(.ROOK, toBis - 1);
                sV = (sV + next - prev);
            }
        }
    } else {
        // is capture
        const victimSq: typel.e_square = if (move.isEnpassant()) chess.enPassantVictimSq(from, to) else (@enumFromInt(to));
        const victimScs: psqtVect = getPieceInfos(info.victim, victimSq);
        sV -= victimScs;
    }
    return computeTapered(sV[0], sV[1], phase);

    //const ret = sV[0] + computeTapered(sV[1], sV[2], phase);
    //if (comptime white) {
    //    return ret;
    //}
    //return -ret;
}

pub fn materialImbalance(p_state: *const boardl.boardState) scoreType {
    const wPiece: @Vector(5, scoreType) = .{
        p_state.b.pieceCount[0],
        p_state.b.pieceCount[1],
        p_state.b.pieceCount[2],
        p_state.b.pieceCount[3],
        p_state.b.pieceCount[4],
    };
    const bPiece: @Vector(5, scoreType) = .{
        p_state.b.pieceCount[6],
        p_state.b.pieceCount[7],
        p_state.b.pieceCount[8],
        p_state.b.pieceCount[9],
        p_state.b.pieceCount[10],
    };
    const scores = (wPiece - bPiece) * @as(@Vector(5, scoreType), .{ weightl.simplePawnScore, weightl.simpleBishopScore, weightl.simpleKnightScore, weightl.simpleRookScore, weightl.simpleQueenScore });
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

pub inline fn getPieceCountValues() [chess.N_PIECES]scoreType {
    return .{ weightl.global_PawnVal, weightl.global_BishopVal, weightl.global_KnightVal, weightl.global_RookVal, weightl.global_QueenVal, 0 };
}
// other more complex values may be inserted below
//pub fn getPieceInfos(piece: e_piece, sq: typel.e_square) [2]typel.scoreType {
pub fn getPieceInfos(piece: e_piece, sq: typel.e_square) psqtVect {
    switch (piece) {
        .nEmptySquare, .nWhite, .nBlack => {
            //return .{ 0, 0 };
            return @splat(0);
        },
        .nWhitePawn => {
            return getPieceInfos_cst(.PAWN, @intFromEnum(sq));
        },
        .nBlackPawn => {
            return -getPieceInfos_cst(.PAWN, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteBishop => {
            return getPieceInfos_cst(.BISHOP, @intFromEnum(sq));
        },
        .nBlackBishop => {
            return -getPieceInfos_cst(.BISHOP, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteKnight => {
            return getPieceInfos_cst(.KNIGHT, @intFromEnum(sq));
        },
        .nBlackKnight => {
            return -getPieceInfos_cst(.KNIGHT, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteRook => {
            return getPieceInfos_cst(.ROOK, @intFromEnum(sq));
        },
        .nBlackRook => {
            return -getPieceInfos_cst(.ROOK, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteQueen => {
            return getPieceInfos_cst(.QUEEN, @intFromEnum(sq));
        },
        .nBlackQueen => {
            return -getPieceInfos_cst(.QUEEN, chess.flipSq(@intFromEnum(sq)));
        },
        .nWhiteKing => {
            return getPieceInfos_cst(.KING, @intFromEnum(sq));
        },
        .nBlackKing => {
            return -getPieceInfos_cst(.KING, chess.flipSq(@intFromEnum(sq)));
        },
    }
}
pub inline fn getPieceInfos_cst(comptime piece: typel.e_pieceType, sq: u8) psqtVect {
    //pub inline fn getPieceInfos_cst(comptime piece: typel.e_pieceType, sq: u8) [3]typel.scoreType {
    switch (piece) {
        .PAWN => {
            //return .{ weightl.simplePawnScore, weightl.global_Pawn_PSQT[MG][sq], weightl.global_Pawn_PSQT[EG][sq] };
            return .{ weightl.global_Pawn_PSQT[MG][sq], weightl.global_Pawn_PSQT[EG][sq] };
        },
        .BISHOP => {
            //return .{ weightl.simpleBishopScore, weightl.global_Bishop_PSQT[MG][sq], weightl.global_Bishop_PSQT[EG][sq] };
            return .{ weightl.global_Bishop_PSQT[MG][sq], weightl.global_Bishop_PSQT[EG][sq] };
        },
        .KNIGHT => {
            //return .{ weightl.simpleKnightScore, weightl.global_Knight_PSQT[MG][sq], weightl.global_Knight_PSQT[EG][sq] };
            return .{ weightl.global_Knight_PSQT[MG][sq], weightl.global_Knight_PSQT[EG][sq] };
        },
        .ROOK => {
            //return .{ weightl.simpleRookScore, weightl.global_Rook_PSQT[MG][sq], weightl.global_Rook_PSQT[EG][sq] };
            return .{ weightl.global_Rook_PSQT[MG][sq], weightl.global_Rook_PSQT[EG][sq] };
        },
        .QUEEN => {
            //return .{ weightl.simpleQueenScore, weightl.global_Queen_PSQT[MG][sq], weightl.global_Queen_PSQT[EG][sq] };
            return .{ weightl.global_Queen_PSQT[MG][sq], weightl.global_Queen_PSQT[EG][sq] };
        },
        .KING => {
            //return .{ 0, weightl.global_King_PSQT[MG][sq], weightl.global_King_PSQT[EG][sq] };
            return .{ weightl.global_King_PSQT[MG][sq], weightl.global_King_PSQT[EG][sq] };
        },
    }
}

const N_PHASES: usize = 2;

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

    //const color_mask: scoreType = if (p_board.whiteToMove()) 1 else -1;
    const stat = c_evaluate(p_board, p_board.whiteToMove());
    var info: threadingl.threadInfo = .{ .alive = true };

    const alpha: scoreType = -weightl.simpleCheckMateScore;
    const beta: scoreType = weightl.simpleCheckMateScore;
    var ss: alphaBetal.searchStack = .{};
    const isChecked = p_board.isChecked();
    if (isChecked) return false;
    const quiesc = alphaBetal.quiescenceSearch(p_board, &info, alpha, beta, 0, &ss);
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
    fen: [chess.MAX_FEN_LENGTH]u8 = @splat(0),

    pub fn set_fen(p_self: *texelEntry, fen: []const u8, result: f32, computeCoeffs: bool) !void {
        p_self.tuples = .{};
        p_self.result = result;
        var board = chess.getBoardFromFen(fen) catch {
            std.debug.print("[ERROR] set_fen: error while using the fen: '{s}'\n", .{fen});
            @panic("");
        };

        board.frame.nnueAccumul = nnuel.computeAccPair(&nnuel.nnueNet.net, &board);
        p_self.eval = c_evaluate(&board, true);
        p_self.phase = board.getPhase();
        p_self.turn = board.whiteToMove();
        p_self.valid = isBoardTexelValid(&board);
        if (!p_self.valid) {
            return texel_err.board_err;
        }
        p_self.fen = @splat(0);
        for (0..fen.len) |i| {
            p_self.fen[i] = fen[i];
        }

        if (computeCoeffs) {
            try getCoeffsFromBoard(&board, &p_self.tuples);
        }
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
    // piece counts
    p_out.appendCoeff(.{ .wcoeff = @intCast(p_state.getPieceCount(.nWhitePawn)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackPawn)) });
    std.debug.assert(idx == configl.TEXEL_PAWN_COUNT_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = @intCast(p_state.getPieceCount(.nWhiteBishop)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackBishop)) });
    std.debug.assert(idx == configl.TEXEL_BISHOP_COUNT_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = @intCast(p_state.getPieceCount(.nWhiteKnight)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackKnight)) });
    std.debug.assert(idx == configl.TEXEL_KNIGHT_COUNT_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = @intCast(p_state.getPieceCount(.nWhiteRook)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackRook)) });
    std.debug.assert(idx == configl.TEXEL_ROOK_COUNT_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = @intCast(p_state.getPieceCount(.nWhiteQueen)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackQueen)) });
    std.debug.assert(idx == configl.TEXEL_QUEEN_COUNT_IDX);
    idx += 1;

    const allwhiteMoveBB = moveGenl._cst_moveGenBB_all(p_state, true);
    const allblackMoveBB = moveGenl._cst_moveGenBB_all(p_state, false);
    //const whiteMoveBB = allwhiteMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromEnum(e_color.WHITE)]);
    //const blackMoveBB = allblackMoveBB.andFn(~p_state.b.c_occupiedBB[@intFromEnum(e_color.BLACK)]);
    // mobility
    const moveW: scoreType = @intCast(allwhiteMoveBB.count());
    const moveB: scoreType = @intCast(allblackMoveBB.count());

    p_out.appendCoeff(.{ .wcoeff = moveW, .bcoeff = moveB });
    std.debug.assert(idx == configl.TEXEL_MOVE_COUNT_IDX);
    idx += 1;

    const bAttacks = (allblackMoveBB.getAttackedMask(chess.UNIVERSE));
    const wAttacks = (allwhiteMoveBB.getAttackedMask(chess.UNIVERSE));
    //const kingMoveW = allwhiteMoveBB.kingMoves & (~allblackMoveBB.getAttackedMask(chess.UNIVERSE));
    //const kingMoveB = allblackMoveBB.kingMoves & (~allwhiteMoveBB.getAttackedMask(chess.UNIVERSE));
    const kingMoveW = allwhiteMoveBB.kingMoves & (~bAttacks) & ~p_state.occupiedBB_col(.WHITE);
    const kingMoveB = allblackMoveBB.kingMoves & (~wAttacks) & ~p_state.occupiedBB_col(.BLACK);

    p_out.appendCoeff(.{ .wcoeff = @intCast(chess.popcount(kingMoveW)), .bcoeff = @intCast(chess.popcount(kingMoveB)) });
    std.debug.assert(idx == configl.TEXEL_KINGMOVE_COUNT_IDX);
    idx += 1;

    // structure protection
    const w_pieceProtect = allwhiteMoveBB.andFn(p_state.occupiedBB_col(.WHITE) ^ chess.sqToBitboard(p_state.b.wKingSq));
    const b_pieceProtect = allblackMoveBB.andFn(p_state.occupiedBB_col(.BLACK) ^ chess.sqToBitboard(p_state.b.bKingSq));
    p_out.appendCoeff(.{ .wcoeff = @intCast(w_pieceProtect.count()), .bcoeff = @intCast(b_pieceProtect.count()) });
    std.debug.assert(idx == configl.TEXEL_PROTECTION_COUNT_IDX);
    idx += 1;

    const w_pieceCenterProt = allwhiteMoveBB.andFn(chess.centerBB).collapse();
    const b_pieceCenterProt = allblackMoveBB.andFn(chess.centerBB).collapse();
    p_out.appendCoeff(.{ .wcoeff = @intCast(chess.popcount(w_pieceCenterProt)), .bcoeff = @intCast(chess.popcount(b_pieceCenterProt)) });
    std.debug.assert(idx == configl.TEXEL_CENTER_PROTECTION_IDX);
    idx += 1;

    // pawn structure
    p_out.appendCoeff(.{ .wcoeff = @intCast(chess.ipopcount(chess.isolatedPawns(p_state.getPieceBB(e_piece.nWhitePawn)))), .bcoeff = @intCast(chess.ipopcount(chess.isolatedPawns(p_state.getPieceBB(e_piece.nBlackPawn)))) });
    std.debug.assert(idx == configl.TEXEL_PAWN_ISOL_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = @intCast(chess.ipopcount(chess.stackedPawns(p_state.getPieceBB(e_piece.nWhitePawn)))), .bcoeff = @intCast(chess.ipopcount(chess.stackedPawns(p_state.getPieceBB(e_piece.nBlackPawn)))) });
    std.debug.assert(idx == configl.TEXEL_PAWN_STACKED_IDX);
    idx += 1;

    const wp = p_state.getPieceBB(.nWhitePawn);
    const bp = p_state.getPieceBB(.nBlackPawn);
    const nWhitePassed: i8 = @intCast(chess.popcount(chess.passedPawns(wp, bp)));
    const nBlackPassed: i8 = @intCast(chess.popcount(chess.passedPawns(bp, wp)));

    p_out.appendCoeff(.{ .wcoeff = @intCast(nWhitePassed), .bcoeff = @intCast(nBlackPassed) });
    std.debug.assert(idx == configl.TEXEL_PAWN_PASSED_IDX);
    idx += 1;

    // tempo
    if (p_state.whiteToMove()) {
        p_out.appendCoeff(.{ .wcoeff = 0, .bcoeff = @intFromBool(p_state.isChecked()) });
    } else {
        p_out.appendCoeff(.{ .wcoeff = @intFromBool(p_state.isChecked()), .bcoeff = 0 });
    }
    std.debug.assert(idx == configl.TEXEL_TEMPO_CHECKS_IDX);
    idx += 1;

    const nonPawns = ~p_state.getPieceBB_t(.PAWN);
    const wThreats = allwhiteMoveBB.andFn(p_state.occupiedBB_col(.BLACK) & nonPawns);
    const bThreats = allblackMoveBB.andFn(p_state.occupiedBB_col(.WHITE) & nonPawns);

    p_out.appendCoeff(.{ .wcoeff = @intCast(wThreats.count()), .bcoeff = @intCast(bThreats.count()) });
    std.debug.assert(idx == configl.TEXEL_PIECE_THREAT_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = 0, .bcoeff = 0 });
    std.debug.assert(idx == configl.TEXEL_WEAK_CHECKMATE_IDX);
    idx += 1;

    const maskW = chess.safetyArea(p_state.b.wKingSq);
    const maskB = chess.safetyArea(p_state.b.bKingSq);

    p_out.appendCoeff(.{ .wcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhitePawn))), .bcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackPawn))) });
    std.debug.assert(idx == configl.TEXEL_SAFETY_PAWN_PROX_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhiteBishop))), .bcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackBishop))) });
    std.debug.assert(idx == configl.TEXEL_SAFETY_BISHOP_PROX_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhiteKnight))), .bcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackKnight))) });
    std.debug.assert(idx == configl.TEXEL_SAFETY_KNIGHT_PROX_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhiteRook))), .bcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackRook))) });
    std.debug.assert(idx == configl.TEXEL_SAFETY_ROOK_PROX_IDX);
    idx += 1;

    p_out.appendCoeff(.{ .wcoeff = @intCast(chess.ipopcount(maskB & p_state.getPieceBB(e_piece.nWhiteQueen))), .bcoeff = @intCast(chess.ipopcount(maskW & p_state.getPieceBB(e_piece.nBlackQueen))) });
    std.debug.assert(idx == configl.TEXEL_SAFETY_QUEEN_PROX_IDX);
    idx += 1;

    const wKing = squarel.squareInfo.init(p_state.b.wKingSq);
    const bKing = squarel.squareInfo.init(p_state.b.bKingSq);
    const distance: scoreType = squarel.maxBenDistance - @as(scoreType, @intCast(wKing.computeMHDistance(bKing)));

    p_out.appendCoeff(.{ .wcoeff = distance, .bcoeff = distance });
    std.debug.assert(idx == configl.TEXEL_KING_PROXIMITY_IDX);
    idx += 1;

    if (configl.TUNE_COMPLEXITY) {}
    // piece psqt
    std.debug.assert(idx == configl.TEXEL_PAWN_PSQT_IDX);
    p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhitePawn)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackPawn))));
    idx += 64;

    std.debug.assert(idx == configl.TEXEL_BISHOP_PSQT_IDX);
    p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteBishop)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackBishop))));
    idx += 64;
    std.debug.assert(idx == configl.TEXEL_KNIGHT_PSQT_IDX);

    p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteKnight)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackKnight))));
    idx += 64;

    std.debug.assert(idx == configl.TEXEL_ROOK_PSQT_IDX);
    p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteRook)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackRook))));
    idx += 64;
    std.debug.assert(idx == configl.TEXEL_QUEEN_PSQT_IDX);

    p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteQueen)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackQueen))));
    idx += 64;
    std.debug.assert(idx == configl.TEXEL_KING_PSQT_IDX);

    p_out.add1DCoeff(&getMaskFromBB(p_state.getPieceBB(e_piece.nWhiteKing)), &getMaskFromBB(chess.rotate180(p_state.getPieceBB(e_piece.nBlackKing))));
    idx += 64;

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

    pub fn print(p_self: *NVector) void {
        std.debug.print("( ", .{});
        for (0..p_self.val.len) |i| {
            std.debug.print(" {d} ", .{p_self.val[i]});
        }
        std.debug.print(")\n", .{});
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
        p_self.items[@intFromEnum(e_color.WHITE)].val[p_self.len] = item.wcoeff;
        p_self.items[@intFromEnum(e_color.BLACK)].val[p_self.len] = item.bcoeff;
        p_self.len += 1;
    }

    pub fn add1DCoeff(p_self: *coeffVector, w: []const scoreType, b: []const scoreType) void {
        std.debug.assert(w.len == b.len);
        for (0..w.len) |i| {
            p_self.appendCoeff(.{ .wcoeff = w[i], .bcoeff = b[i] });
        }
    }
};

pub fn getEntriesFromFile(alloc: std.mem.Allocator, path: string, nSkips: usize, computeCoeff: bool) ![]texelEntry {
    var tokens = try filel.getTokensFromFileAlloc(alloc, path._slice(), '\n', configl.N_POSITIONS, nSkips);
    var entries: []texelEntry = try alloc.alloc(texelEntry, configl.N_POSITIONS);

    for (0..tokens.items.len) |i| {
        var s = tokens.items[i];
        const outcome = try s.extractFromBounds("[", "]");
        var foutcome: f32 = 0;
        if (utilsl.contains(outcome, "0.5", .ignoreCase)) {
            foutcome = 0.5;
        } else if (utilsl.contains(outcome, "1.0", .ignoreCase)) {
            foutcome = 1;
        }
        entries[i].set_fen(s._slice(), foutcome, computeCoeff) catch {
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
        try writer.print("Phase,Outcome,Eval", .{});
    }
};
pub const csvBody = struct {
    entry: *texelEntry = undefined,
    pub fn format(self: csvBody, writer: *std.Io.Writer) !void {
        const tuple = self.entry.tuples;
        for (0..tuple.len) |i| {
            const val = tuple.items[@intFromEnum(e_color.WHITE)].val[i] - tuple.items[@intFromEnum(e_color.BLACK)].val[i];
            try writer.print("{d},", .{val});
        }

        try writer.print("{d},{d},{d}", .{ self.entry.phase, self.entry.result, self.entry.eval });
    }
};

pub fn createEmptyCSVFile(alloc: std.mem.Allocator, logFile: *logl.logging(CSV_ENTRY_SIZE)) !void {
    // format
    // Coeff_1_w, Coeff_1_b, ...., Coeff_n_w, Coeff_n_b, phase, outcome)
    // <--comma separated values--->
    // save header
    const headerTemplate: csvHeader = .{ .n_params = configl.N_TERMS };
    const header_str = try std.fmt.allocPrint(alloc, "{f}\n", .{headerTemplate});
    defer alloc.free(header_str);
    try logFile.write(header_str);
}
pub fn saveCoefficientToFile(logFile: *logl.logging(CSV_ENTRY_SIZE), entries: []texelEntry, comptime t: saveType) !u64 {
    // <--comma separated values--->

    const print_freq: usize = 10000;
    var saved: u64 = 0;
    for (0..entries.len) |i| {
        if (i % print_freq == 0) {
            std.debug.print("{d} / {d} \r", .{ i, entries.len });
        }
        if (!entries[i].valid) {
            continue;
        }
        saved += 1;
        if (t == .CSV) {
            const body: csvBody = .{ .entry = &entries[i] };
            var buffer: [CSV_ENTRY_SIZE]u8 = std.mem.zeroes([CSV_ENTRY_SIZE]u8);
            const body_str = try std.fmt.bufPrint(&buffer, "{f}", .{body});
            try logFile.append(body_str);
        } else if (t == .BOOK) {
            var buffer: [CSV_ENTRY_SIZE]u8 = std.mem.zeroes([CSV_ENTRY_SIZE]u8);
            const body_str = try std.fmt.bufPrint(&buffer, "{s} [{d}]\n", .{ entries[i].fen, entries[i].result });
            try logFile.append(utilsl.trimStr(body_str));
        }
    }
    return saved;
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
const saveType = enum { CSV, BOOK };

pub fn test_save(alloc: std.mem.Allocator, logFile: *logl.logging(CSV_ENTRY_SIZE), dataPath: string, comptime t: saveType) !void {
    const allEntries = try filel.getFileLineSize(alloc, dataPath._slice());
    var remainingEntries = allEntries;
    std.debug.print("[DEBUG] test_save: number of lines found: {d}\n", .{allEntries});

    if (t == .CSV) {
        try createEmptyCSVFile(alloc, logFile);
    }
    var skips: usize = 0;
    var saved: u64 = 0;
    while (remainingEntries != 0) {
        std.debug.print("Remaining entries: {d} {d} saved positions\n", .{ remainingEntries, saved });
        remainingEntries = remainingEntries -| configl.N_POSITIONS;
        const entries = try getEntriesFromFile(alloc, dataPath, skips, t != .BOOK);

        printEntriesInfo(entries);
        defer alloc.free(entries);
        saved += try saveCoefficientToFile(logFile, entries, t);
        skips += configl.N_POSITIONS;
    }
}
//https://www.talkchess.com/forum3/viewtopic.php?f=7&t=74403
pub const probCutMoveCount: [6]scoreType = .{ 8, 10, 14, 20, 20, 40 };
pub const dFutilityMargin: scoreType = 300;

// move heuristic "sections"
pub const SEE_values: [13]scoreType = .{ weightl.simplePawnScore, weightl.simpleKnightScore, weightl.simpleBishopScore, weightl.simpleRookScore, weightl.simpleQueenScore, weightl.simpleKingScore, weightl.simplePawnScore, weightl.simpleKnightScore, weightl.simpleBishopScore, weightl.simpleRookScore, weightl.simpleQueenScore, weightl.simpleKingScore, 0 };

pub inline fn depthToMilliDepth(d: i32) milliDepth {
    return d * 1024;
}
pub inline fn milliDepthToDepth(md: milliDepth) typel.depthT {
    return @intCast(@divFloor(md, 1024));
}

pub fn losingCapture(p_state: *const boardl.boardState, move: IMove) bool {
    const otherKingSq = p_state.getKingSq(!p_state.whiteToMove());
    const safetyArea = chess.safetyArea(otherKingSq);
    const to = move.getTo();
    if ((to & safetyArea) != 0 or moveGenl.moveDeliverCheck(p_state, move, false)) {
        return false;
    }
    return SEE(p_state, move) < 0;
}
pub fn losingCaptureT(p_state: *const boardl.boardState, move: IMove, threshold: scoreType) bool {
    const otherKingSq = p_state.getKingSq(!p_state.whiteToMove());
    const safetyArea = chess.safetyArea(otherKingSq);
    const to = move.getTo();
    if ((to & safetyArea) != 0 or moveGenl.moveDeliverCheck(p_state, move, false)) {
        return false;
    }
    return !SEE_threshold(p_state, move, threshold);
}
pub const score = struct {
    s: scoreType = typel.scoreNone,
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

pub fn SEE(p_state: *const boardl.boardState, move: IMove) scoreType {
    if (!move.isCapture()) {
        return 0;
    }
    const to = move.getTo();
    const from = move.getFrom();
    return _SEE_loop(p_state, @enumFromInt(to), @enumFromInt(from), p_state.whiteToMove());
}

// source: https://www.chessprogramming.org/SEE_-_The_Swap_Algorithm
pub fn _SEE_loop(p_state: *const boardl.boardState, toSq: squarel.e_square, fromSq: squarel.e_square, white: bool) scoreType {
    const horizPiece = (p_state.getPieceBB_t(.ROOK) |
        p_state.getPieceBB_t(.QUEEN));

    const diagPiece = (p_state.getPieceBB_t(.BISHOP) |
        p_state.getPieceBB_t(.QUEEN));

    var occ = p_state.b.occupiedBB();

    const attacker = chess.getAllAttackerFromSq(p_state, occ, !white, toSq);
    const defender = chess.getAllAttackerFromSq(p_state, occ, white, toSq);

    const attadef = attacker | defender;
    var fromSet = chess.sqToBitboard(fromSq);
    const mayXray = diagPiece | horizPiece;
    var _attadef = attadef;

    const toSqInfo = squarel.squareInfo.init(toSq);
    const toSqDiags = toSqInfo.getDiagonalsBB();

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
pub fn SEE_threshold(p_state: *const boardl.boardState, move: IMove, threshold: scoreType) bool {
    // returns if moves is atleast better than threshold source: heavely inspired by https://github.com/Adam-Kulju/Patricia/

    const to = move.getTo();
    const from = move.getFrom();
    var gain: scoreType = SEE_values[@intFromEnum(p_state.getPiece(to))] - threshold;
    if (gain < 0) return false;

    gain -= SEE_values[@intFromEnum(p_state.getPiece(from))];
    if (gain >= 0) return true;

    const toSq: typel.e_square = @enumFromInt(to);
    const horizPiece = (p_state.getPieceBB_t(.ROOK) | p_state.getPieceBB_t(.QUEEN));

    const diagPiece = (p_state.getPieceBB_t(.BISHOP) | p_state.getPieceBB_t(.QUEEN));
    const _occ = p_state.b.occupiedBB();
    var occ = _occ ^ chess.xToBitboard(from);
    var white = p_state.whiteToMove();
    var attadef = chess.getAllAttackerFromSq(p_state, _occ, !white, toSq) | chess.getAllAttackerFromSq(p_state, occ, white, toSq);

    while (true) {
        white = !white;
        attadef &= occ;
        const currAtt = attadef & p_state.b.c_occupiedBB[chess.whiteBoolToInt(white)];
        if (currAtt == 0) {
            return white != p_state.whiteToMove();
        }
        // this is always a hit
        var attType: e_pieceType = .PAWN;
        for (0..chess.N_PIECES_TYPES) |i| {
            const p = currAtt & p_state.b.pieceBB[i];
            if (p != 0) {
                const pIdx = chess.bitscan(p);
                occ ^= chess.xToBitboard(pIdx);
                attType = @enumFromInt(i);
                break;
            }
        }
        if (attType == .PAWN or attType == .BISHOP or attType == .QUEEN) {
            attadef |= chess.getBishopAttacks(occ, toSq) & diagPiece;
        }
        if (attType == .ROOK or attType == .QUEEN) {
            attadef |= chess.getRookAttacks(occ, toSq) & horizPiece;
        }
        gain = -gain - SEE_values[@intFromEnum(attType)] - 1;
        if (gain >= 0) {
            return white == p_state.whiteToMove();
        }
    }
    return true;
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
    var allAttack = attDef & p_state.b.c_occupiedBB[chess.whiteBoolToInt(white)];
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

// enough for all texel entry and some more
const CSV_ENTRY_SIZE: usize = 1024;

pub fn saveTexelCsv(alloc: std.mem.Allocator) !void {
    var savePath: string = try string.initFromSlice(alloc, "out/csv/CCRL-4040.[2370489]_13990894pos_eval.csv");
    var name: string = try string.initFromSlice(alloc, "opening/CCRL-4040.[2370489]_shuffled.book");
    //var name: string = try string.initFromSlice(alloc, "opening/E12.33-1M-D12-Resolved.book");

    defer name.free(alloc);
    defer savePath.free(alloc);

    var logFile = try logl.logging(CSV_ENTRY_SIZE).init(alloc, 100_000, savePath, true);
    try test_save(alloc, &logFile, name, .CSV);
    try logFile.free(alloc);
}
pub fn saveTexelBook(alloc: std.mem.Allocator) !void {
    var savePath: string = try string.initFromSlice(alloc, "out/book/CCRL-4040.[2370489]_filtered.book");
    var name: string = try string.initFromSlice(alloc, "opening/CCRL-4040.[2370489]_shuffled.book");

    defer name.free(alloc);
    defer savePath.free(alloc);

    var logFile = try logl.logging(CSV_ENTRY_SIZE).init(alloc, 100_000, savePath, true);
    try test_save(alloc, &logFile, name, .BOOK);
    try logFile.free(alloc);
}

pub fn main(alloc: std.mem.Allocator) !void {
    chess.initAll(false);
    //nnuel.nnueNet = try .init(alloc, configl.NET_PATH);
    //try sanityCheck();
    //try test_main();
    //try saveTexelCsv(alloc);
    try saveTexelBook(alloc);
}
