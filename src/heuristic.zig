const chess = @import("chess.zig");
const moveGenl = @import("move_generation.zig");
const filel = @import("file.zig");
const stringl = @import("string.zig");
const utilsl = @import("utils.zig");

const std = @import("std");

const e_piece = chess.e_piece;
const string = stringl.string;
pub const scoreType: type = f64;

// values from https://www.chessprogramming.org/Evaluation for now
pub const simplePawnScore: scoreType = 1;
pub const simpleBishopScore: scoreType = 3;
pub const simpleKnightScore: scoreType = 3;
pub const simpleRookScore: scoreType = 5;
pub const simpleQueenScore: scoreType = 9;
pub const simpleCheckMateScore: scoreType = 99999;
pub const simpleStalemateScore: scoreType = 0;
pub const simpleMobilityScore: scoreType = 0.1;
pub const simpleIsolatedPawnScore: scoreType = 0.2;
pub const simpleStackedPawnScore: scoreType = 0.2;

pub const e_heuristicType = enum(u8) { Simple = 0, Bitmap };

//const pawnScoreArr = [chess.N_SQUARES]scoreType{
//    0,     0,    0,    0,     0,     0,     0,    0,
//    -0.31, 0.8,  -0.7, -0.37, -0.36, -0.14, 0.3,  -0.31,
//    -0.22, 0.9,  0.5,  -0.11, -0.10, -0.2,  0.3,  -0.19,
//    -0.26, 0.3,  0.10, 0.9,   0.6,   0.1,   0,    -0.23,
//    -0.17, 0.16, -0.2, 0.15,  0.14,  0,     0.15, -0.13,
//    0.7,   0.29, 0.21, 0.44,  0.40,  0.31,  0.44, 0.7,
//    0.78,  0.83, 0.86, 0.73,  0.102, 0.82,  0.85, 0.90,
//    0,     0,    0,    0,     0,     0,     0,    0,
//};

var pawnScoreArr = [chess.N_SQUARES]scoreType{
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -0.31, 0.08, -0.07, -0.37, -0.36, -0.14, 0.03, -0.31, -0.22, 0.09, 0.05, -0.11, -0.1, -0.02, 0.03, -0.19, -0.26, 0.03, 0.1, 0.09, 0.06, 0.01, 0.0, -0.23, -0.17, 0.16, -0.02, 0.15, 0.14, 0.0, 0.15, -0.13, 0.07, 0.29, 0.21, 0.44, 0.4, 0.31, 0.44, 0.07, 0.78, 0.8300000000000001, 0.86, 0.73, 1.02, 0.8200000000000001, 0.85, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
};

//const knightScoreArr = [chess.N_SQUARES]scoreType{
//    -0.74, -0.23, -0.26, -0.24, -0.19, -0.35, -0.22, -0.69,
//    -0.23, -0.15, 0.02,  0.0,   0.02,  0.0,   -0.23, -0.20,
//    -0.18, 0.10,  0.13,  0.22,  0.18,  0.15,  0.11,  -0.14,
//    -0.01, 0.05,  0.31,  0.21,  0.22,  0.5,   0.02,  0.0,
//    0.24,  0.24,  0.45,  0.37,  0.33,  0.1,   0.25,  0.17,
//    0.10,  0.67,  0.01,  0.74,  0.73,  0.7,   0.62,  -0.02,
//    -0.03, -0.06, 0.900, -0.36, 0.04,  0.2,   -0.4,  -0.14,
//    -0.66, -0.53, -0.75, -0.75, -0.10, -0.55, -0.58, -0.70,
//};
var knightScoreArr = [chess.N_SQUARES]scoreType{
    -0.0525, 0.015, -0.11249999999999999, -0.09, -0.105, -0.11249999999999999, -0.075, -0.075, 0.1425, 0.15, 0.08249999999999999, 0.045, 0.0525, 0.045, 0.15, 0.12, 0.105, 0.1875, 0.18, 0.11249999999999999, 0.06, 0.1875, 0.15, 0.11249999999999999, 0.0975, 0.075, 0.1275, 0.1725, 0.1275, 0.12, 0.0, 0.0525, 0.1875, 0.1275, 0.15, 0.255, 0.195, 0.1875, 0.11249999999999999, 0.075, -0.0675, 0.2925, -0.24, 0.3075, 0.39, -0.075, 0.21, -0.105, -0.08249999999999999, 0.15, 0.2625, -0.315, -0.2925, 0.23249999999999998, 0.015, -0.16499999999999998, -0.4425, -0.585, -0.615, -0.57, -0.1725, -0.8025, -0.27749999999999997, -0.375,
};

//const bishopScoreArr = [chess.N_SQUARES]scoreType{
//    -0.07, 0.2,   -0.15, -0.12, -0.14, -0.15,  -0.10, -0.10,
//    0.19,  0.20,  0.11,  0.6,   0.07,  0.06,   0.20,  0.16,
//    0.14,  0.25,  0.24,  0.15,  0.08,  0.25,   0.20,  0.15,
//    0.13,  0.10,  0.17,  0.23,  0.17,  0.16,   0.0,   0.07,
//    0.25,  0.17,  0.20,  0.34,  0.26,  0.25,   0.15,  0.10,
//    -0.9,  0.39,  -0.32, 0.41,  0.52,  -0.10,  0.28,  -0.14,
//    -0.11, 0.20,  0.35,  -0.42, -0.39, 0.31,   0.02,  -0.22,
//    -0.59, -0.78, -0.82, -0.76, -0.23, -0.907, -0.37, -0.50,
//};
var bishopScoreArr = [chess.N_SQUARES]scoreType{
    -0.0525, 0.015, -0.11249999999999999, -0.09, -0.105, -0.11249999999999999, -0.075, -0.075, 0.1425, 0.15, 0.08249999999999999, 0.045, 0.0525, 0.045, 0.15, 0.12, 0.105, 0.1875, 0.18, 0.11249999999999999, 0.06, 0.1875, 0.15, 0.11249999999999999, 0.0975, 0.075, 0.1275, 0.1725, 0.1275, 0.12, 0.0, 0.0525, 0.1875, 0.1275, 0.15, 0.255, 0.195, 0.1875, 0.11249999999999999, 0.075, -0.0675, 0.2925, -0.24, 0.3075, 0.39, -0.075, 0.21, -0.105, -0.08249999999999999, 0.15, 0.2625, -0.315, -0.2925, 0.23249999999999998, 0.015, -0.16499999999999998, -0.4425, -0.585, -0.615, -0.57, -0.1725, -0.8025, -0.27749999999999997, -0.375,
};

//const rookScoreArr = [chess.N_SQUARES]scoreType{
//    -0.30, -0.24, -0.18, 0.05,  -0.02, -0.18, -0.31, -0.32,
//    -0.53, -0.38, -0.31, -0.26, -0.29, -0.43, -0.44, -0.53,
//    -0.42, -0.28, -0.42, -0.25, -0.25, -0.35, -0.26, -0.46,
//    -0.28, -0.35, -0.16, -0.21, -0.13, -0.29, -0.46, -0.30,
//    0.0,   0.5,   0.16,  0.13,  0.18,  -0.04, -0.09, -0.06,
//    0.19,  0.35,  0.28,  0.33,  0.45,  0.27,  0.25,  0.15,
//    0.55,  0.29,  0.56,  0.67,  0.55,  0.62,  0.34,  0.60,
//    0.35,  0.29,  0.33,  0.4,   0.37,  0.33,  0.56,  0.50,
//};

var rookScoreArr = [chess.N_SQUARES]scoreType{
    -0.25, -0.2, -0.15, 0.041666666666666664, -0.016666666666666666, -0.15, -0.2583333333333333, -0.26666666666666666, -0.44166666666666665, -0.31666666666666665, -0.2583333333333333, -0.21666666666666667, -0.24166666666666667, -0.35833333333333334, -0.36666666666666664, -0.44166666666666665, -0.35, -0.23333333333333334, -0.35, -0.20833333333333334, -0.20833333333333334, -0.2916666666666667, -0.21666666666666667, -0.3833333333333333, -0.23333333333333334, -0.2916666666666667, -0.13333333333333333, -0.175, -0.10833333333333334, -0.24166666666666667, -0.3833333333333333, -0.25, 0.0, 0.041666666666666664, 0.13333333333333333, 0.10833333333333334, 0.15, -0.03333333333333333, -0.075, -0.05, 0.15833333333333333, 0.2916666666666667, 0.23333333333333334, 0.275, 0.375, 0.225, 0.20833333333333334, 0.125, 0.4583333333333333, 0.24166666666666667, 0.4666666666666667, 0.5583333333333333, 0.4583333333333333, 0.5166666666666666, 0.2833333333333333, 0.5, 0.2916666666666667, 0.24166666666666667, 0.275, 0.03333333333333333, 0.30833333333333335, 0.275, 0.4666666666666667, 0.4166666666666667,
};
//const queenScoreArr = [chess.N_SQUARES]scoreType{
//    -0.39, -0.30, -0.31, -0.13,  -0.31, -0.36, -0.34, -0.42,
//    -0.36, -0.18, 0,     -0.19,  -0.15, -0.15, -0.21, -0.38,
//    -0.30, -0.06, -0.13, -0.11,  -0.16, -0.11, -0.16, -0.27,
//    -0.14, -0.15, -0.02, -0.05,  -0.01, -0.10, -0.20, -0.22,
//    0.01,  -0.16, 0.22,  0.17,   0.25,  0.20,  -0.13, -0.6,
//    -0.02, 0.43,  0.32,  0.60,   0.72,  0.63,  0.43,  0.2,
//    0.14,  0.32,  0.60,  -0.10,  0.20,  0.76,  0.57,  0.24,
//    0.06,  0.01,  -0.08, -0.904, 0.69,  0.24,  0.88,  0.26,
//};
var queenScoreArr = [chess.N_SQUARES]scoreType{
    -0.2925, -0.22499999999999998, -0.23249999999999998, -0.0975, -0.23249999999999998, -0.27, -0.255, -0.315, -0.27, -0.135, 0.0, -0.1425, -0.11249999999999999, -0.11249999999999999, -0.1575, -0.285, -0.22499999999999998, -0.045, -0.0975, -0.08249999999999999, -0.12, -0.08249999999999999, -0.12, -0.20249999999999999, -0.105, -0.11249999999999999, -0.015, -0.0375, -0.0075, -0.075, -0.15, -0.16499999999999998, 0.0075, -0.12, 0.16499999999999998, 0.1275, 0.1875, 0.15, -0.0975, -0.045, -0.015, 0.3225, 0.24, 0.44999999999999996, 0.54, 0.4725, 0.3225, 0.015, 0.105, 0.24, 0.44999999999999996, -0.075, 0.15, 0.57, 0.4275, 0.18, 0.045, 0.0075, -0.06, -0.78, 0.5175, 0.18, 0.6599999999999999, 0.195,
};

//const kingScoreArr = [chess.N_SQUARES]scoreType{
//    0.17,  0.30,  -0.3,  -0.14, 0.6,   -0.01, 0.40,  0.18,
//    -0.04, 0.03,  -0.14, -0.50, -0.57, -0.18, 0.13,  0.04,
//    -0.47, -0.42, -0.43, -0.79, -0.64, -0.32, -0.29, -0.32,
//    -0.55, -0.43, -0.52, -0.28, -0.51, -0.47, -0.08, -0.50,
//    -0.55, 0.50,  0.11,  -0.4,  -0.19, 0.13,  0.0,   -0.49,
//    -0.62, 0.12,  -0.57, 0.44,  -0.67, 0.28,  0.37,  -0.31,
//    -0.32, 0.10,  0.55,  0.56,  0.56,  0.55,  0.10,  0.03,
//    0.4,   0.54,  0.47,  -0.99, -0.99, 0.60,  0.83,  -0.62,
//};
var kingScoreArr = [chess.N_SQUARES]scoreType{
    0.17, 0.3, -0.03, -0.14, 0.06, -0.01, 0.4, 0.18, -0.04, 0.03, -0.14, -0.5, -0.5700000000000001, -0.18, 0.13, 0.04, -0.47000000000000003, -0.42, -0.43, -0.79, -0.64, -0.32, -0.29, -0.32, -0.55, -0.43, -0.52, -0.28, -0.51, -0.47000000000000003, -0.08, -0.5, -0.55, 0.5, 0.11, -0.04, -0.19, 0.13, 0.0, -0.49, -0.62, 0.12, -0.5700000000000001, 0.44, -0.67, 0.28, 0.37, -0.31, -0.32, 0.1, 0.55, 0.56, 0.56, 0.55, 0.1, 0.03, 0.04, 0.54, 0.47000000000000003, -0.99, -0.99, 0.6, 0.8300000000000001, -0.62,
};

pub fn mockHeuristic(p_state: *chess.Board_state) scoreType {
    _ = p_state;
    return 0;
}

pub fn simpleHeuristic(p_state: *chess.Board_state) scoreType {
    var score: scoreType = 0;
    score += @as(scoreType, @floatFromInt(p_state.getPieceCount(.nWhitePawn))) * simplePawnScore;
    score += @as(scoreType, @floatFromInt(p_state.getPieceCount(.nWhiteBishop))) * simpleBishopScore;
    score += @as(scoreType, @floatFromInt(p_state.getPieceCount(.nWhiteKnight))) * simpleKnightScore;
    score += @as(scoreType, @floatFromInt(p_state.getPieceCount(.nWhiteRook))) * simpleRookScore;
    score += @as(scoreType, @floatFromInt(p_state.getPieceCount(.nWhiteQueen))) * simpleQueenScore;

    score -= @as(scoreType, @floatFromInt(p_state.getPieceCount(.nBlackPawn))) * simplePawnScore;
    score -= @as(scoreType, @floatFromInt(p_state.getPieceCount(.nBlackBishop))) * simpleBishopScore;
    score -= @as(scoreType, @floatFromInt(p_state.getPieceCount(.nBlackKnight))) * simpleKnightScore;
    score -= @as(scoreType, @floatFromInt(p_state.getPieceCount(.nBlackRook))) * simpleRookScore;
    score -= @as(scoreType, @floatFromInt(p_state.getPieceCount(.nBlackQueen))) * simpleQueenScore;

    return score;
}
/// heuristic from past engine python projects
pub fn _pastHeuristic(p_state: *chess.Board_state) scoreType {
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
    return score + simpleHeuristic(p_state);
}
pub fn pastHeuristic(p_state: *chess.Board_state) scoreType {
    var score: scoreType = 0;
    for (0..chess.N_SQUARES) |sq| {
        const piece = p_state.get_piece(@intCast(sq));
        switch (piece) {
            .nEmptySquare, .nWhite, .nBlack => {},

            .nWhitePawn => {
                score += pawnScoreArr[sq];
            },
            .nWhiteBishop => {
                score += bishopScoreArr[sq];
            },
            .nWhiteKnight => {
                score += knightScoreArr[sq];
            },
            .nWhiteRook => {
                score += rookScoreArr[sq];
            },
            .nWhiteQueen => {
                score += queenScoreArr[sq];
            },
            .nWhiteKing => {
                score += kingScoreArr[sq];
            },

            .nBlackPawn => {
                score -= pawnScoreArr[(chess.N_SQUARES - 1) - sq];
            },
            .nBlackBishop => {
                score -= bishopScoreArr[(chess.N_SQUARES - 1) - sq];
            },
            .nBlackKnight => {
                score -= knightScoreArr[(chess.N_SQUARES - 1) - sq];
            },
            .nBlackRook => {
                score -= rookScoreArr[(chess.N_SQUARES - 1) - sq];
            },
            .nBlackQueen => {
                score -= queenScoreArr[(chess.N_SQUARES - 1) - sq];
            },
            .nBlackKing => {
                score -= kingScoreArr[(chess.N_SQUARES - 1) - sq];
            },
        }
    }
    return score + simpleHeuristic(p_state) + mobilityScore(p_state) + pawnStructureScore(p_state);
}
pub fn pawnStructureScore(p_state: *chess.Board_state) scoreType {
    const isolatedScore = (-simpleIsolatedPawnScore) * @as(scoreType, @floatFromInt(chess.l_popcount(chess.isolatedPawns(p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)])) - chess.l_popcount(chess.isolatedPawns(p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)]))));
    const doubledPawn = (-simpleStackedPawnScore) * @as(scoreType, @floatFromInt(chess.l_popcount(chess.stackedPawns(p_state.pieceBB[@intFromEnum(e_piece.nWhitePawn)])) - chess.l_popcount(chess.stackedPawns(p_state.pieceBB[@intFromEnum(e_piece.nBlackPawn)]))));
    return doubledPawn + isolatedScore;
}
pub fn mobilityScore(p_state: *chess.Board_state) scoreType {
    // going to use "raw" mobility only taking board coverage
    // now trying with only legals
    var moveW = moveGenl._moveGenBB(p_state, true);
    var moveB = moveGenl._moveGenBB(p_state, false);
    return simpleMobilityScore * @as(scoreType, @floatFromInt(moveW.count() - moveB.count()));

    // these are insanely expensive
    //const moveW = moveGenl.generateMoveCountLegalMoves(p_state, true);
    //const moveB = moveGenl.generateMoveCountLegalMoves(p_state, false);
    //return simpleMobilityScore * @as(scoreType, @floatFromInt(moveW - moveB));
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
pub fn modifyHeuristicWeight(alloc: std.mem.Allocator, path: []const u8, debug: bool) !void {
    // format
    var tokens = try filel.getTokensFromFile(alloc, path, ';');
    //var tokens = try filel.getTokensFromFile(alloc, path, ']');
    defer stringl.freeArrayList_string(alloc, &tokens);
    for (0..tokens.items.len) |j| {
        var s = tokens.items[j];
        //try s.extendWithResize(alloc, "]");
        const valuesStr: []const u8 = s.extractFromBounds("[", "]") catch {
            continue;
        };

        var tmp = try string.initFromSlice(alloc, valuesStr);
        defer tmp.free(alloc);

        var values = try tmp.split(alloc, ',');
        defer values.deinit(alloc);
        if (values.items.len != chess.N_SQUARES) {
            continue;
        }
        var buffer: [chess.N_SQUARES]scoreType = undefined;
        for (0..chess.N_SQUARES) |i| {
            buffer[i] = std.fmt.parseFloat(scoreType, utilsl.stripStr(values.items[i])) catch {
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
            pawnScoreArr = buffer;
        } else if (s.containsE("knight", .ignoreCase)) {
            knightScoreArr = buffer;
        } else if (s.containsE("bishop", .ignoreCase)) {
            bishopScoreArr = buffer;
        } else if (s.containsE("rook", .ignoreCase)) {
            rookScoreArr = buffer;
        } else if (s.containsE("queen", .ignoreCase)) {
            queenScoreArr = buffer;
        } else if (s.containsE("king", .ignoreCase)) {
            kingScoreArr = buffer;
        } else {
            if (debug) {
                std.debug.print("[DEBUG] modifyHeuristicWeight: unknown token \n[", .{});
            }
        }
    }
}
