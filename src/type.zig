pub const e_color = enum(u1) { BLACK = 0, WHITE = 1 };

pub const e_piece = enum(u8) { nWhitePawn = 0, nWhiteBishop = 1, nWhiteKnight = 2, nWhiteRook = 3, nWhiteQueen = 4, nWhiteKing = 5, nBlackPawn = 6, nBlackBishop = 7, nBlackKnight = 8, nBlackRook = 9, nBlackQueen = 10, nBlackKing = 11, nEmptySquare = 12, nWhite, nBlack };
pub const e_pieceType = enum(u8) { PAWN, BISHOP, KNIGHT, ROOK, QUEEN, KING };
pub const e_moveGenFlag = enum(u8) { CAPTURE, QUIET, PROMO, EVASION };

pub const e_moveType = enum { STANDARD, EP, PROMOTION, CASTLE };
pub const e_scoreType = enum { NONE, MATE, STD, DRAW };

pub const e_moveFlags = enum(u8) { QUIETMOVE = 0, DOUBLEPAWN = 1, KINGCASTLE = 2, QUEENCASTLE = 3, CAPTURE = 4, ENPASSANT = 5, KNIGHTPROMO = 8, BISHOPPROMO = 9, ROOKPROMO = 10, QUEENPROMO = 11, KNIGHTPROMOCAPTURE = 12, BISHOPPROMOCAPTURE = 13, ROOKPROMOCAPTURE = 14, QUEENPROMOCAPTURE = 15 };

pub const e_square = enum(u8) { a1 = 0, b1, c1, d1, e1, f1, g1, h1, a2, b2, c2, d2, e2, f2, g2, h2, a3, b3, c3, d3, e3, f3, g3, h3, a4, b4, c4, d4, e4, f4, g4, h4, a5, b5, c5, d5, e5, f5, g5, h5, a6, b6, c6, d6, e6, f6, g6, h6, a7, b7, c7, d7, e7, f7, g7, h7, a8, b8, c8, d8, e8, f8, g8, h8, invalid };

pub const bitboard: type = u64;
pub const scoreType: type = i32;
pub const weightType: type = i32;
