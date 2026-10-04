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

pub fn add_param(alloc: std.mem.Allocator, addr: *scoreType, min: scoreType, max: scoreType, name: []const u8) void {
    const p: param_entry = .{ .addr = addr, .opt = .{ .argType = .SPIN, .optionType = .INVALID, .name = name, .info = enginel.optionInfo{ .spin = .{ .default = addr.*, .min = min, .max = max } } } };
    tunerOpts.append(alloc, p) catch unreachable;
}

pub fn add_param_1d(comptime size: usize, values: *[size]scoreType, min: scoreType, max: scoreType, name: []const u8) !void {
    for (0..size) |i| {
        const n = try std.fmt.allocPrint(mainl.getGlobalGPA(), "{s}_{d}", .{ name, i });
        try strOpts.append(mainl.getGlobalGPA(), n);
        const p: param_entry = .{ .addr = &values[i], .opt = .{ .argType = .SPIN, .optionType = .INVALID, .name = strOpts.items[strOpts.items.len - 1][0..n.len], .info = enginel.optionInfo{ .spin = .{ .default = values[i], .min = min, .max = max } } } };
        tunerOpts.append(mainl.getGlobalGPA(), p) catch unreachable;
    }
}

const WEIGHT_MIN: scoreType = 1;
// global things here
pub fn appendAll(alloc: std.mem.Allocator) !void {
    modif_val();
    add_param(alloc, &global_MobilityVal[0], WEIGHT_MIN, 200, "global_MobilityVal_MG");
    add_param(alloc, &global_MobilityVal[1], WEIGHT_MIN, 200, "global_MobilityVal_EG");

    // structure
    add_param(alloc, &global_StructureProtectionVal[0], WEIGHT_MIN, 200, "global_StructureProtectionVal_MG");
    add_param(alloc, &global_StructureProtectionVal[1], WEIGHT_MIN, 200, "global_StructureProtectionVal_EG");

    add_param(alloc, &global_centerProtectionVal[0], WEIGHT_MIN, 200, "global_centerProtectionVal_MG");
    add_param(alloc, &global_centerProtectionVal[1], WEIGHT_MIN, 200, "global_centerProtectionVal_EG");

    add_param(alloc, &global_HangingVal[0], -200, -WEIGHT_MIN, "global_HangingVal_MG");
    add_param(alloc, &global_HangingVal[1], -200, -WEIGHT_MIN, "global_HangingVal_EG");

    add_param(alloc, &global_pieceThreatScore[0], WEIGHT_MIN, 200, "global_pieceThreatScore_MG");
    add_param(alloc, &global_pieceThreatScore[1], WEIGHT_MIN, 200, "global_pieceThreatScore_EG");

    // pieces

    // pawn structure
    add_param(alloc, &global_IsolatedPawnVal[0], -200, -WEIGHT_MIN, "global_IsolatedPawnVal_MG");
    add_param(alloc, &global_IsolatedPawnVal[1], -200, -WEIGHT_MIN, "global_IsolatedPawnVal_EG");
    add_param(alloc, &global_StackedPawnVal[0], -200, -WEIGHT_MIN, "global_StackedPawnVal_MG");
    add_param(alloc, &global_StackedPawnVal[1], -200, -WEIGHT_MIN, "global_StackedPawnVal_EG");
    add_param(alloc, &global_PassedPawnVal[0], WEIGHT_MIN, 200, "global_PassedPawnVal_MG");
    add_param(alloc, &global_PassedPawnVal[1], WEIGHT_MIN, 200, "global_PassedPawnVal_EG");
    add_param(alloc, &global_phalanxDuoPawnVal[0], WEIGHT_MIN, 200, "global_phalanxDuoPawnVal_MG");
    add_param(alloc, &global_phalanxDuoPawnVal[1], WEIGHT_MIN, 200, "global_phalanxDuoPawnVal_EG");
    add_param(alloc, &global_connectionPawnVal[0], WEIGHT_MIN, 200, "global_connectionPawnVal_MG");
    add_param(alloc, &global_connectionPawnVal[1], WEIGHT_MIN, 200, "global_connectionPawnVal_EG");

    // knight
    add_param(alloc, &global_KnightTrapped[0], WEIGHT_MIN, 100, "global_KnightTrapped_MG");
    add_param(alloc, &global_KnightTrapped[1], WEIGHT_MIN, 100, "global_KnightTrapped_EG");

    add_param(alloc, &global_KnightDefendedByPawn[0], WEIGHT_MIN, 100, "global_KnightTrapped_MG");
    add_param(alloc, &global_KnightDefendedByPawn[1], WEIGHT_MIN, 100, "global_KnightTrapped_EG");

    // bishop
    add_param(alloc, &global_materialBishopPair[0], WEIGHT_MIN, 300, "global_materialBishopPair_MG");
    add_param(alloc, &global_materialBishopPair[1], WEIGHT_MIN, 300, "global_materialBishopPair_EG");

    // rook
    add_param(alloc, &global_OpenFileRookVal[0], WEIGHT_MIN, 200, "global_OpenFileRookVal_MG");
    add_param(alloc, &global_OpenFileRookVal[1], WEIGHT_MIN, 200, "global_OpenFileRookVal_EG");

    add_param(alloc, &global_RookLastRanks[0], WEIGHT_MIN, 200, "global_RookLastRanks_MG");
    add_param(alloc, &global_RookLastRanks[1], WEIGHT_MIN, 200, "global_RookLastRanks_EG");

    add_param(alloc, &global_Rookdoubled[0], WEIGHT_MIN, 200, "global_Rookdoubled_MG");
    add_param(alloc, &global_Rookdoubled[1], WEIGHT_MIN, 200, "global_Rookdoubled_EG");

    add_param(alloc, &global_RookOnQueenFile[0], WEIGHT_MIN, 200, "global_RookOnQueenFile_MG");
    add_param(alloc, &global_RookOnQueenFile[1], WEIGHT_MIN, 200, "global_RookOnQueenFile_EG");

    // king

    add_param(alloc, &global_KingProximityVal[0], WEIGHT_MIN, 200, "global_KingProximityVal_MG");
    add_param(alloc, &global_KingProximityVal[1], WEIGHT_MIN, 200, "global_KingProximityVal_EG");

    add_param(alloc, &global_KingTropism, WEIGHT_MIN, 200, "global_KingTropism");

    add_param(alloc, &global_KingPawnlessFlank[0], WEIGHT_MIN, 200, "global_KingPawnlessFlank_MG");
    add_param(alloc, &global_KingPawnlessFlank[1], WEIGHT_MIN, 200, "global_KingPawnlessFlank_EG");

    add_param(alloc, &global_KingOpenFile, WEIGHT_MIN, 200, "global_KingOpenFile");

    // LMR
    add_param(alloc, &lmr_scoreThreshold, 0, 20000, "lmr_scoreThreshold");
    add_param(alloc, &lmr_expectedCutOff, 0, 2000, "lmr_expectedCutOff");
    add_param(alloc, &lmr_notImproving, 0, 2000, "lmr_notImproving");
    add_param(alloc, &lmr_hashMoveCapture, 0, 2000, "lmr_hashMoveCapture");
    add_param(alloc, &lmr_baseDeficit, 0, 2000, "lmr_baseDeficit");
    add_param(alloc, &lmr_badCapture, 0, 2000, "lmr_badCapture");

    add_param(alloc, &lmr_highFailScore, 100, 2000, "lmr_highFailScore");
    add_param(alloc, &lmr_highFailCount, 1, 16, "lmr_highFailCount");
    add_param(alloc, &lmr_hashMoveIsGood, 0, 4000, "lmr_hashMoveIsGood");

    add_param(alloc, &lmr_inCheck, -4000, 0, "lmr_inCheck");
    add_param(alloc, &lmr_givesCheck, -4000, 0, "lmr_givesCheck");
    add_param(alloc, &lmr_killerMove, -4000, 0, "lmr_killerMove");
    add_param(alloc, &lmr_threatening, -4000, 0, "lmr_threatening");
    add_param(alloc, &lmr_inPvMode, -4000, 0, "lmr_inPvMode");
    add_param(alloc, &lmr_isPromotion, -4000, 0, "lmr_isPromotion");
    add_param(alloc, &lmr_histDiv, 0, 12000, "lmr_histDiv");

    // margins
    //add_param(alloc, &futilityMargin[0], 0, 1500, "futilityMargin_0");
    //add_param(alloc, &futilityMargin[1], 0, 1500, "futilityMargin_1");
    //add_param(alloc, &futilityMargin[2], 0, 1500, "futilityMargin_2");
    //add_param(alloc, &futilityMargin[3], 0, 1500, "futilityMargin_3");
    //try add_param_1d(futilityMargin.len, &futilityMargin, 0, 1500, "futilityMargin");
    //try add_param_1d(rfpMargin.len, &rfpMargin, 0, 1500, "rfpMargin");

    add_param(alloc, &rfpNotImproving, -500, 0, "rfpNotImproving");
    add_param(alloc, &rfpImproving, -500, 0, "rfpImproving");
    add_param(alloc, &rfpDepth, 2, 12, "rfpDepth");
    add_param(alloc, &rfpCoeff, 25, 150, "rfpCoeff");
    add_param(alloc, &rfpConst, 25, 150, "rfpConst");

    add_param(alloc, &captureExtensionThresh, 0, 10000, "captureExtensionThresh");

    add_param(alloc, &aspirationCoefficient, 10, 200, "aspirationCoefficient");
    add_param(alloc, &aspirationMinDepthVar, 2, 14, "aspirationMinDepthVar");
    add_param(alloc, &nullMoveDepthAugmentThreshold, 8, 32, "nullMoveDepthAugmentThreshold");
    add_param(alloc, &nullMoveDepthAugment, 2, 6, "nullMoveDepthAugment");
    add_param(alloc, &nullMoveReduction, 2, 8, "nullMoveReduction");
    add_param(alloc, &nullMoveReductionImproving, 2, 8, "nullMoveReductionImproving");

    add_param(alloc, &razoringBaseImproving, 0, 1000, "razoringBaseImproving");
    add_param(alloc, &razoringBaseNotImproving, 0, 1000, "razoringBaseNotImproving");
    add_param(alloc, &razoringCoefficient, 0, 1000, "razoringCoefficient");
    add_param(alloc, &razoringMaxDepth, 2, 12, "razoringMaxDepth");
    add_param(alloc, &IIRDepthMin, 2, 6, "IIRDepthMin");
    add_param(alloc, &LMRDepth, 2, 8, "LMRDepth");

    add_param(alloc, &SeePruningMaxDepth, 2, 12, "SeePruningMaxDepth");
    add_param(alloc, &SeePruningQuietMargin, -400, 0, "SeePruningQuietMargin");
    add_param(alloc, &SeePruningCaptureMargin, -400, 0, "SeePruningCaptureMargin");

    add_param(alloc, &probCutMargin, 0, 500, "probCutMargin");
    add_param(alloc, &probCutMinimalDepth, 2, 10, "probCutMinimalDepth");

    add_param(alloc, &futilityDepth, 2, 16, "futilityDepth");
    add_param(alloc, &futilityCoeff, 50, 500, "futilityCoeff");
    add_param(alloc, &futilityConst, 50, 500, "futilityConst");

    add_param(alloc, &historyMaxDepth, 2, 14, "historyMaxDepth");
    add_param(alloc, &historyThreshCoeff, -12000, 0, "historyThreshCoeff");
    add_param(alloc, &historyThreshConst, -10000, 0, "historyThreshConst");
    add_param(alloc, &historyMinExplore, 3, 24, "historyMinExplore");

    add_param(alloc, &historyBonusCoeff, 150, 512, "historyBonusCoeff");
    add_param(alloc, &historyBonusMax, 1024, 65576, "historyBonusMax");
    //add_param(alloc, &historyBonusBetaDiff, 200, 1024, "historyBonusBetaDiff");

    add_param(alloc, &lmpMaxDepth, 2, 14, "lmpMaxDepth");
    add_param(alloc, &lmpBase, 1, 24, "lmpBase");

    add_param(alloc, &moveReductionAmount, 1, 10, "moveReductionAmount");
    add_param(alloc, &moveQsearchAmount, 1, 10, "moveQsearchAmount");

    add_param(alloc, &moveGenMinSeeThreshold, -256, -32, "moveGenMinSeeThreshold");

    add_param(alloc, &corrHistMax, 64, 10000, "corrHistMax");
    add_param(alloc, &corrHistW, 64, 512, "corrHistW");

    add_param(alloc, &singularExtensionMinDepth, 2, 14, "singularExtensionMinDepth");
    add_param(alloc, &singularExtensionDeltaTTDepth, 2, 6, "singularExtensionDeltaTTDepth");
    add_param(alloc, &singularMarginDoubleExt, 8, 128, "singularMarginDoubleExt");

    add_param(alloc, &bestMoveMax, 4, 32, "bestMoveMax");
    add_param(alloc, &nodeFactor1, 100, 200, "nodeFactor1");
    add_param(alloc, &nodeFactor2, 100, 200, "nodeFactor2");

    add_param(alloc, &tmFactor, 100, 200, "tmFactor");
    add_param(alloc, &tmBmCoeff, 3, 30, "tmBmCoeff");

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

// ============ structure ============
pub var global_StructureProtectionVal: [2]scoreType = .{ 18, 19 };
pub var global_centerProtectionVal: [2]scoreType = .{ 1, 2 };
pub var global_HangingVal: [2]scoreType = .{ -32, -32 };
pub var global_pieceThreatScore: [2]scoreType = .{ 48, 13 };

// pieces
// ============ pawn structure ============
pub var global_IsolatedPawnVal: [2]scoreType = .{ -2, 0 };
pub var global_StackedPawnVal: [2]scoreType = .{ -7, -2 };
pub var global_PassedPawnVal: [2]scoreType = .{ 2, 20 };
pub var global_phalanxDuoPawnVal: [2]scoreType = .{ 3, 11 };
pub var global_connectionPawnVal: [2]scoreType = .{ 5, 10 };

// knight
pub var global_KnightTrapped: [2]scoreType = .{ 4, 4 };
pub var global_KnightDefendedByPawn: [2]scoreType = .{ 4, 4 };

// bishop
pub var global_materialBishopPair: [2]scoreType = .{ 55, 62 };

// rook
pub var global_OpenFileRookVal: [2]scoreType = .{ 47, 15 };
pub var global_RookLastRanks: [2]scoreType = .{ 32, 32 };
pub var global_Rookdoubled: [2]scoreType = .{ 16, 16 };
pub var global_RookOnQueenFile: [2]scoreType = .{ 8, 8 };

// king
pub var global_KingProximityVal: [2]scoreType = .{ 5, 5 };
pub var global_KingTropism: scoreType = 8;
pub var global_KingPawnlessFlank: [2]scoreType = .{ 8, 32 };
pub var global_KingOpenFile: scoreType = 8;

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

pub const searchMoveBufferSize: usize = 64;

pub fn modif_val() void {
    //
}
