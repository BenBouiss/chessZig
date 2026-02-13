const stringl = @import("string.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");

const std = @import("std");

const string = stringl.string;

pub const file_err = error{
    fileNotFound_error,
    mem_error,
};

pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch {
        return false;
    };
    return true;
}
pub fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd();

    dir.access(path, .{}) catch {
        return false;
    };
    return true;
}
pub fn makedirR(path: []const u8) !void {
    var dir = std.fs.cwd();
    dir.makePath(path) catch {
        return;
    };
    return;
}

pub fn getTokensFromFileAlloc(alloc: std.mem.Allocator, path: []const u8, sep: u8, maxsize: i64) anyerror!std.ArrayList(string) {
    if (!fileExists(path)) {
        return file_err.fileNotFound_error;
    }
    var ret = std.ArrayList(string).initCapacity(alloc, 2) catch {
        return file_err.mem_error;
    };

    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();
    const file_size = try file.getEndPos();
    var buffer: []u8 = try alloc.alloc(u8, file_size);
    defer alloc.free(buffer);
    _ = try file.read(buffer[0..buffer.len]);
    const _sep: []const u8 = &[_]u8{sep};
    var flines = std.mem.tokenizeAny(u8, buffer, _sep);
    var count: u64 = 0;
    while (flines.next()) |line| {
        if (count == maxsize) {
            break;
        }
        const s = string.initFromSlice(alloc, line) catch {
            ret.deinit(alloc);
            return file_err.mem_error;
        };

        ret.append(alloc, s) catch {
            ret.deinit(alloc);
            return file_err.mem_error;
        };
        count += 1;
    }
    return ret;
}
pub fn getTokensFromFile(alloc: std.mem.Allocator, path: []const u8, sep: u8) anyerror!std.ArrayList(string) {
    if (!fileExists(path)) {
        return file_err.fileNotFound_error;
    }
    var ret = std.ArrayList(string).initCapacity(alloc, 2) catch {
        return file_err.mem_error;
    };

    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    var buffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
    var f_reader = file.reader(&buffer);
    const reader = &f_reader.interface;
    while (true) {
        var _buffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
        var w: std.io.Writer = .fixed(&_buffer);
        const size = reader.streamDelimiter(&w, sep) catch {
            break;
        };
        reader.toss(1);
        if (size <= 1) {
            continue;
        }
        const s = string.initFromSlice(alloc, &_buffer) catch {
            ret.deinit(alloc);
            return file_err.mem_error;
        };

        ret.append(alloc, s) catch {
            ret.deinit(alloc);
            return file_err.mem_error;
        };
    }
    return ret;
}
pub fn main(alloc: std.mem.Allocator, path: []const u8) !void {
    var tokens = try getTokensFromFile(alloc, path, '\n');
    defer stringl.freeArrayList_string(alloc, &tokens);
    for (0..tokens.items.len) |i| {
        std.debug.print("Token: n°{d}: {s} \n", .{ i, tokens.items[i]._slice() });
    }
}
