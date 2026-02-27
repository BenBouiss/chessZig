const configl = @import("config.zig");
const heuristicl = @import("heuristic.zig");
const chessl = @import("chess.zig");

const scoreType = heuristicl.scoreType;
const weightType = heuristicl.weightType;
const NVector = heuristicl.NVector;

// values from https://www.chessprogramming.org/Evaluation for now
pub const simplePawnScore: scoreType = 100;
pub const simpleBishopScore: scoreType = 300;
pub const simpleKnightScore: scoreType = 300;
pub const simpleRookScore: scoreType = 500;
pub const simpleQueenScore: scoreType = 900;
pub const simpleCheckMateScore: scoreType = 99999;
pub const simpleStalemateScore: scoreType = 0;

pub const simpleMobilityScore: scoreType = 5;
pub const simpleIsolatedPawnScore: scoreType = -1;
pub const simpleStackedPawnScore: scoreType = -1;

pub const simplePassedPawnScore: scoreType = 2;
pub const simpleStructureProtectionScore: scoreType = 1;

// source: https://www.chessprogramming.org/King_Safety
pub const simpleSafetyBishopScore: scoreType = 20;
pub const simpleSafetyKnightScore: scoreType = 20;
pub const simpleSafetyRookScore: scoreType = 40;
pub const simpleSafetyQueenScore: scoreType = 80;

pub var weights: heuristicl.coeffTuple = .{ .val = [_]NVector{ .{ .val = undefined }, .{ .val = undefined } } };

pub const pawnScoreArr = [chessl.N_SQUARES]scoreType{ 0, 0, 0, 0, 0, 0, 0, 0, -31, 8, -7, -37, -36, -14, 3, -31, -22, 9, 5, -11, -10, -2, 3, -19, -26, 3, 10, 9, 6, 1, 0, -23, -17, 16, -2, 15, 14, 0, 15, -13, 7, 28, 21, 44, 40, 31, 44, 7, 78, 83, 86, 73, 102, 82, 85, 90, 0, 0, 0, 0, 0, 0, 0, 0 };

pub const knightScoreArr = [chessl.N_SQUARES]scoreType{ -5, 1, -11, -9, -10, -11, -7, -7, 14, 15, 8, 4, 5, 4, 15, 12, 10, 18, 18, 11, 6, 18, 15, 11, 9, 7, 12, 17, 12, 12, 0, 5, 18, 12, 15, 25, 19, 18, 11, 7, -6, 29, -24, 30, 39, -7, 21, -10, -8, 15, 26, -31, -29, 23, 1, -16, -44, -58, -61, -56, -17, -80, -27, -37 };

pub const bishopScoreArr = [chessl.N_SQUARES]scoreType{ -5, 1, -11, -9, -10, -11, -7, -7, 14, 15, 8, 4, 5, 4, 15, 12, 10, 18, 18, 11, 6, 18, 15, 11, 9, 7, 12, 17, 12, 12, 0, 5, 18, 12, 15, 25, 19, 18, 11, 7, -6, 29, -24, 30, 39, -7, 21, -10, -8, 15, 26, -31, -29, 23, 1, -16, -44, -58, -61, -56, -17, -80, -27, -37 };

pub const rookScoreArr = [chessl.N_SQUARES]scoreType{ -25, -20, -15, 4, -1, -15, -25, -26, -44, -31, -25, -21, -24, -35, -36, -44, -35, -23, -35, -20, -20, -29, -21, -38, -23, -29, -13, -17, -10, -24, -38, -25, 0, 4, 13, 10, 15, -3, -7, -5, 15, 29, 23, 27, 37, 22, 20, 12, 45, 24, 46, 55, 45, 51, 28, 50, 29, 24, 27, 3, 30, 27, 46, 41 };

pub const queenScoreArr = [chessl.N_SQUARES]scoreType{ -29, -22, -23, -9, -23, -27, -25, -31, -27, -13, 0, -14, -11, -11, -15, -28, -22, -4, -9, -8, -12, -8, -12, -20, -10, -11, -1, -3, 0, -7, -15, -16, 0, -12, 16, 12, 18, 15, -9, -4, -1, 32, 24, 44, 54, 47, 32, 1, 10, 24, 44, -7, 15, 56, 42, 18, 4, 0, -6, -78, 51, 18, 65, 19 };

pub const kingScoreArr = [chessl.N_SQUARES]scoreType{ 17, 30, -3, -14, 6, -1, 40, 18, -4, 3, -14, -50, -57, -18, 13, 4, -47, -42, -43, -79, -64, -32, -28, -32, -55, -43, -52, -28, -51, -47, -8, -50, -55, 50, 11, -4, -19, 13, 0, -49, -62, 12, -57, 44, -67, 28, 37, -31, -32, 10, 55, 56, 56, 55, 10, 3, 4, 54, 47, -99, -99, 60, 83, -62 };
