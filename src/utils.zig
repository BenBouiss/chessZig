const std = @import("std");

const debug_err = error{ERR_INPUT};

pub const strTokens = enum(u8) { standardToken, ignoreCase };

pub fn clear() void {
    //std.debug.print("Clearing screen \n", .{});
    std.debug.print("\x1B[2J\x1B[H", .{});
}

pub fn absolute(x: i8) i8 {
    return std.math.sign(x) * x;
}

pub fn max(x: i8, y: i8) i8 {
    if (x < y) {
        return y;
    }
    return x;
}
pub fn min(comptime T: type, x: T, y: T) T {
    if (x < y) {
        return x;
    }
    return y;
}

pub fn cutArrayListEvenly(comptime T: type, alloc: std.mem.Allocator, arr: std.ArrayList(T), size: usize) !std.ArrayList(std.ArrayList(T)) {
    const sizeEach: usize = arr.items.len / size;
    var ret: std.ArrayList(std.ArrayList(T)) = .{};
    try ret.append(alloc, .{});
    var cell: usize = 0;
    var count: usize = 0;
    const last_cell = sizeEach * size;
    var remainder_start = arr.items.len;
    for (0..arr.items.len) |i| {
        if (count == sizeEach) {
            if (i != last_cell) {
                count = 0;
                cell += 1;
                try ret.append(alloc, .{});
            } else {
                remainder_start = i;
                break;
            }
        }
        try ret.items[cell].append(alloc, arr.items[i]);
        count += 1;
    }
    for (remainder_start..arr.items.len) |i| {
        try ret.items[i - remainder_start].append(alloc, arr.items[i]);
    }
    return ret;
}

pub fn equal(comptime T: type, a: []const T, b: []const T) bool {
    if (a.len != b.len) {
        return false;
    }
    for (a, b) |e1, e2| {
        if (e1 != e2) {
            return false;
        }
    }
    return true;
}

pub fn lowerLetter(letter: u8) u8 {
    if ((letter >= 65) and (letter <= 90)) {
        return letter + 32;
    }
    return letter;
}

pub fn contains(a: []const u8, b: []const u8, comptime token: strTokens) bool {
    // checks if the string b is present in a
    if (b.len > a.len) {
        return false;
    }
    var moveTarget: u32 = 0;
    for (0..a.len) |i| {
        if (moveTarget == b.len) {
            return true;
        }
        if (comptime token == .standardToken) {
            if (a[i] == b[moveTarget]) {
                moveTarget += 1;
            } else {
                moveTarget = 0;
            }
        } else if (comptime token == .ignoreCase) {
            if (lowerLetter(a[i]) == lowerLetter(b[moveTarget])) {
                moveTarget += 1;
            } else {
                moveTarget = 0;
            }
        }
    }
    return moveTarget == b.len;
}

pub fn find(comptime T: type, a: []const T, e: T) i8 {
    var ret: i8 = 0;
    for (a) |a_e| {
        if (a_e == e) {
            return ret;
        }
        ret += 1;
    }
    return -1;
}
pub fn findM(comptime T: type, a: []const T, e: []const T) i8 {
    if (e.len > a.len) {
        return -1;
    }
    var ret: i8 = 0;
    var count: i8 = 0;
    for (0..a.len) |i| {
        const a_e = a[i];
        if (count == e.len) {
            return ret;
        }

        if (a_e == e[@intCast(count)]) {
            if (count == 0) {
                ret = @intCast(i);
            }
            count += 1;
        } else {
            count = 0;
        }
    }
    if (count == e.len) {
        return ret;
    }
    return -1;
}

pub fn split(comptime T: type, alloc: std.mem.Allocator, a: []const T, e: T) !std.ArrayList([]const T) {
    var ret = try std.ArrayList([]const T).initCapacity(alloc, 4);
    if (a.len == 0) {
        return ret;
    }
    var first_idx: usize = 0;
    for (0..a.len) |i| {
        if (a[i] == e) {
            if (first_idx != i) {
                try ret.append(alloc, a[first_idx..i]);
            }
            first_idx = i + 1;
        }
    }
    if (ret.items.len == 0) {
        try ret.append(alloc, a);
        first_idx = a.len;
    }
    if (first_idx != (a.len)) {
        try ret.append(alloc, a[first_idx..a.len]);
    }
    return ret;
}
pub fn trimStr(str: []const u8) []const u8 {
    for (0..str.len) |i| {
        if (str[i] == 0) {
            return str[0..i];
        }
    }
    return str;
}

pub fn lower(alloc: std.mem.Allocator, buffer: []const u8) ![]const u8 {
    var ret = try alloc.alloc(u8, buffer.len);
    for (0..buffer.len) |i| {
        if ((buffer[i] >= 65) and (buffer[i] <= 90)) {
            ret[i] = buffer[i] + 32;
        } else {
            ret[i] = buffer[i];
        }
    }
    return ret;
}

pub fn str_countLetter(buffer: []const u8, letter: u8) u64 {
    var count: u64 = 0;
    for (0..buffer.len) |i| {
        if (buffer[i] == letter) {
            count += 1;
        }
    }
    return count;
}

pub fn concatArrayList(comptime T: type, alloc: std.mem.Allocator, arr: std.ArrayList([]const T), separator: T) ![]const T {
    var sizeBuffer: usize = arr.items.len - 1;
    if (sizeBuffer < 0) {
        return debug_err.ERR_INPUT;
    }
    for (arr.items) |seq| {
        sizeBuffer += seq.len;
    }
    var ret = try alloc.alloc(T, sizeBuffer);
    var count: usize = 0;
    for (0..arr.items.len) |i| {
        for (0..arr.items[i].len) |j| {
            ret[count] += arr.items[i][j];
            count += 1;
        }
        if (i != (arr.items.len - 1)) {
            ret[count] = separator;
            count += 1;
        }
    }

    return ret;
}

pub fn concatSlice(comptime T: type, alloc: std.mem.Allocator, arr: [][]const T, separator: T) ![]const T {
    var sizeBuffer: usize = arr.len - 1;
    if (sizeBuffer < 0) {
        return debug_err.ERR_INPUT;
    }
    for (arr) |seq| {
        sizeBuffer += seq.len;
    }
    var ret = try alloc.alloc(T, sizeBuffer);
    var count: usize = 0;
    for (0..arr.len) |i| {
        for (0..arr[i].len) |j| {
            ret[count] += arr[i][j];
            count += 1;
        }
        if (i != (arr.len - 1)) {
            ret[count] = separator;
            count += 1;
        }
    }

    return ret;
}
pub fn removePaddingValue(buffer: []const u8) []const u8 {
    var last_idx: usize = 0;
    for (buffer) |e| {
        if (e == 0) {
            return buffer[0..last_idx];
        }
        last_idx += 1;
    }
    return buffer;
}

pub fn printArrayListTasStr(comptime T: type, a: std.ArrayList(T)) void {
    std.debug.print("(", .{});
    for (0..a.items.len) |i| {
        std.debug.print("'{s}'(size: {d}) ", .{ a.items[i], a.items[i].len });
        if (i != (a.items.len - 1)) {
            std.debug.print(", ", .{});
        }
    }
    std.debug.print(") \n", .{});
    return;
}
pub fn askContinue() void {
    std.debug.print("Press continue: ", .{});
    var stdin_buffer: [32]u8 = undefined;
    var line_buffer: [32]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&stdin_buffer);
    var w: std.io.Writer = .fixed(&line_buffer);

    _ = stdin.interface.streamDelimiterLimit(&w, '\n', .unlimited) catch void;

    std.debug.print("\n", .{});
    return;
}

pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch {
        return false;
    };
    return true;
}
