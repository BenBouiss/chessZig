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
const moveGenl = @import("move_generation.zig");

const string = stringl.string;
const file_err = filel.file_err;

pub const fileFormat = enum { bulletFF, viriFF };
const boardLogFiles = union(fileFormat) { bulletFF: *logging(FEN_EVAL_ENTRY_SIZE), viriFF: *logging(@sizeOf(boardl.viriGame)) };

pub fn logging(comptime SIZE: usize) type {
    return struct {
        scratchArr: [][SIZE + 1]u8,
        insertions: usize = 0,
        totalSize: usize = 0,
        filename: stringl.string,
        l: lockl.lock = .{},
        freed: bool = false,
        textMode: bool = true,
        const self = @This();
        pub fn init(alloc: std.mem.Allocator, totalSize: usize, filename: string, textMode: bool) !logging(SIZE) {
            if (!filel.fileExists(filename._slice())) {
                const file = try std.Io.Dir.createFile(.cwd(), mainl.getGlobalIo(), filename._slice(), .{ .read = true });
                defer file.close(mainl.getGlobalIo());
            }
            const arr = try alloc.alloc([SIZE + 1]u8, totalSize);
            for (0..arr.len) |i| {
                arr[i] = @splat(0);
            }

            return .{ .filename = filename, .insertions = 0, .totalSize = totalSize, .scratchArr = arr, .textMode = textMode };
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
            if (p_self.textMode) {
                @memset(p_self.scratchArr[p_self.insertions][item.len..], 0);
                p_self.scratchArr[p_self.insertions][item.len] = '\n';
            }

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
                const msg = if (p_self.textMode) utilsl.trimStr(p_self.scratchArr[i][0..SIZE]) else (p_self.scratchArr[i][0..SIZE]);
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
pub fn parseLogFile(alloc: std.mem.Allocator, path: []const u8, logFile: boardLogFiles, outFile: fileFormat) !void {
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
            var ret = try chessl.getBoardFromFen(chessl.DEFAULT_FEN);
            try chessl.applyUciMoves(&ret, utilsl.stripStr(s._slice()), false);
            const moves = ret.moveHistory;
            switch (outFile) {
                .bulletFF => {
                    str_incrementalMoveContainer(logFile.bulletFF, &moves) catch {
                        continue;
                    };
                },
                .viriFF => {
                    packed_incrementalMoveContainer(logFile.viriFF, &moves) catch {
                        continue;
                    };
                },
            }

            const remainingTokens = tokens.items.len - startFens;
            _ = remainingTokens;
            //std.debug.print("{d} / {d} \r", .{ i - startFens, remainingTokens });
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
pub fn packed_incrementalMoveContainer(logFile: *logging(@sizeOf(boardl.viriGame)), moves: *const movel.matchMoveContainer) !void {
    var state = chessl.getBoardFromFen(chessl.DEFAULT_FEN) catch {
        return;
    };
    var tmp = state.copy();
    for (0..moves.len) |i| {
        const move = moves.moves[i];
        tmp.makeMove(move);
    }
    const fmoves = moveGenl.generateLegalMoves(&tmp);
    var outcome: u8 = 1;
    if (fmoves.len == 0) {
        if (tmp.isChecked()) {
            // 0 is black win 1 is white
            outcome = if (tmp.whiteToMove()) 0 else 2;
        }
    }

    for (0..moves.len) |i| {
        const move = moves.moves[i];
        state.makeMove(move);
        const info = schedulerl.startSearch(&state, .{ .fixedDepth = true, .reportProgress = false }, 8);
        if (!info.currentBest.move.isValid()) {
            break;
        }
        const score = if (state.whiteToMove()) info.currentBest.scoring else (-info.currentBest.scoring);
        var pB: boardl.packedBoard = .init(&state);
        pB.score = @intCast(score);
        pB.outcome = outcome;
        var game: boardl.viriGame = .{ .b = pB, .bestMove = .{ .move = .init(info.currentBest.move), .score = @intCast(score) } };

        const b = transmutePtr(boardl.viriGame, &game);
        try logFile.append(b);
    }
    try logFile.commit();
}

pub fn str_incrementalMoveContainer(logFile: *logging(FEN_EVAL_ENTRY_SIZE), moves: *const movel.matchMoveContainer) !void {
    var state = chessl.getBoardFromFen(chessl.DEFAULT_FEN) catch {
        return;
    };

    var tmp = state.copy();
    for (0..moves.len) |i| {
        const move = moves.moves[i];
        tmp.makeMove(move);
    }
    const fmoves = moveGenl.generateLegalMoves(&tmp);
    var outcome: u8 = 1;
    if (fmoves.len == 0) {
        if (tmp.isChecked()) {
            // 0 is black win 1 is white
            outcome = if (tmp.whiteToMove()) 0 else 1;
        }
    }
    for (0..moves.len) |i| {
        const move = moves.moves[i];
        state.makeMove(move);
        const info = schedulerl.startSearch(&state, .{ .fixedDepth = true, .reportProgress = false }, 10);
        const score = info.currentBest.scoring;
        //const score = -35;
        var buffer: [FEN_EVAL_ENTRY_SIZE]u8 = @splat(0);
        const fen = state.get_fen();
        const written = try std.fmt.bufPrint(&buffer, "{s} {d} {d};", .{ utilsl.trimStr(&fen), score, outcome });
        try logFile.append(written);
    }
    try logFile.commit();
}
pub fn parsingLog(alloc: std.mem.Allocator) !void {
    var savePath: string = try string.initFromSlice(alloc, "out/csv/res_1781964187051005583.book");
    defer savePath.free(alloc);
    var logFile = try logging(FEN_EVAL_ENTRY_SIZE).init(alloc, 100, savePath, true);
    const name: []const u8 = "out/logs/evaluate/match_logs_1781964187051005583.txt";
    try parseLogFile(alloc, name, .{ .bulletFF = &logFile }, .bulletFF);
    try logFile.free(alloc);
}
const pathList = [_][]const u8{
    "out/logs/evaluate/match_logs_1781964187051005583.txt",
    "out/logs/evaluate/match_logs_1781964552331028244.txt",
    "out/logs/evaluate/match_logs_1781968465094705791.txt",
    "out/logs/evaluate/match_logs_1781968917402516457.txt",
    "out/logs/evaluate/match_logs_1781970900418177401.txt",
    "out/logs/evaluate/match_logs_1781971785919973390.txt",
    "out/logs/evaluate/match_logs_1781973423419658123.txt",
    "out/logs/evaluate/match_logs_1782043180403209278.txt",
    "out/logs/evaluate/match_logs_1782044146239931455.txt",
    "out/logs/evaluate/match_logs_1782131914819839091.txt",
    "out/logs/evaluate/match_logs_1782141418082879038.txt",
    "out/logs/evaluate/match_logs_1782405524208254193.txt",
    "out/logs/evaluate/match_logs_1782406643139774633.txt",
    "out/logs/evaluate/match_logs_1782430460710032450.txt",
    "out/logs/evaluate/match_logs_1782430660195329632.txt",
    "out/logs/evaluate/match_logs_1782435504982777199.txt",
};
const pathList2 = [_][]const u8{
    "out/logs/evaluate/match_logs_1781353198416158269.txt",
    "out/logs/evaluate/match_logs_1781351635371071120.txt",
    "out/logs/evaluate/match_logs_1781346055312055793.txt",
    "out/logs/evaluate/match_logs_1781344849477324558.txt",
    "out/logs/evaluate/match_logs_1781281151688529592.txt",
    "out/logs/evaluate/match_logs_1781280473320063936.txt",
    "out/logs/evaluate/match_logs_1781279115099938488.txt",
    "out/logs/evaluate/match_logs_1781276811167693826.txt",
    "out/logs/evaluate/match_logs_1781276025657219016.txt",
    "out/logs/evaluate/match_logs_1781271996810438773.txt",
    "out/logs/evaluate/match_logs_1781268094048348107.txt",
    "out/logs/evaluate/match_logs_1781267427379961648.txt",
    "out/logs/evaluate/match_logs_1781209883757823965.txt",
    "out/logs/evaluate/match_logs_1781208843495162472.txt",
    "out/logs/evaluate/match_logs_1781194883474155627.txt",
    "out/logs/evaluate/match_logs_1781193953799669575.txt",
    "out/logs/evaluate/match_logs_1781192656664084777.txt",
    "out/logs/evaluate/match_logs_1781191638985552301.txt",
    "out/logs/evaluate/match_logs_1781190215074483457.txt",
    "out/logs/evaluate/match_logs_1781189345817040602.txt",
    "out/logs/evaluate/match_logs_1781391918435393167.txt",
    "out/logs/evaluate/match_logs_1781391323617428069.txt",
    "out/logs/evaluate/match_logs_1781378755452319509.txt",
    "out/logs/evaluate/match_logs_1781371810551117668.txt",
    "out/logs/evaluate/match_logs_1781367065833079142.txt",
    "out/logs/evaluate/match_logs_1781365974580178037.txt",
    "out/logs/evaluate/match_logs_1781365156761167285.txt",
    "out/logs/evaluate/match_logs_1781364253130528610.txt",
    "out/logs/evaluate/match_logs_1781362473127927794.txt",
    "out/logs/evaluate/match_logs_1781360071059051179.txt",
    "out/logs/evaluate/match_logs_1781359583935583359.txt",
    "out/logs/evaluate/match_logs_1781355195356944944.txt",
};

const pathList3 = [_][]const u8{
    "out/logs/evaluate/match_logs_1781176446622977552.txt",
    "out/logs/evaluate/match_logs_1781175536675355981.txt",
    "out/logs/evaluate/match_logs_1781172427547442820.txt",
    "out/logs/evaluate/match_logs_1781171495856065529.txt",
    "out/logs/evaluate/match_logs_1781168374237557971.txt",
    "out/logs/evaluate/match_logs_1781124452098329048.txt",
    "out/logs/evaluate/match_logs_1781123625731901073.txt",
    "out/logs/evaluate/match_logs_1781120408901792508.txt",
    "out/logs/evaluate/match_logs_1781103079528198693.txt",
    "out/logs/evaluate/match_logs_1781102157278515985.txt",
    "out/logs/evaluate/match_logs_1781353198416158269.txt",
    "out/logs/evaluate/match_logs_1781351635371071120.txt",
    "out/logs/evaluate/match_logs_1781346055312055793.txt",
    "out/logs/evaluate/match_logs_1781344849477324558.txt",
    "out/logs/evaluate/match_logs_1781281151688529592.txt",
    "out/logs/evaluate/match_logs_1781280473320063936.txt",
    "out/logs/evaluate/match_logs_1781279115099938488.txt",
    "out/logs/evaluate/match_logs_1781276811167693826.txt",
    "out/logs/evaluate/match_logs_1781276025657219016.txt",
    "out/logs/evaluate/match_logs_1781271996810438773.txt",
    "out/logs/evaluate/match_logs_1781268094048348107.txt",
    "out/logs/evaluate/match_logs_1781267427379961648.txt",
    "out/logs/evaluate/match_logs_1781209883757823965.txt",
    "out/logs/evaluate/match_logs_1781208843495162472.txt",
    "out/logs/evaluate/match_logs_1781194883474155627.txt",
    "out/logs/evaluate/match_logs_1781193953799669575.txt",
    "out/logs/evaluate/match_logs_1781192656664084777.txt",
    "out/logs/evaluate/match_logs_1781191638985552301.txt",
    "out/logs/evaluate/match_logs_1781190215074483457.txt",
    "out/logs/evaluate/match_logs_1781189345817040602.txt",
    "out/logs/evaluate/match_logs_1781181343715003644.txt",
    "out/logs/evaluate/match_logs_1781177248639341533.txt",
};
pub fn parsingLog_binF(alloc: std.mem.Allocator, nThreads: usize) !void {
    const batchSize = @divFloor(pathList3.len, nThreads);
    var threads: std.ArrayList(std.Thread) = .empty;
    for (0..nThreads) |i| {
        const thread = try std.Thread.spawn(.{}, thread_parsingLog_binF, .{ alloc, pathList3[i * batchSize .. (i + 1) * batchSize], i, 639341533 });
        try threads.append(alloc, thread);
    }
    for (0..threads.items.len) |i| {
        threads.items[i].join();
    }
}
pub fn thread_parsingLog_binF(alloc: std.mem.Allocator, fileBatch: []const []const u8, threadIdx: usize, uid: usize) !void {
    const saveName = try std.fmt.allocPrint(alloc, "out/bin/data_thread_{d}_{d}.viribinpack", .{ threadIdx, uid });
    var savePath: string = string.initFromBuffer(saveName);
    defer savePath.free(alloc);
    var logFile = try logging(@sizeOf(boardl.viriGame)).init(alloc, 10000, savePath, false);
    for (0..fileBatch.len) |i| {
        std.debug.print("Thread {d} starting file {s}\n", .{ threadIdx, fileBatch[i] });
        try parseLogFile(alloc, fileBatch[i], .{ .viriFF = &logFile }, .viriFF);
    }
    try logFile.free(alloc);
}
pub fn parsingBook(alloc: std.mem.Allocator) !void {
    var savePath: string = try string.initFromSlice(alloc, "out/csv/CCRL-4040.[2370489]_2.book");
    var name: string = try string.initFromSlice(alloc, "../bin/CCRL-4040.[2370489].pgn");
    defer name.free(alloc);
    defer savePath.free(alloc);

    var logFile = try logging(FEN_EVAL_ENTRY_SIZE).init(alloc, 1_000_000, savePath, true);
    try parseBook(alloc, &logFile, &name);
    try logFile.free(alloc);
}
// https://thebitstream.me/posts/how-to-serialize-in-zig/
pub fn transmuteSlice(comptime T: type, x: []T) []u8 {
    const num_bytes = @sizeOf(T) * x.len;
    const x0: [*]u8 = @ptrCast(x);
    const x1: []u8 = x0[0..num_bytes];
    return x1;
}

// for struct
pub fn transmutePtr(comptime T: type, x: *T) []u8 {
    const num_bytes = @sizeOf(T);
    const x0: [*]u8 = @ptrCast(x);
    const x1: []u8 = x0[0..num_bytes];
    return x1;
}

pub fn test_viriBin(alloc: std.mem.Allocator) !void {
    var savePath: string = try string.initFromSlice(alloc, "out/data.bin");
    defer savePath.free(alloc);
    const outPath = "out/d.bin";

    var logFile = try logging(@sizeOf(boardl.viriGame)).init(alloc, 10, savePath, false);
    const file = try std.Io.Dir.createFile(.cwd(), mainl.getGlobalIo(), outPath, .{ .read = true });
    defer file.close(mainl.getGlobalIo());
    var state = chessl.getBoardFromFen(chessl.DEFAULT_FEN) catch {
        return;
    };
    const info = schedulerl.startSearch(&state, .{ .fixedDepth = true, .reportProgress = false }, 10);
    var pB: boardl.packedBoard = .init(&state);
    pB.outcome = 2;
    _ = info;
    //pB.score = @intCast(info.currentBest.scoring);
    var b: boardl.viriGame = .{ .b = pB };
    const bin = transmutePtr(boardl.viriGame, &b);
    _ = try file.writePositionalAll(mainl.getGlobalIo(), bin, 0);
    try logFile.append(bin);
    try logFile.append(bin);
    try logFile.append(bin);
    try logFile.append(bin);
    std.debug.print("[DEBUG] len of b {d} size of struct {d}, logfile {} \n", .{ bin.len, @sizeOf(boardl.viriGame), logFile.scratchArr[0].len });

    try logFile.commit();
    try logFile.free(alloc);
}
pub fn main(alloc: std.mem.Allocator) !void {
    mainl.initAll(alloc, false);
    hashl._initOrReallocHashTable(alloc, 25, false);
    defer hashl.hashTable.free(alloc, false);
    try parsingLog_binF(alloc, 4);
    //try parsingBook(alloc);
    //try test_viriBin(alloc);
}
