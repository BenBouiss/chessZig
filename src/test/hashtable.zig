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
const configl = @import("../config.zig");

const std = @import("std");

const Board_state = chessl.Board_state;

test "entry retrievale" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    mainl.initAll(arena, false);
    hashl._initOrReallocHashTable(arena, 25, false);
    for (0..100) |i| {
        const entry: hashl.Hash_entry = .{ .exploredDepth = 1, .key = .{ .code = @intCast(i) }, .val = .{ .search = .{ .evaluation = @intCast(i * i) } }, .valid = true };
        try std.testing.expect(hashl.hashTable.storeEntry(&entry));

        const entry2: hashl.Hash_entry = .{ .exploredDepth = 2, .key = .{ .code = @as(u64, @intCast(i)) + hashl.hashTable.size }, .val = .{ .search = .{ .evaluation = @intCast(i * i * i) } }, .valid = true };
        try std.testing.expect(hashl.hashTable.storeEntry(&entry2));
    }
    for (0..100) |i| {
        const entry = hashl.getEntryFromMatch(.{ .code = @intCast(i) }, 1);
        try std.testing.expect(entry.?.valid);

        const entry2 = hashl.getEntryFromMatch(.{ .code = @as(u64, @intCast(i)) + hashl.hashTable.size }, 1);
        try std.testing.expect(entry2.?.valid);

        const bucket = hashl.hashTable.getBucketFromFullHashIndex(@intCast(i));
        try std.testing.expectEqual(bucket.len, 2);
    }

    std.log.info("[TEST]: entry storing passed\n", .{});
    hashl.hashTable.free(arena, false);
}

test "entry overwrite" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    mainl.initAll(arena, false);
    hashl._initOrReallocHashTable(arena, 25, false);
    defer hashl.hashTable.free(arena, false);

    const m: u64 = @intCast(hashl.hashTable.size);
    const code: u64 = 4;
    //const depths = [_]u8{ 1, 4 };

    for (0..100) |i| {
        const entry: hashl.Hash_entry = .{ .exploredDepth = @intCast(i), .key = .{ .code = code }, .val = .{ .search = .{ .evaluation = @intCast(i) } }, .valid = true };
        try std.testing.expect(hashl.hashTable.storeEntry(&entry));
    }
    const bucket = hashl.hashTable.getBucketFromFullHashIndex(code);

    try std.testing.expectEqual(1, bucket.len);

    const entry: hashl.Hash_entry = .{ .exploredDepth = 200, .key = .{ .code = code + m }, .val = .{ .search = .{ .evaluation = 0 } }, .valid = true };
    try std.testing.expect(hashl.hashTable.storeEntry(&entry));

    try std.testing.expectEqual(2, bucket.len);

    std.log.info("[TEST]: entry overwrite passed\n", .{});
}

test "entry replacement" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    mainl.initAll(arena, false);
    hashl._initOrReallocHashTable(arena, 25, false);
    defer hashl.hashTable.free(arena, false);
    const d = [_]u8{ 16, 4 };
    const code: u64 = 42;
    for (0..d.len) |i| {
        const entry: hashl.Hash_entry = .{ .exploredDepth = d[i], .key = .{ .code = code }, .val = .{ .search = .{ .evaluation = 1 } }, .valid = true };
        std.debug.assert(hashl.hashTable.storeEntry(&entry));
    }
    const _bucket = hashl.hashTable.getBucketFromFullHashIndex(code);
    try std.testing.expectEqual(1, _bucket.len);

    std.log.info("[TEST]: entry replacement passed\n", .{});
}
