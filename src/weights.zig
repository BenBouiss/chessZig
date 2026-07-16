const heuristicl = @import("heuristic.zig");
const chessl = @import("chess.zig");
const typel = @import("type.zig");

const std = @import("std");
const mainl = @import("main.zig");
const enginel = @import("engine.zig");
const configl = @import("config.zig");

const scoreType = typel.scoreType;
const milliDepth = typel.milliDepth;
const heuristicValues = heuristicl.heuristicValues;

// values from https://www.chessprogramming.org/Evaluation for now
pub const simplePawnScore: scoreType = 100;
pub const simpleBishopScore: scoreType = 300;
pub const simpleKnightScore: scoreType = 300;
pub const simpleRookScore: scoreType = 500;
pub const simpleQueenScore: scoreType = 900;
pub const simpleKingScore: scoreType = 16000;

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
pub var strOpts: std.ArrayList([]u8) = .empty;

pub fn add_param(addr: *scoreType, min: scoreType, max: scoreType, name: []const u8) void {
    const p: param_entry = .{ .addr = addr, .opt = .{ .argType = .SPIN, .optionType = .INVALID, .name = name, .info = enginel.optionInfo{ .spin = .{ .default = addr.*, .min = min, .max = max } } } };
    tunerOpts.append(mainl.getGlobalGPA(), p) catch unreachable;
}
pub fn add_param_1d(comptime size: usize, values: *[size]scoreType, min: scoreType, max: scoreType, name: []const u8) !void {
    for (0..size) |i| {
        const n = try std.fmt.allocPrint(mainl.getGlobalGPA(), "{s}_{d}", .{ name, i });
        try strOpts.append(mainl.getGlobalGPA(), n);
        const p: param_entry = .{ .addr = &values[i], .opt = .{ .argType = .SPIN, .optionType = .INVALID, .name = strOpts.items[strOpts.items.len - 1][0..n.len], .info = enginel.optionInfo{ .spin = .{ .default = values[i], .min = min, .max = max } } } };
        tunerOpts.append(mainl.getGlobalGPA(), p) catch unreachable;
    }
}

// global things here
pub fn appendAll() !void {
    // counts
    //add_param(&global_PawnVal, 0, 1000, "global_PawnVal");
    //add_param(&global_BishopVal, 0, 100, "global_BishopVal");
    //add_param(&global_KnightVal, 0, 100, "global_KnightVal");
    //add_param(&global_RookVal, 0, 100, "global_RookVal");
    //add_param(&global_QueenVal, 0, 100, "global_QueenVal");
    modif_val();
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
    add_param(&lmr_scoreThreshold, 0, 1000, "lmr_scoreThreshold");
    add_param(&lmr_expectedCutOff, 0, 2000, "lmr_expectedCutOff");
    add_param(&lmr_notImproving, 0, 2000, "lmr_notImproving");
    add_param(&lmr_hashMoveCapture, 0, 2000, "lmr_hashMoveCapture");
    add_param(&lmr_baseDeficit, 0, 2000, "lmr_baseDeficit");
    add_param(&lmr_badCapture, 0, 2000, "lmr_badCapture");
    add_param(&lmr_oldMulti, 0, 800, "lmr_oldMulti");

    add_param(&lmr_highFailScore, 100, 1024, "lmr_highFailScore");
    add_param(&lmr_highFailCount, 2, 16, "lmr_highFailCount");

    add_param(&lmr_givesCheck, -2000, 0, "lmr_givesCheck");
    add_param(&lmr_killerMove, -2000, 0, "lmr_killerMove");
    add_param(&lmr_threatening, -2000, 0, "lmr_threatening");
    add_param(&lmr_inPvMode, -2000, 0, "lmr_inPvMode");
    add_param(&lmr_isPromotion, -2000, 0, "lmr_isPromotion");

    // margins
    //add_param(&futilityMargin[0], 0, 1500, "futilityMargin_0");
    //add_param(&futilityMargin[1], 0, 1500, "futilityMargin_1");
    //add_param(&futilityMargin[2], 0, 1500, "futilityMargin_2");
    //add_param(&futilityMargin[3], 0, 1500, "futilityMargin_3");
    //try add_param_1d(futilityMargin.len, &futilityMargin, 0, 1500, "futilityMargin");
    //try add_param_1d(rfpMargin.len, &rfpMargin, 0, 1500, "rfpMargin");

    add_param(&rfpImproving, -500, 0, "rfpImproving");
    add_param(&rfpDepth, 6, 12, "rfpDepth");
    add_param(&rfpCoeff, 25, 150, "rfpCoeff");
    add_param(&rfpConst, 25, 150, "rfpConst");

    add_param(&captureExtensionThresh, 0, 1500, "captureExtensionThresh");

    add_param(&aspirationCoefficient, 10, 200, "aspirationCoefficient");
    add_param(&nullMoveDepthAugmentThreshold, 8, 32, "nullMoveDepthAugmentThreshold");
    add_param(&nullMoveDepthAugment, 0, 6, "nullMoveDepthAugment");
    add_param(&nullMoveReduction, 0, 5, "nullMoveReduction");
    add_param(&nullMoveReductionImproving, 0, 4, "nullMoveReductionImproving");

    add_param(&razoringBaseImproving, 0, 1000, "razoringBaseImproving");
    add_param(&razoringBaseNotImproving, 0, 1000, "razoringBaseNotImproving");
    add_param(&razoringCoefficient, 0, 1000, "razoringCoefficient");
    add_param(&IIRDepth, 4, 8, "IIRDepth");
    add_param(&LMRDepth, 3, 8, "LMRDepth");

    add_param(&SeePruningMaxDepth, 3, 12, "SeePruningMaxDepth");
    add_param(&SeePruningQuietMargin, -400, 0, "SeePruningQuietMargin");
    add_param(&SeePruningCaptureMargin, -400, 0, "SeePruningCaptureMargin");

    add_param(&probCutMargin, 0, 500, "probCutMargin");
    add_param(&probCutMinimalDepth, 4, 8, "probCutMinimalDepth");
    add_param(&corrHistMax, 0, 4000, "corrHistMax");

    add_param(&futilityDepth, 6, 14, "futilityDepth");
    add_param(&futilityCoeff, 50, 500, "futilityCoeff");
    add_param(&futilityConst, 50, 500, "futilityConst");

    //add_param(&historyDepthMax, 4, 14, "historyDepthMax");
    add_param(&historyThreshCoeff, -1024, 0, "historyThreshCoeff");
    add_param(&historyThreshConst, -512, 0, "historyThreshConst");
    add_param(&historyMinExplore, 3, 24, "historyMinExplore");

    add_param(&lmpMaxDepth, 3, 14, "lmpMaxDepth");
    add_param(&lmpBase, 1, 24, "lmpBase");

    //const start = tunerOpts.items.len;

    //try add_param_1d(&global_Pawn_PSQT[0], -100, 200, "global_Pawn_PSQT_MG");
    //try add_param_1d(&global_Pawn_PSQT[1], -100, 200, "global_Pawn_PSQT_EG");

    //try add_param_1d(&global_Knight_PSQT[0], -100, 200, "global_Knight_PSQT_MG");
    //try add_param_1d(&global_Knight_PSQT[1], -100, 200, "global_Knight_PSQT_EG");

    //try add_param_1d(&global_Bishop_PSQT[0], -100, 200, "global_Bishop_PSQT_MG");
    //try add_param_1d(&global_Bishop_PSQT[1], -100, 200, "global_Bishop_PSQT_EG");

    //try add_param_1d(&global_Rook_PSQT[0], -100, 200, "global_Rook_PSQT_MG");
    //try add_param_1d(&global_Rook_PSQT[1], -100, 200, "global_Rook_PSQT_EG");

    //try add_param_1d(&global_Queen_PSQT[0], -100, 200, "global_Queen_PSQT_MG");
    //try add_param_1d(&global_Queen_PSQT[1], -100, 200, "global_Queen_PSQT_EG");

    //try add_param_1d(&global_King_PSQT[0], -100, 200, "global_King_PSQT_MG");
    //try add_param_1d(&global_King_PSQT[1], -100, 200, "global_King_PSQT_EG");
    //_ = start;
    //for (start..tunerOpts.items.len) |i| {
    //    const e = tunerOpts.items[i];
    //    std.debug.print(" \"{s}\": {{ \"value\": {d}, \"min_value\": {d}, \"max_value\": {d}, \"step\":{d} }}, \n", .{ e.opt.name, e.addr.*, -100, 200, 20 });
    //}
}
pub var global_PawnVal: scoreType = simplePawnScore;
pub var global_BishopVal: scoreType = simpleBishopScore;
pub var global_KnightVal: scoreType = simpleKnightScore;
pub var global_RookVal: scoreType = simpleRookScore;
pub var global_QueenVal: scoreType = simpleQueenScore;

// mobility
pub var global_MobilityVal: [2]scoreType = .{ 11, 11 };
pub var global_KingMobilityVal: [2]scoreType = .{ 1, 0 };
pub var global_OpenFileRookVal: [2]scoreType = .{ 12, 12 };

// structure
pub var global_StructureProtectionVal: [2]scoreType = .{ 20, 12 };
pub var global_centerProtectionVal: [2]scoreType = .{ 0, 0 };

// pawn structure
pub var global_IsolatedPawnVal: [2]scoreType = .{ 2, 1 };
pub var global_StackedPawnVal: [2]scoreType = .{ 12, 9 };
pub var global_PassedPawnVal: [2]scoreType = .{ 2, 1 };
pub var global_phalanxDuoPawnVal: [2]scoreType = .{ 3, 0 };
pub var global_connectionPawnVal: [2]scoreType = .{ 2, 5 };

// tempo
pub var global_tempoChecksScore: [2]scoreType = .{ 8, 9 };
pub var global_pieceThreatScore: [2]scoreType = .{ 32, 6 };
pub const global_weakCheckmate: [2]scoreType = .{ simpleWeakCheckMateScore, simpleWeakCheckMateScore };

// safety
pub var global_SafetyBishopVal: [2]scoreType = .{ 5, 1 };
pub var global_SafetyKnightVal: [2]scoreType = .{ 25, 4 };
pub var global_SafetyRookVal: [2]scoreType = .{ 0, 0 };
pub var global_SafetyQueenVal: [2]scoreType = .{ 3, 36 };

// king
pub var global_KingProximityVal: [2]scoreType = .{ 5, 0 };

// material
pub var global_materialBishopPair: [2]scoreType = .{ 29, 32 };
// PSQT
pub var global_Pawn_PSQT: [2][64]scoreType = @splat(pawnScoreArr);
pub var global_Bishop_PSQT: [2][64]scoreType = @splat(bishopScoreArr);
pub var global_Knight_PSQT: [2][64]scoreType = @splat(knightScoreArr);
pub var global_Rook_PSQT: [2][64]scoreType = @splat(rookScoreArr);
pub var global_Queen_PSQT: [2][64]scoreType = @splat(queenScoreArr);
pub var global_King_PSQT: [2][64]scoreType = .{ [_]scoreType{
    30,  30,  30,  10,  12,  10,  30,  30,
    10,  10,  10,  0,   0,   0,   10,  10,
    0,   0,   0,   -10, -20, -10, 0,   0,
    -20, -30, -50, -50, -50, -50, -30, -20,
    -20, -40, -50, -50, -50, -50, -40, -20,
    -20, -40, -50, -50, -50, -50, -40, -20,
    -30, -40, -50, -50, -50, -50, -40, -30,
    -40, -40, -50, -50, -50, -50, -40, -40,
}, [_]scoreType{
    -40, -30, -30, -30, -30, -30, -30, -30,
    -30, -22, -23, -29, -40, -28, -37, -30,
    -30, -10, 4,   1,   4,   3,   -10, -30,
    -30, -10, 8,   20,  20,  10,  -10, -30,
    -30, -10, 8,   7,   9,   8,   -10, -30,
    -30, -10, 14,  5,   9,   8,   -10, -30,
    -30, -22, -11, -14, -6,  -8,  -17, -30,
    -40, -30, -30, -30, -30, -30, -30, -30,
} };

//https://www.chessprogramming.org/Late_Move_Reductions
// LMR positive (more reduction)
//pub var lmr_scoreThreshold: milliDepth = configl.MAX_HIST_HEURISTIC_VALUE + 1;
pub var lmr_scoreThreshold: milliDepth = 795;
pub var lmr_expectedCutOff: milliDepth = 737;
pub var lmr_notImproving: milliDepth = 820;
pub var lmr_hashMoveCapture: milliDepth = 572;
pub var lmr_baseDeficit: milliDepth = 1066;
pub var lmr_badCapture: milliDepth = 26;
pub var lmr_oldMulti: milliDepth = 41;
pub var lmr_highFailScore: milliDepth = 1001;
pub var lmr_highFailCount: milliDepth = 4;

// LMR negative (less reduction)
pub var lmr_inCheck: milliDepth = -600; // not used since no lmr in check
// try add_param(&lmr_inCheck, 0, 0, 0, "lmr_inCheck");
pub var lmr_givesCheck: milliDepth = -675;
pub var lmr_killerMove: milliDepth = -370;
pub var lmr_threatening: milliDepth = -110;
pub var lmr_inPvMode: milliDepth = -275;
pub var lmr_isPromotion: milliDepth = -178;

// margins

//pub var futilityMargin [4]scoreType = .{ 16, 165, 332, 509 };
//pub var rfpMargin: [4]scoreType = .{ 0, 47, 185, 235 };
pub var rfpImproving: scoreType = -9;
pub var rfpDepth: scoreType = 6;
pub var rfpCoeff: scoreType = 69; // depth * c
pub var rfpConst: scoreType = 42;

pub var captureExtensionThresh: scoreType = 1111;

pub const moveReductionAmount = 4;

// source: https://www.chessprogramming.org/King_Safety
pub const SAFETY_ARR: [8]scoreType = [8]scoreType{ 0, 0, 50, 75, 88, 94, 97, 99 };

pub var aspirationCoefficient: scoreType = 17;

pub var nullMoveDepthAugmentThreshold: scoreType = 18;
pub var nullMoveDepthAugment: scoreType = 2;
pub var nullMoveReduction: scoreType = 3;
pub var nullMoveReductionImproving: scoreType = 3;

pub var razoringBaseImproving: scoreType = 60;
pub var razoringBaseNotImproving: scoreType = 170;
pub var razoringCoefficient: scoreType = 167;

pub var IIRDepth: scoreType = 6; // >= 5
pub var LMRDepth: scoreType = 3; // >= 3

pub var SeePruningMaxDepth: scoreType = 3;
pub var SeePruningQuietMargin: scoreType = -8;
pub var SeePruningCaptureMargin: scoreType = -92;

pub var probCutMargin: scoreType = 267;
pub var probCutMinimalDepth: scoreType = 7;

pub var corrHistMax: scoreType = 2000;
pub var corrHistDiv: scoreType = 4;

pub var lmpMaxDepth: scoreType = 3;
pub var lmpBase: scoreType = 1;
//pub var lmpImproving: scoreType = 4;

// CurEval <= Alpha - PVal[SecondPiece(Opponent) - PVal[ThirdPiece(Opponent) - 2*PosMargin + PosMargin2.

pub var futilityDepth: scoreType = 6;
pub var futilityCoeff: scoreType = 156; // depth * c
pub var futilityConst: scoreType = 209;

//pub var historyDepthMax: scoreType = 4;
pub var historyThreshCoeff: scoreType = -414; //coeff * d + c
pub var historyThreshConst: scoreType = -98;
pub var historyMinExplore: scoreType = 8;

pub var singularExtensionMinDepth: scoreType = 4;
pub var singularExtensionDeltaTTDepth: scoreType = 2;
pub var singularExtensionDepthCoeff: scoreType = 2;

// replace the array with y = a*x + b with x = depth
//pub var futilityMargin: [4]scoreType = .{ 16, 165, 332, 509 };

pub fn modif_val() void {
    // 6
    //global_MobilityVal = .{ 6, 7 };
    //global_KingMobilityVal = .{ 0, 3 };
    //global_OpenFileRookVal = .{ 12, 12 };
    //global_StructureProtectionVal = .{ 20, 14 };
    //global_centerProtectionVal = .{ 3, 2 };
    //global_IsolatedPawnVal = .{ 5, 0 };
    //global_StackedPawnVal = .{ 15, 4 };
    //global_PassedPawnVal = .{ 6, 0 };
    //global_phalanxDuoPawnVal = .{ 1, 0 };
    //global_connectionPawnVal = .{ 3, 6 };
    //global_tempoChecksScore = .{ 9, 7 };
    //global_pieceThreatScore = .{ 31, 6 };
    //global_SafetyBishopVal = .{ 9, 3 };
    //global_SafetyKnightVal = .{ 25, 1 };
    //global_SafetyRookVal = .{ 0, 1 };
    //global_SafetyQueenVal = .{ 2, 31 };
    //global_KingProximityVal = .{ 0, 0 };
    //global_materialBishopPair = .{ 30, 28 };
    //lmr_scoreThreshold = 788;
    //lmr_expectedCutOff = 725;
    //lmr_notImproving = 874;
    //lmr_hashMoveCapture = 631;
    //lmr_baseDeficit = 1045;
    //lmr_badCapture = 74;
    //lmr_oldMulti = 68;
    //lmr_highFailScore = 1018;
    //lmr_highFailCount = 4;
    //lmr_givesCheck = -644;
    //lmr_killerMove = -463;
    //lmr_threatening = 0;
    //lmr_inPvMode = -320;
    //lmr_isPromotion = -140;
    //rfpImproving = -19;
    //rfpDepth = 6;
    //rfpCoeff = 62;
    //rfpConst = 40;
    //captureExtensionThresh = 1053;
    //aspirationCoefficient = 10;
    //nullMoveDepthAugmentThreshold = 18;
    //nullMoveDepthAugment = 3;
    //nullMoveReduction = 3;
    //nullMoveReductionImproving = 3;
    //razoringBaseImproving = 116;
    //razoringBaseNotImproving = 116;
    //razoringCoefficient = 161;
    //IIRDepth = 6;
    //LMRDepth = 3;
    //SeePruningMaxDepth = 3;
    //SeePruningQuietMargin = -11;
    //SeePruningCaptureMargin = -81;
    //probCutMargin = 275;
    //probCutMinimalDepth = 6;
    //futilityDepth = 6;
    //futilityCoeff = 181;
    //futilityConst = 212;
    //historyThreshCoeff = -391;
    //historyThreshConst = -115;
    //historyMinExplore = 7;
    //lmpMaxDepth = 3;
    //lmpBase = 1;

}
