const std = @import("std");

pub fn computeStandardDeviation(comptime T: type, arr: []const T) T {
    std.debug.assert(arr.len != 0);
    const mean = computeMean(T, arr);
    var residue: T = 0;
    for (arr) |item| {
        residue += std.math.pow(T, item - mean, 2);
    }
    return @intCast(std.math.sqrt(@divFloor(@as(u64, @intCast(residue)), @as(u64, @intCast(arr.len)))));
}

pub fn computeMean(comptime T: type, arr: []const T) T {
    // only ints for now
    std.debug.assert(arr.len != 0);
    var tot: T = 0;
    for (arr) |item| {
        tot += item;
    }
    return @divFloor(tot, @as(T, @intCast(arr.len)));
}
