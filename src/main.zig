const std = @import("std");

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

const magicl = @import("magic.zig");
const moveTablel = @import("moveTables.zig");
const hashl = @import("hashTable.zig");
const enginel = @import("engine.zig");
const benchl = @import("benchmark.zig");

const build_options = @import("build_options");
const useDebug = build_options.useDebug;

pub fn initAll() void {
    magicl._initMagic(&magicl.magicTable);
    //hashl._initHash(GLOBAL_ALLOC, 42, 19);

    hashl._initZobrist(GLOBAL_ALLOC, 42);
    hashl._initOrReallocHashTable(GLOBAL_ALLOC, 2000);

    moveTablel._initTables();
    if (comptime useDebug) {
        std.debug.print("[PRE] Building using the useDebug flag\n", .{});
    }
}
pub fn test_bench() void {
    initAll();
    benchl.test_benchmark();
}

pub fn main() anyerror!void {
    //test_bench();
    //initAll();
    enginel.launch_engine(true) catch unreachable;
    hashl.hashTable.free(GLOBAL_ALLOC);
}
