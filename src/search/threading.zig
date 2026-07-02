const movel = @import("../move.zig");
const schedulerl = @import("scheduler.zig");
const configl = @import("../config.zig");
const mainl = @import("../main.zig");
const timel = @import("../time.zig");
const lockl = @import("../lock.zig");
const boardl = @import("../board.zig");

const std = @import("std");

pub const searchStatistic = struct {
    n_cutoffs: u64 = 0,
    n_hashRetrieve: u64 = 0,
    n_nodeExplored: u64 = 0,
};
/// Benchmark function to test the node generation speed in
/// "real world" settings mainly computing heuristics...
pub const threadInfo = struct {
    currentBest: schedulerl.moveDecisionExt = .{},
    currentMove: schedulerl.moveDecisionExt = .{},
    depth: u16 = 0,
    working: bool = false,
    alive: bool = false,
    searchStat: searchStatistic = .{},
};

pub const threadPackageFrame = struct {
    chessState: boardl.boardState,
    moves: std.ArrayList(movel.IMove),
    threadHandle: std.Thread,
    _tInfo: threadInfo,
};
pub const threadPackageArray = std.MultiArrayList(threadPackageFrame);

pub fn getThreadPackArray(alloc: std.mem.Allocator, p_state: *const boardl.boardState, moveArray: *const movel.moveContainer, n_threads: u32) !threadPackageArray {
    const _nThread = @min(n_threads, moveArray.len);
    var ret: threadPackageArray = .{};
    var threadedMoves = try moveArray.cutEvenly(alloc, _nThread);
    defer threadedMoves.deinit(alloc);
    for (0.._nThread) |i| {
        try ret.append(alloc, .{ .chessState = p_state.copy(), .moves = threadedMoves.items[i], .threadHandle = undefined, ._tInfo = .{} });
    }
    return ret;
}
pub fn getCombinedFromPack(p_array: *threadPackageArray) threadInfo {
    var ret: threadInfo = .{};
    for (0..p_array.len) |i| {
        const info = p_array.items(._tInfo)[i];
        ret.searchStat.n_nodeExplored += info.searchStat.n_nodeExplored;
        ret.searchStat.n_hashRetrieve += info.searchStat.n_hashRetrieve;
        ret.searchStat.n_cutoffs += info.searchStat.n_cutoffs;
        if (i == 0 or (ret.currentBest.scoring < info.currentBest.scoring)) {
            ret.currentBest = info.currentBest;
        }
    }
    return ret;
}

pub fn freeThreadPackArray(alloc: std.mem.Allocator, p_array: *threadPackageArray) void {
    for (0..p_array.len) |i| {
        var cell: std.ArrayList(movel.IMove) = p_array.items(.moves)[i];
        cell.deinit(alloc);
        var state: boardl.boardState = p_array.items(.chessState)[i];
        state.free(alloc);
    }
    p_array.deinit(alloc);
}
pub fn joinOnThreadPack(p_array: *threadPackageArray) void {
    for (0..p_array.len) |i| {
        p_array.items(.threadHandle)[i].join();
    }
}

pub const searchPackage = struct {
    chessState: boardl.boardState = undefined,
    depth: u16 = 0,
    features: schedulerl.searchFeatures = .{},
    scheduler: *schedulerl.scheduler = undefined,
};
pub const threadStatus = enum { WAITING, WORKING };
pub const threadP = struct {
    _handle: std.Thread = undefined,
    status: threadStatus = .WAITING,
    searchPing: bool = false,
    alive: bool = false,
    timeWorkingUs: i64 = 0,
};

pub const threadPool = struct {
    threadProps: [configl.MAX_THREAD]threadP = undefined,
    threadInfos: [configl.MAX_THREAD]threadInfo = undefined,
    packages: [configl.MAX_THREAD]searchPackage = undefined,
    nThread: usize = 0,
    running: bool = false,
    working: bool = false,
    lock: lockl.lock = .{},
    debugMode: bool = false,

    pub fn isRunning(p_self: *threadPool) bool {
        p_self.lock.acquireLock();
        defer p_self.lock.releaseLock();
        return p_self.running;
    }
    pub fn timeSpentSearchingUs(p_self: *threadPool) i64 {
        //
        var ret: i64 = 0;
        for (0..p_self.nThread) |i| {
            ret += p_self.threadProps[i].timeWorkingUs;
        }
        return ret;
    }

    pub fn addThread(p_self: *threadPool, n: usize) !void {
        p_self.running = true;
        for (0..n) |_| {
            p_self.threadInfos[p_self.nThread] = .{ .alive = true };
            p_self.threadProps[p_self.nThread]._handle = try std.Thread.spawn(.{}, waitingRoom, .{ p_self, p_self.nThread });
            p_self.nThread += 1;
        }
    }

    pub fn close(p_self: *threadPool) void {
        p_self.running = false;
        for (0..p_self.nThread) |i| {
            p_self.threadInfos[i].alive = false;
            p_self.threadProps[i].alive = false;
        }
        for (0..p_self.nThread) |i| {
            p_self.threadProps[i]._handle.join();
        }
        p_self.nThread = 0;
    }
    pub fn stop(p_self: *threadPool) void {
        for (0..p_self.nThread) |i| {
            p_self.threadInfos[i].alive = false;
        }
    }
    pub fn waitOnFinish(p_self: *threadPool) void {
        while (p_self.getNumberOfWorking() != 0 and p_self.isRunning()) {}
    }
    pub fn getNumberOfWorking(p_self: *const threadPool) usize {
        var ret: usize = 0;
        for (0..p_self.nThread) |i| {
            ret += @intFromBool(p_self.threadProps[i].status == .WORKING);
        }
        return ret;
    }
    pub fn submit(p_self: *threadPool, p_pack: *const searchPackage) threadPoolerr!void {
        if (p_self.working) {
            return threadPoolerr.alreadySearching;
        }
        for (0..p_self.nThread) |i| {
            p_self.packages[i] = p_pack.*;
            p_self.threadInfos[i] = .{ .working = true, .alive = true };
        }
        for (0..p_self.nThread) |i| {
            p_self.threadProps[i].searchPing = true;
            p_self.threadProps[i].status = .WORKING;
        }
        return;
    }
    pub fn getInfos(p_self: *const threadPool) []const threadInfo {
        return p_self.threadInfos[0..p_self.nThread];
    }
    pub fn getSearchStatus(p_self: *const threadPool) schedulerl.searchStatus {
        var endCounter: usize = 0;
        for (0..p_self.nThread) |i| {
            const info: threadInfo = p_self.threadInfos[i];
            endCounter += @intFromBool(!info.working);
        }
        if (endCounter == p_self.nThread) {
            return .FINISHED;
        }
        return .CONTINUE;
    }
    pub fn getCombinedInfo(p_self: *const threadPool) threadInfo {
        var ret: threadInfo = .{};
        for (0..p_self.nThread) |i| {
            const info = p_self.threadInfos[i];
            ret.searchStat.n_nodeExplored += info.searchStat.n_nodeExplored;
            ret.searchStat.n_hashRetrieve += info.searchStat.n_hashRetrieve;
            ret.searchStat.n_cutoffs += info.searchStat.n_cutoffs;
            if (i == 0 or (ret.currentBest.scoring < info.currentBest.scoring)) {
                ret.currentBest = info.currentBest;
                ret.depth = info.depth;
                ret.currentBest.depth = info.depth;
            }
        }
        return ret;
    }
};
pub const threadPoolerr = error{ timedOut, alreadySearching };

pub fn waitingRoom(p_self: *threadPool, idx: usize) void {
    p_self.threadProps[idx].status = .WAITING;
    p_self.threadProps[idx].alive = true;
    p_self.threadProps[idx].timeWorkingUs = 0;
    const alive = &p_self.threadProps[idx].alive;
    while (p_self.isRunning() and alive.*) {
        if (!p_self.working) {
            std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.THREADPOOL_TICKRATE_NS) }, .real) catch unreachable;
        }

        if (p_self.threadProps[idx].searchPing) {
            var sw: timel.stopWatch = .{};
            sw.startTimeTick();
            p_self.threadProps[idx].searchPing = false;
            p_self.threadProps[idx].status = .WORKING;
            var pack = p_self.packages[idx];
            schedulerl._startSearch(pack.scheduler, &pack.chessState, &p_self.threadInfos[idx], pack.features, pack.depth);
            p_self.threadProps[idx].timeWorkingUs += sw.timeSinceStartUs();
            p_self.threadProps[idx].status = .WAITING;
        }
    }
    p_self.running = false;
}
