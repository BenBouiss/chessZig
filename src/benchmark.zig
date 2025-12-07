const chess = @import("chess.zig");
const exploration = @import("exploration.zig");
const movel = @import("move.zig");
const std = @import("std");
const mainl = @import("main.zig");
const hashl = @import("hashTable.zig");

const build_options = @import("build_options");

const GLOBAL_ALLOCATOR = mainl.GLOBAL_ALLOC;
const IMove = movel.IMove;

const useHash = build_options.useHash;

pub const benchmarkResult = struct {
    n_nodes: u64 = 0,
    n_captures: i64 = 0,
    n_doublePawn: i64 = 0,
    n_enpassants: i64 = 0,
    n_castles: i64 = 0,
    n_promotions: i64 = 0,
    n_hashRetrieve: i64 = 0,

    pub fn reset(p_self: *benchmarkResult) void {
        p_self.n_nodes = 0;
        p_self.n_captures = 0;
        p_self.n_doublePawn = 0;
        p_self.n_enpassants = 0;
        p_self.n_castles = 0;
        p_self.n_promotions = 0;
    }
    pub fn addNode(p_self: *benchmarkResult, p_move: *const IMove) void {
        p_self.n_nodes += 1;
        _ = p_move;
        //if (p_move.isDoublePush()) {
        //    p_self.n_doublePawn += 1;
        //    return;
        //}
        //if (p_move.isKingSideCastle() or p_move.isQueenSideCastle()) {
        //    p_self.n_castles += 1;
        //    return;
        //}
        //if (p_move.isCapture()) {
        //    p_self.n_captures += 1;
        //}
        //if (p_move.isEnpassant()) {
        //    p_self.n_enpassants += 1;
        //}
        //if (p_move.isPromotion()) {
        //    p_self.n_promotions += 1;
        //}
    }
    pub fn printInfo(self: benchmarkResult) void {
        std.debug.print("\n|Nodes|Capture|Doublepush|Enpassant|castling|promotions|\n", .{});

        std.debug.print("|=====|=======|=========|========|==========|\n", .{});
        std.debug.print("|{d}|{d}|{d}|{d}|{d}|{d}|\n", .{ self.n_nodes, self.n_captures, self.n_doublePawn, self.n_enpassants, self.n_castles, self.n_promotions });
    }
    pub fn copy(self: benchmarkResult) benchmarkResult {
        return .{
            .n_nodes = self.n_nodes,
            .n_captures = self.n_captures,
            .n_enpassants = self.n_enpassants,
            .n_castles = self.n_castles,
            .n_promotions = self.n_promotions,
        };
    }
    pub fn duplicateNTimes(self: benchmarkResult, alloc: std.mem.Allocator, n: usize) !benchmarkResultsContainer {
        var ret: []benchmarkResult = try alloc.alloc(benchmarkResult, n);
        for (0..n) |i| {
            ret[i] = self.copy();
        }
        return .{ .array = ret, .len = ret.len };
    }
};

const benchmarkResultsContainer = struct {
    array: []benchmarkResult,
    len: usize,
    pub fn combine(self: benchmarkResultsContainer) benchmarkResult {
        var ret: benchmarkResult = .{};
        for (self.array) |bench| {
            ret.n_nodes += bench.n_nodes;
            ret.n_captures += bench.n_captures;
            ret.n_doublePawn += bench.n_doublePawn;
            ret.n_enpassants += bench.n_enpassants;
            ret.n_castles += bench.n_castles;
            ret.n_promotions += bench.n_promotions;
            ret.n_hashRetrieve += bench.n_hashRetrieve;
        }
        return ret;
    }
    pub fn free(p_self: *benchmarkResultsContainer, alloc: std.mem.Allocator) void {
        alloc.free(p_self.array);
    }
};

const ExpectedBenchmarkResults = [_]i64{
    1,
    20,
    400,
    8902,
    197281,
    4865609,
    119060324,
    3195901860,
    84998978956,
    2439530234167,
    69352859712417,
    2097651003696806,
};
// source: https://github.com/Timmoth/grandchesstree

pub fn nodeExplorationBenchmark(p_state: *chess.Board_state, n_max: u8, nThread: u8, batched: bool) void {
    var bench_res: benchmarkResult = .{};
    var _start: i64 = 0;
    var _end: i64 = 0;
    for (1..(n_max + 1)) |depth| {
        bench_res.reset();
        _start = std.time.milliTimestamp();
        std.debug.print("[DEBUG] nodeExplorationBenchmark: Starting benchmark depth = {d}\n", .{depth});
        exploration.explorationNDepthThreadStart(p_state, @intCast(depth), nThread, &bench_res, batched) catch unreachable;
        _end = std.time.milliTimestamp();
        const _node: i64 = @intCast(bench_res.n_nodes);
        std.debug.print("Move generation (depth = {d}): {d} ms for {d} nodes ({d} nodes/s)\n", .{ depth, _end - _start, bench_res.n_nodes, @divFloor(_node, (_end - _start + 1)) * 1000 });
        bench_res.printInfo();
        if (bench_res.n_nodes != ExpectedBenchmarkResults[depth]) {
            std.debug.print("[DEBUG] nodeExplorationBenchmark: At deph {d} expected {d} nodes found {d} (diff: {d} node(s))\n", .{ depth, ExpectedBenchmarkResults[depth], bench_res.n_nodes, ExpectedBenchmarkResults[depth] - _node });
        }
        if (comptime useHash) {
            std.debug.print("[DEBUG] hash moves retrieved: {d}\n", .{bench_res.n_hashRetrieve});
            std.debug.print("[DEBUG] Explored position: {d}\n", .{hashl.hashTable.n_insertion});
        }
        //        std.debug.assert(bench_res.n_nodes == ExpectedBenchmarkResults[depth]);
    }
}
pub fn test_benchmark() void {
    var game_state = chess.getBoardFromFen(chess.DEFAULT_FEN, GLOBAL_ALLOCATOR) catch {};
    std.debug.print("[DEBUG] test_bencharmk: successfully loaded fen code\n", .{});
    game_state.setSeed(42);
    chess.print_boardstate(&game_state);
    nodeExplorationBenchmark(&game_state, 7, 1, false);
}

pub fn main() !void {
    test_benchmark();
}
