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

const boardState = boardl.boardState;
const IMove = movel.IMove;
const scheduler = schedulerl.scheduler;
const packedBoard = boardl.packedBoard;
const viriGame = boardl.viriGame;

const stopWatch = timel.stopWatch;

pub var globalPoolDG: threadPool = .{};
const MAX_THREADS: usize = 64;

const threadPool = struct {
    threads: [MAX_THREADS]threadCtx = @splat(.{}),
    book: bookl.openingDatabase = .{},
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
    const sp: stringl.string = .initFromBuffer(path);
    defer ctx.alloc.free(path);
    var logFile = logl.logging(@sizeOf(viriGame)).init(ctx.alloc, 10000, sp, false) catch unreachable;
    var tt: hashl.Hash_table = hashl.Hash_table.init(ctx.alloc, 16, false) catch unreachable;
    defer tt.free(ctx.alloc, false);
    _threadLoop(ctx, .{ .viriFF = &logFile }, threadId, &tt);
}
pub fn _threadLoop(ctx: *threadCtx, logger: logl.boardLogFiles, threadId: usize, tt: *hashl.Hash_table) void {
    //TODO: figure out what to set the result field in viriformat as the games with random moves are not pre determined
    var gen = std.Random.DefaultPrng.init(ctx.seed);
    const rand = gen.random();
    const isFirst: bool = threadId == 0;
    var checks: usize = 0;

    // translation of the patricia datagen script
    var d: threadingl.threadData = .{};
    var info: threadingl.threadInfo = .{ .alive = true, .d = &d };
    while (!ctx.pool.schedule.interrupt) {
        tt.zero();
        d.reset();
        var state: boardState = ctx.pool.book.pickOneState(.any) catch {
            std.debug.print("err while picking \n", .{});
            continue;
        };
        for (0..4) |_| {
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
            const res = schedulerl._startSearch(&state, &info, .{ .reportProgress = false, .dataGen = true }, typel.MAX_PLY, .{ .softNodeLim = 5_000, .criticalNodeLim = 50_000, .timeMs = 100_000_000 }, tt, &d);

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

            randMove = randomMove(&state, rand);
            if (randMove.isValid()) {
                state.makeMove(randMove);
            }
            //randMove = randomMove(&state, rand);
        }
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
        threadLoop(&globalPoolDG.threads[0], seed + 0);
    }
}
pub fn main(alloc: std.mem.Allocator, sched: *schedulerl.scheduler, cmdBuffer: []const u8) !void {
    // cmdbuffer datagen[0], bookPath[1], nThreads[2]
    var gen = utilsl.splitGenerator(u8).init(cmdBuffer, ' ');
    const path = gen.get(1) orelse {
        std.debug.print("path not found in cmd\n", .{});
        return;
    };

    const n = gen.get_t(2, usize) orelse {
        std.debug.print("n thread not found in cmd\n", .{});
        return;
    };
    //std.debug.print("size of viriformat {d} align {d}\n", .{ @sizeOf(boardl.viriGame), @alignOf(boardl.viriGame) });
    globalPoolDG.book = try bookl.openingDatabase.init(alloc, path, 42, true);
    globalPoolDG.schedule = sched;
    launchThreads(alloc, n) catch {};
}
