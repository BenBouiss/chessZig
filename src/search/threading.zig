const enginel = @import("../engine.zig");
const movel = @import("../move.zig");
const chessl = @import("../chess.zig");
const heuristicl = @import("../heuristic.zig");
const schedulerl = @import("scheduler.zig");

const std = @import("std");

const engine = enginel.engine;
const IMove = movel.IMove;
const Board_state = chessl.Board_state;
const scoreType = heuristicl.scoreType;
const debug_err = chessl.debug_err;
const moveDecisionExt = schedulerl.moveDecisionExt;

/// Benchmark function to test the node generation speed in
/// "real world" settings mainly computing heuristics...
///
///
pub const threadInfo = struct {
    currentBest: moveDecisionExt = .{},
    currentMove: moveDecisionExt = .{},
    n_nodeExplored: u64 = 0,
    n_hashRetrieve: u64 = 0,
    depth: u8 = 0,
    working: bool = false,
    alive: bool = false,
};
pub const threadInfo_container = struct {
    len: u16,
    items: []threadInfo,
    n_active: u16 = 0,
    pub fn init(alloc: std.mem.Allocator, size: u16) !threadInfo_container {
        var ret: threadInfo_container = undefined;
        ret.len = size;
        ret.items = try alloc.alloc(threadInfo, size);
        const emptyStruct: threadInfo = .{};
        for (0..size) |i| {
            ret.items[i] = emptyStruct;
        }
        return ret;
    }
    pub fn combine(self: *threadInfo_container) threadInfo {
        var ret: threadInfo = .{};
        self.n_active = 0;
        for (0..self.len) |i| {
            const info = self.items[i];
            ret.n_nodeExplored += info.n_nodeExplored;
            ret.n_hashRetrieve += info.n_hashRetrieve;
            self.n_active += @intFromBool(info.working);
        }
        return ret;
    }
    pub fn getBestMove(self: *threadInfo_container) moveDecisionExt {
        var ret: moveDecisionExt = .{};
        for (0..self.len) |i| {
            const info = self.items[i];
            if (i == 0 or info.currentBest.scoring > ret.scoring) {
                ret = info.currentBest;
            }
        }
        return ret;
    }
    pub fn free(self: *threadInfo_container, alloc: std.mem.Allocator) void {
        alloc.free(self.items);
    }
};

pub const threadPackageFrame = struct {
    chessState: Board_state,
    moves: std.ArrayList(IMove),
    threadHandle: std.Thread,
    _tInfo: threadInfo,
};
pub const threadPackageArray = std.MultiArrayList(threadPackageFrame);

pub fn getThreadPackArray(alloc: std.mem.Allocator, p_state: *Board_state, moveArray: *movel.moveContainer, n_threads: u32) !threadPackageArray {
    const _nThread = @min(n_threads, moveArray.len);
    var ret: threadPackageArray = .{};
    const threadedMoves = moveArray.cutEvenly(alloc, _nThread) catch {
        std.debug.print("[ERROR] getThreadPackArray: move container init\n", .{});
        return debug_err.valueErr;
    };
    //const cont = try p_state.duplicateNTimes(alloc, @intCast(n_threads));
    for (0.._nThread) |i| {
        try ret.append(alloc, .{ .chessState = p_state.*, .moves = threadedMoves.items[i], .threadHandle = undefined, ._tInfo = .{} });
    }
    return ret;
}
pub fn getCombinedFromPack(p_array: *threadPackageArray) threadInfo {
    var ret: threadInfo = .{};
    for (0..p_array.len) |i| {
        const info = p_array.items(._tInfo)[i];
        ret.n_nodeExplored += info.n_nodeExplored;
        ret.n_hashRetrieve += info.n_hashRetrieve;
        if (i == 0 or (ret.currentBest.scoring < info.currentBest.scoring)) {
            ret.currentBest = info.currentBest;
        }
    }
    return ret;
}
pub fn zeroThreadPackArray(p_array: *threadPackageArray) void {
    for (0..p_array.len) |i| {
        p_array.items(._tInfo)[i].n_nodeExplored = 0;
    }
}
pub fn freeThreadPackArray(alloc: std.mem.Allocator, p_array: *threadPackageArray) void {
    for (0..p_array.len) |i| {
        var cell: std.ArrayList(IMove) = p_array.items(.moves)[i];
        cell.deinit(alloc);
        var state: Board_state = p_array.items(.chessState)[i];
        state.free(alloc);
    }
    p_array.deinit(alloc);
}
pub fn joinOnThreadPack(p_array: *threadPackageArray) void {
    for (0..p_array.len) |i| {
        p_array.items(.threadHandle)[i].join();
    }
}
