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
const timel = @import("../time.zig");

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

test "perft - startpos" {
    mainl.initAll(false);
    const perft_THREAD = 1;
    const perft_BATCHED = true;
    const perft_MAX_DEPTH = 6;
    var board: Board_state = try chessl.getBoardFromFen(GLOBAL_ALLOC, chessl.DEFAULT_FEN);
    //try std.testing.expect(!hashl.isHashTable_init());
    var sw: timel.stopWatch = .{};
    for (1..perft_MAX_DEPTH + 1) |depth| {
        sw.startTimeTick();
        const res = perftl.perftThreadStart(&board, @intCast(depth), perft_THREAD, perft_BATCHED) catch {
            std.debug.print("[PANIC]: Error when launching perft\n", .{});
            @panic("");
        };
        const expect: i64 = @intCast(res.searchStat.n_nodeExplored);
        const timeTaken = sw.timeSinceStartUs();
        try std.testing.expectEqual(expect, benchmarkl.ExpectedBenchmarkResults[depth]);
        std.debug.print("\t[RES] perft({d} ms): depth {d} node: {d}, nps: {d}\n", .{ @divFloor(timeTaken, std.time.us_per_ms), depth, expect, @divFloor(expect * std.time.us_per_s, timeTaken + 1) });
    }

    std.debug.print("[TEST]: Perft checks passed\n", .{});
}
//test "perft - Kiwipete" {
//    mainl.initAll(false);
//    const perft_THREAD = 1;
//    const perft_BATCHED = true;
//    const perft_MAX_DEPTH = 6;
//    var board: Board_state = try chessl.getBoardFromFen(GLOBAL_ALLOC, benchmarkl.KIWIPETE_FEN);
//    //try std.testing.expect(!hashl.isHashTable_init());
//    for (1..perft_MAX_DEPTH + 1) |depth| {
//        const _start: i64 = std.time.microTimestamp();
//        const res = perftl.perftThreadStart(&board, @intCast(depth), perft_THREAD, perft_BATCHED) catch {
//            std.debug.print("[PANIC]: Error when launching perft\n", .{});
//            @panic("");
//        };
//        const expect: i64 = @intCast(res.n_nodeExplored);
//        //try std.testing.expectEqual(expect, benchmarkl.ExpectedPerftResKiwipete[depth]);
//        const _stop = std.time.microTimestamp();
//        std.debug.print("\t[RES] perft({d} ms): depth {d} node: {d}, nps: {d}\n", .{ @divFloor(_stop - _start, std.time.us_per_ms), depth, expect, @divFloor(expect * std.time.us_per_s, 1 + (_stop - _start)) });
//    }
//
//    std.debug.print("[TEST]: Perft kiwipete checks passed\n", .{});
//}

test "book algebraic" {
    mainl.initAll(false);
    const path = "opening/8moves_v3.pgn";
    var s = try stringl.string.initFromSlice(GLOBAL_ALLOC, path);
    defer s.free(GLOBAL_ALLOC);
    try bookl.test_db(&s);
    std.debug.print("[TEST]: Reading random algebraic position passed\n", .{});
}
test "draw detection" {
    mainl.initAll(false);
    var tmp: Board_state = try chessl.getBoardFromFen(GLOBAL_ALLOC, chessl.DEFAULT_FEN);
    try chessl.applyUciMoves(&tmp, "position startpos e2e3 e7e5 d1f3 c7c6 d2d4 d8e7 c1d2 e5d4 f1d3 e7e5 f3g3 e5g3 h2g3 d4e3 d2e3 f8b4 e3d2 b4d2 b1d2 g8f6 d2c4 d7d5 c4d6 e8e7 d6c8 h8c8 f2f4 e7e6 g1f3 c6c5 f3g5 e6e7 c2c3 h7h6 g5f3 b8c6 d3b5 a7a6 b5a4 c6a5 f3e5 e7e6 g3g4 a5c4 e5c4 d5c4 e1c1 e6e7 g4g5 h6g5 f4g5 f6g4 d1d7 e7e6 d7b7 c8d8 h1f1 d8d6 f1f7 e6d5 a4d1 g4e5 d1f3 e5f3 g2f3 g7g6 b7e7 a8h8 f7h7 h8h7 e7h7 d5e5 h7f7 d6b6 c1b1 b6c6 b1c1 c6b6 c1b1 b6c6 b1c1", GLOBAL_ALLOC, false);
    const allMoves = moveGenl.generateLegalMoves(&tmp);
    const nUntilDraw = tmp.move_history.getRepetitions();
    for (0..allMoves.len) |i| {
        tmp.makeMove(allMoves.moves[i]);
        _ = tmp.undoMove();
        try std.testing.expectEqual(nUntilDraw, tmp.move_history.getRepetitions());
    }
    std.debug.print("[TEST]: Draw detection case passed\n", .{});
}

pub fn main() void {
    std.debug.print("[TEST]: Running the move generation checks\n", .{});
}
