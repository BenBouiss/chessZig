const heuristicl = @import("heuristic.zig");
const chessl = @import("chess.zig");
const typel = @import("type.zig");

const std = @import("std");
const mainl = @import("main.zig");
const enginel = @import("engine.zig");
const configl = @import("config.zig");

const scoreType = typel.scoreType;
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

// ============ king ============
pub const simpleKingProximity: scoreType = 5;

pub const pawnScoreArr = [chessl.N_SQUARES]scoreType{
    100, 100, 100, 100, 100, 100, 100, 100,
    69,  108, 93,  63,  64,  86,  103, 69,
    78,  109, 105, 89,  90,  98,  103, 81,
    74,  103, 110, 109, 106, 101, 100, 77,
    83,  116, 98,  115, 114, 100, 115, 87,
    107, 128, 121, 144, 140, 131, 144, 107,
    178, 183, 186, 173, 202, 182, 185, 190,
    100, 100, 100, 100, 100, 100, 100, 100,
};

pub const knightScoreArr = [chessl.N_SQUARES]scoreType{
    295, 301, 289, 291, 290, 289, 293, 293,
    314, 315, 308, 304, 305, 304, 315, 312,
    310, 318, 318, 311, 306, 318, 315, 311,
    309, 307, 312, 317, 312, 312, 300, 305,
    318, 312, 315, 325, 319, 318, 311, 307,
    294, 329, 276, 330, 339, 293, 321, 290,
    292, 315, 326, 269, 271, 323, 301, 284,
    256, 242, 239, 244, 283, 220, 273, 263,
};

pub const bishopScoreArr = [chessl.N_SQUARES]scoreType{
    295, 301, 289, 291, 290, 289, 293, 293,
    314, 315, 308, 304, 305, 304, 315, 312,
    310, 318, 318, 311, 306, 318, 315, 311,
    309, 307, 312, 317, 312, 312, 300, 305,
    318, 312, 315, 325, 319, 318, 311, 307,
    294, 329, 276, 330, 339, 293, 321, 290,
    292, 315, 326, 269, 271, 323, 301, 284,
    256, 242, 239, 244, 283, 220, 273, 263,
};

pub const rookScoreArr = [chessl.N_SQUARES]scoreType{
    475, 480, 485, 504, 499, 485, 475, 474,
    456, 469, 475, 479, 476, 465, 464, 456,
    465, 477, 465, 480, 480, 471, 479, 462,
    477, 471, 487, 483, 490, 476, 462, 475,
    500, 504, 513, 510, 515, 497, 493, 495,
    515, 529, 523, 527, 537, 522, 520, 512,
    545, 524, 546, 555, 545, 551, 528, 550,
    529, 524, 527, 503, 530, 527, 546, 541,
};

pub const queenScoreArr = [chessl.N_SQUARES]scoreType{
    871, 878, 877, 891, 877, 873, 875, 869,
    873, 887, 900, 886, 889, 889, 885, 872,
    878, 896, 891, 892, 888, 892, 888, 880,
    890, 889, 899, 897, 900, 893, 885, 884,
    900, 888, 916, 912, 918, 915, 891, 896,
    899, 932, 924, 944, 954, 947, 932, 901,
    910, 924, 944, 893, 915, 956, 942, 918,
    904, 900, 894, 822, 951, 918, 965, 919,
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
    modif_val();
    add_param(&global_MobilityVal[0], -200, 200, "global_MobilityVal_MG");
    add_param(&global_MobilityVal[1], -200, 200, "global_MobilityVal_EG");

    add_param(&global_OpenFileRookVal[0], -200, 200, "global_OpenFileRookVal_MG");
    add_param(&global_OpenFileRookVal[1], -200, 200, "global_OpenFileRookVal_EG");

    // structure
    add_param(&global_StructureProtectionVal[0], -200, 200, "global_StructureProtectionVal_MG");
    add_param(&global_StructureProtectionVal[1], -200, 200, "global_StructureProtectionVal_EG");

    add_param(&global_centerProtectionVal[0], -200, 200, "global_centerProtectionVal_MG");
    add_param(&global_centerProtectionVal[1], -200, 200, "global_centerProtectionVal_EG");

    add_param(&global_HangingVal[0], -200, 300, "global_HangingVal_MG");
    add_param(&global_HangingVal[1], -200, 300, "global_HangingVal_EG");

    add_param(&global_pieceThreatScore[0], -200, 200, "global_pieceThreatScore_MG");
    add_param(&global_pieceThreatScore[1], -200, 200, "global_pieceThreatScore_EG");

    // pawn structure
    add_param(&global_IsolatedPawnVal[0], -200, 200, "global_IsolatedPawnVal_MG");
    add_param(&global_IsolatedPawnVal[1], -200, 200, "global_IsolatedPawnVal_EG");
    add_param(&global_StackedPawnVal[0], -200, 200, "global_StackedPawnVal_MG");
    add_param(&global_StackedPawnVal[1], -200, 200, "global_StackedPawnVal_EG");
    add_param(&global_PassedPawnVal[0], -200, 200, "global_PassedPawnVal_MG");
    add_param(&global_PassedPawnVal[1], -200, 200, "global_PassedPawnVal_EG");
    add_param(&global_phalanxDuoPawnVal[0], -200, 200, "global_phalanxDuoPawnVal_MG");
    add_param(&global_phalanxDuoPawnVal[1], -200, 200, "global_phalanxDuoPawnVal_EG");
    add_param(&global_connectionPawnVal[0], -200, 200, "global_connectionPawnVal_MG");
    add_param(&global_connectionPawnVal[1], -200, 200, "global_connectionPawnVal_EG");

    // king
    add_param(&global_KingProximityVal[0], -200, 200, "global_KingProximityVal_MG");
    add_param(&global_KingProximityVal[1], -200, 200, "global_KingProximityVal_EG");

    // material
    add_param(&global_materialBishopPair[0], -200, 300, "global_materialBishopPair_MG");
    add_param(&global_materialBishopPair[1], -200, 300, "global_materialBishopPair_EG");
    // LMR
    add_param(&lmr_scoreThreshold, 0, 20000, "lmr_scoreThreshold");
    add_param(&lmr_expectedCutOff, 0, 2000, "lmr_expectedCutOff");
    add_param(&lmr_notImproving, 0, 2000, "lmr_notImproving");
    add_param(&lmr_hashMoveCapture, 0, 2000, "lmr_hashMoveCapture");
    add_param(&lmr_baseDeficit, 0, 2000, "lmr_baseDeficit");
    add_param(&lmr_badCapture, 0, 2000, "lmr_badCapture");

    add_param(&lmr_highFailScore, 100, 2000, "lmr_highFailScore");
    add_param(&lmr_highFailCount, 1, 16, "lmr_highFailCount");
    add_param(&lmr_hashMoveIsGood, 0, 4000, "lmr_hashMoveIsGood");

    add_param(&lmr_inCheck, -4000, 0, "lmr_inCheck");
    add_param(&lmr_givesCheck, -4000, 0, "lmr_givesCheck");
    add_param(&lmr_killerMove, -4000, 0, "lmr_killerMove");
    add_param(&lmr_threatening, -4000, 0, "lmr_threatening");
    add_param(&lmr_inPvMode, -4000, 0, "lmr_inPvMode");
    add_param(&lmr_isPromotion, -4000, 0, "lmr_isPromotion");
    add_param(&lmr_histDiv, 0, 12000, "lmr_histDiv");

    // margins
    //add_param(&futilityMargin[0], 0, 1500, "futilityMargin_0");
    //add_param(&futilityMargin[1], 0, 1500, "futilityMargin_1");
    //add_param(&futilityMargin[2], 0, 1500, "futilityMargin_2");
    //add_param(&futilityMargin[3], 0, 1500, "futilityMargin_3");
    //try add_param_1d(futilityMargin.len, &futilityMargin, 0, 1500, "futilityMargin");
    //try add_param_1d(rfpMargin.len, &rfpMargin, 0, 1500, "rfpMargin");

    add_param(&rfpNotImproving, -500, 0, "rfpNotImproving");
    add_param(&rfpImproving, -500, 0, "rfpImproving");
    add_param(&rfpDepth, 2, 12, "rfpDepth");
    add_param(&rfpCoeff, 25, 150, "rfpCoeff");
    add_param(&rfpConst, 25, 150, "rfpConst");

    add_param(&captureExtensionThresh, 0, 10000, "captureExtensionThresh");

    add_param(&aspirationCoefficient, 10, 200, "aspirationCoefficient");
    add_param(&aspirationMinDepthVar, 2, 14, "aspirationMinDepthVar");
    add_param(&nullMoveDepthAugmentThreshold, 8, 32, "nullMoveDepthAugmentThreshold");
    add_param(&nullMoveDepthAugment, 2, 6, "nullMoveDepthAugment");
    add_param(&nullMoveReduction, 2, 8, "nullMoveReduction");
    add_param(&nullMoveReductionImproving, 2, 8, "nullMoveReductionImproving");

    add_param(&razoringBaseImproving, 0, 1000, "razoringBaseImproving");
    add_param(&razoringBaseNotImproving, 0, 1000, "razoringBaseNotImproving");
    add_param(&razoringCoefficient, 0, 1000, "razoringCoefficient");
    add_param(&razoringMaxDepth, 2, 12, "razoringMaxDepth");
    add_param(&IIRDepthMin, 2, 6, "IIRDepthMin");
    add_param(&LMRDepth, 2, 8, "LMRDepth");

    add_param(&SeePruningMaxDepth, 2, 12, "SeePruningMaxDepth");
    add_param(&SeePruningQuietMargin, -400, 0, "SeePruningQuietMargin");
    add_param(&SeePruningCaptureMargin, -400, 0, "SeePruningCaptureMargin");

    add_param(&probCutMargin, 0, 500, "probCutMargin");
    add_param(&probCutMinimalDepth, 2, 10, "probCutMinimalDepth");

    add_param(&futilityDepth, 2, 16, "futilityDepth");
    add_param(&futilityCoeff, 50, 500, "futilityCoeff");
    add_param(&futilityConst, 50, 500, "futilityConst");

    add_param(&historyMaxDepth, 2, 14, "historyMaxDepth");
    add_param(&historyThreshCoeff, -12000, 0, "historyThreshCoeff");
    add_param(&historyThreshConst, -10000, 0, "historyThreshConst");
    add_param(&historyMinExplore, 3, 24, "historyMinExplore");

    add_param(&historyBonusCoeff, 150, 512, "historyBonusCoeff");
    add_param(&historyBonusMax, 1024, 65576, "historyBonusMax");
    //add_param(&historyBonusBetaDiff, 200, 1024, "historyBonusBetaDiff");

    add_param(&lmpMaxDepth, 2, 14, "lmpMaxDepth");
    add_param(&lmpBase, 1, 24, "lmpBase");

    add_param(&moveReductionAmount, 1, 10, "moveReductionAmount");
    add_param(&moveQsearchAmount, 1, 10, "moveQsearchAmount");

    add_param(&moveGenMinSeeThreshold, -256, -32, "moveGenMinSeeThreshold");

    add_param(&corrHistMax, 64, 10000, "corrHistMax");
    add_param(&corrHistW, 64, 512, "corrHistW");

    add_param(&singularExtensionMinDepth, 2, 14, "singularExtensionMinDepth");
    add_param(&singularExtensionDeltaTTDepth, 2, 6, "singularExtensionDeltaTTDepth");
    add_param(&singularMarginDoubleExt, 8, 128, "singularMarginDoubleExt");

    add_param(&bestMoveMax, 4, 32, "bestMoveMax");
    add_param(&nodeFactor1, 100, 200, "nodeFactor1");
    add_param(&nodeFactor2, 100, 200, "nodeFactor2");

    add_param(&tmFactor, 100, 200, "tmFactor");
    add_param(&tmBmCoeff, 3, 30, "tmBmCoeff");
    add_param(&schedulerGrowthEstim, 1, 6, "schedulerGrowthEstim");

    //const start = tunerOpts.items.len;

    //try add_param_1d(&global_Pawn_PSQT[0], -200, 200, "global_Pawn_PSQT_MG");
    //try add_param_1d(&global_Pawn_PSQT[1], -200, 200, "global_Pawn_PSQT_EG");

    //try add_param_1d(&global_Knight_PSQT[0], -200, 200, "global_Knight_PSQT_MG");
    //try add_param_1d(&global_Knight_PSQT[1], -200, 200, "global_Knight_PSQT_EG");

    //try add_param_1d(&global_Bishop_PSQT[0], -200, 200, "global_Bishop_PSQT_MG");
    //try add_param_1d(&global_Bishop_PSQT[1], -200, 200, "global_Bishop_PSQT_EG");

    //try add_param_1d(&global_Rook_PSQT[0], -200, 200, "global_Rook_PSQT_MG");
    //try add_param_1d(&global_Rook_PSQT[1], -200, 200, "global_Rook_PSQT_EG");

    //try add_param_1d(&global_Queen_PSQT[0], -200, 200, "global_Queen_PSQT_MG");
    //try add_param_1d(&global_Queen_PSQT[1], -200, 200, "global_Queen_PSQT_EG");

    //try add_param_1d(&global_King_PSQT[0], -200, 200, "global_King_PSQT_MG");
    //try add_param_1d(&global_King_PSQT[1], -200, 200, "global_King_PSQT_EG");
    //_ = start;
    //for (start..tunerOpts.items.len) |i| {
    //    const e = tunerOpts.items[i];
    //    std.debug.print(" \"{s}\": {{ \"value\": {d}, \"min_value\": {d}, \"max_value\": {d}, \"step\":{d} }}, \n", .{ e.opt.name, e.addr.*, -200, 200, 20 });
    //}
}
//pub var _global_PawnVal: scoreType = simplePawnScore;
//pub var _global_BishopVal: scoreType = simpleBishopScore;
//pub var _global_KnightVal: scoreType = simpleKnightScore;
//pub var _global_RookVal: scoreType = simpleRookScore;
//pub var _global_QueenVal: scoreType = simpleQueenScore;

// mobility
pub var global_MobilityVal: [2]scoreType = .{ 6, 11 };
pub var global_OpenFileRookVal: [2]scoreType = .{ 47, 15 };

// material
pub var global_materialBishopPair: [2]scoreType = .{ 55, 62 };

// ============ structure ============
pub var global_StructureProtectionVal: [2]scoreType = .{ 18, 19 };
pub var global_centerProtectionVal: [2]scoreType = .{ 1, 2 };
pub var global_HangingVal: [2]scoreType = .{ -32, -32 };
pub var global_pieceThreatScore: [2]scoreType = .{ 48, 13 };

// ============ pawn structure ============
pub var global_IsolatedPawnVal: [2]scoreType = .{ -2, 0 };
pub var global_StackedPawnVal: [2]scoreType = .{ -7, -2 };
pub var global_PassedPawnVal: [2]scoreType = .{ 2, 20 };
pub var global_phalanxDuoPawnVal: [2]scoreType = .{ 3, 11 };
pub var global_connectionPawnVal: [2]scoreType = .{ 5, 10 };

// king
pub var global_KingProximityVal: [2]scoreType = .{ 5, 0 };

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
//pub var lmr_scoreThreshold: scoreType = configl.MAX_HIST_HEURISTIC_VALUE + 1;
pub var lmr_scoreThreshold: scoreType = 990;
//pub var lmr_scoreThreshold: scoreType = 806 * 2;
pub var lmr_expectedCutOff: scoreType = 234;
pub var lmr_notImproving: scoreType = 1272;
pub var lmr_hashMoveCapture: scoreType = 1049;
pub var lmr_baseDeficit: scoreType = 664;
pub var lmr_badCapture: scoreType = 329;
pub var lmr_highFailScore: scoreType = 1020;
pub var lmr_highFailCount: scoreType = 10;
pub var lmr_hashMoveIsGood: scoreType = 1024;

// LMR negative (less reduction)
pub var lmr_inCheck: scoreType = -1024;
// try add_param(&lmr_inCheck, 0, 0, 0, "lmr_inCheck");
pub var lmr_givesCheck: scoreType = -779;
pub var lmr_killerMove: scoreType = -1105;
pub var lmr_threatening: scoreType = -281;
pub var lmr_inPvMode: scoreType = -85;
pub var lmr_isPromotion: scoreType = -379;

pub var lmr_histDiv: scoreType = 9848;

// margins

//pub var futilityMargin [4]scoreType = .{ 16, 165, 332, 509 };
//pub var rfpMargin: [4]scoreType = .{ 0, 47, 185, 235 };
pub var rfpNotImproving: scoreType = -38;
pub var rfpImproving: scoreType = -25;

pub var rfpDepth: scoreType = 11;
pub var rfpCoeff: scoreType = 84; // depth * c
pub var rfpConst: scoreType = 79;

pub var captureExtensionThresh: scoreType = 265;
//pub var captureExtensionThresh: scoreType = 28 * 16;
//pub var captureExtensionThresh: scoreType = 28 * 4;

pub var aspirationCoefficient: scoreType = 39;
pub var aspirationMinDepthVar: scoreType = 6;

pub var nullMoveDepthAugmentThreshold: scoreType = 8;
pub var nullMoveDepthAugment: scoreType = 3;
pub var nullMoveReduction: scoreType = 3;
pub var nullMoveReductionImproving: scoreType = 4;

pub var razoringBaseImproving: scoreType = 176;
pub var razoringBaseNotImproving: scoreType = 450;
pub var razoringCoefficient: scoreType = 206;
pub var razoringMaxDepth: scoreType = 3;

pub var IIRDepthMin: scoreType = 5; // >= 5
pub var LMRDepth: scoreType = 3; // >= 3

pub var SeePruningMaxDepth: scoreType = 3;
pub var SeePruningQuietMargin: scoreType = -128;
pub var SeePruningCaptureMargin: scoreType = -388;

pub var probCutMargin: scoreType = 303;
pub var probCutMinimalDepth: scoreType = 5;

pub var futilityDepth: scoreType = 9;
pub var futilityCoeff: scoreType = 175; // depth * c
pub var futilityConst: scoreType = 232;

pub var historyMaxDepth: scoreType = 5; //coeff * d + c
//
pub var historyThreshCoeff: scoreType = -741; //coeff * d + c
pub var historyThreshConst: scoreType = -84;
//pub var historyThreshConst: scoreType = (-150) * 16;
//pub var historyThreshConst: scoreType = (-150) * 4;
pub var historyMinExplore: scoreType = 12;

pub var historyBonusCoeff: scoreType = 303;
pub var historyBonusMax: scoreType = 16166;
//pub var historyBonusMax: scoreType = 3000;
//pub var historyBonusBetaDiff: scoreType = 300;

pub var lmpMaxDepth: scoreType = 3;
pub var lmpBase: scoreType = 1;
//pub var lmpImproving: scoreType = 4;

pub var moveReductionAmount: scoreType = 2;
pub var moveQsearchAmount: scoreType = 1;

pub var moveGenMinSeeThreshold: scoreType = -53;
// source: https://www.chessprogramming.org/King_Safety
pub const SAFETY_ARR: [200]scoreType = [_]scoreType{
    0,   0,   1,   2,   3,   5,   7,   9,   12,  15,  18,  22,  26,  30,  35,  39,  44,  50,  56,  62,  68,  75,  82,  85,  89,  97,  105, 113, 122, 131, 140, 150, 169, 180, 191, 202, 213, 225, 237, 248, 260, 272, 283, 295, 307, 319, 330, 342, 354, 366, 377, 389, 401, 412, 424, 436, 448, 459, 471, 483, 494, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500,
    500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500,
};

pub var singularExtensionMinDepth: scoreType = 9;
pub var singularExtensionDeltaTTDepth: scoreType = 2;
pub var singularMarginDoubleExt: scoreType = 46;

pub var corrHistMax: scoreType = 911;
pub var corrHistW: scoreType = 82;
// replace the array with y = a*x + b with x = depth
//pub var futilityMargin: [4]scoreType = .{ 16, 165, 332, 509 };
pub var bestMoveMax: scoreType = 8;

pub var nodeFactor1: scoreType = 149;
pub var nodeFactor2: scoreType = 177;

pub var tmFactor: scoreType = 152;
pub var tmBmCoeff: scoreType = 6;

pub var schedulerGrowthEstim: scoreType = 2;

pub const searchMoveBufferSize: usize = 64;

pub fn modif_val() void {

    //global_Pawn_PSQT = .{ [_]scoreType{ 75, 75, 76, 74, 75, 74, 75, 75, 44, 33, 32, 39, 46, 111, 110, 36, 56, 48, 33, 35, 64, 98, 111, 105, 59, 57, 73, 72, 79, 112, 106, 88, 126, 105, 98, 97, 112, 142, 120, 97, 159, 193, 169, 186, 177, 191, 166, 171, 203, 186, 173, 183, 144, 111, 106, 108, 75, 75, 75, 75, 74, 75, 75, 75 }, [_]scoreType{ 31, 32, 33, 31, 32, 32, 32, 32, 128, 99, 106, 47, 108, 142, 102, 105, 87, 88, 67, 87, 102, 93, 91, 65, 130, 106, 58, 2, 43, 200, 116, 80, 171, 150, 121, 45, 80, 115, 141, 143, 238, 196, 168, 127, 130, 169, 178, 195, 252, 220, 177, 153, 123, 119, 133, 161, 32, 32, 32, 32, 32, 32, 31, 32 } };
    //global_Knight_PSQT = .{ [_]scoreType{ 289, 230, 223, 221, 226, 231, 245, 305, 257, 254, 238, 256, 257, 279, 249, 278, 227, 240, 254, 308, 344, 286, 286, 273, 267, 305, 315, 283, 317, 329, 331, 271, 302, 304, 329, 343, 337, 395, 319, 341, 314, 333, 261, 377, 331, 373, 312, 354, 313, 324, 338, 311, 326, 339, 331, 322, 303, 325, 318, 326, 329, 321, 330, 317 }, [_]scoreType{ 283, 212, 232, 230, 223, 220, 263, 301, 272, 274, 250, 204, 231, 271, 262, 289, 271, 237, 262, 277, 276, 213, 258, 281, 297, 315, 324, 313, 327, 314, 322, 314, 317, 336, 346, 357, 366, 350, 336, 326, 320, 328, 379, 362, 338, 338, 316, 319, 314, 315, 326, 338, 324, 327, 321, 317, 309, 319, 317, 321, 322, 317, 321, 308 } };
    //global_Bishop_PSQT = .{ [_]scoreType{ 291, 259, 287, 236, 258, 296, 295, 270, 346, 297, 329, 291, 308, 333, 327, 299, 292, 311, 337, 311, 333, 315, 323, 297, 324, 271, 307, 328, 306, 310, 314, 328, 309, 318, 298, 346, 326, 311, 300, 316, 271, 318, 238, 321, 316, 200, 311, 334, 293, 302, 296, 299, 268, 296, 278, 273, 285, 291, 287, 297, 292, 267, 295, 287 }, [_]scoreType{ 246, 244, 232, 253, 264, 236, 271, 268, 293, 281, 279, 283, 304, 286, 289, 276, 302, 307, 300, 311, 321, 287, 281, 293, 313, 309, 350, 329, 325, 315, 306, 278, 305, 336, 319, 344, 324, 326, 320, 305, 295, 331, 336, 336, 325, 307, 310, 307, 301, 322, 309, 311, 306, 299, 295, 281, 299, 298, 307, 311, 298, 287, 299, 289 } };
    //global_Rook_PSQT = .{ [_]scoreType{ 426, 446, 464, 479, 476, 442, 485, 435, 392, 425, 428, 444, 428, 428, 470, 435, 436, 445, 438, 440, 447, 457, 509, 485, 490, 495, 483, 482, 489, 495, 489, 501, 531, 531, 550, 550, 541, 527, 546, 541, 559, 559, 556, 552, 551, 564, 547, 535, 553, 564, 560, 562, 551, 537, 535, 545, 515, 525, 512, 508, 525, 517, 524, 514 }, [_]scoreType{ 410, 418, 439, 421, 409, 424, 445, 430, 439, 438, 442, 430, 402, 404, 463, 450, 432, 456, 459, 447, 431, 445, 483, 458, 497, 502, 501, 493, 485, 490, 495, 491, 547, 551, 545, 532, 525, 525, 530, 535, 574, 568, 572, 562, 555, 555, 551, 542, 582, 590, 577, 566, 542, 537, 545, 557, 548, 544, 538, 538, 534, 526, 537, 510 } };
    //global_Queen_PSQT = .{ [_]scoreType{ 896, 843, 852, 880, 842, 787, 854, 886, 866, 888, 896, 895, 886, 869, 863, 893, 871, 889, 907, 885, 894, 884, 898, 896, 871, 908, 900, 892, 914, 911, 921, 916, 892, 900, 928, 915, 934, 933, 930, 938, 903, 898, 907, 925, 928, 944, 928, 930, 911, 910, 926, 906, 923, 929, 918, 921, 900, 904, 908, 887, 908, 901, 911, 918 }, [_]scoreType{ 883, 858, 869, 844, 846, 828, 874, 891, 887, 878, 862, 863, 852, 839, 856, 893, 885, 894, 891, 890, 885, 888, 890, 889, 899, 908, 914, 925, 910, 913, 907, 909, 904, 910, 928, 930, 929, 925, 926, 924, 906, 920, 913, 927, 918, 931, 921, 918, 917, 922, 928, 914, 928, 922, 915, 913, 907, 905, 907, 903, 911, 901, 911, 913 } };
    //global_King_PSQT = .{ [_]scoreType{ -47, 33, -16, -101, -37, -85, 20, -24, 0, -8, -18, -23, 0, -11, 55, 1, -8, 5, 1, -12, 21, -4, 9, -20, -1, 7, 7, 15, 21, 10, 2, -3, 0, 16, 11, 20, 12, 16, 16, 5, 3, 10, 13, 11, 9, 8, 11, 8, 0, 4, 4, 3, 5, 5, 8, 4, -3, 0, 0, 1, 0, 1, 0, -1 }, [_]scoreType{ -82, -25, -69, -86, -111, -90, -66, -124, -37, -41, -57, -51, -58, -40, -49, -67, -16, -28, -18, -22, 4, -21, -3, -52, 10, 16, 13, 40, 38, 33, 29, 9, 16, 68, 39, 74, 49, 68, 62, 34, 21, 52, 52, 52, 53, 63, 60, 46, 4, 22, 15, 25, 24, 26, 38, 26, -9, 8, 5, 4, 4, 9, 6, -3 } };

    //global_MobilityVal = .{ 3, 21 };
    //global_OpenFileRookVal = .{ 38, 12 };
    //global_StructureProtectionVal = .{ 12, 16 };
    //global_HangingVal = .{ 35, 35 };
    //global_centerProtectionVal = .{ 5, 5 };
    //global_IsolatedPawnVal = .{ 3, 3 };
    //global_StackedPawnVal = .{ 6, 2 };
    //global_PassedPawnVal = .{ 1, 22 };
    //global_phalanxDuoPawnVal = .{ 5, 1 };
    //global_connectionPawnVal = .{ 8, 10 };
    //global_pieceThreatScore = .{ 41, 16 };
    //global_SafetyBishopVal = .{ 16, 5 };
    //global_SafetyKnightVal = .{ 26, 4 };
    //global_SafetyRookVal = .{ 11, 2 };
    //global_SafetyQueenVal = .{ 13, 26 };
    //global_KingProximityVal = .{ 3, 0 };
    //global_materialBishopPair = .{ 59, 56 };
    //lmr_scoreThreshold = 1772;
    //lmr_expectedCutOff = 24;
    //lmr_notImproving = 1120;
    //lmr_hashMoveCapture = 857;
    //lmr_baseDeficit = 505;
    //lmr_badCapture = 334;
    //lmr_highFailScore = 1018;
    //lmr_highFailCount = 9;
    //lmr_givesCheck = -800;
    //lmr_killerMove = -1097;
    //lmr_threatening = -222;
    //lmr_inPvMode = -53;
    //lmr_isPromotion = -354;
    //lmr_histDiv = 10662;
    //rfpNotImproving = -37;
    //rfpImproving = -15;
    //rfpDepth = 11;
    //rfpCoeff = 97;
    //rfpConst = 80;
    //captureExtensionThresh = 419;
    //aspirationCoefficient = 33;
    //aspirationMinDepthVar = 6;
    //nullMoveDepthAugmentThreshold = 8;
    //nullMoveDepthAugment = 4;
    //nullMoveReduction = 3;
    //nullMoveReductionImproving = 4;
    //razoringBaseImproving = 147;
    //razoringBaseNotImproving = 450;
    //razoringCoefficient = 133;
    //razoringMaxDepth = 4;
    //IIRDepthMin = 5;
    //LMRDepth = 2;
    //SeePruningMaxDepth = 5;
    //SeePruningQuietMargin = -154;
    //SeePruningCaptureMargin = -394;
    //probCutMargin = 303;
    //probCutMinimalDepth = 7;
    //futilityDepth = 10;
    //futilityCoeff = 206;
    //futilityConst = 267;
    //historyMaxDepth = 6;
    //historyThreshCoeff = -1357;
    //historyThreshConst = -36;
    //historyMinExplore = 13;
    //historyBonusCoeff = 300;
    //historyBonusMax = 13644;
    //lmpMaxDepth = 4;
    //lmpBase = 2;
    //moveReductionAmount = 2;
    //moveQsearchAmount = 1;
    //moveGenMinSeeThreshold = -61;
    //corrHistMax = 1359;
    //corrHistW = 109;
    //singularExtensionMinDepth = 9;
    //singularExtensionDeltaTTDepth = 3;
    //singularMarginDoubleExt = 28;
    //global_Pawn_PSQT = .{ [_]scoreType{ -107, -106, -107, -106, -106, -106, -106, -106, 6, 6, -22, -36, 8, 132, 143, -29, 8, -1, -25, -46, 3, 93, 121, 70, 51, 50, 62, 59, 68, 120, 118, 67, 149, 137, 149, 135, 149, 224, 144, 111, 254, 318, 361, 374, 357, 379, 418, 221, 499, 499, 499, 499, 499, 276, 204, 213, -106, -105, -106, -106, -106, -107, -106, -106 }, [_]scoreType{ -299, -299, -299, -299, -299, -299, -299, -299, 275, 141, 151, 265, 218, 197, 107, 188, 207, 120, 95, 185, 167, 128, 79, 141, 262, 164, 71, -8, 58, 130, 129, 164, 371, 239, 170, 66, 85, 170, 216, 271, 499, 402, 340, 172, 195, 302, 303, 409, 499, 499, 428, 297, 285, 398, 435, 499, -299, -299, -299, -299, -299, -299, -299, -299 } };
    //global_Knight_PSQT = .{ [_]scoreType{ -99, 85, 26, 60, 106, 142, 105, 199, -2, 69, 128, 180, 176, 235, 99, 156, 92, 173, 221, 310, 350, 262, 246, 117, 166, 227, 311, 255, 319, 331, 379, 240, 257, 254, 370, 370, 318, 467, 248, 467, 307, 363, 245, 477, 470, 692, 307, 441, 362, 259, 433, 342, 418, 437, 585, 495, 200, 518, 455, 580, 671, 482, 699, 546 }, [_]scoreType{ -2, 143, 189, 189, 210, 128, 140, 166, 165, 204, 176, 214, 198, 216, 193, 247, 162, 162, 119, 229, 192, 61, 182, 252, 312, 339, 299, 316, 321, 267, 308, 336, 396, 362, 312, 385, 408, 345, 497, 444, 408, 344, 457, 301, 328, 295, 430, 417, 429, 452, 387, 493, 436, 387, 459, 387, 229, 382, 403, 436, 465, 459, 379, 255 } };
    //global_Bishop_PSQT = .{ [_]scoreType{ 224, 240, 230, 157, 204, 240, 318, 129, 340, 267, 371, 260, 298, 408, 323, 388, 262, 340, 346, 316, 356, 323, 349, 239, 325, 289, 326, 402, 399, 323, 323, 356, 308, 308, 387, 430, 388, 389, 270, 319, 306, 311, 247, 408, 361, 251, 315, 382, 271, 343, 302, 289, 199, 392, 164, 214, 152, 290, 278, 228, 261, 216, 317, 231 }, [_]scoreType{ 285, 225, 304, 297, 310, 285, 223, 259, 305, 249, 214, 237, 252, 150, 209, 105, 317, 187, 213, 222, 221, 170, 173, 307, 298, 254, 243, 170, 149, 164, 237, 263, 332, 319, 225, 230, 200, 281, 316, 400, 369, 378, 371, 245, 284, 367, 382, 374, 427, 372, 374, 388, 386, 339, 392, 354, 498, 456, 471, 444, 473, 433, 401, 421 } };
    //global_Rook_PSQT = .{ [_]scoreType{ 305, 343, 371, 395, 407, 366, 457, 366, 202, 284, 313, 335, 370, 377, 448, 251, 245, 255, 309, 332, 383, 369, 499, 341, 289, 316, 395, 369, 400, 343, 468, 361, 445, 477, 552, 573, 590, 587, 643, 601, 581, 619, 605, 632, 692, 843, 899, 751, 538, 461, 550, 610, 682, 802, 867, 811, 482, 586, 392, 503, 676, 899, 899, 887 }, [_]scoreType{ 498, 465, 435, 373, 343, 455, 390, 431, 483, 401, 419, 356, 313, 285, 310, 424, 456, 480, 437, 377, 366, 337, 320, 389, 580, 541, 465, 435, 439, 510, 485, 475, 639, 629, 514, 502, 438, 539, 581, 606, 665, 610, 595, 523, 507, 559, 571, 606, 648, 722, 606, 569, 563, 510, 526, 566, 666, 637, 644, 614, 539, 536, 562, 537 } };
    //global_Queen_PSQT = .{ [_]scoreType{ 836, 814, 811, 875, 888, 710, 684, 794, 771, 884, 907, 922, 909, 946, 912, 885, 791, 861, 904, 887, 904, 872, 911, 911, 812, 836, 853, 880, 865, 900, 939, 931, 847, 783, 886, 886, 908, 895, 895, 919, 855, 768, 819, 890, 983, 1054, 1026, 977, 915, 819, 838, 818, 875, 1017, 1099, 1176, 953, 980, 989, 608, 989, 1104, 1216, 1208 }, [_]scoreType{ 786, 774, 783, 690, 537, 606, 656, 738, 950, 755, 715, 700, 654, 501, 501, 707, 859, 794, 740, 687, 673, 750, 714, 753, 999, 954, 846, 812, 783, 856, 868, 1049, 1125, 1043, 962, 836, 894, 985, 1092, 1184, 1090, 1164, 1029, 975, 876, 974, 1030, 1113, 1061, 1123, 1106, 1087, 1083, 1025, 1139, 1133, 1002, 980, 1078, 1132, 1026, 1037, 1016, 1012 } };
    //global_King_PSQT = .{ [_]scoreType{ -85, 87, -29, -337, -52, -216, 53, -30, 132, -13, -76, -137, -54, -65, 139, 4, 73, -4, -78, -200, 0, -149, -47, -139, -61, 69, 80, 113, 1, -34, -80, -117, 41, 19, 6, 93, 27, 35, -7, -36, 6, 41, 49, 34, 37, -21, 78, 50, 30, 42, 84, 9, 59, 76, 60, 62, -14, 21, 64, 67, 47, 43, 35, 13 }, [_]scoreType{ -236, -184, -185, -70, -240, -135, -202, -218, -210, -261, -191, -188, -203, -201, -297, -149, -114, -166, -153, -122, -153, -171, -221, -111, 8, -99, -84, -82, -96, -101, -104, -8, 152, 51, 53, 40, 18, 35, 27, 110, 209, 201, 192, 127, 150, 197, 212, 187, 113, 217, 211, 190, 222, 224, 212, 280, -32, 152, 254, 261, 207, 253, 180, 40 } };

    //global_MobilityVal = .{ -7, 41 };
    //global_OpenFileRookVal = .{ 35, 83 };
    //global_materialBishopPair = .{ -26, 197 };
    //global_StructureProtectionVal = .{ -3, 7 };
    //global_centerProtectionVal = .{ 6, 6 };
    //global_HangingVal = .{ 26, 191 };
    //global_pieceThreatScore = .{ 26, 124 };
    //global_IsolatedPawnVal = .{ -19, -32 };
    //global_StackedPawnVal = .{ -14, -24 };
    //global_PassedPawnVal = .{ -54, 73 };
    //global_phalanxDuoPawnVal = .{ -44, 81 };
    //global_connectionPawnVal = .{ 40, 16 };
    //global_KingProximityVal = .{ -2, 4 };

    //global_MobilityVal = .{ 9, 60 };
    //global_OpenFileRookVal = .{ 50, 64 };
    //global_StructureProtectionVal = .{ 30, 36 };
    //global_centerProtectionVal = .{ 3, 9 };
    //global_HangingVal = .{ -10, -160 };
    //global_pieceThreatScore = .{ 51, 123 };
    //global_IsolatedPawnVal = .{ 10, 44 };
    //global_StackedPawnVal = .{ -9, -33 };
    //global_PassedPawnVal = .{ -45, 89 };
    //global_phalanxDuoPawnVal = .{ -8, 55 };
    //global_connectionPawnVal = .{ 60, 12 };
    //global_KingProximityVal = .{ 28, -4 };
    //global_materialBishopPair = .{ 5, 188 };
    //lmr_scoreThreshold = 1931;
    //lmr_expectedCutOff = 217;
    //lmr_notImproving = 1193;
    //lmr_hashMoveCapture = 1235;
    //lmr_baseDeficit = 606;
    //lmr_badCapture = 928;
    //lmr_highFailScore = 792;
    //lmr_highFailCount = 3;
    //lmr_hashMoveIsGood = 1093;
    //lmr_inCheck = -1441;
    //lmr_givesCheck = -450;
    //lmr_killerMove = -1159;
    //lmr_threatening = -911;
    //lmr_inPvMode = -271;
    //lmr_isPromotion = -1081;
    //lmr_histDiv = 8799;
    //rfpNotImproving = -23;
    //rfpImproving = -1;
    //rfpDepth = 12;
    //rfpCoeff = 67;
    //rfpConst = 104;
    //captureExtensionThresh = 1223;
    //aspirationCoefficient = 67;
    //aspirationMinDepthVar = 7;
    //nullMoveDepthAugmentThreshold = 8;
    //nullMoveDepthAugment = 5;
    //nullMoveReduction = 6;
    //nullMoveReductionImproving = 6;
    //razoringBaseImproving = 46;
    //razoringBaseNotImproving = 499;
    //razoringCoefficient = 295;
    //razoringMaxDepth = 5;
    //IIRDepthMin = 6;
    //LMRDepth = 2;
    //SeePruningMaxDepth = 2;
    //SeePruningQuietMargin = -146;
    //SeePruningCaptureMargin = -395;
    //probCutMargin = 261;
    //probCutMinimalDepth = 6;
    //futilityDepth = 6;
    //futilityCoeff = 218;
    //futilityConst = 212;
    //historyMaxDepth = 6;
    //historyThreshCoeff = -1902;
    //historyThreshConst = -2049;
    //historyMinExplore = 24;
    //historyBonusCoeff = 291;
    //historyBonusMax = 3887;
    //lmpMaxDepth = 8;
    //lmpBase = 1;
    //moveReductionAmount = 1;
    //moveQsearchAmount = 1;
    //moveGenMinSeeThreshold = -36;
    //corrHistMax = 205;
    //corrHistW = 142;
    //singularExtensionMinDepth = 11;
    //singularExtensionDeltaTTDepth = 4;
    //singularMarginDoubleExt = 85;
}
