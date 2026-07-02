const heuristicl = @import("heuristic.zig");
const chessl = @import("chess.zig");
const typel = @import("type.zig");

const std = @import("std");
const mainl = @import("main.zig");
const enginel = @import("engine.zig");

const scoreType = typel.scoreType;
const milliDepth = typel.milliDepth;
const heuristicValues = heuristicl.heuristicValues;

// values from https://www.chessprogramming.org/Evaluation for now
pub const simplePawnScore: scoreType = 100;
pub const simpleBishopScore: scoreType = 300;
pub const simpleKnightScore: scoreType = 300;
pub const simpleRookScore: scoreType = 500;
pub const simpleQueenScore: scoreType = 900;
pub const simpleCheckMateScore: scoreType = 31000;
pub const simpleCheckMateThreshold: scoreType = 30000;
pub const simpleStalemateScore: scoreType = 0;

// ============ pawn structure ============
pub const simpleIsolatedPawnScore: scoreType = 1;
pub const simpleStackedPawnScore: scoreType = 1;
pub const simplePassedPawnScore: scoreType = 2;

// ============ structure ============
pub const simpleMobilityScore: scoreType = 5;
pub const simpleKingMobilityScore: scoreType = 10;
pub const simpleWeakCheckMateScore: scoreType = 1000;
pub const simpleStructureProtectionScore: scoreType = 1;

// ============ tempo ============
pub const simpleTempoChecksScore: scoreType = 25;
pub const simplePieceThreatScore: scoreType = 16;

// source: https://www.chessprogramming.org/King_Safety
// ============ safety ============
pub const simpleSafetyBishopScore: scoreType = 20;
pub const simpleSafetyKnightScore: scoreType = 20;
pub const simpleSafetyRookScore: scoreType = 40;
pub const simpleSafetyQueenScore: scoreType = 80;

// ============ king ============
pub const simpleKingProximity: scoreType = 5;

pub const pawnScoreArr = [chessl.N_SQUARES]scoreType{
    0,   0,  0,  0,   0,   0,   0,  0,
    -31, 8,  -7, -37, -36, -14, 3,  -31,
    -22, 9,  5,  -11, -10, -2,  3,  -19,
    -26, 3,  10, 9,   6,   1,   0,  -23,
    -17, 16, -2, 15,  14,  0,   15, -13,
    7,   28, 21, 44,  40,  31,  44, 7,
    78,  83, 86, 73,  102, 82,  85, 90,
    0,   0,  0,  0,   0,   0,   0,  0,
};

pub const knightScoreArr = [chessl.N_SQUARES]scoreType{
    -5,  1,   -11, -9,  -10, -11, -7,  -7,
    14,  15,  8,   4,   5,   4,   15,  12,
    10,  18,  18,  11,  6,   18,  15,  11,
    9,   7,   12,  17,  12,  12,  0,   5,
    18,  12,  15,  25,  19,  18,  11,  7,
    -6,  29,  -24, 30,  39,  -7,  21,  -10,
    -8,  15,  26,  -31, -29, 23,  1,   -16,
    -44, -58, -61, -56, -17, -80, -27, -37,
};

pub const bishopScoreArr = [chessl.N_SQUARES]scoreType{
    -5,  1,   -11, -9,  -10, -11, -7,  -7,
    14,  15,  8,   4,   5,   4,   15,  12,
    10,  18,  18,  11,  6,   18,  15,  11,
    9,   7,   12,  17,  12,  12,  0,   5,
    18,  12,  15,  25,  19,  18,  11,  7,
    -6,  29,  -24, 30,  39,  -7,  21,  -10,
    -8,  15,  26,  -31, -29, 23,  1,   -16,
    -44, -58, -61, -56, -17, -80, -27, -37,
};

pub const rookScoreArr = [chessl.N_SQUARES]scoreType{
    -25, -20, -15, 4,   -1,  -15, -25, -26,
    -44, -31, -25, -21, -24, -35, -36, -44,
    -35, -23, -35, -20, -20, -29, -21, -38,
    -23, -29, -13, -17, -10, -24, -38, -25,
    0,   4,   13,  10,  15,  -3,  -7,  -5,
    15,  29,  23,  27,  37,  22,  20,  12,
    45,  24,  46,  55,  45,  51,  28,  50,
    29,  24,  27,  3,   30,  27,  46,  41,
};

pub const queenScoreArr = [chessl.N_SQUARES]scoreType{
    -29, -22, -23, -9,  -23, -27, -25, -31,
    -27, -13, 0,   -14, -11, -11, -15, -28,
    -22, -4,  -9,  -8,  -12, -8,  -12, -20,
    -10, -11, -1,  -3,  0,   -7,  -15, -16,
    0,   -12, 16,  12,  18,  15,  -9,  -4,
    -1,  32,  24,  44,  54,  47,  32,  1,
    10,  24,  44,  -7,  15,  56,  42,  18,
    4,   0,   -6,  -78, 51,  18,  65,  19,
};

pub const kingScoreArr = [chessl.N_SQUARES]scoreType{
    17,  30,  -3,  -14, 6,   -1,  40,  18,
    -4,  3,   -14, -50, -57, -18, 13,  4,
    -47, -42, -43, -79, -64, -32, -28, -32,
    -55, -43, -52, -28, -51, -47, -8,  -50,
    -55, 50,  11,  -4,  -19, 13,  0,   -49,
    -62, 12,  -57, 44,  -67, 28,  37,  -31,
    -32, 10,  55,  56,  56,  55,  10,  3,
    4,   54,  47,  -99, -99, 60,  83,  -62,
};

// source: https://www.chessprogramming.org/Simplified_Evaluation_Function
pub const kingScoreArr_EG = [chessl.N_SQUARES]scoreType{ -50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -30, 0, 0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50 };

pub var tunerOpts: std.ArrayList(param_entry) = .empty;
pub const param_entry = struct {
    opt: enginel.setOptionEntry,
    addr: *scoreType,
};
pub fn add_param(addr: *scoreType, min: scoreType, max: scoreType, name: []const u8) void {
    const p: param_entry = .{ .addr = addr, .opt = .{ .argType = .SPIN, .optionType = .INVALID, .name = name, .info = enginel.optionInfo{ .spin = .{ .default = addr.*, .min = min, .max = max } } } };
    tunerOpts.append(mainl.getGlobalGPA(), p) catch unreachable;
}

// global things here
pub fn appendAll() void {
    // counts
    //add_param(&global_PawnVal, 0, 1000, "global_PawnVal");
    //add_param(&global_BishopVal, 0, 100, "global_BishopVal");
    //add_param(&global_KnightVal, 0, 100, "global_KnightVal");
    //add_param(&global_RookVal, 0, 100, "global_RookVal");
    //add_param(&global_QueenVal, 0, 100, "global_QueenVal");

    // 'texel'
    add_param(&global_MobilityVal[0], 0, 100, "global_MobilityVal_MG");
    add_param(&global_MobilityVal[1], 0, 100, "global_MobilityVal_EG");

    add_param(&global_KingMobilityVal[0], 0, 100, "global_KingMobilityVal_MG");
    add_param(&global_KingMobilityVal[1], 0, 100, "global_KingMobilityVal_EG");
    add_param(&global_OpenFileRookVal[0], 0, 100, "global_OpenFileRookVal_MG");
    add_param(&global_OpenFileRookVal[1], 0, 100, "global_OpenFileRookVal_EG");

    // structure
    add_param(&global_StructureProtectionVal[0], 0, 100, "global_StructureProtectionVal_MG");
    add_param(&global_StructureProtectionVal[1], 0, 100, "global_StructureProtectionVal_EG");
    add_param(&global_centerProtectionVal[0], 0, 100, "global_centerProtectionVal_MG");
    add_param(&global_centerProtectionVal[1], 0, 100, "global_centerProtectionVal_EG");

    // pawn structure
    add_param(&global_IsolatedPawnVal[0], 0, 100, "global_IsolatedPawnVal_MG");
    add_param(&global_IsolatedPawnVal[1], 0, 100, "global_IsolatedPawnVal_EG");
    add_param(&global_StackedPawnVal[0], 0, 100, "global_StackedPawnVal_MG");
    add_param(&global_StackedPawnVal[1], 0, 100, "global_StackedPawnVal_EG");
    add_param(&global_PassedPawnVal[0], 0, 100, "global_PassedPawnVal_MG");
    add_param(&global_PassedPawnVal[1], 0, 100, "global_PassedPawnVal_EG");
    add_param(&global_phalanxDuoPawnVal[0], 0, 100, "global_phalanxDuoPawnVal_MG");
    add_param(&global_phalanxDuoPawnVal[1], 0, 100, "global_phalanxDuoPawnVal_EG");
    add_param(&global_connectionPawnVal[0], 0, 100, "global_connectionPawnVal_MG");
    add_param(&global_connectionPawnVal[1], 0, 100, "global_connectionPawnVal_EG");

    // tempo
    add_param(&global_tempoChecksScore[0], 0, 100, "global_tempoChecksScore_MG");
    add_param(&global_tempoChecksScore[1], 0, 100, "global_tempoChecksScore_EG");
    add_param(&global_pieceThreatScore[0], 0, 100, "global_pieceThreatScore_MG");
    add_param(&global_pieceThreatScore[1], 0, 100, "global_pieceThreatScore_EG");

    // safety
    add_param(&global_SafetyBishopVal[0], 0, 100, "global_SafetyBishopVal_MG");
    add_param(&global_SafetyBishopVal[1], 0, 100, "global_SafetyBishopVal_EG");
    add_param(&global_SafetyKnightVal[0], 0, 100, "global_SafetyKnightVal_MG");
    add_param(&global_SafetyKnightVal[1], 0, 100, "global_SafetyKnightVal_EG");
    add_param(&global_SafetyRookVal[0], 0, 100, "global_SafetyRookVal_MG");
    add_param(&global_SafetyRookVal[1], 0, 100, "global_SafetyRookVal_EG");
    add_param(&global_SafetyQueenVal[0], 0, 100, "global_SafetyQueenVal_MG");
    add_param(&global_SafetyQueenVal[1], 0, 100, "global_SafetyQueenVal_EG");

    // king
    add_param(&global_KingProximityVal[0], 0, 100, "global_KingProximityVal_MG");
    add_param(&global_KingProximityVal[1], 0, 100, "global_KingProximityVal_EG");

    // material
    add_param(&global_materialBishopPair[0], 0, 100, "global_materialBishopPair_MG");
    add_param(&global_materialBishopPair[1], 0, 100, "global_materialBishopPair_EG");
    // LMR
    add_param(&lmr_expectedCutOff, 0, 2000, "lmr_expectedCutOff");
    add_param(&lmr_notImproving, 0, 2000, "lmr_notImproving");
    add_param(&lmr_hashMoveCapture, 0, 2000, "lmr_hashMoveCapture");
    add_param(&lmr_baseDeficit, 0, 2000, "lmr_baseDeficit");
    add_param(&lmr_badCapture, 0, 2000, "lmr_badCapture");
    add_param(&lmr_oldMulti, 0, 800, "lmr_oldMulti");
    add_param(&lmr_givesCheck, -2000, 0, "lmr_givesCheck");
    add_param(&lmr_killerMove, -2000, 0, "lmr_killerMove");
    add_param(&lmr_threatening, -2000, 0, "lmr_threatening");
    add_param(&lmr_inPvMode, -2000, 0, "lmr_inPvMode");
    add_param(&lmr_isPromotion, -2000, 0, "lmr_isPromotion");
    //
}
pub var global_PawnVal: scoreType = simplePawnScore;

pub var global_BishopVal: scoreType = simpleBishopScore;
pub var global_KnightVal: scoreType = simpleKnightScore;
pub var global_RookVal: scoreType = simpleRookScore;
pub var global_QueenVal: scoreType = simpleQueenScore;

// mobility
pub var global_MobilityVal: [2]scoreType = .{ 6, 9 };
pub var global_KingMobilityVal: [2]scoreType = .{ 1, 1 };
pub var global_OpenFileRookVal: [2]scoreType = .{ 10, 1 };

// structure
pub var global_StructureProtectionVal: [2]scoreType = .{ 21, 26 };
pub var global_centerProtectionVal: [2]scoreType = .{ 3, 4 };

// pawn structure
pub var global_IsolatedPawnVal: [2]scoreType = .{ 1, 0 };
pub var global_StackedPawnVal: [2]scoreType = .{ 1, 2 };
pub var global_PassedPawnVal: [2]scoreType = .{ 22, 35 };
pub var global_phalanxDuoPawnVal: [2]scoreType = .{ 2, 6 };
pub var global_connectionPawnVal: [2]scoreType = .{ 4, 3 };

// tempo
pub var global_tempoChecksScore: [2]scoreType = .{ 25, 14 };
pub var global_pieceThreatScore: [2]scoreType = .{ 16, 6 };
pub const global_weakCheckmate: [2]scoreType = .{ simpleWeakCheckMateScore, simpleWeakCheckMateScore };

// safety
pub var global_SafetyBishopVal: [2]scoreType = .{ 11, 9 };
pub var global_SafetyKnightVal: [2]scoreType = .{ 3, 1 };
pub var global_SafetyRookVal: [2]scoreType = .{ 10, 4 };
pub var global_SafetyQueenVal: [2]scoreType = .{ 11, 12 };

// king
pub var global_KingProximityVal: [2]scoreType = .{ 1, 0 };

// material
pub var global_materialBishopPair: [2]scoreType = .{ 16, 23 };
// PSQT
pub var global_Pawn_PSQT: [2][64]scoreType = .{ pawnScoreArr, pawnScoreArr };
pub var global_Bishop_PSQT: [2][64]scoreType = .{ bishopScoreArr, bishopScoreArr };
pub var global_Knight_PSQT: [2][64]scoreType = .{ knightScoreArr, knightScoreArr };
pub var global_Rook_PSQT: [2][64]scoreType = .{ rookScoreArr, rookScoreArr };
pub var global_Queen_PSQT: [2][64]scoreType = .{ queenScoreArr, queenScoreArr };
pub var global_King_PSQT: [2][64]scoreType = .{ _kingScoreArrMG, _kingScoreArrEG };

const _kingScoreArrMG = [chessl.N_SQUARES]scoreType{
    30,  30,  30,  10,  12,  10,  30,  30,
    10,  10,  10,  0,   0,   0,   10,  10,
    0,   0,   0,   -10, -20, -10, 0,   0,
    -20, -30, -50, -50, -50, -50, -30, -20,
    -20, -40, -50, -50, -50, -50, -40, -20,
    -20, -40, -50, -50, -50, -50, -40, -20,
    -30, -40, -50, -50, -50, -50, -40, -30,
    -40, -40, -50, -50, -50, -50, -40, -40,
};

const _kingScoreArrEG = [chessl.N_SQUARES]scoreType{
    -40, -30, -30, -30, -30, -30, -30, -30,
    -30, -22, -23, -29, -40, -28, -37, -30,
    -30, -10, 4,   1,   4,   3,   -10, -30,
    -30, -10, 8,   20,  20,  10,  -10, -30,
    -30, -10, 8,   7,   9,   8,   -10, -30,
    -30, -10, 14,  5,   9,   8,   -10, -30,
    -30, -22, -11, -14, -6,  -8,  -17, -30,
    -40, -30, -30, -30, -30, -30, -30, -30,
};

//https://www.chessprogramming.org/Late_Move_Reductions
// LMR positive (more reduction)
pub var lmr_expectedCutOff: milliDepth = 1021;
pub var lmr_notImproving: milliDepth = 525;
pub var lmr_hashMoveCapture: milliDepth = 270;
pub var lmr_baseDeficit: milliDepth = 1000;
pub var lmr_badCapture: milliDepth = 295;
pub var lmr_oldMulti: milliDepth = 0;
// LMR negative (less reduction)
pub var lmr_inCheck: milliDepth = -600; // not used since no lmr in check
// try add_param(&lmr_inCheck, 0, 0, 0, "lmr_inCheck");
pub var lmr_givesCheck: milliDepth = -684;
pub var lmr_killerMove: milliDepth = -525;
pub var lmr_threatening: milliDepth = -219;
pub var lmr_inPvMode: milliDepth = -406;
pub var lmr_isPromotion: milliDepth = -193;

//    lmr_expectedCutOff = 300,
//    lmr_notImproving = 150,
//    lmr_hashMoveCapture = 100,
//    lmr_baseDeficit = 1024,
//    lmr_badCapture = 80,
//    lmr_oldMulti = 50,
//    lmr_givesCheck = -400,
//    lmr_killerMove = -100,
//    lmr_inPvNode = -150,
//    lmr_isPromotion = -75,
//    lmr_threatening = -75,
