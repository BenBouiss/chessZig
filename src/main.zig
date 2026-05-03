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
fn waitOnEngine(eng: *enginel.engine) !void {
    try std.Io.sleep(getGlobalIo(), .{ .nanoseconds = @intCast(configl.INFO_TICKRATE_NS * 2) }, .real);
    while (eng.searcher.searching) {
        try std.Io.sleep(getGlobalIo(), .{ .nanoseconds = @intCast(configl.INFO_TICKRATE_NS) }, .real);
    }
}
inline fn getDecision(eng: *enginel.engine) moveDecisionExt {
    return eng.searcher.schedul.finalChoice;
}

const fenListMateOne = [_][]const u8{
    "position fen Q7/8/8/8/5K1k/8/8/8 w - - 0 0",
    "position fen q7/8/8/8/5k1K/8/8/8 b - - 0 0",
};

pub fn test_decision(alloc: std.mem.Allocator) !void {
    var eng = try initEngine(alloc);
    defer eng.free();
    for (0..fenListMateOne.len) |i| {
        const fenCmd = fenListMateOne[i];
        eng.executeBuffer(fenCmd);
        eng.executeBuffer("go depth 4");
        try waitOnEngine(&eng);
        const dec = getDecision(&eng);
        try std.testing.expect(dec.scoring > 8000);
    }
    std.debug.print("[TEST]: Mate in one test passed\n", .{});
}
pub fn test_speed(alloc: std.mem.Allocator) !void {
    var eng = try initEngine(alloc);
    defer eng.free();
    //eng.executeBuffer("setoption name useQuiescence value true");
    //eng.executeBuffer("position fen r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    eng.executeBuffer("position fen r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1 ");
    //eng.executeBuffer("setoption name useNullPruning value true");
    eng.executeBuffer("go depth 7");
    try waitOnEngine(&eng);
}
pub fn test_bug(alloc: std.mem.Allocator) !void {
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
    try waitOnEngine(&eng);
}
pub fn test_bug2(alloc: std.mem.Allocator) !void {
    initAll(alloc, false);
    var eng = try initEngine(alloc);
    defer eng.free();
    eng.executeBuffer("ucinewgame");
    eng.executeBuffer("position startpos c2c4 g8f6 b1c3 e7e5 g1f3 b8c6 e2e4 f8b4 d2d3 e8g8 g2g3 d7d6 f1g2 c8g4 h2h3 g4f3 g2f3 f8e8 e1f1 d8e7 f3h5 c6d4 c1g5 e7e6 c3d5 f6d5 c4d5 e6d7 a2a3 h7h6 g5e3 b4c5 b2b4 c5b6 a1c1 a7a5 b4a5 a8a5 h5g4 d7b5 e3d4 b6d4 c1c7 a5a3 d1f3 b5d3 f3d3 a3d3 c7b7 d3d2 h1h2 g7g6 g4d7 e8a8 b7b1 a8d8 b1b7 d8a8 b7b1 a8d8 b1b7 d2c2 f1g1 c2e2 g1f1 e2d2 h3h4 d8a8 b7b1 h6h5 d7c6 a8d8 b1b7 d8a8 b7b1 a8d8 b1b7 d2a2 c6d7 a2a7 b7a7 d4a7 d7a4 d8b8 a4c2 b8b4 f2f4 e5f4 g3f4 a7e3 h2h3 e3f4 h3f3 f4e5 f3a3 b4c4 a3a8 g8h7 c2d3 c4c3 f1e2 e5f4 e2f3 f4d2 f3e2 d2f4 e2f3 f4e5 f3e3 c3b3 a8c8 b3a3 c8b8 h7g7 b8c8 g7f6 c8h8 e5g3 h8d8 a3b3 e3d2 g3e5 d8e8 e5d4 d3e2 b3a3 d2e1 d4e3 e2f3 a3a2 f3d1 a2g2 d1g4 h5g4 e8d8 f6e5 d8e8 e5d4 e8e7 ");
    eng.executeBuffer("isready");
    eng.executeBuffer("go wtime 45600 btime 48400 winc 0 binc 0");
    try waitOnEngine(&eng);
}
pub fn test_perft(alloc: std.mem.Allocator) !void {
    initAll(alloc, false);
    var eng = try initEngine(alloc);
    defer eng.free();
    eng.executeBuffer("position startpos");
    eng.executeBuffer("go perft depth 5 batched");
    try waitOnEngine(&eng);
}
pub fn test_bench(alloc: std.mem.Allocator) !void {
    initAll(alloc, false);
    var eng = try initEngine(alloc);
    defer eng.executeBuffer("quit");
    //eng.executeBuffer("debug on");
    //eng.executeBuffer("setoption name useQuiescence value true");
    //eng.executeBuffer("setoption name useHash value true");
    eng.executeBuffer("setoption name searchType value zws");
    eng.executeBuffer("benchmark");
    try waitOnEngine(&eng);
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
pub inline fn getGlobalIo() std.Io {
    std.debug.assert(GLOBAL_CTX.isInit);
    return GLOBAL_CTX.io;
}
pub inline fn getGlobalGPA() std.mem.Allocator {
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
    //initAll(GPA, false);
    defer hashl._freeHash(GPA, false);
    //try test_test();
    //try test_perft(GPA);
    //try test_bench();
    //try test_speed();
    //try heuristicl.main(GPA);
    //try chessl.main(GPA);
    //try test_bug();
    //try test_bug2(GPA);
    //var path = try stringl.string.initFromSlice(getGlobalGPA(), "opening/8moves_v3.pgn");
    //defer path.free(getGlobalGPA());
    //try bookl.main(&path, GPA);

    //try benchl.main(GLOBAL_ALLOC);
}
