const chessl = @import("../chess.zig");

const std = @import("std");

const Board_state = chessl.Board_state;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

test "in between" {
    try std.testing.expectEqual(chessl.inBetween(.a1, .a8), 0x1010101010100);
    try std.testing.expectEqual(chessl.inBetween(.f1, .f8), 0x20202020202000);
    try std.testing.expectEqual(chessl.inBetween(.h4, .a4), 0x7e000000);
    try std.testing.expectEqual(chessl.inBetween(.a8, .h8), 0x7e00000000000000);
    try std.testing.expectEqual(chessl.inBetween(.a1, .h8), 0x40201008040200);
    try std.testing.expectEqual(chessl.inBetween(.a8, .h1), 0x2040810204000);
}
