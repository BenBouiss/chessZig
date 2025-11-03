const std = @import("std");

pub fn clear() void {
    //std.debug.print("Clearing screen \n", .{});
    std.debug.print("\x1B[2J\x1B[H", .{});
}

pub fn absolute(x: i8) i8 {
    return std.math.sign(x) * x;
}
