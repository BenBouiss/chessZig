const chess = @import("chess.zig");
const exploration = @import("exploration.zig");
const movel = @import("move.zig");
const std = @import("std");
const IMove = movel.IMove;

pub const benchmarkResult = struct {
    n_nodes: i64 = 0,
    n_captures: i64 = 0,
    n_enpassants: i64 = 0,
    n_castles: i64 = 0,
    n_promotions: i64 = 0,

    pub fn reset(p_self: *benchmarkResult) void {
        p_self.n_nodes = 0;
        p_self.n_captures = 0;
        p_self.n_enpassants = 0;
        p_self.n_castles = 0;
        p_self.n_promotions = 0;
    }
    pub fn addNode(p_self: *benchmarkResult, move: IMove) void {
        p_self.n_nodes += 1;
        if (move.isCapture()) {
            p_self.n_captures += 1;
        }
        if (move.isEnpassant()) {
            p_self.n_enpassants += 1;
        }
        if (move.isKingSideCastle() or move.isQueenSideCastle()) {
            p_self.n_castles += 1;
        }
        if (move.isPromotion()) {
            p_self.n_promotions += 1;
        }
    }
    pub fn printInfo(self: benchmarkResult) void {
        std.debug.print("\n|Nodes|Capture|Enpassant|castling|promotions|\n", .{});

        std.debug.print("|=====|=======|=========|========|==========|\n", .{});
        std.debug.print("|{d}|{d}|{d}|{d}|{d}|\n", .{ self.n_nodes, self.n_captures, self.n_enpassants, self.n_castles, self.n_promotions });
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
pub fn nodeExplorationBenchmark(p_state: *chess.Board_state, n_max: u8) void {
    var bench_res: benchmarkResult = .{};
    var _start: i64 = 0;
    var _end: i64 = 0;
    for (1..(n_max + 1)) |depth| {
        bench_res.reset();
        _start = std.time.milliTimestamp();
        exploration.explorationNDepth(p_state, @intCast(depth), &bench_res) catch unreachable;
        _end = std.time.milliTimestamp();
        std.debug.print("Move generation (depth = {d}): {d} ms for {d} nodes ({d} nodes/s)\n", .{ depth, _end - _start, bench_res.n_nodes, @divFloor((bench_res.n_nodes), (_end - _start + 1)) * 1000 });
        bench_res.printInfo();
        if (bench_res.n_nodes != ExpectedBenchmarkResults[depth]) {
            std.debug.print("[DEBUG] nodeExplorationBenchmark: At deph {d} expected {d} nodes found {d} (diff: {d} node(s))\n", .{ depth, ExpectedBenchmarkResults[depth], bench_res.n_nodes, ExpectedBenchmarkResults[depth] - bench_res.n_nodes });
        }
        //        std.debug.assert(bench_res.n_nodes == ExpectedBenchmarkResults[depth]);
    }
}
pub fn test_benchmark() void {
    chess.initRayAttacks();
    var game_state = chess.getBoardFromFen(chess.DEFAULT_FEN);
    game_state.setSeed(42);
    nodeExplorationBenchmark(&game_state, 5);
}

pub fn main() !void {
    test_benchmark();
}
