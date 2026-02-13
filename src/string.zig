const std = @import("std");
const utilsl = @import("utils.zig");

pub const string_err = error{
    mem_error,
    nei_error,
    itemNotFound_error,
};

pub const string = struct {
    len: usize,
    capacity: usize,
    data: []u8,
    //freed: bool = false,
    pub fn initFromSlice(alloc: std.mem.Allocator, slice: []const u8) !string {
        var ret: string = undefined;
        ret.len = slice.len;
        ret.capacity = slice.len;
        ret.data = try alloc.alloc(u8, ret.capacity);
        try ret.copyFromSlice(slice);
        return ret;
    }

    pub fn initZero(alloc: std.mem.Allocator, cap: usize) !string {
        var ret: string = undefined;
        ret.data = try alloc.alloc(u8, cap);
        ret.capacity = cap;
        ret.len = 0;
        return ret;
    }
    pub inline fn initFromBuffer(buffer: []u8) string {
        // this str does not take ownership of the data use carefully
        return .{ .len = buffer.len, .data = buffer, .capacity = buffer.len };
    }

    pub fn copyFromSlice(p_self: *string, slice: []const u8) string_err!void {
        if (slice.len > p_self.capacity) {
            return string_err.nei_error;
        }
        for (0..slice.len) |i| {
            p_self.data[i] = slice[i];
        }
    }
    pub fn put(p_self: *string, letter: u8) bool {
        if ((p_self.len + 1) > p_self.capacity) {
            return false;
        }
        p_self.data[p_self.len] = letter;
        p_self.len += 1;
        return true;
    }
    pub fn extend(p_self: *string, slice: []const u8) bool {
        if ((slice.len + p_self.len) > p_self.capacity) {
            return false;
        }
        for (slice) |letter| {
            _ = p_self.put(letter);
        }
        return true;
    }
    pub fn extendWithResize(p_self: *string, alloc: std.mem.Allocator, slice: []const u8) !void {
        if ((slice.len + p_self.len) > p_self.capacity) {
            p_self.data = try alloc.realloc(p_self.data, (slice.len + p_self.len));
        }
        for (slice) |letter| {
            _ = p_self.put(letter);
        }
    }
    pub fn extendWithResizeStr(p_self: *string, alloc: std.mem.Allocator, other: *string) !void {
        try p_self.extendWithResize(alloc, other._slice());
    }
    pub fn _slice(p_self: *const string) []const u8 {
        return p_self.data[0..p_self.len];
    }
    pub fn free(p_self: *string, alloc: std.mem.Allocator) void {
        alloc.free(p_self.data);
    }
    pub fn startsWith(p_self: *const string, other: []const u8) bool {
        if (other.len > p_self.len) {
            return false;
        }
        for (0..other.len) |i| {
            if (p_self.data[i] != other[i]) {
                return false;
            }
        }
        return true;
    }
    pub inline fn startsWithStr(p_self: *const string, other: *string) bool {
        return p_self.startsWith(other._slice());
    }
    pub fn endsWith(p_self: *const string, other: []const u8) bool {
        if (other.len > p_self.len) {
            return false;
        }
        for (0..other.len) |i| {
            const idx1 = p_self.len - 1 - i;
            const idx2 = other.len - 1 - i;
            if (p_self.data[idx1] != other[idx2]) {
                return false;
            }
        }
        return true;
    }
    pub inline fn endsWithStr(p_self: *const string, other: *string) bool {
        return p_self.endsWith(other._slice());
    }
    pub inline fn copy(p_self: *const string, alloc: std.mem.Allocator) !string {
        return string.initFromSlice(alloc, p_self._slice());
    }
    pub fn contains(p_self: *const string, substr: *string, token: utilsl.strTokens) bool {
        if (p_self.len < substr.len) {
            return false;
        }
        return utilsl.contains(p_self._slice(), substr._slice(), token);
    }
    pub fn containsE(p_self: *const string, substr: []const u8, comptime token: utilsl.strTokens) bool {
        if (p_self.len < substr.len) {
            return false;
        }
        return utilsl.contains(p_self._slice(), substr, token);
    }
    pub fn find(p_self: *const string, e: []const u8) string_err!usize {
        const ret = utilsl.findM(u8, p_self._slice(), e);
        if (ret < 0) {
            return string_err.itemNotFound_error;
        }
        return @intCast(ret);
    }
    pub fn findE(p_self: *const string, e: u8) string_err!usize {
        const ret = utilsl.find(u8, p_self._slice(), e);
        if (ret < 0) {
            return string_err.itemNotFound_error;
        }
        return @intCast(ret);
    }
    pub fn extractFromBounds(p_self: *const string, lBound: []const u8, rBound: []const u8) string_err![]const u8 {
        if (!p_self.containsE(lBound, .ignoreCase)) {
            return string_err.itemNotFound_error;
        }
        if (!p_self.containsE(rBound, .ignoreCase)) {
            return string_err.itemNotFound_error;
        }

        const startIndex = try p_self.find(lBound);
        const endIndex = utilsl.findM(u8, p_self._slice()[startIndex + 1 ..], rBound);
        if (endIndex < 0) {
            return string_err.itemNotFound_error;
        }
        return p_self._slice()[(startIndex + 1) .. (@as(usize, @intCast(endIndex)) + startIndex) + 1];
    }
    pub fn split(self: *const string, alloc: std.mem.Allocator, e: u8) !std.ArrayList([]const u8) {
        return try utilsl.split(u8, alloc, self._slice(), e);
    }
    pub fn clearRetainingCapacity(self: *string) void {
        self.len = 0;
    }
};
pub fn freeArrayList_string(alloc: std.mem.Allocator, arr: *std.ArrayList(string)) void {
    for (0..arr.items.len) |i| {
        arr.items[i].free(alloc);
    }
    arr.deinit(alloc);
}

pub fn mergePaths(alloc: std.mem.Allocator, s1: *string, s2: *string) !string {
    const slashCount: usize = @intFromBool(s1.endsWith("/")) + @intFromBool(s2.startsWith("/"));
    var ret: string = undefined;
    if (slashCount == 0) {
        const merged = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ s1._slice(), s2._slice() });
        ret = string.initFromBuffer(&merged);
        return ret;
    }
    if (slashCount == 1) {
        const merged = try std.fmt.allocPrint(alloc, "{s}{s}", .{ s1._slice(), s2._slice() });
        ret = string.initFromBuffer(&merged);
        return ret;
    }
    if (slashCount == 2) {
        const merged = try std.fmt.allocPrint(alloc, "{s}{s}", .{ s1._slice(), s2._slice()[1..s2.len] });
        ret = string.initFromBuffer(&merged);
        return ret;
    }
}
