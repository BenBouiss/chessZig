const chess = @import("chess.zig");

pub const simplePawnScore: i64 = 10;
pub const simpleBishopScore: i64 = 40;
pub const simpleKnightScore: i64 = 40;
pub const simpleRookScore: i64 = 60;
pub const simpleQueenScore: i64 = 120;
pub const simpleCheckMateScore: i64 = 9999;
pub const simpleStalemateScore: i64 = 0;

pub const e_heuristicType = enum(u8) { Simple = 0, Bitmap };

pub fn mockHeuristic(p_state: *chess.Board_state) i64 {
    _ = p_state;
    return 0;
}

pub fn simpleHeuristic(p_state: *chess.Board_state) i64 {
    var score: i64 = 0;
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
