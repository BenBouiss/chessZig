const chess = @import("chess.zig");
const moveGenl = @import("move_generation.zig");
const filel = @import("file.zig");
const stringl = @import("string.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const statusl = @import("board_status.zig");
const weightl = @import("weights.zig");
const squarel = @import("square.zig");
const mainl = @import("main.zig");
const movel = @import("move.zig");
const schedulerl = @import("search/scheduler.zig");

const std = @import("std");

const e_piece = chess.e_piece;
const e_turn = statusl.e_turn;
const string = stringl.string;
const IMove = movel.IMove;
const moveBBState = movel.moveBBState;
pub const scoreType: type = i32;
pub const weightType: type = i32;
const searchFeatures = schedulerl.searchFeatures;

pub fn evaluate(p_state: *chess.Board_state, values: *heuristicValues) scoreType {
    const allwhiteMoveBB = moveGenl.cst_moveGenBB_extra(p_state, true, .ALL);
    const allblackMoveBB = moveGenl.cst_moveGenBB_extra(p_state, false, .ALL);
    const whiteMoveBB = allwhiteMoveBB.andFn(~p_state.c_occupiedBB[@intFromBool(true)]);
    const blackMoveBB = allblackMoveBB.andFn(~p_state.c_occupiedBB[@intFromBool(false)]);

    var score: scoreType = 0;
    score += evaluate_PSQT(p_state, values);
    score += evaluate_mobility(p_state, &whiteMoveBB, &blackMoveBB, values.MobilityValue);
    score += evaluate_safety(p_state, &whiteMoveBB, &blackMoveBB, values);
    score += evaluate_structure(p_state, &allwhiteMoveBB, &allblackMoveBB, values);
    score += evaluate_pawnStructure(p_state, values.IsolatedPawnValue, values.StackedPawnValue, values.PassedPawnValue);
    return score;
}

pub const heuristicComponents = struct {
    PSQT: scoreType = 0,
    Mobility: scoreType = 0,
    PawnStruct: scoreType = 0,
    Safety: scoreType = 0,
    Structure: scoreType = 0,
    pub fn total(self: *const heuristicComponents) scoreType {
        return self.PSQT + self.Mobility + self.PawnStruct + self.Safety + self.Structure;
    }
    pub fn print(self: *const heuristicComponents) void {
        std.debug.print("Score: PQST = {d}, Mobility = {d}, PawnStruct = {d}, Safety = {d}, Structure = {d}, Total = {d}\n", .{ self.PSQT, self.Mobility, self.PawnStruct, self.Safety, self.Structure, self.total() });
    }
};
pub fn evaluate_debug(p_state: *chess.Board_state, values: *heuristicValues) heuristicComponents {
    const allwhiteMoveBB = moveGenl.cst_moveGenBB_extra(p_state, true, .ALL);
    const allblackMoveBB = moveGenl.cst_moveGenBB_extra(p_state, false, .ALL);
    const whiteMoveBB = allwhiteMoveBB.andFn(~p_state.c_occupiedBB[@intFromBool(true)]);
    const blackMoveBB = allblackMoveBB.andFn(~p_state.c_occupiedBB[@intFromBool(false)]);
    const ret: heuristicComponents = .{
        .PSQT = evaluate_PSQT(p_state, values),
        .Mobility = evaluate_mobility(p_state, &whiteMoveBB, &blackMoveBB, values.MobilityValue),

        .Safety = evaluate_safety(p_state, &whiteMoveBB, &blackMoveBB, values),
        .Structure = evaluate_structure(p_state, &allwhiteMoveBB, &allblackMoveBB, values),

        .PawnStruct = evaluate_pawnStructure(p_state, values.IsolatedPawnValue, values.StackedPawnValue, values.PassedPawnValue),
    };
    return ret;
}

pub fn evaluate_PSQT(p_state: *chess.Board_state, values: *heuristicValues) scoreType {
    var score: scoreType = 0;
    for (0..chess.N_SQUARES) |sq| {
        const piece = p_state.get_piece(@intCast(sq));
        switch (piece) {
            .nEmptySquare, .nWhite, .nBlack => {},

            .nWhitePawn => {
                score += values.Pawn_PSQT[sq] + values.PawnValue;
            },
            .nWhiteBishop => {
                score += values.Bishop_PSQT[sq] + values.BishopValue;
            },
            .nWhiteKnight => {
                score += values.Knight_PSQT[sq] + values.KnightValue;
            },
            .nWhiteRook => {
                score += values.Rook_PSQT[sq] + values.RookValue;
            },
            .nWhiteQueen => {
                score += values.Queen_PSQT[sq] + values.QueenValue;
            },
            .nWhiteKing => {
                score += values.King_PSQT[sq];
            },

            .nBlackPawn => {
                score -= (values.Pawn_PSQT[sq ^ 56] + values.PawnValue);
            },
            .nBlackBishop => {
                score -= (values.Bishop_PSQT[sq ^ 56] + values.BishopValue);
            },
            .nBlackKnight => {
                score -= (values.Knight_PSQT[sq ^ 56] + values.KnightValue);
            },
            .nBlackRook => {
                score -= (values.Rook_PSQT[sq ^ 56] + values.RookValue);
            },
            .nBlackQueen => {
                score -= (values.Queen_PSQT[sq ^ 56] + values.QueenValue);
            },
            .nBlackKing => {
                score -= (values.King_PSQT[sq ^ 56]);
            },
        }
    }
    return score;
}

pub fn evaluate_pawnStructure(p_state: *chess.Board_state, isolatedCoef: scoreType, stackedCoef: scoreType, passedCoef: scoreType) scoreType {
    const wp = p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)];
    const bp = p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)];

    const nWhiteIsolated: i8 = @intCast(chess.l_popcount(chess.isolatedPawns(wp)));
    const nBlackIsolated: i8 = @intCast(chess.l_popcount(chess.isolatedPawns(bp)));
    const isolatedScore = isolatedCoef * @as(scoreType, @intCast(nWhiteIsolated - nBlackIsolated));

    const nWhiteDoubled: i8 = @intCast(chess.l_popcount(chess.stackedPawns(wp)));
    const nBlackDoubled: i8 = @intCast(chess.l_popcount(chess.stackedPawns(bp)));
    const doubledPawnScore = stackedCoef * @as(scoreType, @intCast(nWhiteDoubled - nBlackDoubled));

    const nWhitePassed: i8 = @intCast(chess.l_popcount(chess.passedPawns(wp, bp)));
    const nBlackPassed: i8 = @intCast(chess.l_popcount(chess.passedPawns(bp, wp)));
    const passedPawnScore = passedCoef * @as(scoreType, @intCast(nWhitePassed - nBlackPassed));
    return doubledPawnScore + isolatedScore + passedPawnScore;
}
pub fn evaluate_mobility(p_state: *chess.Board_state, p_whiteMoveBB: *const moveBBState, p_blackMoveBB: *const moveBBState, mobilityCoef: scoreType) scoreType {
    // going to use "raw" mobility only taking board coverage
    // now trying with only legals
    _ = p_state;
    const moveW: i64 = @intCast(p_whiteMoveBB.count());

    const moveB: i64 = @intCast(p_blackMoveBB.count());

    return mobilityCoef * @as(scoreType, @intCast(moveW - moveB));

    // these are insanely expensive
    //const moveW = moveGenl.generateMoveCountLegalMoves(p_state, true);
    //const moveB = moveGenl.generateMoveCountLegalMoves(p_state, false);
    //return simpleMobilityScore * @as(scoreType, @floatFromInt(moveW - moveB));
}
pub fn evaluate_safety(p_state: *chess.Board_state, p_whiteMoveBB: *const moveBBState, p_blackMoveBB: *const moveBBState, values: *heuristicValues) scoreType {
    // counting negative for white as the best safety is not attackers => 0 heuristic
    var retSaf: scoreType = 0;
    const kingWSafety = chess.safetyArea(p_state.wKingSq);
    const kingBSafety = chess.safetyArea(p_state.bKingSq);
    const bKnightAtt: scoreType = @intCast(chess.l_popcount(kingWSafety & p_blackMoveBB.knightMoves));
    const bBishopAtt: scoreType = @intCast(chess.l_popcount(kingWSafety & p_blackMoveBB.bishopMoves));
    const bRookAtt: scoreType = @intCast(chess.l_popcount(kingWSafety & p_blackMoveBB.rookMoves));
    const bQueenAtt: scoreType = @intCast(chess.l_popcount(kingWSafety & p_blackMoveBB.queenMoves));

    const wKnightAtt: scoreType = @intCast(chess.l_popcount(kingBSafety & p_whiteMoveBB.knightMoves));
    const wBishopAtt: scoreType = @intCast(chess.l_popcount(kingBSafety & p_whiteMoveBB.bishopMoves));
    const wRookAtt: scoreType = @intCast(chess.l_popcount(kingBSafety & p_whiteMoveBB.rookMoves));
    const wQueenAtt: scoreType = @intCast(chess.l_popcount(kingBSafety & p_whiteMoveBB.queenMoves));

    retSaf += @intCast(values.SafetyKnightValue * wKnightAtt + values.SafetyBishopValue * wBishopAtt + values.SafetyRookValue * wRookAtt + values.SafetyQueenValue * wQueenAtt);
    retSaf -= @intCast(values.SafetyKnightValue * bKnightAtt + values.SafetyBishopValue * bBishopAtt + values.SafetyRookValue * bRookAtt + values.SafetyQueenValue * bQueenAtt);

    // white is advantaged from a high safety_arr index, more =wPieceAtt are present in the black king vicinity thus it should be counted as positive
    retSaf += @intCast(SAFETY_ARR[@intCast(@min(SAFETY_ARR.len - 1, wKnightAtt + wBishopAtt + wRookAtt + wQueenAtt))]);
    retSaf -= @intCast(SAFETY_ARR[@intCast(@min(SAFETY_ARR.len - 1, bKnightAtt + bBishopAtt + bRookAtt + bQueenAtt))]);
    return retSaf;
}
pub fn evaluate_structure(p_state: *chess.Board_state, p_whiteMoveBB: *const moveBBState, p_blackMoveBB: *const moveBBState, values: *heuristicValues) scoreType {
    // structure protection,
    // use the c_moveBBstate & c_occupied, this returns the safety of each individual pieces against capture
    const w_pieceProtect = p_whiteMoveBB.andFn(p_state.c_occupiedBB[@intFromBool(true)] ^ chess.sqToBitboard(p_state.wKingSq));
    const b_pieceProtect = p_blackMoveBB.andFn(p_state.c_occupiedBB[@intFromBool(false)] ^ chess.sqToBitboard(p_state.bKingSq));
    return (@as(scoreType, @intCast(w_pieceProtect.count())) - @as(scoreType, @intCast(b_pieceProtect.count()))) * values.StructureProtectionValue;
}

pub fn epieceToHeuristic(piece: e_piece, values: *heuristicValues) scoreType {
    switch (piece) {
        .nEmptySquare, .nWhite, .nBlack, .nWhiteKing, .nBlackKing => {
            return 0;
        },
        .nWhitePawn, .nBlackPawn => {
            return values.PawnValue;
        },
        .nWhiteBishop, .nBlackBishop => {
            return values.BishopValue;
        },
        .nWhiteKnight, .nBlackKnight => {
            return values.KnightValue;
        },
        .nWhiteRook, .nBlackRook => {
            return values.RookValue;
        },
        .nWhiteQueen, .nBlackQueen => {
            return values.QueenValue;
        },
    }
}
//pub const m= struct {
//    index: usize,
//    fromPiece: scoreType,
//    toPiece: scoreType,
//};

pub fn texelEvaluation(p_state: *chess.Board_state) scoreType {
    // need to evaluate the pqst more efficiently ie with same method from past heuristic
    const entry = texelEntry.initFromBoardFast(p_state);
    var ret = texelEvaluation_PSQT(p_state, &weightl.weights, &entry.pFactors) + texelEvaluation_mobility(p_state, &weightl.weights, &entry.pFactors) + texelEvaluation_pawnStructure(p_state, &weightl.weights, &entry.pFactors);
    if (comptime configl.TUNE_SAFETY) {
        ret += texelEvaluation_safety(p_state, &weightl.weights, &entry.pFactors);
    }
    return ret;
}
pub fn texelEvaluationSlow(p_state: *chess.Board_state) scoreType {
    var entry = texelEntry.initFromBoard(p_state);
    return entry.get_eval(&weightl.weights);
}
pub fn texelEvaluation_mobility(p_state: *chess.Board_state, w: *coeffTuple, pfactors: *const [N_PHASES]scoreType) scoreType {
    const moveW: i64 = @intCast(moveGenl.cst_moveGenBB(p_state, true).count());
    const moveB: i64 = @intCast(moveGenl.cst_moveGenBB(p_state, false).count());
    return (@as(scoreType, @intCast(moveW - moveB))) * (w.val[MG].val[configl.TEXEL_MOVE_COUNT_IDX] * pfactors[MG] + w.val[EG].val[configl.TEXEL_MOVE_COUNT_IDX] * pfactors[EG]);
}
pub fn texelEvaluation_pawnStructure(p_state: *chess.Board_state, w: *coeffTuple, pfactors: *const [N_PHASES]scoreType) scoreType {
    const isolatedQt = @as(scoreType, @intCast(chess.il_popcount(chess.isolatedPawns(p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)])) - chess.il_popcount(chess.isolatedPawns(p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)]))));
    const isolatedScore = isolatedQt * (w.val[MG].val[configl.TEXEL_PAWN_ISOL_IDX] * pfactors[MG] + w.val[EG].val[configl.TEXEL_PAWN_ISOL_IDX] * pfactors[EG]);

    const doubledPawnQt = @as(scoreType, @intCast(chess.il_popcount(chess.stackedPawns(p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)])) - chess.il_popcount(chess.stackedPawns(p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)]))));
    const doublePawnScore = doubledPawnQt * (w.val[MG].val[configl.TEXEL_PAWN_STACKED_IDX] * pfactors[MG] + w.val[EG].val[configl.TEXEL_PAWN_STACKED_IDX] * pfactors[EG]);
    return isolatedScore + doublePawnScore;
}
pub fn texelEvaluation_safety(p_state: *chess.Board_state, w: *coeffTuple, pfactors: *const [N_PHASES]scoreType) scoreType {
    const kingW = squarel.squareInfo.init(p_state.getKingSq(true));
    const kingB = squarel.squareInfo.init(p_state.getKingSq(false));
    const maskW = kingW.getAllAttackingSquares();
    const maskB = kingB.getAllAttackingSquares();

    const pawnSafety = @as(weightType, @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)]) - chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)]))) * ((w.val[MG].val[configl.TEXEL_SAFETY_PAWN_PROX_IDX] * pfactors[MG] + w.val[EG].val[configl.TEXEL_SAFETY_PAWN_PROX_IDX] * pfactors[EG]));

    const bishopSafety = @as(weightType, @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackBishop)]) - chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhiteBishop)]))) * ((w.val[MG].val[configl.TEXEL_SAFETY_BISHOP_PROX_IDX] * pfactors[MG] + w.val[EG].val[configl.TEXEL_SAFETY_BISHOP_PROX_IDX] * pfactors[EG]));

    const knightSafety = @as(weightType, @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackKnight)]) - chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhiteKnight)]))) * ((w.val[MG].val[configl.TEXEL_SAFETY_KNIGHT_PROX_IDX] * pfactors[MG] + w.val[EG].val[configl.TEXEL_SAFETY_KNIGHT_PROX_IDX] * pfactors[EG]));

    const rookSafety = @as(weightType, @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackRook)]) - chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhiteRook)]))) * ((w.val[MG].val[configl.TEXEL_SAFETY_ROOK_PROX_IDX] * pfactors[MG] + w.val[EG].val[configl.TEXEL_SAFETY_ROOK_PROX_IDX] * pfactors[EG]));

    const queenSafety = @as(weightType, @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)]) - chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]))) * ((w.val[MG].val[configl.TEXEL_SAFETY_QUEEN_PROX_IDX] * pfactors[MG] + w.val[EG].val[configl.TEXEL_SAFETY_QUEEN_PROX_IDX] * pfactors[EG]));
    return pawnSafety + bishopSafety + knightSafety + rookSafety + queenSafety;
}

pub fn texelEvaluation_PSQT(p_state: *chess.Board_state, w: *coeffTuple, pfactors: *const [N_PHASES]scoreType) scoreType {
    var score: scoreType = 0;
    for (0..chess.N_SQUARES) |sq| {
        const piece = p_state.get_piece(@intCast(sq));
        switch (piece) {
            .nEmptySquare, .nWhite, .nBlack => {},

            .nWhitePawn => {
                score += pfactors[MG] * (w.val[MG].val[configl.TEXEL_PAWN_PSQT_IDX + sq] + w.val[MG].val[configl.TEXEL_PAWN_COUNT_IDX]);
                score += pfactors[EG] * (w.val[EG].val[configl.TEXEL_PAWN_PSQT_IDX + sq] + w.val[EG].val[configl.TEXEL_PAWN_COUNT_IDX]);
            },
            .nWhiteBishop => {
                score += pfactors[MG] * (w.val[MG].val[configl.TEXEL_BISHOP_PSQT_IDX + sq] + w.val[MG].val[configl.TEXEL_BISHOP_COUNT_IDX]);
                score += pfactors[EG] * (w.val[EG].val[configl.TEXEL_BISHOP_PSQT_IDX + sq] + w.val[EG].val[configl.TEXEL_BISHOP_COUNT_IDX]);
            },
            .nWhiteKnight => {
                score += pfactors[MG] * (w.val[MG].val[configl.TEXEL_KNIGHT_PSQT_IDX + sq] + w.val[MG].val[configl.TEXEL_KNIGHT_COUNT_IDX]);
                score += pfactors[EG] * (w.val[EG].val[configl.TEXEL_KNIGHT_PSQT_IDX + sq] + w.val[EG].val[configl.TEXEL_KNIGHT_COUNT_IDX]);
            },
            .nWhiteRook => {
                score += pfactors[MG] * (w.val[MG].val[configl.TEXEL_ROOK_PSQT_IDX + sq] + w.val[MG].val[configl.TEXEL_ROOK_COUNT_IDX]);
                score += pfactors[EG] * (w.val[EG].val[configl.TEXEL_ROOK_PSQT_IDX + sq] + w.val[EG].val[configl.TEXEL_ROOK_COUNT_IDX]);
            },
            .nWhiteQueen => {
                score += pfactors[MG] * (w.val[MG].val[configl.TEXEL_QUEEN_PSQT_IDX + sq] + w.val[MG].val[configl.TEXEL_QUEEN_COUNT_IDX]);
                score += pfactors[EG] * (w.val[EG].val[configl.TEXEL_QUEEN_PSQT_IDX + sq] + w.val[EG].val[configl.TEXEL_QUEEN_COUNT_IDX]);
            },
            .nWhiteKing => {
                score += pfactors[MG] * (w.val[MG].val[configl.TEXEL_KING_PSQT_IDX + sq]);
                score += pfactors[EG] * (w.val[EG].val[configl.TEXEL_KING_PSQT_IDX + sq]);
            },

            .nBlackPawn => {
                score -= pfactors[MG] * (w.val[MG].val[configl.TEXEL_PAWN_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[MG].val[configl.TEXEL_PAWN_COUNT_IDX]);
                score -= pfactors[EG] * (w.val[EG].val[configl.TEXEL_PAWN_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[EG].val[configl.TEXEL_PAWN_COUNT_IDX]);
            },
            .nBlackBishop => {
                score -= pfactors[MG] * (w.val[MG].val[configl.TEXEL_BISHOP_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[MG].val[configl.TEXEL_BISHOP_COUNT_IDX]);
                score -= pfactors[EG] * (w.val[EG].val[configl.TEXEL_BISHOP_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[EG].val[configl.TEXEL_BISHOP_COUNT_IDX]);
            },
            .nBlackKnight => {
                score -= pfactors[MG] * (w.val[MG].val[configl.TEXEL_KNIGHT_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[MG].val[configl.TEXEL_KNIGHT_COUNT_IDX]);
                score -= pfactors[EG] * (w.val[EG].val[configl.TEXEL_KNIGHT_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[EG].val[configl.TEXEL_KNIGHT_COUNT_IDX]);
            },
            .nBlackRook => {
                score -= pfactors[MG] * (w.val[MG].val[configl.TEXEL_ROOK_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[MG].val[configl.TEXEL_ROOK_COUNT_IDX]);
                score -= pfactors[EG] * (w.val[EG].val[configl.TEXEL_ROOK_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[EG].val[configl.TEXEL_ROOK_COUNT_IDX]);
            },
            .nBlackQueen => {
                score -= pfactors[MG] * (w.val[MG].val[configl.TEXEL_QUEEN_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[MG].val[configl.TEXEL_QUEEN_COUNT_IDX]);
                score -= pfactors[EG] * (w.val[EG].val[configl.TEXEL_QUEEN_PSQT_IDX + (chess.N_SQUARES - 1 - sq)] + w.val[EG].val[configl.TEXEL_QUEEN_COUNT_IDX]);
            },
            .nBlackKing => {
                score -= pfactors[MG] * (w.val[MG].val[configl.TEXEL_KING_PSQT_IDX + (chess.N_SQUARES - 1 - sq)]);
                score -= pfactors[EG] * (w.val[EG].val[configl.TEXEL_KING_PSQT_IDX + (chess.N_SQUARES - 1 - sq)]);
            },
        }
    }
    return score;
}

pub fn matDotScoreChess(m1: [chess.N_SQUARES]scoreType, m2: [chess.N_SQUARES]scoreType) scoreType {
    var ret: scoreType = 0;
    for (0..chess.N_SQUARES) |i| {
        ret += (m1[i] * m2[i]);
    }
    return ret;
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
    if (s.containsE("pawn", .ignoreCase)) {
        globalHeuristic.Pawn_PSQT = buffer;
    } else if (s.containsE("knight", .ignoreCase)) {
        globalHeuristic.Knight_PSQT = buffer;
    } else if (s.containsE("bishop", .ignoreCase)) {
        globalHeuristic.Bishop_PSQT = buffer;
    } else if (s.containsE("rook", .ignoreCase)) {
        globalHeuristic.Rook_PSQT = buffer;
    } else if (s.containsE("queen", .ignoreCase)) {
        globalHeuristic.Queen_PSQT = buffer;
    } else if (s.containsE("king", .ignoreCase)) {
        globalHeuristic.King_PSQT = buffer;
    } else {
        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: unknown token \n[", .{});
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

    if (s.containsE("isolatedPawn", .ignoreCase)) {
        globalHeuristic.IsolatedPawnValue = _val;
    } else if (s.containsE("mobility", .ignoreCase)) {
        globalHeuristic.MobilityValue = _val;
    } else if (s.containsE("stackedPawn", .ignoreCase)) {
        globalHeuristic.StackedPawnValue = _val;
    } else if (s.containsE("passedPawn", .ignoreCase)) {
        globalHeuristic.PassedPawnValue = _val;
    } else if (s.containsE("safetyKnight", .ignoreCase)) {
        globalHeuristic.SafetyKnightValue = _val;
    } else if (s.containsE("safetyBishop", .ignoreCase)) {
        globalHeuristic.SafetyBishopValue = _val;
    } else if (s.containsE("safetyRook", .ignoreCase)) {
        globalHeuristic.SafetyRookValue = _val;
    } else if (s.containsE("safetyQueen", .ignoreCase)) {
        globalHeuristic.SafetyQueenValue = _val;
    } else if (s.containsE("structureProtection", .ignoreCase)) {
        globalHeuristic.StructureProtectionValue = _val;
    } else {
        if (debug) {
            std.debug.print("[DEBUG] modifyHeuristicWeight: unknown token {s}\n", .{s._slice()});
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
    MobilityValue: scoreType = weightl.simpleMobilityScore,
    IsolatedPawnValue: scoreType = weightl.simpleIsolatedPawnScore,
    StackedPawnValue: scoreType = weightl.simpleStackedPawnScore,
    PassedPawnValue: scoreType = weightl.simplePassedPawnScore,

    SafetyBishopValue: scoreType = weightl.simpleSafetyBishopScore,
    SafetyKnightValue: scoreType = weightl.simpleSafetyKnightScore,
    SafetyRookValue: scoreType = weightl.simpleSafetyRookScore,
    SafetyQueenValue: scoreType = weightl.simpleQueenScore,

    StructureProtectionValue: scoreType = weightl.simpleStructureProtectionScore,

    Pawn_PSQT: [chess.N_SQUARES]scoreType = weightl.pawnScoreArr,
    Bishop_PSQT: [chess.N_SQUARES]scoreType = weightl.bishopScoreArr,
    Knight_PSQT: [chess.N_SQUARES]scoreType = weightl.knightScoreArr,
    Rook_PSQT: [chess.N_SQUARES]scoreType = weightl.rookScoreArr,
    Queen_PSQT: [chess.N_SQUARES]scoreType = weightl.queenScoreArr,
    King_PSQT: [chess.N_SQUARES]scoreType = weightl.kingScoreArr,

    // other more complex values may be inserted below
};

// source: https://www.chessprogramming.org/King_Safety
const SAFETY_ARR: [8]scoreType = [8]scoreType{ 0, 0, 50, 75, 88, 94, 97, 99 };

var STRUCTURE_PROTECTION: scoreType = 1;
const N_PHASES: usize = 2;
const N_WEIGHTS: usize = 256;
const NTERMS: usize = 1024;
pub var globalHeuristic: heuristicValues = .{};

// value between 0 and 1
const TUNE_K: scoreType = 5;

pub const MG: usize = 0;
pub const EG: usize = 1;

pub fn computePhase(p_board: *chess.Board_state) scoreType {
    const phase: i32 = 24 - 4 * (p_board.getPieceCount(.nWhiteQueen) + p_board.getPieceCount(.nBlackQueen)) - 2 * (p_board.getPieceCount(.nWhiteRook) + p_board.getPieceCount(.nBlackRook)) - (p_board.getPieceCount(.nWhiteBishop) + p_board.getPieceCount(.nBlackBishop)) - (p_board.getPieceCount(.nWhiteKnight) + p_board.getPieceCount(.nBlackKnight));
    const _phase: scoreType = @intCast(phase);
    return @divFloor(256 * (24 - _phase), 24);
}
pub const texelEntry = struct {
    //
    //seval: i32 = 0,
    // phase value describing how far the game progressed
    phase: scoreType = 0.0,
    // turn of the extracted fen
    turn: bool = true,

    //
    eval: i32 = 0,

    //optional afterwards
    //complexity: i32,
    //safety: [chess.NUMBER_PLAYER]i32,

    // 0.0 black win, 0.5 draw, 1.0 white win
    result: f32 = -1,
    //
    //sfactor: scoreType = -1,
    pFactors: [N_PHASES]scoreType = std.mem.zeroes([N_PHASES]scoreType),

    // coeffs provided by the board reading the fen
    // C vects from the eq with L the weight
    // E = L . (Cw - Cb)
    tuples: coeffVector = .{},
    pub fn initFromBoard(p_state: *chess.Board_state) texelEntry {
        var ret: texelEntry = .{};
        ret.phase = computePhase(p_state);
        ret.pFactors[MG] = @divFloor(256 - ret.phase, 256);
        ret.pFactors[EG] = @divFloor(1 * ret.phase, 256);
        ret.turn = p_state.whiteToMove();
        try getCoeffsFromBoard(p_state, &ret.tuples);
        return ret;
    }
    pub fn initFromBoardFast(p_state: *chess.Board_state) texelEntry {
        var ret: texelEntry = .{};
        ret.phase = computePhase(p_state);
        ret.pFactors[MG] = @divFloor(256 - ret.phase, 256);
        ret.pFactors[EG] = @divFloor(1 * ret.phase, 256);
        return ret;
    }

    pub fn set_fen(p_self: *texelEntry, alloc: std.mem.Allocator, fen: []const u8, result: f32) !void {
        p_self.tuples = .{};
        p_self.result = result;
        var board = chess.getBoardFromFen(alloc, fen) catch {
            std.debug.print("[ERROR] set_fen: error while using the fen: '{s}'\n", .{fen});
            @panic("");
        };
        defer board.free(alloc);
        const phase: i32 = 24 - 4 * (board.getPieceCount(.nWhiteQueen) + board.getPieceCount(.nBlackQueen)) - 2 * (board.getPieceCount(.nWhiteRook) + board.getPieceCount(.nBlackRook)) - (board.getPieceCount(.nWhiteBishop) + board.getPieceCount(.nBlackBishop)) - (board.getPieceCount(.nWhiteKnight) + board.getPieceCount(.nBlackKnight));
        const _phase: scoreType = @intCast(phase);

        p_self.phase = @divFloor((256 * (24 - _phase)), 24);

        p_self.pFactors[MG] = @divFloor(256 - p_self.phase, 256);
        p_self.pFactors[EG] = @divFloor(1 * p_self.phase, 256);

        p_self.turn = board.whiteToMove();
        //p_self.seval = @intFromFloat(pastHeuristic(&board));
        //if (!board.whiteToMove()) {
        //    p_self.seval = -p_self.seval;
        //}
        try getCoeffsFromBoard(&board, &p_self.tuples);
        return;
    }
    pub fn print(p_self: *texelEntry) void {
        //
        std.debug.print("Printing texelEntry: \n", .{});
        std.debug.print("Res: {d}\n", .{p_self.result});
        //std.debug.print("Res: {d}, seval: {d}\n", .{ p_self.result, p_self.seval });
        std.debug.print("Coefficients array: ", .{});
        p_self.tuples.print();
    }
    pub fn get_eval(p_self: *texelEntry, weights: *coeffTuple) scoreType {
        // simple eval here
        //const _phase: scoreType = @floatFromInt(p_self.phase);

        var deltaC = p_self.tuples.get_delta();
        const E_mg = weights.val[MG].dotProduct(&deltaC);
        const E_eg = weights.val[EG].dotProduct(&deltaC);

        return p_self.pFactors[MG] * E_mg + (p_self.pFactors[EG] * E_eg);
    }
};

pub fn sigmoid(comptime T: type, x: T) f32 {
    return (1.0 / (1.0 + std.math.exp(@as(f32, @floatFromInt(-TUNE_K * x)))));
}

pub fn getCoeffsFromBoard(p_state: *chess.Board_state, p_out: *coeffVector) !void {
    // Normal:
    var idx: usize = 0;
    if (configl.TUNE_NORMAL) {
        // piece counts
        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhitePawn)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackPawn)) });
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhiteBishop)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackBishop)) });
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhiteKnight)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackKnight)) });
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhiteRook)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackRook)) });
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(p_state.getPieceCount(.nWhiteQueen)), .bcoeff = @intCast(p_state.getPieceCount(.nBlackQueen)) });
        idx += 1;

        // mobility
        var moveW = moveGenl.cst_moveGenBB(p_state, true);
        var moveB = moveGenl.cst_moveGenBB(p_state, false);

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(moveW.count()), .bcoeff = @intCast(moveB.count()) });
        idx += 1;

        // pawn structure
        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.il_popcount(chess.isolatedPawns(p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)]))), .bcoeff = @intCast(chess.il_popcount(chess.isolatedPawns(p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)]))) });
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.il_popcount(chess.stackedPawns(p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)]))), .bcoeff = @intCast(chess.il_popcount(chess.stackedPawns(p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)]))) });
        idx += 1;

        p_out.add1DCoeff(&getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)]), &getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)])), &idx);

        p_out.add1DCoeff(&getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteBishop)]), &getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackBishop)])), &idx);

        p_out.add1DCoeff(&getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteKnight)]), &getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackKnight)])), &idx);

        p_out.add1DCoeff(&getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteRook)]), &getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackRook)])), &idx);

        p_out.add1DCoeff(&getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]), &getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)])), &idx);

        p_out.add1DCoeff(&getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteKing)]), &getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackKing)])), &idx);
    }
    if (comptime (configl.TUNE_SAFETY)) {
        const kingW = squarel.squareInfo.init(p_state.getKingSq(true));
        const kingB = squarel.squareInfo.init(p_state.getKingSq(false));
        const maskW = kingW.getAllAttackingSquares();
        const maskB = kingB.getAllAttackingSquares();

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)])), .bcoeff = @intCast(chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)])) });
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackBishop)])), .bcoeff = @intCast(chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhiteBishop)])) });
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackKnight)])), .bcoeff = @intCast(chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhiteKnight)])) });
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackRook)])), .bcoeff = @intCast(chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhiteRook)])) });
        idx += 1;

        p_out.appendCoeff(.{ .index = @intCast(idx), .wcoeff = @intCast(chess.il_popcount(maskW & p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)])), .bcoeff = @intCast(chess.il_popcount(maskB & p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)])) });
        idx += 1;
    }

    if (configl.TUNE_COMPLEXITY) {}
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
        defer file.close();
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
    pub fn get_delta(p_self: *coeffVector) NVector {
        return p_self.items[@intFromEnum(e_turn.WHITE)].substractVect(&p_self.items[@intFromEnum(e_turn.BLACK)]);
    }
};

pub fn getEntriesFromFile(alloc: std.mem.Allocator, path: string) ![]texelEntry {
    var tokens = try filel.getTokensFromFileAlloc(alloc, path._slice(), '\n', configl.N_POSITIONS);
    var entries: []texelEntry = try alloc.alloc(texelEntry, configl.N_POSITIONS);

    for (0..configl.N_POSITIONS) |i| {
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
        try entries[i].set_fen(alloc, s._slice(), foutcome);
        //entries[i].print();
    }
    defer stringl.freeArrayList_string(alloc, &tokens);
    return entries;
}

pub fn mainTexel(alloc: std.mem.Allocator, path: string) !void {
    const entries = try getEntriesFromFile(alloc, path);
    defer alloc.free(entries);
    printEntriesInfo(entries);
    try optimization_entrypoint(alloc, entries);

    return;
}
pub const csvHeader = struct {
    templateEntry: *texelEntry = undefined,
    pub fn format(self: csvHeader, writer: *std.Io.Writer) !void {
        const tuple = self.templateEntry.tuples;
        for (0..tuple.len) |i| {
            try writer.print("Coeff_{d}_w,Coeff_{d}_b,", .{ i, i });
        }

        try writer.print("Phase,Outcome", .{});
    }
};
pub const csvBody = struct {
    entry: *texelEntry = undefined,
    pub fn format(self: csvBody, writer: *std.Io.Writer) !void {
        const tuple = self.entry.tuples;
        for (0..tuple.len) |i| {
            try writer.print("{d},{d},", .{ tuple.items[@intFromEnum(e_turn.WHITE)].val[i], tuple.items[@intFromEnum(e_turn.BLACK)].val[i] });
        }

        try writer.print("{d},{d}", .{ self.entry.phase, self.entry.result });
    }
};
pub fn saveCoefficientToFile(alloc: std.mem.Allocator, entries: []texelEntry, path: string) !void {
    // format
    // Coeff_1_w, Coeff_1_b, ...., Coeff_n_w, Coeff_n_b, phase, outcome)
    // <--comma separated values--->

    const file = try std.fs.cwd().createFile(path._slice(), .{ .read = true });
    defer file.close();

    // save header
    const headerTemplate: csvHeader = .{ .templateEntry = &entries[0] };

    const header_str = try std.fmt.allocPrint(alloc, "{f}\n", .{headerTemplate});
    defer alloc.free(header_str);
    _ = try file.write(header_str);
    // save
    const print_freq: usize = 10000;
    for (0..entries.len) |i| {
        if (i % print_freq == 0) {
            std.debug.print("{d} / {d} \r", .{ i, entries.len });
        }
        const body: csvBody = .{ .entry = &entries[i] };
        const body_str = try std.fmt.allocPrint(alloc, "{f}\n", .{body});
        defer alloc.free(body_str);
        _ = try file.write(body_str);
    }
}

pub fn printEntriesInfo(entries: []const texelEntry) void {
    var buffer: [3]usize = .{ 0, 0, 0 };
    for (0..entries.len) |i| {
        buffer[@intFromFloat(entries[i].result * 2)] += 1;
    }
    std.debug.print("[DEBUG] printEntriesInfo: Breakdown of entries found 0: {d}, 0.5: {d}, 1: {d}\n", .{ buffer[0], buffer[1], buffer[2] });
}

pub fn test_entries(entries: []const texelEntry, weights: *coeffTuple) !void {
    for (0..entries.len) |i| {
        var ent = entries[i];
        // MSE by default
        const eval = ent.get_eval(weights);
        std.debug.print("[DEBUG] test_entries: eval with random weights: {d}\n", .{eval});
    }
}

pub fn optimization_entrypoint(alloc: std.mem.Allocator, entries: []const texelEntry) !void {
    if (configl.USE_ADAGRAD) {
        try optimization_adagrad(alloc, entries);
    } else {
        try optimization_std(alloc, entries);
    }
}
pub fn optimization_std(alloc: std.mem.Allocator, entries: []const texelEntry) !void {
    // init alleat weight
    var weights: coeffTuple = coeffTuple.init(configl.SEED, configl.TUNER_START_FROM_OLD);
    var bestWeights = weights.copy();
    var bestScore: scoreType = -1;
    var context: optimizationContext = .{};
    for (0..configl.EPOCH) |ep| {
        // I hate this
        context.on_epoch_start();
        weights = weightUpdate(&context, entries, &weights);
        var err: f32 = 0;
        for (0..entries.len) |i| {
            var ent = entries[i];
            // MSE by default
            const eval: f32 = sigmoid(scoreType, ent.get_eval(&weights));
            err += std.math.pow(f32, @as(f32, @floatFromInt(ent.result)) - eval, 2);
        }
        if (err < bestScore or bestScore == -1) {
            bestScore = err;
            bestWeights = weights.copy();
        }
        std.debug.print("[RESULT] optimization_entrypoint: epoch {d} error {d} ({d})\n", .{ ep, err / @as(scoreType, @floatFromInt(entries.len)), err });
    }

    std.debug.print("[RESULT] optimization_entrypoint: best found weights with err = ({d})\n", .{bestScore});
    try bestWeights.saveToFile(alloc, "logs/tmp_test.txt");
    return;
}
pub fn optimization_adagrad(alloc: std.mem.Allocator, entries: []const texelEntry) !void {
    // init alleat weight
    var weights: coeffTuple = coeffTuple.init(configl.SEED, configl.TUNER_START_FROM_OLD);
    var bestWeights = weights.copy();
    var bestScore: scoreType = -1;
    var context: optimizationContext = .{};
    var adagrad: coeffTuple = .{};
    for (0..configl.EPOCH) |ep| {
        // I hate this
        context.on_epoch_start();
        weights = adaGradWeightUpdate(&context, entries, &weights, &adagrad);
        var err: scoreType = 0;
        for (0..entries.len) |i| {
            var ent = entries[i];
            // MSE by default
            err += std.math.pow(scoreType, ent.result - sigmoid(scoreType, ent.get_eval(&weights)), 2);
        }
        if (err < bestScore or bestScore == -1) {
            bestScore = err;
            bestWeights = weights.copy();
        }
        std.debug.print("[RESULT] optimization_entrypoint: epoch {d}, error {d} ({d}), learning rate {d}\n", .{ ep, err / @as(scoreType, @floatFromInt(entries.len)), err, context.learningRate });
    }

    std.debug.print("[RESULT] optimization_entrypoint: best found weights with err = ({d})\n", .{bestScore});
    try bestWeights.saveToFile(alloc, "logs/tmp_test.txt");
    return;
}
pub const optimizationContext = struct {
    epoch: usize = 0,
    learningRate: scoreType = configl.LEARNING_RATE,
    learningRate_freq: usize = configl.LEARNING_RATE_FREQ,

    pub fn on_epoch_start(p_self: *optimizationContext) void {
        p_self.epoch += 1;
        if ((p_self.epoch % p_self.learningRate_freq) == 0) {
            p_self.learningRate *= configl.LEARNING_RATE_DROP;
            p_self.learningRate = @max(p_self.learningRate, configl.LEARNING_RATE_MIN);
        }
    }
};

pub fn weightUpdate(ctx: *optimizationContext, entries: []const texelEntry, weights: *coeffTuple) coeffTuple {
    var newWeights: coeffTuple = weights.copy();
    const batchAmount: usize = @intFromFloat(@ceil(@as(scoreType, @floatFromInt(entries.len)) / configl.BATCH_SIZE));
    // single sample batch at first
    // for the multi sample batch can also send a slice of the entries to the compute gradient function

    for (0..batchAmount) |batch| {
        // compute gradient for each batch
        // then apply it onto the next set of weights
        //var gradient
        var grad = computeGradient(entries[batch * configl.BATCH_SIZE .. (batch + 1) * configl.BATCH_SIZE], weights);

        //TODO Find better way to keep track of the learning
        grad.val[MG].multiplyEq(ctx.learningRate);
        grad.val[EG].multiplyEq(ctx.learningRate);

        // still wrong? should be a add instead of substract
        newWeights.val[MG].substractVectEq(&grad.val[MG]);
        newWeights.val[EG].substractVectEq(&grad.val[EG]);
        //newWeights.val[MG].addVectEq(&grad.val[MG]);
        //newWeights.val[EG].addVectEq(&grad.val[EG]);
    }
    return newWeights;
}
pub fn adaGradWeightUpdate(ctx: *optimizationContext, entries: []const texelEntry, weights: *coeffTuple, adagradCoeff: *coeffTuple) coeffTuple {
    var newWeights: coeffTuple = weights.copy();
    const batchAmount: usize = @intFromFloat(@ceil(@as(scoreType, @floatFromInt(entries.len)) / configl.BATCH_SIZE));
    // single sample batch at first
    // for the multi sample batch can also send a slice of the entries to the compute gradient function

    for (0..batchAmount) |batch| {
        // compute gradient for each batch
        // then apply it onto the next set of weights
        const grad = computeGradient(entries[batch * configl.BATCH_SIZE .. (batch + 1) * configl.BATCH_SIZE], weights);

        for (0..configl.N_TERMS) |i| {
            adagradCoeff.val[MG].val[i] += std.math.pow(scoreType, 2 * grad.val[MG].val[i] / configl.BATCH_SIZE, 2.0);
            adagradCoeff.val[EG].val[i] += std.math.pow(scoreType, 2 * grad.val[EG].val[i] / configl.BATCH_SIZE, 2.0);

            // still have this problem with - instead of + >:)
            newWeights.val[MG].val[i] -= (TUNE_K * 2.0 / configl.BATCH_SIZE) * grad.val[MG].val[i] * (ctx.learningRate / std.math.sqrt(1e-8 + adagradCoeff.val[MG].val[i]));
            newWeights.val[EG].val[i] -= (TUNE_K * 2.0 / configl.BATCH_SIZE) * grad.val[EG].val[i] * (ctx.learningRate / std.math.sqrt(1e-8 + adagradCoeff.val[EG].val[i]));
        }
    }
    return newWeights;
}
pub fn computeGradient(batch_entries: []const texelEntry, weights: *coeffTuple) coeffTuple {
    var ret: coeffTuple = .{};
    for (0..batch_entries.len) |j| {
        var ent = batch_entries[j];
        // this is constant between epochs
        var deltaC = ent.tuples.get_delta();

        const s = sigmoid(scoreType, ent.get_eval(weights));
        const X = @as(scoreType, @floatCast(TUNE_K)) * s * (ent.result - s) * (1 - s);

        var mg_tmp = deltaC.copy();
        mg_tmp.multiplyEq(X * ent.pFactors[MG]);
        ret.val[MG].addVectEq(&mg_tmp);

        var eg_tmp = deltaC.copy();
        eg_tmp.multiplyEq(X * ent.pFactors[EG]);
        ret.val[EG].addVectEq(&eg_tmp);
    }
    ret.val[MG].multiplyEq(@as(scoreType, @divFloor(-2, batch_entries.len)));
    ret.val[EG].multiplyEq(@as(scoreType, @divFloor(-2, batch_entries.len)));

    return ret;
}
pub fn test_main() !void {
    var board = try chess.getBoardFromFen(mainl.GLOBAL_ALLOC, chess.DEFAULT_FEN);
    std.debug.print("[DEBUG] test_main: eval using default weight on default fen: {d}\n", .{texelEvaluation(&board)});
    @panic("");
}
pub fn sanityCheck() !void {
    var path: string = try string.initFromSlice(mainl.GLOBAL_ALLOC, "opening/E12.33-1M-D12-Resolved.book");
    defer path.free(mainl.GLOBAL_ALLOC);

    var tokens = try filel.getTokensFromFileAlloc(mainl.GLOBAL_ALLOC, path._slice(), '\n', configl.N_POSITIONS);
    defer stringl.freeArrayList_string(mainl.GLOBAL_ALLOC, &tokens);
    var err: f32 = 0;
    for (tokens.items) |fen| {
        var foutcome: f32 = 0;
        if (fen.containsE("0.5", .ignoreCase)) {
            foutcome = 0.5;
        } else if (fen.containsE("1.0", .ignoreCase)) {
            foutcome = 1;
        }
        var board = try chess.getBoardFromFen(mainl.GLOBAL_ALLOC, fen._slice());
        //err += std.math.pow(scoreType, (sigmoid(scoreType, texelEvaluation(&board)) - foutcome), 2);

        const eval: f32 = sigmoid(scoreType, texelEvaluation(&board));
        err += std.math.pow(f32, foutcome - eval, 2);
        defer board.free(mainl.GLOBAL_ALLOC);
    }

    std.debug.print("[RESULT] sanityCheck: error {d} ({d})\n", .{ err / @as(f32, @floatFromInt(tokens.items.len)), err });

    var board = try chess.getBoardFromFen(mainl.GLOBAL_ALLOC, chess.DEFAULT_FEN);
    const raw_eval = texelEvaluation(&board);
    std.debug.print("[DEBUG] sanityCheck: eval using default weight on default fen: {d}, rounded: {d}\n", .{ raw_eval, sigmoid(scoreType, raw_eval) });
}
pub fn test_save(alloc: std.mem.Allocator, dataPath: string, savePath: string) !void {
    //
    const entries = try getEntriesFromFile(alloc, dataPath);
    defer alloc.free(entries);
    try saveCoefficientToFile(alloc, entries, savePath);
}

// move heuristic "sections"
// https://github.com/maksimKorzh/chess_programming MVA_lva table
pub const mvv_lva: [12][12]scoreType = .{ .{ 105, 205, 305, 405, 505, 605, 105, 205, 305, 405, 505, 605 }, .{ 104, 204, 304, 404, 504, 604, 104, 204, 304, 404, 504, 604 }, .{ 103, 203, 303, 403, 503, 603, 103, 203, 303, 403, 503, 603 }, .{ 102, 202, 302, 402, 502, 602, 102, 202, 302, 402, 502, 602 }, .{ 101, 201, 301, 401, 501, 601, 101, 201, 301, 401, 501, 601 }, .{ 100, 200, 300, 400, 500, 600, 100, 200, 300, 400, 500, 600 }, .{ 105, 205, 305, 405, 505, 605, 105, 205, 305, 405, 505, 605 }, .{ 104, 204, 304, 404, 504, 604, 104, 204, 304, 404, 504, 604 }, .{ 103, 203, 303, 403, 503, 603, 103, 203, 303, 403, 503, 603 }, .{ 102, 202, 302, 402, 502, 602, 102, 202, 302, 402, 502, 602 }, .{ 101, 201, 301, 401, 501, 601, 101, 201, 301, 401, 501, 601 }, .{ 100, 200, 300, 400, 500, 600, 100, 200, 300, 400, 500, 600 } };

// indexes: ply, idx (either 1st or 2nd)
pub var killerMoves: [64][2]IMove = undefined;

// indexes: sideToMove, piece, fromSq, toSq
// https://www.chessprogramming.org/History_Heuristic#Update
pub var historyHeuristic: [2][64][64]scoreType = std.mem.zeroes([2][64][64]scoreType);

pub fn _initMoveOrdering() void {
    historyHeuristic = std.mem.zeroes([2][64][64]scoreType);
    killerMoves = undefined;
}
pub fn eval_move_heuristic_line(move: IMove, ply: u16, prevLine: *const movel.line) scoreType {
    if (move.equal(prevLine.moves[ply])) {
        // previous best move at that ply
        return configl.ORDERING_LINE_VALUE;
    }
    if (move.isCapture()) {
        return mvv_lva[@intFromEnum(move.getFromPiece())][@intFromEnum(move.getCapturePiece())];
    } else {
        //
        if (move.equal(killerMoves[ply][0])) {
            return 90;
        } else if (move.equal(killerMoves[ply][1])) {
            return 80;
        } else {
            if (comptime configl.DEFAULT_USE_HISTORY) {
                const w = @intFromEnum(move.getFromPiece()) <= @intFromEnum(e_piece.nWhiteKing);
                return historyHeuristic[@intFromBool(w)][move.getFrom()][move.getTo()];
            }
        }
    }
    return 0;
}
pub fn eval_move_heuristic(move: IMove, ply: u16, prevLine: *const movel.line, comptime useLine: bool) scoreType {
    if (comptime useLine) {
        return eval_move_heuristic_line(move, ply, prevLine);
    }
    return eval_move_heuristic_std(move, ply);
}
pub fn eval_move_heuristic_std(move: IMove, ply: u16) scoreType {
    if (move.isCapture()) {
        return mvv_lva[@intFromEnum(move.getFromPiece())][@intFromEnum(move.getCapturePiece())];
    } else {
        //
        if (move.equal(killerMoves[ply][0])) {
            return 90;
        } else if (move.equal(killerMoves[ply][1])) {
            return 80;
        } else {
            if (comptime configl.DEFAULT_USE_HISTORY) {
                const w = @intFromEnum(move.getFromPiece()) <= @intFromEnum(e_piece.nWhiteKing);
                return historyHeuristic[@intFromBool(w)][move.getFrom()][move.getTo()];
            }
        }
    }
    return 0;
}
pub fn updateHistoryHeurist(white: bool, from: u8, to: u8, bonus: scoreType) void {
    const _bonus = @max(-configl.MAX_HIST_HEURISTIC_VALUE, @min(configl.MAX_HIST_HEURISTIC_VALUE, bonus));
    historyHeuristic[@intFromBool(white)][from][to] += _bonus - @divFloor(historyHeuristic[@intFromBool(white)][from][to] * @as(scoreType, @intCast(@abs(_bonus))), configl.MAX_HIST_HEURISTIC_VALUE);
}
pub inline fn computeHistoryBonus(depth: u16) scoreType {
    return @intCast(depth * 10);
}
pub fn cmp_eval_move(context: [chess.MAX_POSSIBLE_MOVE]scoreType, a: usize, b: usize) bool {
    return context[a] > context[b];
}
pub fn cst_eval_move_sorting_mask(p_moves: *const movel.moveContainer, ply: u16, prevLine: *const movel.line, comptime useLine: bool) [chess.MAX_POSSIBLE_MOVE]usize {
    var ret: [chess.MAX_POSSIBLE_MOVE]usize = undefined;
    var scores: [chess.MAX_POSSIBLE_MOVE]scoreType = undefined;
    for (0..p_moves.len) |i| {
        ret[i] = i;
        scores[i] = eval_move_heuristic(p_moves.moves[i], ply, prevLine, useLine);
    }
    std.mem.sort(usize, ret[0..p_moves.len], scores, cmp_eval_move);
    return ret;
}

pub fn eval_move_sorting_mask(p_moves: *const movel.moveContainer, ply: u16, prevLine: *const movel.line, p_feature: *const searchFeatures) [chess.MAX_POSSIBLE_MOVE]usize {
    if (p_feature.usingIncrementalSearch) {
        return cst_eval_move_sorting_mask(p_moves, ply, prevLine, true);
    }
    return cst_eval_move_sorting_mask(p_moves, ply, prevLine, false);
}
pub fn main() !void {
    try sanityCheck();
    //try test_main();
    var path: string = try string.initFromSlice(mainl.GLOBAL_ALLOC, "opening/E12.33-1M-D12-Resolved.book");
    var savePath: string = try string.initFromSlice(mainl.GLOBAL_ALLOC, "logs/test_weights_int.csv");
    defer path.free(mainl.GLOBAL_ALLOC);
    defer savePath.free(mainl.GLOBAL_ALLOC);

    try test_save(mainl.GLOBAL_ALLOC, path, savePath);
    //try mainTexel(mainl.GLOBAL_ALLOC, path);
}
