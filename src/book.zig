const std = @import("std");
const mainl = @import("main.zig");
const stringl = @import("string.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const chessl = @import("chess.zig");
const filel = @import("file.zig");
const hashl = @import("hashTable.zig");
const boardl = @import("board.zig");

const string = stringl.string;

pub const outcomeFlag = enum(u8) { any, draw, blackWin, whiteWin };
pub const entryType = enum(u8) { line, fen };

pub const bookErr = error{noValidEntryErr};

pub fn getOutcomeFlag(str: []const u8) outcomeFlag {
    if (utilsl.contains(str, "1/2-1/2", .ignoreCase)) {
        return .draw;
    }
    if (utilsl.contains(str, "1-0", .ignoreCase)) {
        return .whiteWin;
    }
    if (utilsl.contains(str, "0-1", .ignoreCase)) {
        return .blackWin;
    }
    // dont know from there
    return .any;
}
//
pub const entry = struct {
    v: string = undefined,
    t: entryType = .line,
};
pub const openingDatabase = struct {
    //
    drawnEntries: std.ArrayList(entry) = .empty,
    whiteEntries: std.ArrayList(entry) = .empty,
    blackEntries: std.ArrayList(entry) = .empty,
    initialized: bool = false,

    rngIntGenerator: std.Random.DefaultPrng = undefined,
    seed: u64 = 42,
    pub fn init(alloc: std.mem.Allocator, path: []const u8, seed: u64, verbose: bool) !openingDatabase {
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
        ret.drawnEntries = try .initCapacity(alloc, 4);
        ret.whiteEntries = try .initCapacity(alloc, 4);
        ret.blackEntries = try .initCapacity(alloc, 4);
        ret.initialized = true;
        if (utilsl.contains(path, ".pgn", .ignoreCase)) {
            try readEntriesPgn(&ret, alloc, path);
        } else if (utilsl.contains(path, ".epd", .ignoreCase)) {
            try readEntriesEpd(&ret, alloc, path);
        }
        ret.setSeed(seed);
        if (verbose) {
            ret.printInfo();
        }
        return ret;
    }
    pub fn addEntry(p_self: *openingDatabase, alloc: std.mem.Allocator, flag: outcomeFlag, lineStr: *string, t: entryType) !void {
        switch (flag) {
            .draw, .any => {
                try p_self.drawnEntries.append(alloc, .{ .t = t, .v = try lineStr.copy(alloc) });
            },
            .whiteWin => {
                try p_self.whiteEntries.append(alloc, .{ .t = t, .v = try lineStr.copy(alloc) });
            },
            .blackWin => {
                try p_self.blackEntries.append(alloc, .{ .t = t, .v = try lineStr.copy(alloc) });
            },
        }
    }
    pub fn getSize(p_self: *const openingDatabase, outcome: outcomeFlag) usize {
        switch (outcome) {
            .draw => {
                return p_self.drawnEntries.items.len;
            },
            .whiteWin => {
                return p_self.whiteEntries.items.len;
            },
            .blackWin => {
                return p_self.blackEntries.items.len;
            },
            .any => {
                return p_self.drawnEntries.items.len + p_self.whiteEntries.items.len + p_self.blackEntries.items.len;
            },
        }
    }
    pub fn getItem(p_self: *const openingDatabase, outcome: outcomeFlag, idx: usize) ?entry {
        const n = p_self.getSize(outcome);
        if (idx >= n) {
            return null;
        }
        switch (outcome) {
            .draw => {
                return p_self.drawnEntries.items[idx];
            },
            .whiteWin => {
                return p_self.whiteEntries.items[idx];
            },
            .blackWin => {
                return p_self.blackEntries.items[idx];
            },
            .any => {
                const ndraw = p_self.drawnEntries.items.len;
                const nwhiteW = p_self.whiteEntries.items.len;
                if (idx < ndraw) {
                    return p_self.drawnEntries.items[idx];
                }
                if (idx < (ndraw + nwhiteW)) {
                    return p_self.whiteEntries.items[idx];
                }
                return p_self.blackEntries.items[idx];
            },
        }
    }
    pub fn setSeed(p_self: *openingDatabase, seed: u64) void {
        p_self.seed = seed;
        p_self.rngIntGenerator.seed(seed);
    }
    pub fn free(p_self: *openingDatabase, alloc: std.mem.Allocator) void {
        if (!p_self.initialized) {
            return;
        }
        for (p_self.whiteEntries.items) |*str| {
            str.v.free(alloc);
        }
        for (p_self.blackEntries.items) |*str| {
            str.v.free(alloc);
        }
        for (p_self.drawnEntries.items) |*str| {
            str.v.free(alloc);
        }
        p_self.whiteEntries.deinit(alloc);
        p_self.blackEntries.deinit(alloc);
        p_self.drawnEntries.deinit(alloc);
        p_self.initialized = false;
    }
    pub fn pickOneState(p_self: *openingDatabase, flag: outcomeFlag) !boardl.boardState {
        std.debug.assert(p_self.initialized);
        var randInt = p_self.rngIntGenerator.random();
        const n = p_self.getSize(flag);
        std.debug.assert(n != 0);
        const randIdx = randInt.intRangeAtMost(usize, 0, n - 1);
        const ent = p_self.getItem(flag, randIdx) orelse return bookErr.noValidEntryErr;
        switch (ent.t) {
            .line => {
                return try chessl.algebraicLineToBoardstate(&ent.v);
            },
            .fen => {
                return try chessl.getBoardFromFen(ent.v._slice());
            },
        }
    }
    pub fn sample(p_self: *openingDatabase, alloc: std.mem.Allocator, size: usize, flag: outcomeFlag) !std.ArrayList(entry) {
        std.debug.assert(p_self.initialized);
        var drawing: std.ArrayList(entry) = undefined;
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
            .any => {
                @panic("hehe");
            },
        }
        var ret: std.ArrayList(entry) = try .initCapacity(alloc, 4);
        var randInt = p_self.rngIntGenerator.random();
        for (0..size) |_| {
            const randIdx = randInt.intRangeAtMost(usize, 0, drawing.items.len);
            try ret.append(alloc, drawing.items[randIdx]);
        }
        return ret;
    }
    pub fn printInfo(p_self: *openingDatabase) void {
        std.log.info("Number of drawn openings: {d}", .{p_self.drawnEntries.items.len});
        std.log.info("Number of white won openings: {d}", .{p_self.whiteEntries.items.len});
        std.log.info("Number of black won openings: {d}", .{p_self.blackEntries.items.len});
    }
};
pub fn readEntriesPgn(db: *openingDatabase, alloc: std.mem.Allocator, path: []const u8) !void {
    const file = try std.Io.Dir.openFile(.cwd(), mainl.getGlobalIo(), path, .{});
    defer file.close(mainl.getGlobalIo());
    var buffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
    var f_reader = file.reader(mainl.getGlobalIo(), &buffer);
    const reader = &f_reader.interface;
    const buffer_size = 1024;
    var currentEntriesType: outcomeFlag = .draw;
    var emptySpaces: u8 = 0;
    var lineBuffer: [configl.MAX_MATCH_STR_LENGTH]u8 = std.mem.zeroes([configl.MAX_MATCH_STR_LENGTH]u8);
    var lineStr = string.initFromBuffer(&lineBuffer);
    lineStr.clearRetainingCapacity();
    while (true) {
        var _buffer: [buffer_size]u8 = std.mem.zeroes([buffer_size]u8);
        var w: std.Io.Writer = .fixed(&_buffer);
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
                db.addEntry(alloc, currentEntriesType, &lineStr, .line) catch {
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
pub fn readEntriesEpd(db: *openingDatabase, alloc: std.mem.Allocator, path: []const u8) !void {
    var read: u64 = 0;
    const file = try std.Io.Dir.openFile(.cwd(), mainl.getGlobalIo(), path, .{});
    const file_size = try file.length(mainl.getGlobalIo());
    var buffer: []u8 = try alloc.alloc(u8, file_size);
    defer file.close(mainl.getGlobalIo());
    defer alloc.free(buffer);

    _ = try file.readPositionalAll(mainl.getGlobalIo(), buffer[0..buffer.len], 0);
    var itr = std.mem.tokenizeAny(u8, buffer, "\n");
    var strBuffer: [chessl.MAX_FEN_LENGTH]u8 = @splat(0);

    while (itr.next()) |line| {
        if (read % 1024 == 0) {
            std.debug.print("read {d} entries \r", .{read});
        }
        var fen: string = .initFromBuffer(&strBuffer);
        fen.copyFromSlice(line) catch unreachable;
        try db.addEntry(alloc, .any, &fen, .fen);
        read += 1;
    }
}

pub fn test_read(path: *string) !void {
    //const file = try std.fs.cwd().openFile(path._slice(), .{ .mode = .read_only });
    const file = try std.Io.Dir.openFile(.cwd(), mainl.getGlobalIo(), path._slice(), .{});
    defer file.close(mainl.getGlobalIo());
    var buffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
    var f_reader = file.reader(mainl.getGlobalIo(), &buffer);
    const reader = &f_reader.interface;
    const buffer_size = 1024;
    // in this only to depth 8, thus it should not be that big
    while (true) {
        var _buffer: [buffer_size]u8 = std.mem.zeroes([buffer_size]u8);
        var w: std.Io.Writer = .fixed(&_buffer);
        var s = string.initFromBuffer(&_buffer);
        const size = reader.streamDelimiter(&w, '\n') catch {
            break;
        };
        reader.toss(1);

        std.debug.print("Found {d} bytes in the file '{s}'\n", .{ size, s._slice()[0 .. size - 1] });
    }
}
const boardFrameStack = struct {
    item: [chessl.MAX_POSSIBLE_MOVE]boardl.boardFrame = undefined,
    len: usize = 0,
    pub fn pop(self: *boardFrameStack) boardl.boardFrame {
        std.debug.assert(self.len != 0);
        self.len -= 1;
        return self.item[self.len];
    }
    pub fn push(self: *boardFrameStack, f: boardl.boardFrame) void {
        std.debug.assert(self.len < self.item.len);
        self.item[self.len] = f;
        self.len += 1;
    }
};

pub fn test_db(path: *string, alloc: std.mem.Allocator, full: bool) !void {
    var db = try openingDatabase.init(alloc, path._slice(), 42, false);
    defer db.free(alloc);
    db.printInfo();
    var openings: std.ArrayList(entry) = .empty;
    if (full) {
        openings.deinit(alloc);
        openings = db.drawnEntries;
    } else {
        openings = try db.sample(alloc, 5, .draw);
    }

    const base = try chessl.getBoardFromFen(chessl.DEFAULT_FEN);
    var stack: boardFrameStack = .{};
    for (0..openings.items.len) |i| {
        if (openings.items[i].t == .fen) {
            _ = chessl.getBoardFromFen(openings.items[i].v._slice()) catch |err| {
                std.debug.print("error {} on fen {s} \n", .{ err, openings.items[i].v._slice() });
                @panic("err");
            };
            continue;
        }
        var tmp = base.copy();
        var algeFen = openings.items[i].v;
        const moves = try chessl._algebraicLineToIMoveMatch(algeFen._slice(), &tmp);
        tmp = base.copy();

        for (0..moves.len) |j| {
            const move = moves.moves[j];
            stack.push(tmp.frame);
            tmp.makeMove(move);
        }
        for (0..moves.len) |_| {
            _ = tmp.undoMove();
            tmp.frame = stack.pop();
        }
    }
    if (!full) {
        openings.deinit(alloc);
    }
}
pub fn test_draw(path: *string, alloc: std.mem.Allocator) !void {
    var db = try openingDatabase.init(alloc, path, 42);
    var openings_1 = try db.sample(alloc, 1, .draw);
    defer openings_1.deinit(alloc);

    var openings_2 = try db.sample(alloc, 1, .draw);
    defer openings_2.deinit(alloc);
    std.debug.print("{s}\n", .{openings_1.items[0]._slice()});
    std.debug.print("{s}\n", .{openings_2.items[0]._slice()});
}

pub fn main(alloc: std.mem.Allocator) !void {
    //
    //const path = "opening/8moves_v3.pgn";
    //const path = "../bin/CCRL-4040.[2370489].pgn";
    const path = "opening/UHO_Lichess_4852_v1.epd";
    var s = try stringl.string.initFromSlice(alloc, path);
    defer s.free(alloc);
    //hashl.zobristKeys.free(alloc);
    if (!filel.fileExists(s._slice())) {
        std.debug.print("File {s} does not exists \n", .{s._slice()});
        return;
    }
    try test_db(&s, alloc, true);

    std.log.info("[TEST]: Reading random algebraic position passed", .{});
    //try test_read(path);
    //try test_draw(path, alloc);
}
