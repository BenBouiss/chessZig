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

test "entry retrievale" {
    mainl.initAll(false);
    hashl._initOrReallocHashTable(GLOBAL_ALLOC, 25, true);
    defer hashl.hashTable.free(GLOBAL_ALLOC);
    for (0..100) |i| {
        const entry: hashl.Hash_entry = .{ .exploredDeph = 1, .key = .{ .code = @intCast(i) }, .val = .{ .search = .{ .evaluation = @intCast(i * i) } }, .valid = true };
        try std.testing.expect(hashl.hashTable.storeEntry(&entry));

        const entry2: hashl.Hash_entry = .{ .exploredDeph = 1, .key = .{ .code = @as(u64, @intCast(i)) + hashl.hashTable.entries.len }, .val = .{ .search = .{ .evaluation = @intCast(i * i * i) } }, .valid = true };
        try std.testing.expect(hashl.hashTable.storeEntry(&entry2));
    }
    for (0..100) |i| {
        const entry = hashl.getEntryFromMatch(.{ .code = @intCast(i) }, 1);
        try std.testing.expect(entry.?.valid);

        const entry2 = hashl.getEntryFromMatch(.{ .code = @as(u64, @intCast(i)) + hashl.hashTable.entries.len }, 1);
        try std.testing.expect(entry2.?.valid);

        const bucket = hashl.hashTable.getBucketFromFullHashIndex(@intCast(i));
        try std.testing.expect(bucket.len == 2);
    }

    std.debug.print("[TEST]: entry storing passed\n", .{});
}
