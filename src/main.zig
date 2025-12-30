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

const build_options = @import("build_options");
const useDebug = build_options.useDebug;

pub fn initAll() void {
    magicl._initMagic(&magicl.magicTable);

    hashl._initZobrist(GLOBAL_ALLOC, 42);
    //hashl._initOrReallocHashTable(GLOBAL_ALLOC, 2000);

    moveTablel._initTables();
    if (comptime useDebug) {
        std.debug.print("[PRE] Building using the useDebug flag\n", .{});
    }
}
pub fn test_bench() void {
    initAll();
    benchl.test_benchmark();
}
pub fn test_speedTest() !void {
    var engine: enginel.engine = try enginel.engine.init(GLOBAL_ALLOC);
    //engine.uciMode = true;
    engine.executeBuffer("uci");
    engine.executeBuffer("debug on");
    engine.executeBuffer("setoption name hash value 100");
    engine.executeBuffer("isready");
    engine.executeBuffer("benchmark");

    while (engine.searcher.searching) {
        std.Thread.sleep(configl.INFO_TICKRATE_NS);
    }
}

pub fn main() anyerror!void {
    try chessl.main();
    //test_bench();
    //try enginel.launch_engine(true);
    //try test_speedTest();
}
