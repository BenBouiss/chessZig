const std = @import("std");

const typel = @import("type.zig");
const boardl = @import("board.zig");
const chessl = @import("chess.zig");
const enginel = @import("engine.zig");
const heuristicl = @import("heuristic.zig");
const stringl = @import("string.zig");
const filel = @import("file.zig");
const configl = @import("config.zig");
const utilsl = @import("utils.zig");
const mainl = @import("main.zig");
const movel = @import("move.zig");
const ssel = @import("intrinsics/sse.zig");
const mathl = @import("math.zig");

const scoreType = typel.scoreType;
const e_color = typel.e_color;
const accumulator: type = [HL_SIZE]i16;
pub const vectAcum: type = @Vector(HL_SIZE, i16);
const embeded_net = @embedFile(configl.NET_PATH);

pub const networkScale = 400;
pub const QA = 255;
pub const QB = 64;
pub const QAQB = 255 * 64;
pub const HL_SIZE = if (configl.USE_NNUE) 512 else 0;
// https://chessprogramming.org/NNUE#output-buckets
pub const OUTPUT_BUCKETS = 8;
pub const BUCKET_DIV = @divFloor(32, OUTPUT_BUCKETS);
//pub const HL_SIZE = if (configl.USE_NNUE) 128 else 0;
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
pub inline fn bucketIdx(occ: u64) usize {
    return @divFloor(chessl.popcount(occ) - 2, BUCKET_DIV);
}

//https://www.chessprogramming.org/NNUE
pub const network = extern struct {
    accWeights: [INPUT_SIZE]vectAcum align(64) = std.mem.zeroes([INPUT_SIZE]vectAcum),
    accBiases: [HL_SIZE]i16 = @splat(0),
    b_outputWeights: [OUTPUT_BUCKETS][2 * HL_SIZE]i16 = std.mem.zeroes([OUTPUT_BUCKETS][2 * HL_SIZE]i16),
    b_outputBiase: [OUTPUT_BUCKETS]i16 = @splat(0),

    //outputWeights: [2 * HL_SIZE]i16 = @splat(0),
    //outputBiase: i16 = 0,
    pub fn init(alloc: std.mem.Allocator, path: []const u8) !network {
        const content = try std.Io.Dir.readFileAlloc(.cwd(), mainl.getGlobalIo(), path, alloc, .unlimited);
        const ret: *network = @ptrCast(@alignCast(content));
        return ret.*;
    }
    pub fn initCplt() network {
        const net: *network = @ptrCast(@alignCast(@constCast(embeded_net)));
        return net.*;
    }
};

pub const nnueNet: network = if (configl.USE_NNUE) (.initCplt()) else (.{});

pub const accumulatorPair = struct {
    w: accumulator align(64) = @splat(0),
    b: accumulator align(64) = @splat(0),
    pub fn print(self: *const accumulatorPair) void {
        std.debug.print("w {any} \n b {any} \n", .{ self.w, self.b });
    }
};
pub const accumulatorPairStack = struct {
    items: [typel.MAX_PLY + 4]accumulatorPair = @splat(.{}),
    len: usize = 0,
    pub inline fn getCurrent(self: *accumulatorPairStack) *accumulatorPair {
        return &self.items[self.len - 1];
    }
    pub inline fn getNext(self: *accumulatorPairStack) *accumulatorPair {
        return &self.items[self.len];
    }

    pub inline fn pop(self: *accumulatorPairStack) void {
        self.len -= 1;
    }
};

//  The standard way to do this is to set `white_pawn = 0, white_knight = 1, ..., black_pawn = 6, ..., black_king = 11` and
// for each piece `Piece` on square `Square`, you set the `64 * Piece + Square`th element of the input vector to 1.

// c * 64 * 6 + p * 64 + sq
// 64 * (6c + p) + sq
// 64 * P + sq

pub inline fn networkIndex(piece: typel.e_pieceType, color: e_color, sq: typel.e_square) usize {
    return @as(usize, @intFromEnum(color)) * 64 * 6 + @as(usize, @intFromEnum(piece)) * 64 + @as(usize, @intFromEnum(sq));
}

pub inline fn networkIndexPair(piece: typel.e_pieceType, sq: typel.e_square, side: e_color) [2]usize {
    return [2]usize{ networkIndex(piece, side, sq), networkIndex(piece, @enumFromInt(1 - @intFromEnum(side)), @enumFromInt(chessl.flipSq(@intFromEnum(sq)))) };
}
pub fn quiet_Add_Sub(next: *accumulatorPair, prev: *accumulatorPair, fromP: typel.e_pieceType, toP: typel.e_pieceType, fromSq: typel.e_square, toSq: typel.e_square, side: e_color) void {
    const sub = networkIndexPair(fromP, fromSq, side);
    const add = networkIndexPair(toP, toSq, side);

    next.w = (@as(@Vector(HL_SIZE, i16), prev.w) +
        nnueNet.accWeights[add[@intFromEnum(e_color.WHITE)]] -
        nnueNet.accWeights[sub[@intFromEnum(e_color.WHITE)]]);

    next.b = (@as(@Vector(HL_SIZE, i16), prev.b) +
        nnueNet.accWeights[add[@intFromEnum(e_color.BLACK)]] -
        nnueNet.accWeights[sub[@intFromEnum(e_color.BLACK)]]);
}
pub fn castling_Add_Add_Sub_Sub(next: *accumulatorPair, prev: *accumulatorPair, side: e_color, info: boardl.castleS) void {
    const kSub = networkIndexPair(.KING, info.kingFrom, side);
    const kAdd = networkIndexPair(.KING, info.kingTo, side);

    const rSub = networkIndexPair(.ROOK, info.rookFrom, side);
    const rAdd = networkIndexPair(.ROOK, info.rookTo, side);

    next.w = (@as(@Vector(HL_SIZE, i16), prev.w) +
        nnueNet.accWeights[kAdd[@intFromEnum(e_color.WHITE)]] +
        nnueNet.accWeights[rAdd[@intFromEnum(e_color.WHITE)]] -
        nnueNet.accWeights[kSub[@intFromEnum(e_color.WHITE)]] -
        nnueNet.accWeights[rSub[@intFromEnum(e_color.WHITE)]]);

    next.b = (@as(@Vector(HL_SIZE, i16), prev.b) +
        nnueNet.accWeights[kAdd[@intFromEnum(e_color.BLACK)]] +
        nnueNet.accWeights[rAdd[@intFromEnum(e_color.BLACK)]] -
        nnueNet.accWeights[kSub[@intFromEnum(e_color.BLACK)]] -
        nnueNet.accWeights[rSub[@intFromEnum(e_color.BLACK)]]);
}
pub fn capture_Add_Sub_Sub(next: *accumulatorPair, prev: *accumulatorPair, fromP: typel.e_pieceType, toP: typel.e_pieceType, fromSq: typel.e_square, toSq: typel.e_square, side: e_color, cPiece: typel.e_pieceType, captureSq: typel.e_square) void {
    const sub = networkIndexPair(fromP, fromSq, side);
    const add = networkIndexPair(toP, toSq, side);
    const victimSub = networkIndexPair(cPiece, captureSq, chessl.invert_e_color(side));

    next.w = (@as(@Vector(HL_SIZE, i16), prev.w) +
        nnueNet.accWeights[add[@intFromEnum(e_color.WHITE)]] -
        nnueNet.accWeights[sub[@intFromEnum(e_color.WHITE)]] -
        nnueNet.accWeights[victimSub[@intFromEnum(e_color.WHITE)]]);

    next.b = (@as(@Vector(HL_SIZE, i16), prev.b) +
        nnueNet.accWeights[add[@intFromEnum(e_color.BLACK)]] -
        nnueNet.accWeights[sub[@intFromEnum(e_color.BLACK)]] -
        nnueNet.accWeights[victimSub[@intFromEnum(e_color.BLACK)]]);
}

// easier to vectorize compared to below
//pub inline fn activationFunc(val: i16) i16 {
//    return std.math.clamp(val, 0, qA);
//}
// SCReLU :
pub inline fn activationFunc(val: i16) i32 {
    return std.math.pow(i32, std.math.clamp(val, 0, QA), 2);
}
pub fn forward(n: *const network, buck: usize, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    var ret: i32 = 0;
    for (0..HL_SIZE) |i| {
        ret += activationFunc(stm_acc[i]) * @as(i32, @intCast(n.b_outputWeights[buck][i]));
        ret += activationFunc(nstm_acc[i]) * @as(i32, @intCast(n.b_outputWeights[buck][i + HL_SIZE]));
    }
    // only used with the activ that uses the pow(2) SCReLU
    ret = @divFloor(ret, QA);
    ret += n.b_outputBiase[buck];
    ret = @divFloor(ret * networkScale, QAQB);
    return ret;
}
pub fn _forward(n: *const network, buck: usize, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    var ret: i32 = 0;
    for (0..HL_SIZE) |i| {
        const us_clamped: i32 = @intCast(std.math.clamp(stm_acc[i], 0, QA));
        const opp_clamped: i32 = @intCast(std.math.clamp(nstm_acc[i], 0, QA));
        ret += (us_clamped * us_clamped) * @as(i32, @intCast(n.b_outputWeights[buck][i]));
        ret += (opp_clamped * opp_clamped) * @as(i32, @intCast(n.b_outputWeights[buck][i + HL_SIZE]));
    }
    ret = @divFloor(ret, QA);
    ret += n.b_outputBiase[buck];
    ret = @divFloor(ret * networkScale, QAQB);
    return ret;
}
pub fn __forward(n: *const network, buck: usize, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    var sum: __m256i = ssel._mm_setzero_si256();
    // 8 * 16 = 128 i16
    // x * 16 = 1024
    for (0..FORWARD_LOOP) |i| {
        const us = ssel._mm256_load_si256(@ptrCast(@alignCast(@constCast(&stm_acc[i * 16]))));
        const us_weights = ssel._mm256_load_si256(@ptrCast(@alignCast(@constCast(&n.b_outputWeights[buck][i * 16]))));

        const us_clamped: __m256i = ssel._mm256_min_epi16(ssel._mm256_max_epi16(us, VEC_ZERO), VEC_QA);
        const us_results: __m256i = ssel._mm256_madd_epi16(ssel._mm256_mullo_epi16(us_weights, us_clamped), us_clamped);

        const opp = ssel._mm256_load_si256(@ptrCast(@alignCast(@constCast(&nstm_acc[i * 16]))));
        const opp_weights = ssel._mm256_load_si256(@ptrCast(@alignCast(@constCast(&n.b_outputWeights[buck][i * 16 + HL_SIZE]))));

        const opp_clamped: __m256i = ssel._mm256_min_epi16(ssel._mm256_max_epi16(opp, VEC_ZERO), VEC_QA);
        const opp_results: __m256i = ssel._mm256_madd_epi16(ssel._mm256_mullo_epi16(opp_weights, opp_clamped), opp_clamped);
        sum = ssel._mm256_add_epi32(sum, us_results);
        sum = ssel._mm256_add_epi32(sum, opp_results);
    }
    const _sum = ssel.__m256i_cast_8x32i(sum);
    const s: scoreType = @divFloor(_sum[0] + _sum[1] + _sum[2] + _sum[3] + _sum[4] + _sum[5] + _sum[6] + _sum[7], QA) + n.b_outputBiase[buck];
    return @divFloor(s * networkScale, QAQB);
}
pub fn ___forward(buck: usize, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    //std.debug.print("bucket id {d} \n", .{buck});
    var sum: __m512i = ssel._mm_setzero_si512();
    // 8 * 16 = 128 i16
    // x * 16 = 1024
    for (0.._FORWARD_LOOP) |i| {
        const us = ssel._mm512_load_si512(@ptrCast(@alignCast(@constCast(&stm_acc[i * 32]))));
        const us_weights = ssel._mm512_load_si512(@ptrCast(@alignCast(@constCast(&nnueNet.b_outputWeights[buck][i * 32]))));

        const us_clamped: __m512i = ssel._mm512_min_epi16(ssel._mm512_max_epi16(us, _VEC_ZERO), _VEC_QA);
        const us_results: __m512i = ssel._mm512_madd_epi16(ssel._mm512_mullo_epi16(us_weights, us_clamped), us_clamped);

        const opp = ssel._mm512_load_si512(@ptrCast(@alignCast(@constCast(&nstm_acc[i * 32]))));
        const opp_weights = ssel._mm512_load_si512(@ptrCast(@alignCast(@constCast(&nnueNet.b_outputWeights[buck][i * 32 + HL_SIZE]))));

        const opp_clamped: __m512i = ssel._mm512_min_epi16(ssel._mm512_max_epi16(opp, _VEC_ZERO), _VEC_QA);
        const opp_results: __m512i = ssel._mm512_madd_epi16(ssel._mm512_mullo_epi16(opp_weights, opp_clamped), opp_clamped);
        sum = ssel._mm512_add_epi32(sum, us_results);
        sum = ssel._mm512_add_epi32(sum, opp_results);
    }
    const _sum = ssel.__m512i_cast_16x32i(sum);
    const s: scoreType = @divFloor(_sum[0] + _sum[1] + _sum[2] + _sum[3] + _sum[4] + _sum[5] + _sum[6] + _sum[7] + _sum[8] + _sum[9] + _sum[10] + _sum[11] + _sum[12] + _sum[13] + _sum[14] + _sum[15], QA) + nnueNet.b_outputBiase[buck];
    return @divFloor(s * networkScale, QAQB);
}

pub fn computeAccPair(net: *const network, board: *const boardl.boardState) accumulatorPair {
    var ret: accumulatorPair = .{ .w = net.accBiases, .b = net.accBiases };
    for (0..64) |sq| {
        const p = board.getPiece(@intCast(sq));
        if (p == .nEmptySquare) {
            continue;
        }
        const add = networkIndexPair(chessl.e_pieceTo_e_pieceType(p), @enumFromInt(sq), chessl.e_colorFromPiece(p));
        ret.w = @as(@Vector(HL_SIZE, i16), ret.w) + net.accWeights[add[@intFromEnum(e_color.WHITE)]];
        ret.b = @as(@Vector(HL_SIZE, i16), ret.b) + net.accWeights[add[@intFromEnum(e_color.BLACK)]];
        //for (0..HL_SIZE) |i| {
        //    ret.w[i] += addW[i];
        //    ret.b[i] += addB[i];
        //}
    }
    return ret;
}

pub fn updateNnueOnMove(p_state: *boardl.boardState, move: movel.IMove, stack: *accumulatorPairStack) void {
    // !whiteToMove since this is done after makeMove
    const white = !p_state.whiteToMove();
    const isCapture = move.isCapture();
    const isPromo = move.isPromotion();
    const isCastle = move.isCastle();
    const to = move.getTo();
    var fromPiece: typel.e_pieceType = chessl.e_pieceTo_e_pieceType(p_state.getPiece(to));
    const _toPiece: typel.e_pieceType = fromPiece;
    const from = move.getFrom();
    const c = chessl.boolTo_e_color(white);
    if (isPromo) {
        fromPiece = .PAWN;
    }
    if (isCapture) {
        // is capture
        const victimSq: typel.e_square = if (move.isEnpassant()) chessl.enPassantVictimSq(from, to) else (@enumFromInt(to));
        capture_Add_Sub_Sub(stack.getNext(), stack.getCurrent(), fromPiece, _toPiece, @enumFromInt(from), @enumFromInt(to), c, chessl.e_pieceTo_e_pieceType(p_state.frame.victim), victimSq);
    } else {
        if (isCastle) {
            castling_Add_Add_Sub_Sub(stack.getNext(), stack.getCurrent(), c, .init(white, move.isKingSideCastle()));
        } else {
            quiet_Add_Sub(stack.getNext(), stack.getCurrent(), fromPiece, _toPiece, @enumFromInt(from), @enumFromInt(to), c);
        }
    }
    stack.len += 1;
}

pub inline fn evaluate(bucketId: usize, white: bool, pair: *const accumulatorPair) scoreType {
    //std.debug.print("align {d} {any}\n", .{ @alignOf(@TypeOf(nnueNet.buckets)), nnueNet.getBucket(bucketId).outputWeights });
    //std.debug.print("align {d}\n", .{@alignOf(network)});
    //return if (white) ___forward(nnueNet.getBucket(bucketId), &pair.w, &pair.b) else ___forward(nnueNet.getBucket(bucketId), &pair.b, &pair.w);
    return if (white) ___forward(bucketId, &pair.w, &pair.b) else ___forward(bucketId, &pair.b, &pair.w);
}
//pub const BAD_FEN = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w HAha - 0 1";
pub const BAD_FEN = "1n3R2/r2N4/4kB1p/1P6/8/p4NPB/P1P2P1P/3R2K1 b - - 3 57";
pub fn debugTest(net: *const network, fen: []const u8) void {
    var state = chessl.getBoardFromFen(fen) catch {
        return;
    };
    const acc = computeAccPair(net, &state);
    const b = bucketIdx(state.occupiedBB());
    const eval = if (state.whiteToMove()) forward(net, b, &acc.w, &acc.b) else (forward(net, b, &acc.b, &acc.w));
    const _eval = if (state.whiteToMove()) _forward(net, b, &acc.w, &acc.b) else (_forward(net, b, &acc.b, &acc.w));
    const __eval = if (state.whiteToMove()) __forward(net, b, &acc.w, &acc.b) else (__forward(net, b, &acc.b, &acc.w));
    const ___eval = if (state.whiteToMove()) ___forward(b, &acc.w, &acc.b) else (___forward(b, &acc.b, &acc.w));

    const eW = __forward(net, b, &acc.w, &acc.b);
    const eB = __forward(net, b, &acc.b, &acc.w);

    std.debug.print("fen {s} eval {d} _eval {d} __eval {d} __evalW {d} __evalB {d} ___eval {d}\n", .{ fen, eval, _eval, __eval, eW, eB, ___eval });
}
pub fn deb(alloc: std.mem.Allocator) !void {
    //const netPath = "src/extern/simple-320-colM-128/quantised.bin";

    //const net: network = try .init(alloc, netPath);
    for (0..enginel.benchmarkEntries.len) |i| {
        const fen = enginel.benchmarkEntries[i];
        debugTest(&nnueNet, fen);
    }
    debugTest(&nnueNet, BAD_FEN);
    _ = alloc;
}
pub fn main(alloc: std.mem.Allocator) !void {
    //const netPath = "out/bin/quantised.bin";
    //const netPath = "out/bin/simple-130/quantised.bin";
    //const netPath = configl.NET_PATH;
    // try deb(alloc);
    //const idx = networkIndex(.PAWN, .WHITE, .e4);
    //std.debug.print("{any}\n", .{nnueNet.accWeights[idx]});
    //std.debug.print("{any}\n", .{nnueNet.accBiases});
    //std.debug.print("{any}\n", .{nnueNet.outputWeights});
    //std.debug.print("{any}\n", .{nnueNet.outputBiase});
    std.debug.print("size of bucket net {d} bytes \n", .{@sizeOf(network)});
    std.debug.print("embeded net {d} bytes \n", .{embeded_net.len});
    std.debug.print("align of network {d} bytes \n", .{@alignOf(network)});
    try deb(alloc);
    return;
}
