const std = @import("std");
const mainl = @import("main.zig");
const stringl = @import("string.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const chessl = @import("chess.zig");

const _alloc = mainl.GLOBAL_ALLOC;
const string = stringl.string;

pub const outcomeFlag = enum(u8) { draw, blackWin, whiteWin };

pub fn getOutcomeFlag(str: []const u8) outcomeFlag {
    if (utilsl.contains(str, "1/2-1/2", .ignoreCase)) {
        return .draw;
    }
    // dont know from there
    if (utilsl.contains(str, "1-0", .ignoreCase)) {
        return .whiteWin;
    }
    if (utilsl.contains(str, "0-1", .ignoreCase)) {
        return .blackWin;
    }
    return .draw;
}
pub const openingDatabase = struct {
    //
    drawnEntries: std.ArrayList(string) = undefined,
    whiteEntries: std.ArrayList(string) = undefined,
    blackEntries: std.ArrayList(string) = undefined,
    initialized: bool = false,
    size: usize = 0,

    rngIntGenerator: std.Random.DefaultPrng = undefined,
    randInt: std.Random = undefined,
    seed: u64 = 42,
    pub fn init(alloc: std.mem.Allocator, path: *string, seed: u64) !openingDatabase {
        // exemple of an entry
        // [Event "?"]
        //[Site "?"]
        //[Date "2013.11.04"]
        //[Round "1"]
        //[White "Stockfish"]
        //[Black "Stockfish"]
        //[Result "1/2-1/2"]
        //[Eco "A05"]
        //
        //1. Nf3 Nf6 2. c4 c5 3. Nc3 e6 4. e4 Nc6 5. h3 d5 6. cxd5 exd5 7. e5 Ne4 8.
        //Bb5 Be7 1/2-1/2
        //
        // ... next ones afterwards

        var ret: openingDatabase = .{};
        ret.drawnEntries = .{};
        ret.whiteEntries = .{};
        ret.blackEntries = .{};
        ret.initialized = true;
        try readEntries(&ret, alloc, path);
        ret.setSeed(seed);
        ret.printInfo();
        return ret;
    }
    pub fn addEntry(p_self: *openingDatabase, alloc: std.mem.Allocator, flag: outcomeFlag, lineStr: *string) !void {
        switch (flag) {
            .draw => {
                try p_self.drawnEntries.append(alloc, try lineStr.copy(alloc));
            },
            .whiteWin => {
                try p_self.whiteEntries.append(alloc, try lineStr.copy(alloc));
            },
            .blackWin => {
                try p_self.blackEntries.append(alloc, try lineStr.copy(alloc));
            },
        }
        p_self.size += 1;
    }
    pub fn setSeed(p_self: *openingDatabase, seed: u64) void {
        p_self.seed = seed;
        p_self.rngIntGenerator.seed(seed);
        p_self.randInt = p_self.rngIntGenerator.random();
    }
    pub fn free(p_self: *openingDatabase, alloc: std.mem.Allocator) void {
        if (!p_self.initialized) {
            return;
        }
        for (p_self.whiteEntries.items) |*str| {
            str.free(alloc);
        }
        for (p_self.blackEntries.items) |*str| {
            str.free(alloc);
        }
        for (p_self.drawnEntries.items) |*str| {
            str.free(alloc);
        }
        p_self.whiteEntries.deinit(alloc);
        p_self.blackEntries.deinit(alloc);
        p_self.drawnEntries.deinit(alloc);
        p_self.initialized = false;
    }
    pub fn sample(p_self: *openingDatabase, alloc: std.mem.Allocator, size: usize, flag: outcomeFlag) !std.ArrayList(string) {
        var drawing: std.ArrayList(string) = undefined;
        switch (flag) {
            .draw => {
                drawing = p_self.drawnEntries;
            },
            .whiteWin => {
                drawing = p_self.whiteEntries;
            },
            .blackWin => {
                drawing = p_self.blackEntries;
            },
        }
        var ret: std.ArrayList(string) = .{};
        for (0..size) |_| {
            const randIdx = p_self.randInt.intRangeAtMost(usize, 0, drawing.items.len);
            try ret.append(alloc, drawing.items[randIdx]);
        }
        return ret;
    }
    pub fn printInfo(p_self: *openingDatabase) void {
        std.debug.print("Number of drawn openings: {d}\n", .{p_self.drawnEntries.items.len});
        std.debug.print("Number of white won openings: {d}\n", .{p_self.whiteEntries.items.len});
        std.debug.print("Number of black won openings: {d}\n", .{p_self.blackEntries.items.len});
    }
};
pub fn readEntries(db: *openingDatabase, alloc: std.mem.Allocator, path: *string) !void {
    const file = try std.fs.cwd().openFile(path._slice(), .{ .mode = .read_only });
    defer file.close();
    var buffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
    var f_reader = file.reader(&buffer);
    const reader = &f_reader.interface;
    const buffer_size = 1024;
    var currentEntriesType: outcomeFlag = .draw;
    var emptySpaces: u8 = 0;
    var lineBuffer: [configl.MAX_MATCH_STR_LENGTH]u8 = std.mem.zeroes([configl.MAX_MATCH_STR_LENGTH]u8);
    var lineStr = string.initFromBuffer(&lineBuffer);
    lineStr.clearRetainingCapacity();
    while (true) {
        var _buffer: [buffer_size]u8 = std.mem.zeroes([buffer_size]u8);
        var w: std.io.Writer = .fixed(&_buffer);
        var s = string.initFromBuffer(&_buffer);

        const size = reader.streamDelimiter(&w, '\n') catch {
            break;
        };
        reader.toss(1);

        s.len = size - 1;
        if (size == 1) {
            emptySpaces += 1;
            if (emptySpaces == 2) {
                // save to db
                db.addEntry(alloc, currentEntriesType, &lineStr) catch {
                    @panic("Cant add entries to database");
                };
                lineStr.clearRetainingCapacity();
                emptySpaces = 0;
                continue;
            }
        }
        if (s.containsE("result", .ignoreCase)) {
            const outCome = s.extractFromBounds("\"", "\"") catch {
                continue;
            };
            currentEntriesType = getOutcomeFlag(outCome);
        } else if (emptySpaces != 0) {
            // save to str
            _ = lineStr.put(' ');
            try lineStr.extendWithResize(alloc, s._slice()[0 .. size - 1]);
        }
    }
}

pub fn test_read(path: *string) !void {
    const file = try std.fs.cwd().openFile(path._slice(), .{ .mode = .read_only });
    defer file.close();
    var buffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
    var f_reader = file.reader(&buffer);
    const reader = &f_reader.interface;
    const buffer_size = 1024;
    // in this only to depth 8, thus it should not be that big
    while (true) {
        var _buffer: [buffer_size]u8 = std.mem.zeroes([buffer_size]u8);
        var w: std.io.Writer = .fixed(&_buffer);
        var s = string.initFromBuffer(&_buffer);
        const size = reader.streamDelimiter(&w, '\n') catch {
            break;
        };
        reader.toss(1);

        std.debug.print("Found {d} bytes in the file '{s}'\n", .{ size, s._slice()[0 .. size - 1] });
    }
}

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

pub fn test_db(path: *string) !void {
    var db = try openingDatabase.init(GLOBAL_ALLOC, path, 42);
    var openings = try db.sample(GLOBAL_ALLOC, 5, .draw);
    defer openings.deinit(GLOBAL_ALLOC);

    for (0..openings.items.len) |i| {
        var algeFen = openings.items[i];
        const moves = try chessl.algebraicLineToIMoveMatch(&algeFen);
        var tmp = try chessl.getBoardFromFen(GLOBAL_ALLOC, chessl.DEFAULT_FEN);
        for (0..moves.len) |j| {
            const move = moves.moves[j];
            tmp.makeMove(move);
        }
        //chessl.print_boardstate(&tmp);
    }
    for (openings.items) |*str| {
        defer str.free(GLOBAL_ALLOC);
        //std.debug.print("{s}\n", .{str._slice()});
    }
}

pub fn main(path: *string) !void {
    //
    if (!utilsl.fileExists(path._slice())) {
        std.debug.print("File {s} does not exists \n", .{path._slice()});
        return;
    }
    //try test_read(path);

    var db = try openingDatabase.init(GLOBAL_ALLOC, path, 42);
    var openings = try db.sample(GLOBAL_ALLOC, 5, .draw);
    defer openings.deinit(GLOBAL_ALLOC);
    for (openings.items) |*str| {
        defer str.free(GLOBAL_ALLOC);
        std.debug.print("{s}\n", .{str._slice()});
    }
}
