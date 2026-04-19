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

test "entry retrievale" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    mainl.initAll(arena, false);
    hashl._initOrReallocHashTable(arena, 25, false);
    defer hashl.hashTable.free(arena, false);
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

    std.log.info("[TEST]: entry storing passed\n", .{});
}
test "entry overwriting" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    mainl.initAll(arena, false);
    hashl._initOrReallocHashTable(arena, 25, false);
    defer hashl.hashTable.free(arena, false);

    const CODE = 42;
    const entry: hashl.Hash_entry = .{ .exploredDeph = 1, .key = .{ .code = CODE }, .val = .{ .search = .{ .evaluation = 1 } }, .valid = true };

    try std.testing.expect(hashl.hashTable.storeEntry(&entry));
    for (0..100) |i| {
        const _entry: hashl.Hash_entry = .{ .exploredDeph = @intCast(i), .key = .{ .code = CODE }, .val = .{ .search = .{ .evaluation = @intCast(i * i) } }, .valid = true };
        try std.testing.expect(hashl.hashTable.storeEntry(&_entry));

        const bucket = hashl.hashTable.getBucketFromFullHashIndex(CODE);
        try std.testing.expect(bucket.len == 1);
    }

    std.log.info("[TEST]: entry overwriting passed\n", .{});
}
