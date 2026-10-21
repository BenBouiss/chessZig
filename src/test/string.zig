const std = @import("std");
const stringl = @import("../string.zig");
const utilsl = @import("../utils.zig");
const string = stringl.string;

const extractTestCases = [_][2][]const u8{
    .{ "[Result \"1/2-1/2\"]", "1/2-1/2" },
    .{ "[Result \"1-0\"]", "1-0" },
    .{
        "[Result \"0-1\"]", "0-1",
    },
};

test "extract" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    for (extractTestCases) |s| {
        const str = string.initViewFromSlice(s[0]);
        const ext = str.extractFromBounds("\"", "\"") catch unreachable;
        try std.testing.expect(utilsl.equal(u8, ext, s[1]));
    }
}
