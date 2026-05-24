const hashl = @import("../hashTable.zig");
const mainl = @import("../main.zig");
const std = @import("std");
const stringl = @import("../string.zig");
const bookl = @import("../book.zig");
const chessl = @import("../chess.zig");

test "entry retrievale" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    mainl.initAll(arena, false);
    hashl._initOrReallocHashTable(arena, 25, false);
    for (0..100) |i| {
        const code1: u64 = @intCast(i);
        const entry = hashl.buildEntryFromMatchResult(.{ .code = code1 }, 1, @intCast(i * i));
        try std.testing.expect(hashl.hashTable.storeEntry(&entry, code1));

        const code2 = @as(u64, @intCast(i)) + hashl.hashTable.size;
        const entry2 = hashl.buildEntryFromMatchResult(.{ .code = code2 }, 2, @intCast(i * i * i));
        try std.testing.expect(hashl.hashTable.storeEntry(&entry2, code2));
    }
    for (0..100) |i| {
        const entry = hashl.getEntryFromMatch(.{ .code = @intCast(i) }, 1);
        try std.testing.expect(entry.?.valid());

        const entry2 = hashl.getEntryFromMatch(.{ .code = @as(u64, @intCast(i)) + hashl.hashTable.size }, 1);
        try std.testing.expect(entry2.?.valid());

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
        const entry = hashl.buildEntryFromMatchResult(.{ .code = code }, @intCast(i), @intCast(i));
        try std.testing.expect(hashl.hashTable.storeEntry(&entry, code));
    }
    const bucket = hashl.hashTable.getBucketFromFullHashIndex(code);

    try std.testing.expectEqual(1, bucket.len);

    const entry = hashl.buildEntryFromMatchResult(.{ .code = code + m }, 200, 0);
    try std.testing.expect(hashl.hashTable.storeEntry(&entry, code + m));

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
        const entry = hashl.buildEntryFromMatchResult(.{ .code = code }, d[i], 1);
        std.debug.assert(hashl.hashTable.storeEntry(&entry, code));
    }
    const _bucket = hashl.hashTable.getBucketFromFullHashIndex(code);
    try std.testing.expectEqual(1, _bucket.len);

    std.log.info("[TEST]: entry replacement passed\n", .{});
}

const fenNode = struct {
    val: *[chessl.MAX_FEN_LENGTH]u8 = undefined,
    node: std.DoublyLinkedList.Node = .{},
    pub fn init(alloc: std.mem.Allocator, fen: []const u8) !*fenNode {
        var ret: *fenNode = try alloc.create(fenNode);
        const _s = try alloc.create([chessl.MAX_FEN_LENGTH]u8);
        @memcpy(_s, fen);
        ret.val = _s;
        return ret;
    }
};
// loop over the opening book, fill a hashMap of fen -> key
// check that key is always same of same fen
test "zobrist key consistency" {
    //var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    //defer arena_allocator.deinit();
    //const alloc = arena_allocator.allocator();
    const alloc = std.heap.page_allocator;
    mainl.initAll(alloc, false);
    //std.debug.print("key_shift: {d}\n", .{hashl.KEY_SHIFT});
    //
    const path = "opening/8moves_v3.pgn";
    var s = try stringl.string.initFromSlice(alloc, path);
    defer s.free(alloc);
    var db = try bookl.openingDatabase.init(alloc, &s, 42);
    defer db.free(alloc);
    var openings: std.ArrayList(stringl.string) = .empty;
    openings = db.drawnEntries;

    const base = try chessl.getBoardFromFen(chessl.DEFAULT_FEN);
    var tmp = base.copy();
    var map: std.StringHashMap(u64) = .init(alloc);
    var keys: std.DoublyLinkedList = .{};
    for (0..openings.items.len) |i| {
        var algeFen = openings.items[i];

        _ = try chessl._algebraicLineToIMoveMatch(alloc, &algeFen, &tmp);
        try std.testing.expectEqual(hashl.fullComputeZobristKeys(&tmp).code, tmp.frame.key.code);

        const fen = tmp.get_fen();

        if (map.contains(fen[0..fen.len])) {
            const k = map.get(fen[0..fen.len]).?;
            if (k != tmp.frame.key.code) {
                std.debug.print("error at fen {s}\n", .{fen});
                try std.testing.expectEqual(k, tmp.frame.key.code);
            }
        } else {
            //std.debug.print("put\n", .{});
            const n: *fenNode = try .init(alloc, &fen);
            try map.put(n.val[0..n.val.len], tmp.frame.key.code);
            keys.append(&n.node);
        }

        tmp = base.copy();
    }
    const fenNodeOffset: usize = 8;
    for (0..keys.len()) |i| {
        const n = keys.pop();
        if (n) |_n| {
            const node: *fenNode = @ptrFromInt(@intFromPtr(_n) - fenNodeOffset);
            alloc.destroy(node);
        }
        _ = i;
    }
}
