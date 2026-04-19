const std = @import("std");

const magicl = @import("magic.zig");
const moveTablel = @import("moveTables.zig");
const hashl = @import("hashTable.zig");
const enginel = @import("engine.zig");
const benchl = @import("benchmark.zig");
const speedTestl = @import("speedTest.zig");
const configl = @import("config.zig");
const chessl = @import("chess.zig");
const evalEngl = @import("evaluateEngine.zig");
const bookl = @import("book.zig");
const stringl = @import("string.zig");
const filel = @import("file.zig");
const perftl = @import("search/perft.zig");
const heuristicl = @import("heuristic.zig");
const timel = @import("time.zig");

const build_options = @import("build_options");
const useDebug = build_options.useDebug;

const schedulerl = @import("search/scheduler.zig");
const moveDecisionExt = schedulerl.moveDecisionExt;

pub fn initAll(alloc: std.mem.Allocator, verbose: bool) void {
    magicl._initMagic(&magicl.magicTable, verbose);

    hashl._initZobrist(alloc, 42);
    //hashl._initOrReallocHashTable(GLOBAL_ALLOC, 2000);

    moveTablel._initTables(verbose);
    if (comptime useDebug) {
        std.debug.print("[PRE] Building using the useDebug flag\n", .{});
    }
}

fn initEngine(alloc: std.mem.Allocator) !enginel.engine {
    var engine: enginel.engine = try enginel.engine.init(alloc);
    engine.executeBuffer("uci");
    //engine.executeBuffer("debug on");
    engine.executeBuffer("isready");
    return engine;
}
fn waitOnEngine(eng: *enginel.engine) void {
    std.Thread.sleep(std.time.ns_per_s);
    while (eng.searcher.searching) {
        std.Thread.sleep(configl.INFO_TICKRATE_NS);
    }
}
inline fn getDecision(eng: *enginel.engine) moveDecisionExt {
    return eng.searcher.schedul.finalChoice;
}

const fenListMateOne = [_][]const u8{
    "position fen Q7/8/8/8/5K1k/8/8/8 w - - 0 0",
    "position fen q7/8/8/8/5k1K/8/8/8 b - - 0 0",
};

pub fn test_decision(alloc: std.mem.Alloator) !void {
    var eng = try initEngine(alloc);
    defer eng.free();
    for (0..fenListMateOne.len) |i| {
        const fenCmd = fenListMateOne[i];
        eng.executeBuffer(fenCmd);
        eng.executeBuffer("go depth 4");
        waitOnEngine(&eng);
        const dec = getDecision(&eng);
        try std.testing.expect(dec.scoring > 8000);
    }
    std.debug.print("[TEST]: Mate in one test passed\n", .{});
}
pub fn test_speed(alloc: std.mem.Alloator) !void {
    var eng = try initEngine(alloc);
    defer eng.free();
    //eng.executeBuffer("setoption name useQuiescence value true");
    //eng.executeBuffer("position fen r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    eng.executeBuffer("position fen r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1 ");
    //eng.executeBuffer("setoption name useNullPruning value true");
    eng.executeBuffer("go depth 7");
    waitOnEngine(&eng);
}
pub fn test_bug(alloc: std.mem.Alloator) !void {
    initAll(alloc, false);
    var eng = try initEngine(alloc);
    defer eng.free();
    eng.executeBuffer("setoption name UCI_elo value 3000");
    eng.executeBuffer("setoption name fixedDepth value true");
    eng.executeBuffer("setoption name useHash value false");
    //eng.executeBuffer("setoption name useQuiescence value true");
    eng.executeBuffer("ucinewgame");
    eng.executeBuffer("position fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 0");
    eng.executeBuffer("isready");
    eng.executeBuffer("go wtime 300000 btime 300000 winc 5000 binc 5000");
    waitOnEngine(&eng);
}
pub fn test_perft(alloc: std.mem.Alloator) !void {
    initAll(alloc, false);
    var eng = try initEngine(alloc);
    defer eng.free();
    eng.executeBuffer("position startpos");
    eng.executeBuffer("go perft depth 6 batched");
    waitOnEngine(&eng);
}
pub fn test_bench(alloc: std.mem.Alloator) !void {
    initAll(alloc, false);
    var eng = try initEngine(alloc);
    defer eng.executeBuffer("quit");
    //eng.executeBuffer("debug on");
    //eng.executeBuffer("setoption name useQuiescence value true");
    //eng.executeBuffer("setoption name useHash value true");
    eng.executeBuffer("setoption name searchType value zws");
    eng.executeBuffer("benchmark");
    waitOnEngine(&eng);
}

pub const globalCtx = struct {
    io: std.Io = undefined,
    gpa: std.mem.Allocator = undefined,
    isInit: bool = false,
    pub fn setInit(p_self: *globalCtx, init: std.process.Init) void {
        p_self.io = init.io;
        p_self.gpa = init.gpa;
        p_self.isInit = true;
    }
};
pub var GLOBAL_CTX: globalCtx = .{};
pub fn getGlobalIo() std.Io {
    std.debug.assert(GLOBAL_CTX.isInit);
    return GLOBAL_CTX.io;
}
pub fn getGlobalGPA() std.mem.Allocator {
    std.debug.assert(GLOBAL_CTX.isInit);
    return GLOBAL_CTX.gpa;
}

pub fn test_test() !void {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    initAll(arena, true);
    const perft_THREAD = 1;
    const perft_BATCHED = true;
    const perft_MAX_DEPTH = 6;
    var board: chessl.Board_state = try chessl.getBoardFromFen(arena, chessl.DEFAULT_FEN);
    //try std.testing.expect(!hashl.isHashTable_init());
    var sw: timel.stopWatch = .{};
    for (1..perft_MAX_DEPTH + 1) |depth| {
        sw.startTimeTick();
        const res = perftl.perftThreadStart(&board, arena, @intCast(depth), perft_THREAD, perft_BATCHED) catch {
            std.debug.print("[PANIC]: Error when launching perft\n", .{});
            try std.testing.expect(false);
            return;
        };
        const expect: i64 = @intCast(res.searchStat.n_nodeExplored);
        const timeTaken = sw.timeSinceStartUs();
        sw.stop();
        try std.testing.expectEqual(expect, benchl.ExpectedBenchmarkResults[depth]);
        std.debug.print("\t[RES] perft({d} ms): depth {d} node: {d}, nps: {d}\n", .{ @divFloor(timeTaken, std.time.us_per_ms), depth, expect, @divFloor(expect * std.time.us_per_s, timeTaken + 1) });
    }

    std.debug.print("[TEST]: Perft checks passed\n", .{});
}

pub fn main(init: std.process.Init) anyerror!void {
    GLOBAL_CTX.setInit(init);
    const GPA = init.gpa;
    initAll(GPA, false);
    try test_test();
    //try test_perft();
    //try test_bench();
    //try test_speed();
    //try heuristicl.main(GPA);
    //try chessl.main();
    //try test_bug();
    //var path = try stringl.string.initFromSlice(getGlobalGPA(), "opening/8moves_v3.pgn");
    //defer path.free(getGlobalGPA());
    //try bookl.main(&path, GPA);

    //try benchl.main(GLOBAL_ALLOC);
}
