const chessl = @import("../chess.zig");
const utilsl = @import("../utils.zig");
const moveTablel = @import("../moveTables.zig");
const movel = @import("../move.zig");
const squarel = @import("../square.zig");
const heuristicl = @import("../heuristic.zig");
const stringl = @import("../string.zig");
const filel = @import("../file.zig");

const std = @import("std");

const Board_state = chessl.Board_state;

test "in between" {
    moveTablel._initTables(false);
    try std.testing.expectEqual(chessl.inBetween(.a1, .a8), 0x1010101010100);
    try std.testing.expectEqual(chessl.inBetween(.f1, .f8), 0x20202020202000);
    try std.testing.expectEqual(chessl.inBetween(.h4, .a4), 0x7e000000);
    try std.testing.expectEqual(chessl.inBetween(.a8, .h8), 0x7e00000000000000);
    try std.testing.expectEqual(chessl.inBetween(.a1, .h8), 0x40201008040200);
    try std.testing.expectEqual(chessl.inBetween(.a8, .h1), 0x2040810204000);

    std.log.info("[TEST]: inbetween passed\n", .{});
}
test "rotate" {
    const initialPawn: u64 = 0xFF00000000FF00;
    try std.testing.expectEqual(initialPawn, chessl.rotate180(initialPawn));
    const initialPawnW: u64 = 0xFF00;
    const initialPawnB: u64 = 0xFF000000000000;
    try std.testing.expectEqual(initialPawnW, chessl.rotate180(initialPawnB));
    try std.testing.expectEqual(chessl.rotate180(initialPawnW), initialPawnB);
    std.log.info("[TEST]: rotate passed\n", .{});
}

test "find" {
    try std.testing.expectEqual(0, utilsl.findM(u8, "Ben Ben", "Ben"));
    try std.testing.expectEqual(0, utilsl.findM(u8, "[engine]", "["));
    try std.testing.expectEqual(7, utilsl.findM(u8, "[engine]", "]"));
    try std.testing.expectEqual(1, utilsl.findM(u8, "[engine]", "engine"));
    try std.testing.expectEqual(-1, utilsl.findM(u8, "[engine]", "a"));
    std.log.info("[TEST]: find passed\n", .{});
}

test "SEE" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    _ = arena;
    // source https://www.chessprogramming.org/SEE_-_The_Swap_Algorithm#cite_note-3
    const fen = "1k1r4/1pp4p/p7/4p3/8/P5P1/1PP4P/2K1R3 w - - 0 1";
    var move = movel.build_move(@intFromEnum(squarel.e_square.e1), @intFromEnum(squarel.e_square.e5), @intFromEnum(movel.e_moveFlags.CAPTURE), .nWhiteRook);
    var state = try chessl.getBoardFromFen(fen);
    move.setCapture(state.get_piece(move.getTo()));
    try std.testing.expectEqual(heuristicl.SEE(&state, move), 100);

    const fen2 = "1k1r3q/1ppn3p/p4b2/4p3/8/P2N2P1/1PP1R1BP/2K1Q3 w - - 0 1";
    move = movel.build_move(@intFromEnum(squarel.e_square.d3), @intFromEnum(squarel.e_square.e5), @intFromEnum(movel.e_moveFlags.CAPTURE), .nWhiteKnight);
    state = try chessl.getBoardFromFen(fen2);
    move.setCapture(state.get_piece(move.getTo()));
    try std.testing.expectEqual(heuristicl.SEE(&state, move), -200);
}

const testcases = [_][]const u8{
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 0 ",
    " rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 0 ",
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR  w HAha - 0 0 ",
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR   w   HAha - 0  0  ",
    "   rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 0 ",
};

test "generator" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var tokens = utilsl.split(u8, arena, chessl.DEFAULT_FEN, ' ') catch unreachable;
    defer tokens.deinit(arena);
    for (0..testcases.len) |i| {
        const vers = testcases[i];
        var gen = utilsl.splitGenerator(u8).init(vers, ' ');
        var j: usize = 0;
        try std.testing.expectEqual(tokens.items.len, gen.len());
        while (gen.next()) |tok| : (j += 1) {
            try std.testing.expect(utilsl.equal(u8, tokens.items[j], tok));
        }
    }
}
const join_testcases = [_][3][]const u8{
    [_][]const u8{ "out", "engine.log", "out/engine.log" },
    [_][]const u8{ "out/", "engine.log", "out/engine.log" },
    [_][]const u8{ "out/", "/engine.log", "out/engine.log" },
};

test "join" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    for (0..join_testcases.len) |i| {
        var joined = try filel.joinPath(arena, join_testcases[i][0], join_testcases[i][1]);
        defer joined.free(arena);
        try std.testing.expect(utilsl.equal(u8, joined._slice(), join_testcases[i][2]));
    }
}
