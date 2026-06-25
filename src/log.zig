const std = @import("std");

const stringl = @import("string.zig");
const chessl = @import("chess.zig");
const utilsl = @import("utils.zig");
const filel = @import("file.zig");
const mainl = @import("main.zig");
const lockl = @import("lock.zig");
const movel = @import("move.zig");
const schedulerl = @import("search/scheduler.zig");
const hashl = @import("hashTable.zig");
const bookl = @import("book.zig");
const boardl = @import("board.zig");

const string = stringl.string;
const file_err = filel.file_err;

pub fn logging(comptime SIZE: usize) type {
    return struct {
        scratchArr: [][SIZE + 1]u8,
        insertions: usize = 0,
        totalSize: usize = 0,
        filename: stringl.string,
        l: lockl.lock = .{},
        freed: bool = false,
        const self = @This();
        pub fn init(alloc: std.mem.Allocator, totalSize: usize, filename: string) !logging(SIZE) {
            if (!filel.fileExists(filename._slice())) {
                const file = try std.Io.Dir.createFile(.cwd(), mainl.getGlobalIo(), filename._slice(), .{ .read = true });
                defer file.close(mainl.getGlobalIo());
            }
            const arr = try alloc.alloc([SIZE + 1]u8, totalSize);
            for (0..arr.len) |i| {
                arr[i] = @splat(0);
            }

            return .{ .filename = filename, .insertions = 0, .totalSize = totalSize, .scratchArr = arr };
        }
        pub fn append(p_self: *self, item: []const u8) !void {
            p_self.l.acquireLock();
            if (p_self.insertions == p_self.totalSize) {
                try p_self.commit();
            }
            if (item.len > SIZE) {
                return file_err.mem_error;
            }
            @memcpy(p_self.scratchArr[p_self.insertions][0..item.len], item);
            @memset(p_self.scratchArr[p_self.insertions][item.len..], 0);
            p_self.scratchArr[p_self.insertions][item.len] = '\n';

            p_self.insertions += 1;
            p_self.l.releaseLock();
        }
        pub fn commit(p_self: *self) !void {
            const file = try std.Io.Dir.openFile(.cwd(), mainl.getGlobalIo(), p_self.filename._slice(), .{ .mode = .write_only });
            const base = file.length(mainl.getGlobalIo()) catch unreachable;
            defer file.close(mainl.getGlobalIo());
            var inserted: u64 = 0;
            for (0..p_self.insertions) |i| {
                //TODO: fix the unreachables
                const msg = utilsl.trimStr(p_self.scratchArr[i][0..SIZE]);
                _ = file.writePositionalAll(mainl.getGlobalIo(), msg, base + inserted) catch unreachable;
                inserted += @intCast(msg.len);
            }
            p_self.insertions = 0;
        }
        pub fn write(p_self: *self, msg: []const u8) !void {
            const file = try std.Io.Dir.openFile(.cwd(), mainl.getGlobalIo(), p_self.filename._slice(), .{ .mode = .write_only });
            defer file.close(mainl.getGlobalIo());
            const base = file.length(mainl.getGlobalIo()) catch unreachable;
            _ = file.writePositionalAll(mainl.getGlobalIo(), utilsl.trimStr(msg), base) catch unreachable;
        }
        pub fn free(p_self: *self, alloc: std.mem.Allocator) !void {
            p_self.l.acquireLock();
            if (p_self.insertions != 0) {
                try p_self.commit();
            }
            alloc.free(p_self.scratchArr);
            p_self.freed = true;
            p_self.l.releaseLock();
        }
    };
}
//

const FEN_EVAL_ENTRY_SIZE: usize = chessl.MAX_FEN_LENGTH + 1 + 24;
const INPOSITION_SAVE_FREQ: u64 = 4;
const FEN_SAVE_FREQ: u64 = 2;
// [fen] [eval](5-6 size); + more just in case
pub fn parseLogFile(alloc: std.mem.Allocator, path: []const u8, logFile: *logging(FEN_EVAL_ENTRY_SIZE)) !void {
    var tokens = try filel.getTokensFromFile(alloc, path, '\n');
    defer stringl.freeArrayList_string(alloc, &tokens);
    var finalPositionFlag: bool = false;
    var startFens: usize = 0;
    for (0..tokens.items.len) |i| {
        var s = tokens.items[i];
        if (s.startsWith("//")) {
            continue;
        }
        if (s.startsWith("final positions")) {
            finalPositionFlag = true;
            startFens = i;
            continue;
        }
        if (finalPositionFlag) {
            const moves = chessl.getMoveContainerFromString(utilsl.stripStr(s._slice()), false) catch {
                continue;
            };
            incrementalMoveContainer(logFile, &moves) catch {
                continue;
            };
            const remainingTokens = tokens.items.len - startFens;
            std.debug.print("{d} / {d} \r", .{ i - startFens, remainingTokens });
        }
    }
}
pub fn parseBook(alloc: std.mem.Allocator, logFile: *logging(FEN_EVAL_ENTRY_SIZE), path: *string) !void {
    var db = try bookl.openingDatabase.init(alloc, path, 42);
    defer db.free(alloc);
    try parseAlgebraicStringList(alloc, logFile, &db.whiteEntries, 1.0, 4_000_000);
    try parseAlgebraicStringList(alloc, logFile, &db.drawnEntries, 0.5, 6_000_000);
    try parseAlgebraicStringList(alloc, logFile, &db.blackEntries, 0.0, 4_000_000);
}
pub fn parseAlgebraicStringList(alloc: std.mem.Allocator, logFile: *logging(FEN_EVAL_ENTRY_SIZE), sArr: *std.ArrayList(string), outcomes: f16, positionLimit: u64) !void {
    const base = try chessl.getBoardFromFen(chessl.DEFAULT_FEN);
    var parsed: u64 = 0;
    var realParsed: u64 = 0;

    for (0..sArr.items.len) |i| {
        if (i % 100 == 0) {
            std.debug.print("{d} / {d} outcome {d:.1}             \r", .{ i, sArr.items.len, outcomes });
        }
        if (i % FEN_SAVE_FREQ == 0) {
            continue;
        }
        if (realParsed >= positionLimit) {
            break;
        }

        var tmp = base.copy();
        const moves = chessl._algebraicLineToIMoveMatch(alloc, sArr.items[i]._slice(), &tmp) catch {
            continue;
        };
        tmp = base.copy();
        for (0..moves.len) |j| {
            const move = moves.moves[j];
            tmp.makeMove(move);
            parsed += 1;
            if (j < 5 or (parsed % INPOSITION_SAVE_FREQ == 0)) {
                continue;
            }
            realParsed += 1;
            //const info = schedulerl.startSearch(&tmp, .{ .fixedDepth = true, .reportProgress = false }, 8);
            //const score = info.currentBest.scoring;
            //if (chessl.isMate(score)) {
            //    break;
            //}
            var buffer: [FEN_EVAL_ENTRY_SIZE]u8 = @splat(0);
            const fen = tmp.get_fen();
            const written = try std.fmt.bufPrint(&buffer, "{s} [{d:.1}];", .{ utilsl.trimStr(&fen), outcomes });
            try logFile.append(written);
        }
        try logFile.commit();
    }
}

pub fn incrementalMoveContainer(logFile: *logging(FEN_EVAL_ENTRY_SIZE), moves: *const movel.matchMoveContainer) !void {
    var state = chessl.getBoardFromFen(chessl.DEFAULT_FEN) catch {
        return;
    };
    for (0..moves.len) |i| {
        const move = moves.moves[i];
        state.makeMove(move);
        const info = schedulerl.startSearch(&state, .{ .fixedDepth = true, .reportProgress = false }, 10);
        const score = info.currentBest.scoring;
        //const score = -35;
        var buffer: [FEN_EVAL_ENTRY_SIZE]u8 = @splat(0);
        const fen = state.get_fen();
        const written = try std.fmt.bufPrint(&buffer, "{s} {d};", .{ utilsl.trimStr(&fen), score });
        try logFile.append(written);
    }
    try logFile.commit();
}
pub fn parsingLog(alloc: std.mem.Allocator) !void {
    var savePath: string = try string.initFromSlice(alloc, "out/csv/res_1781964187051005583.book");
    defer savePath.free(alloc);
    var logFile = try logging(FEN_EVAL_ENTRY_SIZE).init(alloc, 100, savePath);
    const name: []const u8 = "out/logs/evaluate/match_logs_1781964187051005583.txt";
    try parseLogFile(alloc, name, &logFile);
    try logFile.free(alloc);
}
pub fn parsingBook(alloc: std.mem.Allocator) !void {
    var savePath: string = try string.initFromSlice(alloc, "out/csv/CCRL-4040.[2370489]_2.book");
    var name: string = try string.initFromSlice(alloc, "../bin/CCRL-4040.[2370489].pgn");
    defer name.free(alloc);
    defer savePath.free(alloc);

    var logFile = try logging(FEN_EVAL_ENTRY_SIZE).init(alloc, 1_000_000, savePath);
    try parseBook(alloc, &logFile, &name);
    try logFile.free(alloc);
}
pub fn main(alloc: std.mem.Allocator) !void {
    mainl.initAll(alloc, false);
    hashl._initOrReallocHashTable(alloc, 25, false);
    defer hashl.hashTable.free(alloc, false);
    try parsingBook(alloc);
}
