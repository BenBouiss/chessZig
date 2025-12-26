const configl = @import("../config.zig");
const enginel = @import("../engine.zig");
const movel = @import("../move.zig");
const chessl = @import("../chess.zig");
const explorationl = @import("../exploration.zig");
const moveGenl = @import("../move_generation.zig");
const heuristicl = @import("../heuristic.zig");
const hashl = @import("../hashTable.zig");
const mailn = @import("../main.zig");

const std = @import("std");

const engine = enginel.engine;
const IMove = movel.IMove;
const Board_state = chessl.Board_state;
const scoreType = heuristicl.scoreType;
const debug_err = chessl.debug_err;
const moveDecisionExt = explorationl.moveDecisionExt;

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
    running: bool = false,
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
            self.n_active += @intFromBool(info.running);
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

const threadPackageFrame = struct {
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

pub fn freeThreadPackArray(alloc: std.mem.Allocator, p_array: *threadPackageArray) void {
    for (0..p_array.len) |i| {
        var cell: std.ArrayList(IMove) = p_array.items(.moves)[i];
        cell.deinit(alloc);
    }
    p_array.deinit(alloc);
}
pub fn joinOnThreadPack(p_array: *threadPackageArray) void {
    for (0..p_array.len) |i| {
        p_array.items(.threadHandle)[i].join();
    }
}

pub fn waitBenchmarkThread(p_engine: *engine, p_threadPack: *threadPackageArray) void {
    var searcher = &p_engine.searcher;
    while (!searcher.interrupt and (searcher.endCounter != p_threadPack.items(._tInfo).len)) {
        std.Thread.sleep(configl.INFO_TICKRATE_NS);
        searcher.endCounter = 0;
        for (p_threadPack.items(._tInfo)) |*info| {
            if (!info.running) {
                searcher.endCounter += 1;
            }
        }
    }
    searcher.searching = false;
    if (searcher.endCounter != p_threadPack.len) {
        for (0..p_threadPack.len) |i| {
            p_threadPack.items(._tInfo)[i].running = false;
        }
        for (0..p_threadPack.len) |i| {
            if (p_engine.status.debugMode) {
                std.debug.print("[DEBUG] waitBenchmarkThread: Waiting on thread {d}  to finish\n", .{i});
            }
            p_threadPack.items(.threadHandle)[i].join();
        }
    }

    if (p_engine.status.debugMode) {
        std.debug.print("[DEBUG] waitBenchmarkThread: finished waiting on results\n", .{});
    }
}
pub fn waitThreadFinish_NpsReport(p_engine: *enginel.engine, p_arr: *threadPackageArray) !bool {
    const _start: u64 = @intCast(std.time.milliTimestamp());
    while (!p_engine.searcher.interrupt and p_engine.searcher.endCounter != p_engine.searcher.nThreads) {
        std.Thread.sleep(configl.INFO_TICKRATE_NS);

        p_engine.searcher.endCounter = 0;
        for (0..p_arr.len) |i| {
            p_engine.searcher.endCounter += @intFromBool(!p_arr.items(._tInfo)[i].running);
        }

        const res = getCombinedFromPack(p_arr);
        const _end: u64 = @intCast(std.time.milliTimestamp());
        const msg = std.fmt.allocPrint(p_engine.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d}", .{ @divFloor(res.n_nodeExplored, (_end - _start + 1)) * 1000, res.n_nodeExplored, res.n_hashRetrieve, hashl.hashTable.n_insertion }) catch {
            continue;
        };
        defer p_engine.alloc.free(msg);
        p_engine.respond(msg);
    }
    p_engine.searcher.searching = false;
    return true;
}
