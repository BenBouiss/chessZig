const chessl = @import("../chess.zig");
const moveGenl = @import("../move_generation.zig");
const movel = @import("../move.zig");
const squarel = @import("../square.zig");
const explorationl = @import("../exploration.zig");
const benchmarkl = @import("../benchmark.zig");
const mainl = @import("../main.zig");

const std = @import("std");

const Board_state = chessl.Board_state;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

test "en passant checking" {
    mainl.initAll();
    var tmp: Board_state = try chessl.getBoardFromFen(GLOBAL_ALLOC, "5bnr/5ppp/1Q6/2Bkp3/3pP3/3P4/5PPP/4KBNR b H e3 0 39");
    const allMoves = moveGenl.generateLegalMoves(&tmp);
    try std.testing.expectEqual(allMoves.len, 1);
    const move = allMoves.moves[0];
    try std.testing.expect(move.isEnpassant());
    try std.testing.expectEqual(allMoves.len, 1);

    std.debug.print("[TEST]: En passant checking passed\n", .{});
}
test "perft" {
    mainl.initAll();
    var board: Board_state = try chessl.getBoardFromFen(GLOBAL_ALLOC, chessl.DEFAULT_FEN);
    var tmp: benchmarkl.benchmarkResult = .{};
    for (1..7) |depth| {
        const _start: i64 = std.time.microTimestamp();
        try explorationl.explorationNDepthThreadStart(&board, @intCast(depth), 1, &tmp, true);
        const expect: i64 = @intCast(tmp.n_nodes);
        try std.testing.expectEqual(expect, benchmarkl.ExpectedBenchmarkResults[depth]);
        const _stop = std.time.microTimestamp();
        std.debug.print("\t[RES] perft({d} ms): depth {d} node: {d}, nps: {d}\n", .{ @divFloor(_stop - _start, std.time.us_per_ms), depth, expect, @divFloor(expect * std.time.us_per_s, 1 + (_stop - _start)) });
        tmp.reset();
    }

    std.debug.print("[TEST]: Perft checks passed\n", .{});
}

pub fn main() void {
    std.debug.print("[TEST]: Running the move generation checks\n", .{});
}
