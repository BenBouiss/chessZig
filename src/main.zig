const std = @import("std");

const chessl = @import("chess.zig");
const nnuel = @import("nnue.zig");
const heuristicl = @import("heuristic.zig");
const intrinsics = @import("intrinsics/intrinsics.zig");
const logl = @import("log.zig");
const bookl = @import("book.zig");
const moveGenl = @import("move_generation.zig");
const hashl = @import("hashTable.zig");

const fenListMateOne = [_][]const u8{
    "position fen Q7/8/8/8/5K1k/8/8/8 w - - 0 0",
    "position fen q7/8/8/8/5k1K/8/8/8 b - - 0 0",
};

pub const globalCtx = struct {
    io: std.Io = undefined,
    gpa: std.mem.Allocator = undefined,
    isInit: bool = false,
    pub fn setInit(p_self: *globalCtx, init: std.process.Init) void {
        p_self.io = init.io;
        p_self.gpa = init.gpa;
        p_self.isInit = true;
    }
    pub fn setGPA(p_self: *globalCtx, alloc: std.mem.Allocator) void {
        p_self.gpa = alloc;
    }
    pub fn setIO(p_self: *globalCtx, io: std.Io) void {
        p_self.io = io;
    }
};
pub var GLOBAL_CTX: globalCtx = .{};

pub inline fn getGlobalIo() std.Io {
    return GLOBAL_CTX.io;
}
pub inline fn getGlobalGPA() std.mem.Allocator {
    return GLOBAL_CTX.gpa;
}

pub fn main(init: std.process.Init) anyerror!void {
    GLOBAL_CTX.setInit(init);
    const GPA = init.gpa;
    //_ = GPA;
    //hashl.zobristKeys.print();
    //try moveGenl.main();

    //try bookl.main(GPA);
    try chessl.main(GPA);
    //try logl.main(GPA);
    //try nnuel.main(GPA);
    //try heuristicl.main(GPA);

    //try test_bench(GPA, 10);
    //try test_perft(GPA);

    //try test_speed();
    //try test_bug2(GPA);
    //try test_test(GPA);
    //try benchl.main(GLOBAL_ALLOC);
    //try intrinsics.main();
}
