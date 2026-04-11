const std = @import("std");

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

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

const build_options = @import("build_options");
const useDebug = build_options.useDebug;

const schedulerl = @import("search/scheduler.zig");
const moveDecisionExt = schedulerl.moveDecisionExt;

pub fn initAll(verbose: bool) void {
    magicl._initMagic(&magicl.magicTable, verbose);

    hashl._initZobrist(GLOBAL_ALLOC, 42);
    //hashl._initOrReallocHashTable(GLOBAL_ALLOC, 2000);

    moveTablel._initTables(verbose);
    if (comptime useDebug) {
        std.debug.print("[PRE] Building using the useDebug flag\n", .{});
    }
}

fn initEngine() !enginel.engine {
    var engine: enginel.engine = try enginel.engine.init(GLOBAL_ALLOC);
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

pub fn test_decision() !void {
    var eng = try initEngine();
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
pub fn test_speed() !void {
    var eng = try initEngine();
    defer eng.free();
    //eng.executeBuffer("setoption name useQuiescence value true");
    //eng.executeBuffer("position fen r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    eng.executeBuffer("position fen r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1 ");
    //eng.executeBuffer("setoption name useNullPruning value true");
    eng.executeBuffer("go depth 7");
    waitOnEngine(&eng);
}
pub fn test_bug() !void {
    initAll(false);
    var eng = try initEngine();
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
pub fn test_perft() !void {
    initAll(false);
    var eng = try initEngine();
    defer eng.free();
    eng.executeBuffer("position startpos");
    eng.executeBuffer("go perft depth 6 batched");
    waitOnEngine(&eng);
}
pub fn test_bench() !void {
    initAll(false);
    var eng = try initEngine();
    defer eng.executeBuffer("quit");
    //eng.executeBuffer("debug on");
    //eng.executeBuffer("setoption name useQuiescence value true");
    //eng.executeBuffer("setoption name useHash value true");
    eng.executeBuffer("setoption name searchType value zws");
    eng.executeBuffer("benchmark");
    waitOnEngine(&eng);
}

pub fn main() anyerror!void {
    //try test_perft();
    //try test_bench();
    //try test_speed();
    try heuristicl.main();
    //try chessl.main();
    //try test_bug();
    //Jvar path = try stringl.string.initFromSlice(GLOBAL_ALLOC, "opening/8moves_v3.pgn");
    //Jdefer path.free(GLOBAL_ALLOC);
    //Jtry bookl.main(&path);

    //try benchl.main();
}
