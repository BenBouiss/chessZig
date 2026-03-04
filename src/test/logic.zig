const chessl = @import("../chess.zig");
const utilsl = @import("../utils.zig");
const moveTablel = @import("../moveTables.zig");

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
