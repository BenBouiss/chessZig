const chess = @import("chess.zig");

const std = @import("std");

const e_piece = chess.e_piece;
const scoreType: type = i64;

pub const simplePawnScore: scoreType = 10;
pub const simpleBishopScore: scoreType = 40;
pub const simpleKnightScore: scoreType = 40;
pub const simpleRookScore: scoreType = 60;
pub const simpleQueenScore: scoreType = 120;
pub const simpleCheckMateScore: scoreType = 9999;
pub const simpleStalemateScore: scoreType = 0;

pub const e_heuristicType = enum(u8) { Simple = 0, Bitmap };

const pawnScoreArr = [chess.N_SQUARES]scoreType{
    0,   0,  0,  0,   0,   0,   0,  0,
    -31, 8,  -7, -37, -36, -14, 3,  -31,
    -22, 9,  5,  -11, -10, -2,  3,  -19,
    -26, 3,  10, 9,   6,   1,   0,  -23,
    -17, 16, -2, 15,  14,  0,   15, -13,
    7,   29, 21, 44,  40,  31,  44, 7,
    78,  83, 86, 73,  102, 82,  85, 90,
    0,   0,  0,  0,   0,   0,   0,  0,
};

const knightScoreArr = [chess.N_SQUARES]scoreType{
    -74, -23, -26, -24, -19, -35, -22, -69,
    -23, -15, 2,   0,   2,   0,   -23, -20,
    -18, 10,  13,  22,  18,  15,  11,  -14,
    -1,  5,   31,  21,  22,  35,  2,   0,
    24,  24,  45,  37,  33,  41,  25,  17,
    10,  67,  1,   74,  73,  27,  62,  -2,
    -3,  -6,  100, -36, 4,   62,  -4,  -14,
    -66, -53, -75, -75, -10, -55, -58, -70,
};

const bishopScoreArr = [chess.N_SQUARES]scoreType{
    -7,  2,   -15, -12, -14, -15,  -10, -10,
    19,  20,  11,  6,   7,   6,    20,  16,
    14,  25,  24,  15,  8,   25,   20,  15,
    13,  10,  17,  23,  17,  16,   0,   7,
    25,  17,  20,  34,  26,  25,   15,  10,
    -9,  39,  -32, 41,  52,  -10,  28,  -14,
    -11, 20,  35,  -42, -39, 31,   2,   -22,
    -59, -78, -82, -76, -23, -107, -37, -50,
};

const rookScoreArr = [chess.N_SQUARES]scoreType{
    -30, -24, -18, 5,   -2,  -18, -31, -32,
    -53, -38, -31, -26, -29, -43, -44, -53,
    -42, -28, -42, -25, -25, -35, -26, -46,
    -28, -35, -16, -21, -13, -29, -46, -30,
    0,   5,   16,  13,  18,  -4,  -9,  -6,
    19,  35,  28,  33,  45,  27,  25,  15,
    55,  29,  56,  67,  55,  62,  34,  60,
    35,  29,  33,  4,   37,  33,  56,  50,
};

const queenScoreArr = [chess.N_SQUARES]scoreType{
    -39, -30, -31, -13,  -31, -36, -34, -42,
    -36, -18, 0,   -19,  -15, -15, -21, -38,
    -30, -6,  -13, -11,  -16, -11, -16, -27,
    -14, -15, -2,  -5,   -1,  -10, -20, -22,
    1,   -16, 22,  17,   25,  20,  -13, -6,
    -2,  43,  32,  60,   72,  63,  43,  2,
    14,  32,  60,  -10,  20,  76,  57,  24,
    6,   1,   -8,  -104, 69,  24,  88,  26,
};

const kingScoreArr = [chess.N_SQUARES]scoreType{
    17,  30,  -3,  -14, 6,   -1,  40,  18,
    -4,  3,   -14, -50, -57, -18, 13,  4,
    -47, -42, -43, -79, -64, -32, -29, -32,
    -55, -43, -52, -28, -51, -47, -8,  -50,
    -55, 50,  11,  -4,  -19, 13,  0,   -49,
    -62, 12,  -57, 44,  -67, 28,  37,  -31,
    -32, 10,  55,  56,  56,  55,  10,  3,
    4,   54,  47,  -99, -99, 60,  83,  -62,
};

pub fn mockHeuristic(p_state: *chess.Board_state) scoreType {
    _ = p_state;
    return 0;
}

pub fn simpleHeuristic(p_state: *chess.Board_state) scoreType {
    var score: scoreType = 0;
    score += p_state.getPieceCount(.nWhitePawn) * simplePawnScore;
    score += p_state.getPieceCount(.nWhiteBishop) * simpleBishopScore;
    score += p_state.getPieceCount(.nWhiteKnight) * simpleKnightScore;
    score += p_state.getPieceCount(.nWhiteRook) * simpleRookScore;
    score += p_state.getPieceCount(.nWhiteQueen) * simpleQueenScore;

    score -= p_state.getPieceCount(.nBlackPawn) * simplePawnScore;
    score -= p_state.getPieceCount(.nBlackBishop) * simpleBishopScore;
    score -= p_state.getPieceCount(.nBlackKnight) * simpleKnightScore;
    score -= p_state.getPieceCount(.nBlackRook) * simpleRookScore;
    score -= p_state.getPieceCount(.nBlackQueen) * simpleQueenScore;

    return score;
}
/// heuristic from past engine python projects
pub fn pastHeuristic(p_state: *chess.Board_state) scoreType {
    var score: scoreType = 0;
    score += matDotScore(getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)]), pawnScoreArr);
    score += matDotScore(getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteKnight)]), knightScoreArr);
    score += matDotScore(getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteBishop)]), bishopScoreArr);
    score += matDotScore(getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteRook)]), rookScoreArr);
    score += matDotScore(getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteQueen)]), queenScoreArr);
    score += matDotScore(getMaskFromBB(p_state.pieceBB[@intFromEnum(e_piece.nWhiteKing)]), kingScoreArr);

    score -= matDotScore(getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)])), pawnScoreArr);
    score -= matDotScore(getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackKnight)])), knightScoreArr);
    score -= matDotScore(getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackBishop)])), bishopScoreArr);
    score -= matDotScore(getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackRook)])), rookScoreArr);
    score -= matDotScore(getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackQueen)])), queenScoreArr);
    score -= matDotScore(getMaskFromBB(chess.rotate180(p_state.pieceBB[@intFromEnum(e_piece.nBlackKing)])), kingScoreArr);
    return score;
}

pub fn matDotScore(m1: [chess.N_SQUARES]scoreType, m2: [chess.N_SQUARES]scoreType) scoreType {
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
        ret[i] = @bitCast(val);
    }
    return ret;
}
