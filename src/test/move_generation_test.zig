const chessl = @import("../chess.zig");
const moveGenl = @import("../move_generation.zig");
const movel = @import("../move.zig");
const squarel = @import("../square.zig");
const benchmarkl = @import("../benchmark.zig");
const hashl = @import("../hashTable.zig");
const mainl = @import("../main.zig");
const perftl = @import("../search/perft.zig");
const stringl = @import("../string.zig");
const bookl = @import("../book.zig");

const std = @import("std");

const Board_state = chessl.Board_state;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

test "en passant checking" {
    mainl.initAll(false);
    var tmp: Board_state = try chessl.getBoardFromFen(GLOBAL_ALLOC, "5bnr/5ppp/1Q6/2Bkp3/3pP3/3P4/5PPP/4KBNR b H e3 0 39");
    const allMoves = moveGenl.generateLegalMoves(&tmp);
    try std.testing.expectEqual(allMoves.len, 1);
    const move = allMoves.moves[0];
    try std.testing.expect(move.isEnpassant());
    try std.testing.expectEqual(allMoves.len, 1);

    std.debug.print("[TEST]: En passant checking passed\n", .{});
}
test "perft" {
    mainl.initAll(false);
    const perft_THREAD = 1;
    const perft_BATCHED = true;
    const perft_MAX_DEPTH = 6;
    var board: Board_state = try chessl.getBoardFromFen(GLOBAL_ALLOC, chessl.DEFAULT_FEN);
    try std.testing.expect(!hashl.isHashTable_init());
    for (1..perft_MAX_DEPTH + 1) |depth| {
        const _start: i64 = std.time.microTimestamp();
        const res = try perftl.perftThreadStart(&board, @intCast(depth), perft_THREAD, perft_BATCHED);
        const expect: i64 = @intCast(res.n_nodeExplored);
        try std.testing.expectEqual(expect, benchmarkl.ExpectedBenchmarkResults[depth]);
        const _stop = std.time.microTimestamp();
        std.debug.print("\t[RES] perft({d} ms): depth {d} node: {d}, nps: {d}\n", .{ @divFloor(_stop - _start, std.time.us_per_ms), depth, expect, @divFloor(expect * std.time.us_per_s, 1 + (_stop - _start)) });
    }

    std.debug.print("[TEST]: Perft checks passed\n", .{});
}

test "book algebraic" {
    //
    mainl.initAll(false);

    const path = "opening/8moves_v3.pgn";
    var s = try stringl.string.initFromSlice(GLOBAL_ALLOC, path);
    defer s.free(GLOBAL_ALLOC);
    try bookl.test_db(&s);
    std.debug.print("[TEST]: Reading random algebraic position passed\n", .{});
}

pub fn main() void {
    std.debug.print("[TEST]: Running the move generation checks\n", .{});
}
