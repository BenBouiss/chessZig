const std = @import("std");

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
        ret.copyFromSlice(slice);
        return ret;
    }

    pub fn zeroInit(alloc: std.mem.Allocator, cap: usize) !string {
        var ret: string = undefined;
        ret.data = try alloc.alloc(u8, cap);
        ret.capactity = cap;
        ret.len = 0;
        return ret;
    }
    pub fn copyFromSlice(p_self: *string, slice: []const u8) bool {
        if (slice.len > p_self.capactity) {
            return false;
        }
        for (0..slice.len) |i| {
            p_self.data[i] = slice[i];
        }

        return true;
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
};
