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
pub fn erf(comptime T: type, x: T) T {
    // https://en.wikipedia.org/wiki/Error_function#Bounds_and_numerical_approximations
    // extended global Pade approximation with tuned parameters
    const x2 = std.math.pow(T, x, 2);
    const x4 = std.math.pow(T, x, 4);
    const x6 = std.math.pow(T, x, 6);
    const num = 4 + 0.880877880079853 * x2 + 0.144026670907584 * x4 + 0.0077581300270021 * x6;
    const denom = @as(T, std.math.pi) + 0.786235558186528 * x2 + 0.128368576906837 * x4 + 0.00773380006014367 * x6;
    return std.math.sign(x) * std.math.sqrt(1 - std.math.exp(-x2 * num / denom));
}
