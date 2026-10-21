const std = @import("std");

const logl = @import("log.zig");
const schedulerl = @import("scheduler.zig");
const threadingl = @import("threading.zig");
const bookl = @import("book.zig");
const utilsl = @import("utils.zig");
const mainl = @import("main.zig");
const boardl = @import("board.zig");
const movel = @import("move.zig");
const moveGenl = @import("move_generation.zig");
const typel = @import("type.zig");
const timel = @import("time.zig");
const stringl = @import("string.zig");
const chessl = @import("chess.zig");
const hashl = @import("hashTable.zig");
const filel = @import("file.zig");
const configl = @import("config.zig");

const boardState = boardl.boardState;
const IMove = movel.IMove;
const scheduler = schedulerl.scheduler;
const packedBoard = boardl.packedBoard;
const viriGame = boardl.viriGame;
const e_fileFormat = logl.e_fileFormat;
const string = stringl.string;
const scoreType = typel.scoreType;

const debug_err = chessl.debug_err;

const stopWatch = timel.stopWatch;

pub var globalPoolDG: threadPool = .{};
const MAX_THREADS: usize = 64;
const maxViriLength: usize = @sizeOf(packedBoard) + movel.MAX_MATCH_LENGTH * @sizeOf(boardl.viriPackedMove) + @sizeOf(u32);
const viriSize: usize = @sizeOf(boardl.viriGame);
const bulletSize: usize = logl.FEN_EVAL_ENTRY_SIZE;

const threadPool = struct {
    threads: [MAX_THREADS]threadCtx = @splat(.{}),
    book: ?bookl.openingDatabase = null,
    schedule: *scheduler = undefined,
    running: bool = false,
    nThreads: usize = 0,
    startSw: stopWatch = .{},
    pub fn printProgress(self: *const threadPool) void {
        var allP: i64 = 0;
        var nThreads: usize = 0;
        for (0..self.nThreads) |i| {
            const n = self.threads[i].processedPositions;
            allP += n;
            nThreads += @intFromBool(n != 0);
        }
        const pps = @divFloor(allP, self.startSw.timeSinceStartSec() + 1);
        std.debug.print("Time elapsed {d}s position processed {d} pps {d} running threads {d}\n", .{ self.startSw.timeSinceStartSec(), allP, pps, nThreads });
    }
    pub fn killAndWait(self: *threadPool) void {
        if (!self.running) {
            return;
        }
        for (0..self.nThreads) |i| {
            self.threads[i].alive = false;
            std.Thread.join(self.threads[i].handle);
        }
    }
};

const threadCtx = struct {
    alloc: std.mem.Allocator = undefined,
    pool: *threadPool = undefined,
    seed: u64 = 42,
    handle: std.Thread = undefined,
    alive: bool = false,
    processedPositions: i64 = 0,

    pub fn init(alloc: std.mem.Allocator, seed: u64, pool: *threadPool) threadCtx {
        return .{ .alloc = alloc, .pool = pool, .seed = seed };
    }
};
pub fn threadLoop(ctx: *threadCtx, threadId: usize) void {
    ctx.alive = true;
    defer ctx.alive = false;
    const path = std.fmt.allocPrint(ctx.alloc, "out/virif/output_{d}.viribinpack", .{threadId}) catch unreachable;
    const sp: string = .initFromBuffer(path);
    defer ctx.alloc.free(path);
    var logFile = logl.logging(@sizeOf(viriGame)).init(ctx.alloc, MAX_ELEM_LOGGING, sp, false) catch unreachable;
    var tt: hashl.Hash_table = hashl.Hash_table.init(ctx.alloc, 16, false) catch unreachable;
    defer tt.free(ctx.alloc, false);
    _threadLoop(ctx, .{ .viriFF = &logFile }, threadId, &tt);
}
pub fn _threadLoop(ctx: *threadCtx, logger: logl.fileFormatLogger, threadId: usize, tt: *hashl.Hash_table) void {
    //TODO: figure out what to set the result field in viriformat as the games with random moves are not pre determined
    var gen = std.Random.DefaultPrng.init(ctx.seed);
    const rand = gen.random();
    const isFirst: bool = threadId == 0;
    var checks: usize = 0;

    // translation of the patricia datagen script
    var d: threadingl.threadData = .{};
    var info: threadingl.threadInfo = .{ .alive = true, .d = &d };
    var state: boardState = .{};
    while (!ctx.pool.schedule.interrupt) {
        tt.zero();
        d.reset();

        if (ctx.pool.book == null) {
            state = chessl.getBoardFromFen(chessl.DEFAULT_FEN) catch unreachable;
        } else {
            state = ctx.pool.book.?.pickOneState(.any) catch {
                std.debug.print("err while picking \n", .{});
                continue;
            };
        }
        const startRand: usize = 6 + rand.intRangeAtMost(usize, 0, 4);
        for (0..startRand) |_| {
            const randMove = randomMove(&state, rand);
            if (randMove.isValid()) {
                state.makeMove(randMove);
            } else {
                break;
            }
        }

        var boardBuffer: [movel.MAX_MATCH_LENGTH]viriGame = undefined;
        var nboard: usize = 0;
        var result: u8 = 1; // 0 black, 1 draw, 2 win
        var randMove = randomMove(&state, rand);
        while (randMove.isValid() and !state.isStaleMate() and !ctx.pool.schedule.interrupt) {
            const res = schedulerl._startSearch(&state, &info, .{ .reportProgress = false, .dataGen = true }, typel.MAX_PLY, .{ .softNodeLim = 5_000, .criticalNodeLim = 5_000, .timeMs = 100_000_000 }, tt, &d);

            const score = if (state.whiteToMove()) res.score else -res.score;
            if (@abs(score) > 1000) {
                if (score > 0) {
                    result = 2;
                } else {
                    result = 0;
                }
                break;
            }

            if (state.b.turnCount > 200) {
                if (score > 200) {
                    result = 2;
                } else if (score < 200) {
                    result = 0;
                }
                break;
            }
            const bestMove = res.move;
            if (!(bestMove.isCapture() or state.isChecked())) {
                // save
                var pB: packedBoard = .init(&state);
                pB.score = @intCast(score);
                pB.outcome = 1;
                const pBB = pB.toBoard();
                if (!(state.equal(&pBB))) {
                    // panic
                    chessl.print_boardstate(&state);
                    chessl.print_boardstate(&pBB);

                    @panic("decode error");
                }

                const game: viriGame = .{ .b = pB, .bestMove = .{ .move = .init(res.move), .score = @intCast(score) } };
                boardBuffer[nboard] = game;
                nboard += 1;
                if (game.bestMove.move.m_move == 0) {
                    std.debug.print("current rand move {s} best move {s} depth searched {d} info nodes {d} info time {d} us score {d}\n", .{ randMove.getStr(), bestMove.getStr(), res.depth, info.searchStat.n_nodeExplored, info.stopWatch.timeSinceStartUs(), res.score });
                    chessl.print_boardstate(&state);
                    @panic("best move is zero");
                }
                ctx.processedPositions += 1;
                checks += 1;
                if (isFirst and checks >= 2048) {
                    checks = 0;
                    globalPoolDG.printProgress();
                }
            }

            if (bestMove.isValid()) {
                state.makeMove(bestMove);
            } else {
                std.debug.print("[PANIC] datagenLoop weird best move invalid but moves available move in position\n", .{});
                chessl.print_boardstate(&state);
                break;
            }
            randMove = randomMove(&state, rand);
        }
        const prev = logger.viriFF.scratchArr[0];
        std.Random.shuffle(rand, @TypeOf(logger.viriFF.scratchArr[0]), logger.viriFF.scratchArr[0..logger.viriFF.insertions]);
        std.debug.assert(!std.mem.eql(u8, &logger.viriFF.scratchArr[0], &prev));

        for (0..nboard) |i| {
            boardBuffer[i].b.outcome = result;
            const b = logl.transmutePtr(viriGame, &boardBuffer[i]);
            logger.viriFF.append(b) catch {};
        }
    }
    logger.viriFF.commit() catch {};
    std.debug.print("exiting datagen on thread {d}\n", .{threadId});
}
pub fn randomMove(p_state: *const boardState, rand: std.Random) IMove {
    const fmoves = moveGenl.generateLegalMoves(p_state);
    if (fmoves.len == 0) {
        // unsure if fmoves.moves[0] == non valid for next
        return .{};
    }
    if (fmoves.len == 1) {
        return fmoves.moves[0];
    }
    const randIdx = rand.intRangeAtMost(u8, 0, fmoves.len - 1);
    return fmoves.moves[randIdx];
}
pub fn launchThreads(alloc: std.mem.Allocator, n: usize) !void {
    globalPoolDG.running = true;
    globalPoolDG.threads = @splat(.{});
    globalPoolDG.nThreads = n;
    globalPoolDG.startSw = .init(true);
    const seed: u64 = @intCast(globalPoolDG.startSw.startTimeUs);
    if (n != 1) {
        for (0..n) |i| {
            globalPoolDG.threads[i] = .init(alloc, seed + i, &globalPoolDG);
            globalPoolDG.threads[i].handle = try std.Thread.spawn(.{}, threadLoop, .{ &globalPoolDG.threads[i], i });
        }
    } else {
        globalPoolDG.threads[0] = .init(alloc, 0, &globalPoolDG);
        threadLoop(&globalPoolDG.threads[0], 0);
    }
}
//pub fn loggerFromFF(alloc :std.mem.Allocator, ff: e_fileFormat)
pub fn strTofileF(str: []const u8) !e_fileFormat {
    if (utilsl.startsWith(str, "bullet", .ignoreCase)) {
        return .bulletFF;
    }
    if (utilsl.startsWith(str, "viribin", .ignoreCase)) {
        return .viriFF;
    }
    return error.args;
}
const MAX_ELEM_LOGGING: usize = 32_000;
pub fn getLogFromFF(alloc: std.mem.Allocator, ff: e_fileFormat, filename: string) !logl.logging1D {
    switch (ff) {
        .bulletFF => {
            return try .init(alloc, bulletSize, MAX_ELEM_LOGGING, filename, false, true);
        },
        .viriFF => {
            return try .init(alloc, viriSize, MAX_ELEM_LOGGING, filename, false, true);
        },
    }
    return debug_err.argErr;
}
pub fn convert(alloc: std.mem.Allocator, cmdIter: *std.process.Args.Iterator) !void {
    // [inputType] [path] [outputType] [outputPath]
    //std.debug.print("cmd buffer {s}\n", .{cmdBuffer});
    //var gen = utilsl.splitGenerator(u8).init(cmdBuffer, ' ');
    const inputType = try strTofileF(cmdIter.next() orelse return debug_err.argErr);
    const inputPath = cmdIter.next() orelse return debug_err.argErr;
    const outputType = try strTofileF(cmdIter.next() orelse return debug_err.argErr);
    const outputPath = cmdIter.next() orelse return debug_err.argErr;
    const savePath: string = .initViewFromSlice(outputPath);
    var log = try getLogFromFF(alloc, outputType, savePath);
    switch (inputType) {
        .bulletFF => try processBulletFile(alloc, inputPath, outputType, &log),
        .viriFF => try processViribinFile(alloc, inputPath, outputType, &log),
    }
    try log.free(alloc);
}
fn processViribinFile(alloc: std.mem.Allocator, path: []const u8, ff: e_fileFormat, log: *logl.logging1D) !void {
    _ = alloc;
    const file = try std.Io.Dir.openFile(.cwd(), mainl.getGlobalIo(), path, .{});
    defer file.close(mainl.getGlobalIo());
    var reader_buffer: [viriSize * 4096]u8 = undefined;
    var reader = file.reader(mainl.getGlobalIo(), &reader_buffer);
    var interface = &reader.interface;
    var interface_buffer: [viriSize * 4096]u8 = undefined;
    var read: i64 = 0;
    var sw: stopWatch = .init(true);
    while (true) {
        const readbytes = interface.readSliceShort(interface_buffer[0..]) catch break;
        std.debug.assert((readbytes % viriSize == 0));
        const entries: []viriGame = @ptrCast(interface_buffer[0..readbytes]);
        if (readbytes == 0) {
            break;
        }
        for (entries) |ent| {
            if (@mod(read, 1_000_000) == 0) {
                std.debug.print("read {d} entries eps {d}\r", .{ read, @divFloor(read, sw.timeSinceStartMs()) * 1000 });
            }
            read += 1;
            const b = ent.b.toBoard();
            switch (ff) {
                .viriFF => unreachable,
                .bulletFF => {
                    // [FEN] | [score] | [outcome]
                    var bulletBuffer: [bulletSize]u8 = undefined;
                    const fen = b.get_fen();
                    //const move = ent.bestMove.move.toIMove().getStr();
                    //const new = try std.fmt.bufPrint(&bulletBuffer, "{s} | {d} | {d} {s}\n", .{ utilsl.trimStr(&fen), ent.b.score, @as(f64, @floatFromInt(ent.b.outcome)) / 2.0, utilsl.trimStr(&move) });
                    const new = try std.fmt.bufPrint(&bulletBuffer, "{s} | {d} | {d}\n", .{ utilsl.trimStr(&fen), ent.b.score, @as(f64, @floatFromInt(ent.b.outcome)) / 2.0 });
                    try log.append(utilsl.trimStr(new[0..]));
                },
            }
        }
    }
    try log.commit();
}
fn processBulletFile(alloc: std.mem.Allocator, path: []const u8, ff: e_fileFormat, log: *logl.logging1D) !void {
    var randgen = std.Random.DefaultPrng.init(configl.SEED);
    const rand = randgen.random();

    _ = alloc;
    const filename = string.initViewFromSlice(path);
    var fr = try filel.fileReader(4 * bulletSize).init(filename, mainl.getGlobalIo());
    defer fr.close(mainl.getGlobalIo());

    var read: i64 = 0;
    var sw: stopWatch = .init(true);
    while (fr.nextLine()) |line| {
        //std.debug.print("line '{s}' len {d} bulletsize {d}\n", .{ line, line.len, bulletSize });
        var gen = utilsl.splitGenerator(u8).init(line, '|');
        std.debug.assert(gen.len() >= 3);
        const fen = gen.get(0).?;
        const score = gen.get_t(1, scoreType).?;
        const outcome = gen.get_t(2, f32).?;
        const b = chessl.getBoardFromFen(fen) catch continue;
        if (@mod(read, 1_000_000) == 0) {
            std.debug.print("read {d} entries eps {d}\r", .{ read, @divFloor(read, sw.timeSinceStartMs()) * 1000 });
        }
        read += 1;
        switch (ff) {
            .bulletFF => unreachable,
            .viriFF => {
                var pB: packedBoard = .init(&b);
                pB.score = @intCast(score);
                pB.outcome = @intFromFloat(outcome * 2);
                //var game: viriEmptyGame = .{ .b = pB };
                //const pbb = logl.transmutePtr(viriEmptyGame, &game);
                //TODO: for now putting a random move in the entry because no bestMove in bullet format
                var game: viriGame = .{ .b = pB, .bestMove = .{ .move = .init(randomMove(&b, rand)), .score = @intCast(score) } };
                const pbb = logl.transmutePtr(viriGame, &game);
                log.append(pbb) catch {};
            },
        }
    }
    try log.commit();
}
pub const viriEmptyGame = extern struct {
    b: packedBoard align(1),
    pad: u32 align(1) = 0,
};
pub fn main(alloc: std.mem.Allocator, sched: *schedulerl.scheduler, cmdBuffer: []const u8) !void {
    // cmdbuffer datagen[0] nThreads[1] bookPath[2]
    var gen = utilsl.splitGenerator(u8).init(cmdBuffer, ' ');

    const n = gen.get_t(1, usize) orelse {
        std.debug.print("n thread not found in cmd\n", .{});
        return;
    };

    const path = gen.get(2);
    if (path == null) {
        globalPoolDG.book = null;
    } else {
        globalPoolDG.book = try bookl.openingDatabase.init(alloc, path.?, 42, true);
    }
    globalPoolDG.schedule = sched;
    launchThreads(alloc, n) catch |err| {
        std.debug.print("caught err {} while launching dategen\n", .{err});
    };
}
