const std = @import("std");

const typel = @import("type.zig");
const boardl = @import("board.zig");
const chessl = @import("chess.zig");
const heuristicl = @import("heuristic.zig");
const stringl = @import("string.zig");
const filel = @import("file.zig");
const configl = @import("config.zig");
const utilsl = @import("utils.zig");
const mainl = @import("main.zig");
const movel = @import("move.zig");
const benchmarkl = @import("search/benchmark.zig");
const ssel = @import("intrinsics/sse.zig");
const mathl = @import("math.zig");

const scoreType = typel.scoreType;
const e_color = typel.e_color;

pub const networkScale = 400;
pub const QA = 255;
pub const QB = 64;
pub const QAQB = 255 * 64;
pub const HL_SIZE = 128; // 1024 or 3072 per the site(?)
pub const INPUT_SIZE = 768; // 6 pieces x 2 colors x 64 sqs
pub const FORWARD_LOOP = HL_SIZE / 16;
pub const _FORWARD_LOOP = HL_SIZE / 32;

const __m512i = ssel.__m512i;
const __m256i = ssel.__m256i;
const __m128i = ssel.__m128i;

const VEC_ZERO: __m256i = ssel._mm_setzero_si256();
const VEC_QA: __m256i = ssel._mm256_set1_epi16(QA);

const _VEC_ZERO: __m512i = ssel._mm_setzero_si512();
const _VEC_QA: __m512i = ssel._mm512_set1_epi16(QA);

//https://www.chessprogramming.org/NNUE
pub const network = struct {
    accWeights: [INPUT_SIZE][HL_SIZE]i16 align(64) = std.mem.zeroes([INPUT_SIZE][HL_SIZE]i16),
    accBiases: [HL_SIZE]i16 = @splat(0),

    outputWeights: [2 * HL_SIZE]i16 = @splat(0),
    outputBiase: i16 = 0,
    pub fn init(alloc: std.mem.Allocator, path: []const u8) !network {
        const content = try std.Io.Dir.readFileAlloc(.cwd(), mainl.getGlobalIo(), path, alloc, .unlimited);
        const ret: *network = @ptrCast(@alignCast(content));
        return ret.*;
    }
    //pub fn free(self: *network, alloc: std.mem.Allocator) !void {
    //    const _ptr: []u8 = @ptrCast(@alignCast(self));
    //}
};
pub const accumulator = struct {
    values: [HL_SIZE]i16 align(64) = std.mem.zeroes([HL_SIZE]i16),
    pub inline fn init(arr: *const [HL_SIZE]i16) accumulator {
        var ret: accumulator = undefined;
        @memcpy(&ret.values, arr);
        return ret;
    }
    pub fn addNetwork(self: *accumulator, n: *network, index: usize) void {
        for (0..HL_SIZE) |i| {
            self.values[i] += n.accWeights[index][i];
        }
    }
    pub fn subNetwork(self: *accumulator, n: *network, index: usize) void {
        for (0..HL_SIZE) |i| {
            self.values[i] -= n.accWeights[index][i];
        }
    }
};
pub const accumulatorPair = struct {
    w: accumulator = .{},
    b: accumulator = .{},
    pub fn print(self: *const accumulatorPair) void {
        std.debug.print("w {any} \n b {any} \n", .{ self.w, self.b });
    }
};
pub const accumulatorPairStack = struct {
    items: [typel.MAX_PLY + configl.MAX_QUIESC_DEPTH]accumulatorPair = @splat(.{}),
    len: usize = 0,
    pub fn getCurrent(self: *const accumulatorPair) *accumulatorPair {
        return self.items[self.len - 1];
    }
    pub fn append(self: *accumulator, item: accumulatorPair) void {
        self.items[self.len] = item;
        self.len += 1;
    }
    pub fn pop(self: *accumulator) void {
        self.len -= 1;
    }
};

pub inline fn networkIndex(piece: typel.e_pieceType, color: e_color, sq: typel.e_square) usize {
    return @as(usize, @intFromEnum(color)) * 64 * 6 + @as(usize, @intFromEnum(piece)) * 64 + @as(usize, @intFromEnum(sq));
}
pub fn networkIndexPerspective(piece: typel.e_pieceType, sq: typel.e_square, perspective: e_color, side: e_color) usize {
    var _sq: u8 = @intFromEnum(sq);
    var _side = side;
    if (perspective == .BLACK) {
        _side = @enumFromInt(1 - @intFromEnum(_side));
        _sq = chessl.flipSq(_sq);
    }
    return networkIndex(piece, _side, @enumFromInt(_sq));
}
pub inline fn networkIndexPair(piece: typel.e_pieceType, sq: typel.e_square, side: e_color) [2]usize {
    return [2]usize{ networkIndex(piece, side, sq), networkIndex(piece, @enumFromInt(1 - @intFromEnum(side)), @enumFromInt(chessl.flipSq(@intFromEnum(sq)))) };
}
pub fn quiet_Add_Sub(accPair: *accumulatorPair, fromP: typel.e_pieceType, toP: typel.e_pieceType, fromSq: typel.e_square, toSq: typel.e_square, side: e_color) void {
    const sub = networkIndexPair(fromP, fromSq, side);
    const add = networkIndexPair(toP, toSq, side);

    const prevW = &nnueNet.net.accWeights[sub[@intFromEnum(e_color.WHITE)]];
    const nextW = &nnueNet.net.accWeights[add[@intFromEnum(e_color.WHITE)]];
    const prevB = &nnueNet.net.accWeights[sub[@intFromEnum(e_color.BLACK)]];
    const nextB = &nnueNet.net.accWeights[add[@intFromEnum(e_color.BLACK)]];

    for (0..HL_SIZE) |i| {
        accPair.w.values[i] += (nextW[i] - prevW[i]);
        accPair.b.values[i] += (nextB[i] - prevB[i]);
    }
}
pub fn castling_Add_Add_Sub_Sub(accPair: *accumulatorPair, side: e_color, info: *const boardl.castleS) void {
    const kSub = networkIndexPair(.KING, info.kingFrom, side);
    const kAdd = networkIndexPair(.KING, info.kingTo, side);

    const rSub = networkIndexPair(.ROOK, info.rookFrom, side);
    const rAdd = networkIndexPair(.ROOK, info.rookTo, side);

    const kPrevW = &nnueNet.net.accWeights[kSub[@intFromEnum(e_color.WHITE)]];
    const kNextW = &nnueNet.net.accWeights[kAdd[@intFromEnum(e_color.WHITE)]];
    const kPrevB = &nnueNet.net.accWeights[kSub[@intFromEnum(e_color.BLACK)]];
    const kNextB = &nnueNet.net.accWeights[kAdd[@intFromEnum(e_color.BLACK)]];

    const rPrevW = &nnueNet.net.accWeights[rSub[@intFromEnum(e_color.WHITE)]];
    const rNextW = &nnueNet.net.accWeights[rAdd[@intFromEnum(e_color.WHITE)]];
    const rPrevB = &nnueNet.net.accWeights[rSub[@intFromEnum(e_color.BLACK)]];
    const rNextB = &nnueNet.net.accWeights[rAdd[@intFromEnum(e_color.BLACK)]];

    for (0..HL_SIZE) |i| {
        accPair.w.values[i] += (kNextW[i] + rNextW[i] - kPrevW[i] - rPrevW[i]);
        accPair.b.values[i] += (kNextB[i] + rNextB[i] - kPrevB[i] - rPrevB[i]);
    }
}
pub fn capture_Add_Sub_Sub(accPair: *accumulatorPair, fromP: typel.e_pieceType, toP: typel.e_pieceType, fromSq: typel.e_square, toSq: typel.e_square, side: e_color, cPiece: typel.e_pieceType, captureSq: typel.e_square) void {
    const sub = networkIndexPair(fromP, fromSq, side);
    const add = networkIndexPair(toP, toSq, side);

    const victimSub = networkIndexPair(cPiece, captureSq, chessl.invert_e_color(side));

    const prevW = &nnueNet.net.accWeights[sub[@intFromEnum(e_color.WHITE)]];
    const nextW = &nnueNet.net.accWeights[add[@intFromEnum(e_color.WHITE)]];
    const prevB = &nnueNet.net.accWeights[sub[@intFromEnum(e_color.BLACK)]];
    const nextB = &nnueNet.net.accWeights[add[@intFromEnum(e_color.BLACK)]];

    const victimW = &nnueNet.net.accWeights[victimSub[@intFromEnum(e_color.WHITE)]];
    const victimB = &nnueNet.net.accWeights[victimSub[@intFromEnum(e_color.BLACK)]];

    for (0..HL_SIZE) |i| {
        accPair.w.values[i] += (nextW[i] - prevW[i] - victimW[i]);
        accPair.b.values[i] += (nextB[i] - prevB[i] - victimB[i]);
    }
}

// easier to vectorize compared to below
//pub inline fn activationFunc(val: i16) i16 {
//    return std.math.clamp(val, 0, qA);
//}
// SCReLU :
pub inline fn activationFunc(val: i16) i32 {
    return std.math.pow(i32, std.math.clamp(val, 0, QA), 2);
}
pub fn forward(n: *const network, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    var ret: i32 = 0;
    for (0..HL_SIZE) |i| {
        ret += activationFunc(stm_acc.values[i]) * @as(i32, @intCast(n.outputWeights[i]));
        ret += activationFunc(nstm_acc.values[i]) * @as(i32, @intCast(n.outputWeights[i + HL_SIZE]));
    }
    // only used with the activ that uses the pow(2) SCReLU
    ret = @divFloor(ret, QA);
    ret += n.outputBiase;
    ret = @divFloor(ret * networkScale, QAQB);
    return ret;
}
pub fn _forward(n: *const network, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    var ret: i32 = 0;
    for (0..HL_SIZE) |i| {
        const us_clamped: i32 = @intCast(std.math.clamp(stm_acc.values[i], 0, QA));
        const opp_clamped: i32 = @intCast(std.math.clamp(nstm_acc.values[i], 0, QA));
        ret += (us_clamped * us_clamped) * @as(i32, @intCast(n.outputWeights[i]));
        ret += (opp_clamped * opp_clamped) * @as(i32, @intCast(n.outputWeights[i + HL_SIZE]));
    }
    ret = @divFloor(ret, QA);
    ret += n.outputBiase;
    ret = @divFloor(ret * networkScale, QAQB);
    return ret;
}
pub fn __forward(n: *const network, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    var sum: __m256i = ssel._mm_setzero_si256();
    // 8 * 16 = 128 i16
    // x * 16 = 1024
    for (0..FORWARD_LOOP) |i| {
        const us = ssel._mm256_load_si256(@ptrCast(@alignCast(@constCast(&stm_acc.values[i * 16]))));
        const us_weights = ssel._mm256_load_si256(@ptrCast(@alignCast(@constCast(&n.outputWeights[i * 16]))));

        const us_clamped: __m256i = ssel._mm256_min_epi16(ssel._mm256_max_epi16(us, VEC_ZERO), VEC_QA);
        const us_results: __m256i = ssel._mm256_madd_epi16(ssel._mm256_mullo_epi16(us_weights, us_clamped), us_clamped);

        const opp = ssel._mm256_load_si256(@ptrCast(@alignCast(@constCast(&nstm_acc.values[i * 16]))));
        const opp_weights = ssel._mm256_load_si256(@ptrCast(@alignCast(@constCast(&n.outputWeights[i * 16 + HL_SIZE]))));

        const opp_clamped: __m256i = ssel._mm256_min_epi16(ssel._mm256_max_epi16(opp, VEC_ZERO), VEC_QA);
        const opp_results: __m256i = ssel._mm256_madd_epi16(ssel._mm256_mullo_epi16(opp_weights, opp_clamped), opp_clamped);
        sum = ssel._mm256_add_epi32(sum, us_results);
        sum = ssel._mm256_add_epi32(sum, opp_results);
    }
    const _sum = ssel.__m256i_cast_8x32i(sum);
    const s: scoreType = @divFloor(_sum[0] + _sum[1] + _sum[2] + _sum[3] + _sum[4] + _sum[5] + _sum[6] + _sum[7], QA) + n.outputBiase;
    return @divFloor(s * networkScale, QAQB);
}
pub fn ___forward(n: *const network, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    var sum: __m512i = ssel._mm_setzero_si512();
    // 8 * 16 = 128 i16
    // x * 16 = 1024
    for (0.._FORWARD_LOOP) |i| {
        const us = ssel._mm512_load_si512(@ptrCast(@alignCast(@constCast(&stm_acc.values[i * 32]))));
        const us_weights = ssel._mm512_load_si512(@ptrCast(@alignCast(@constCast(&n.outputWeights[i * 32]))));

        const us_clamped: __m512i = ssel._mm512_min_epi16(ssel._mm512_max_epi16(us, _VEC_ZERO), _VEC_QA);
        const us_results: __m512i = ssel._mm512_madd_epi16(ssel._mm512_mullo_epi16(us_weights, us_clamped), us_clamped);

        const opp = ssel._mm512_load_si512(@ptrCast(@alignCast(@constCast(&nstm_acc.values[i * 32]))));
        const opp_weights = ssel._mm512_load_si512(@ptrCast(@alignCast(@constCast(&n.outputWeights[i * 32 + HL_SIZE]))));

        const opp_clamped: __m512i = ssel._mm512_min_epi16(ssel._mm512_max_epi16(opp, _VEC_ZERO), _VEC_QA);
        const opp_results: __m512i = ssel._mm512_madd_epi16(ssel._mm512_mullo_epi16(opp_weights, opp_clamped), opp_clamped);
        sum = ssel._mm512_add_epi32(sum, us_results);
        sum = ssel._mm512_add_epi32(sum, opp_results);
    }
    const _sum = ssel.__m512i_cast_16x32i(sum);
    const s: scoreType = @divFloor(_sum[0] + _sum[1] + _sum[2] + _sum[3] + _sum[4] + _sum[5] + _sum[6] + _sum[7] + _sum[8] + _sum[9] + _sum[10] + _sum[11] + _sum[12] + _sum[13] + _sum[14] + _sum[15], QA) + n.outputBiase;
    return @divFloor(s * networkScale, QAQB);
}

pub fn computeAccPair(net: *const network, board: *const boardl.boardState) accumulatorPair {
    var ret: accumulatorPair = .{ .w = .init(&net.accBiases), .b = .init(&net.accBiases) };
    for (0..64) |sq| {
        const p = board.getPiece(@intCast(sq));
        if (p == .nEmptySquare) {
            continue;
        }
        const _sq: typel.e_square = @enumFromInt(sq);
        const c: e_color = chessl.e_colorFromPiece(p);

        const add = networkIndexPair(chessl.e_pieceTo_e_pieceType(p), _sq, c);
        const addW = &net.accWeights[add[@intFromEnum(e_color.WHITE)]];
        const addB = &net.accWeights[add[@intFromEnum(e_color.BLACK)]];

        for (0..HL_SIZE) |i| {
            ret.w.values[i] += addW[i];
            ret.b.values[i] += addB[i];
        }
    }
    return ret;
}
pub inline fn updateNnueOnMove(p_state: *boardl.boardState, move: movel.IMove) void {
    // !whiteToMove since this is done after makeMove
    _updateNnueOnMove(p_state, !p_state.whiteToMove(), move.isCapture(), move, move.isPromotion(), move.isCastle());
}

pub fn _updateNnueOnMove(p_state: *boardl.boardState, white: bool, isCapture: bool, move: movel.IMove, isPromo: bool, isCastle: bool) void {
    const to = move.getTo();
    var fromPiece: typel.e_pieceType = chessl.e_pieceTo_e_pieceType(p_state.getPiece(to));
    const _toPiece: typel.e_pieceType = fromPiece;
    const from = move.getFrom();
    const c = chessl.boolTo_e_color(white);
    if (isPromo) {
        fromPiece = .PAWN;
    }
    const accPair = &p_state.frame.nnueAccumul;
    if (isCapture) {
        // is capture
        const victimSq: typel.e_square = if (move.isEnpassant()) chessl.enPassantVictimSq(from, to) else (@enumFromInt(to));
        capture_Add_Sub_Sub(accPair, fromPiece, _toPiece, @enumFromInt(from), @enumFromInt(to), c, chessl.e_pieceTo_e_pieceType(p_state.frame.victim), victimSq);
    } else {
        if (isCastle) {
            const info = boardl.castleS.init(white, move.isKingSideCastle());
            castling_Add_Add_Sub_Sub(accPair, c, &info);
        } else {
            quiet_Add_Sub(accPair, fromPiece, _toPiece, @enumFromInt(from), @enumFromInt(to), c);
        }
    }
}
pub const _network = struct {
    net: network = .{},
    inited: bool = false,
    pub fn init(alloc: std.mem.Allocator, path: []const u8) !_network {
        var ret: _network = .{};
        ret.net = try network.init(alloc, path);
        ret.inited = true;
        return ret;
    }
};
pub var nnueNet: _network = .{};
//pub var global_nnueAcc: accumulatorPairStack = .{};

pub fn initNNUE(alloc: std.mem.Allocator, path: []const u8) !void {
    nnueNet = try .init(alloc, path);
}
pub inline fn evaluate(white: bool, pair: *const accumulatorPair) scoreType {
    return if (white) ___forward(&nnueNet.net, &pair.w, &pair.b) else ___forward(&nnueNet.net, &pair.b, &pair.w);
}
//pub const BAD_FEN = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w HAha - 0 1";
pub const BAD_FEN = "1n3R2/r2N4/4kB1p/1P6/8/p4NPB/P1P2P1P/3R2K1 b - - 3 57";
pub fn debugTest(net: *const network, fen: []const u8) void {
    var state = chessl.getBoardFromFen(fen) catch {
        return;
    };
    const acc = computeAccPair(net, &state);
    const eval = if (state.whiteToMove()) forward(net, &acc.w, &acc.b) else (forward(net, &acc.b, &acc.w));
    const _eval = if (state.whiteToMove()) _forward(net, &acc.w, &acc.b) else (_forward(net, &acc.b, &acc.w));
    const __eval = if (state.whiteToMove()) __forward(net, &acc.w, &acc.b) else (__forward(net, &acc.b, &acc.w));
    const ___eval = if (state.whiteToMove()) ___forward(net, &acc.w, &acc.b) else (___forward(net, &acc.b, &acc.w));

    const eW = __forward(net, &acc.w, &acc.b);
    const eB = __forward(net, &acc.b, &acc.w);

    std.debug.print("fen {s} eval {d} _eval {d} __eval {d} __evalW {d} __evalB {d} ___eval {d}\n", .{ fen, eval, _eval, __eval, eW, eB, ___eval });
}
pub fn main(alloc: std.mem.Allocator) !void {
    //const netPath = "out/bin/quantised.bin";
    //const netPath = "out/bin/simple-130/quantised.bin";
    const netPath = configl.NET_PATH;

    const net: network = try .init(alloc, netPath);
    for (0..benchmarkl.benchmarkEntries.len) |i| {
        const fen = benchmarkl.benchmarkEntries[i];
        debugTest(&net, fen);
    }

    debugTest(&net, BAD_FEN);

    return;
}
