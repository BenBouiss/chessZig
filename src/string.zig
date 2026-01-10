const std = @import("std");
const utilsl = @import("utils.zig");

pub const string_err = error{
    mem_error,
    nei_error,
    itemNotFound_error,
};

pub const string = struct {
    len: usize,
    capactity: usize,
    data: []u8,
    //freed: bool = false,
    pub fn initFromSlice(alloc: std.mem.Allocator, slice: []const u8) !string {
        var ret: string = undefined;
        ret.len = slice.len;
        ret.capactity = slice.len;
        ret.data = try alloc.alloc(u8, ret.capactity);
        try ret.copyFromSlice(slice);
        return ret;
    }

    pub fn initZero(alloc: std.mem.Allocator, cap: usize) !string {
        var ret: string = undefined;
        ret.data = try alloc.alloc(u8, cap);
        ret.capactity = cap;
        ret.len = 0;
        return ret;
    }
    pub inline fn initFromBuffer(buffer: []u8) string {
        // this str does not take ownership of the data use carefully
        return .{ .len = buffer.len, .data = buffer, .capactity = buffer.len };
    }

    pub fn copyFromSlice(p_self: *string, slice: []const u8) string_err!void {
        if (slice.len > p_self.capactity) {
            return string_err.nei_error;
        }
        for (0..slice.len) |i| {
            p_self.data[i] = slice[i];
        }
    }
    pub fn put(p_self: *string, letter: u8) bool {
        if ((p_self.len + 1) > p_self.capactity) {
            return false;
        }
        p_self.data[p_self.len] = letter;
        p_self.len += 1;
        return true;
    }
    pub fn extend(p_self: *string, slice: []const u8) bool {
        if ((slice.len + p_self.len) > p_self.capactity) {
            return false;
        }
        for (slice) |letter| {
            _ = p_self.put(letter);
        }
        return true;
    }
    pub fn _slice(self: string) []const u8 {
        return self.data[0..self.len];
    }
    pub fn free(p_self: *string, alloc: std.mem.Allocator) void {
        alloc.free(p_self.data);
    }
    pub fn startsWith(p_self: *string, other: []const u8) bool {
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
    pub inline fn startsWithStr(p_self: *string, other: *string) bool {
        return p_self.startsWith(other.data[0..other.len]);
    }
    pub inline fn copy(p_self: *string, alloc: std.mem.Allocator) string {
        return string.initFromSlice(alloc, p_self._slice());
    }
    pub fn contains(p_self: *string, substr: *string, token: utilsl.strTokens) bool {
        if (p_self.len < substr.len) {
            return false;
        }
        return utilsl.contains(p_self._slice(), substr._slice(), token);
    }
    pub fn containsE(p_self: *string, substr: []const u8, comptime token: utilsl.strTokens) bool {
        if (p_self.len < substr.len) {
            return false;
        }
        return utilsl.contains(p_self._slice(), substr, token);
    }
    pub fn find(p_self: *string, e: []const u8) string_err!usize {
        const ret = utilsl.findM(u8, p_self._slice(), e);
        if (ret < 0) {
            return string_err.itemNotFound_error;
        }
        return @intCast(ret);
    }
    pub fn findE(p_self: *string, e: u8) string_err!usize {
        const ret = utilsl.find(u8, p_self._slice(), e);
        if (ret < 0) {
            return string_err.itemNotFound_error;
        }
        return @intCast(ret);
    }
    pub fn extractFromBounds(p_self: *string, lBound: []const u8, rBound: []const u8) string_err![]const u8 {
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
};
