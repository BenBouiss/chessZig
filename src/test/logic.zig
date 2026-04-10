const chessl = @import("../chess.zig");
const utilsl = @import("../utils.zig");
const moveTablel = @import("../moveTables.zig");
const movel = @import("../move.zig");
const squarel = @import("../square.zig");
const heuristicl = @import("../heuristic.zig");

const std = @import("std");

const Board_state = chessl.Board_state;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

test "in between" {
    moveTablel._initTables(false);
    try std.testing.expectEqual(chessl.inBetween(.a1, .a8), 0x1010101010100);
    try std.testing.expectEqual(chessl.inBetween(.f1, .f8), 0x20202020202000);
    try std.testing.expectEqual(chessl.inBetween(.h4, .a4), 0x7e000000);
    try std.testing.expectEqual(chessl.inBetween(.a8, .h8), 0x7e00000000000000);
    try std.testing.expectEqual(chessl.inBetween(.a1, .h8), 0x40201008040200);
    try std.testing.expectEqual(chessl.inBetween(.a8, .h1), 0x2040810204000);

    std.debug.print("[TEST]: inbetween passed\n", .{});
}
test "rotate" {
    const initialPawn: u64 = 0xFF00000000FF00;
    try std.testing.expectEqual(initialPawn, chessl.rotate180(initialPawn));
    const initialPawnW: u64 = 0xFF00;
    const initialPawnB: u64 = 0xFF000000000000;
    try std.testing.expectEqual(initialPawnW, chessl.rotate180(initialPawnB));
    try std.testing.expectEqual(chessl.rotate180(initialPawnW), initialPawnB);
    std.debug.print("[TEST]: rotate passed\n", .{});
}

test "find" {
    try std.testing.expectEqual(0, utilsl.findM(u8, "Ben Ben", "Ben"));
    try std.testing.expectEqual(0, utilsl.findM(u8, "[engine]", "["));
    try std.testing.expectEqual(7, utilsl.findM(u8, "[engine]", "]"));
    try std.testing.expectEqual(1, utilsl.findM(u8, "[engine]", "engine"));
    try std.testing.expectEqual(-1, utilsl.findM(u8, "[engine]", "a"));
    std.debug.print("[TEST]: find passed\n", .{});
}

test "SEE" {
    // source https://www.chessprogramming.org/SEE_-_The_Swap_Algorithm#cite_note-3
    const fen = "1k1r4/1pp4p/p7/4p3/8/P5P1/1PP4P/2K1R3 w - - 0 1";
    var move = movel.build_move(@intFromEnum(squarel.e_square.e1), @intFromEnum(squarel.e_square.e5), @intFromEnum(movel.e_moveFlags.CAPTURE), .nWhiteRook);
    var state = try chessl.getBoardFromFen(GLOBAL_ALLOC, fen);
    move.setCapture(state.get_piece(move.getTo()));
    try std.testing.expectEqual(heuristicl.SEE(&state, move), 100);

    const fen2 = "1k1r3q/1ppn3p/p4b2/4p3/8/P2N2P1/1PP1R1BP/2K1Q3 w - - 0 1";
    move = movel.build_move(@intFromEnum(squarel.e_square.d3), @intFromEnum(squarel.e_square.e5), @intFromEnum(movel.e_moveFlags.CAPTURE), .nWhiteKnight);
    state = try chessl.getBoardFromFen(GLOBAL_ALLOC, fen2);
    move.setCapture(state.get_piece(move.getTo()));
    try std.testing.expectEqual(heuristicl.SEE(&state, move), -200);
}
