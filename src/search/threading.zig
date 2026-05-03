const enginel = @import("../engine.zig");
const movel = @import("../move.zig");
const chessl = @import("../chess.zig");
const heuristicl = @import("../heuristic.zig");
const schedulerl = @import("scheduler.zig");
const configl = @import("../config.zig");
const mainl = @import("../main.zig");
const timel = @import("../time.zig");
const lockl = @import("../lock.zig");

const std = @import("std");

const engine = enginel.engine;
const IMove = movel.IMove;
const Board_state = chessl.Board_state;
const scoreType = heuristicl.scoreType;
const debug_err = chessl.debug_err;
const moveDecisionExt = schedulerl.moveDecisionExt;

pub const searchStatistic = struct {
    n_cutoffs: u64 = 0,
    n_hashRetrieve: u64 = 0,
    n_nodeExplored: u64 = 0,
};
/// Benchmark function to test the node generation speed in
/// "real world" settings mainly computing heuristics...
pub const threadInfo = struct {
    currentBest: moveDecisionExt = .{},
    currentMove: moveDecisionExt = .{},
    depth: u8 = 0,
    working: bool = false,
    alive: bool = false,
    searchStat: searchStatistic = .{},
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
            ret.searchStat.n_nodeExplored += info.searchStat.n_nodeExplored;
            ret.searchStat.n_hashRetrieve += info.searchStat.n_hashRetrieve;
            ret.searchStat.n_cutoffs += info.searchStat.n_cutoffs;
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

// FIXME: this is getting very anoying to use with the .items(._tInfo)[_]... . the initial idea was to not use a std.ArrayList of this to test the more compact in memory use. use 'packed' to fix if needed
// The original idea behind this was that a threadPackage was supposed to run alongside other threadPackages thus moves was necessary to properly distrube the work among the running packages. In current version of the scheduler this feature is not used and moves is defaulted to undefined as the search is currently single threaded.

pub const threadPackageFrame = struct {
    chessState: Board_state,
    moves: std.ArrayList(IMove),
    threadHandle: std.Thread,
    _tInfo: threadInfo,
};
pub const threadPackageArray = std.MultiArrayList(threadPackageFrame);

pub fn getThreadPackArray(alloc: std.mem.Allocator, p_state: *const Board_state, moveArray: *const movel.moveContainer, n_threads: u32) !threadPackageArray {
    const _nThread = @min(n_threads, moveArray.len);
    var ret: threadPackageArray = .{};
    var threadedMoves = moveArray.cutEvenly(alloc, _nThread) catch {
        std.debug.print("[ERROR] getThreadPackArray: move container init\n", .{});
        return debug_err.valueErr;
    };
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
pub fn zeroThreadPackArray(p_array: *threadPackageArray) void {
    for (0..p_array.len) |i| {
        p_array.items(._tInfo)[i].searchStat.n_nodeExplored = 0;
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

pub const searchPackage = struct {
    chessState: chessl.Board_state = undefined,
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
};

pub const threadPool = struct {
    threadProps: [configl.MAX_THREAD]threadP = undefined,
    threadInfos: [configl.MAX_THREAD]threadInfo = undefined,
    packages: [configl.MAX_THREAD]searchPackage = undefined,

    nThread: usize = 0,
    running: bool = false,
    working: bool = false,
    lock: lockl.lock = .{},

    pub fn isRunning(p_self: *threadPool) bool {
        p_self.lock.acquireLock();
        defer p_self.lock.releaseLock();
        return p_self.running;
    }

    pub fn addThread(p_self: *threadPool, n: usize) !void {
        p_self.running = true;

        std.debug.print("[DEBUG] addThread: Adding {d} thread(s) current nbr {d}\n", .{ n, p_self.nThread });
        for (0..n) |_| {
            p_self.threadInfos[p_self.nThread] = .{ .alive = true };
            p_self.threadProps[p_self.nThread]._handle = try std.Thread.spawn(.{}, waitingRoom, .{ p_self, p_self.nThread });
            p_self.nThread += 1;
        }
    }

    pub fn close(p_self: *threadPool) void {
        std.debug.print("[EXIT] Closing threadPool with {d} threads\n", .{p_self.nThread});
        p_self.running = false;
        for (0..p_self.nThread) |i| {
            p_self.threadInfos[i].alive = false;
            p_self.threadProps[i].alive = false;
        }
        std.debug.print("[EXIT] Joining on threadPool\n", .{});
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
        var sw: timel.stopWatch = .{};
        sw.startTimeTick();
        const timeout = 5;
        while (p_self.getNumberOfWorking() != 0 and p_self.isRunning()) {
            if (sw.timeSinceStartSec() > timeout) {
                sw.reset();
                sw.startTimeTick();
                std.debug.print("[INACTIVITY] threadPool.waitOnFinish : no activity in the last {d} seconds\n", .{timeout});
            }
        }
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
        }

        //var sw: timel.stopWatch = .{};
        //sw.startTimeTick();
        //while (!p_self.working) {
        //    try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.WR_TICKRATE_NS) }, .real);
        //    if (sw.timeSinceStartSec > 4) {
        //        return threadPoolerr.timedOut;
        //    }
        //}
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
            }
        }
        return ret;
    }
};
pub const threadPoolerr = error{ timedOut, alreadySearching };

pub fn waitingRoom(p_self: *threadPool, idx: usize) void {
    p_self.threadProps[idx].status = .WAITING;
    p_self.threadProps[idx].alive = true;
    var sw: timel.stopWatch = .{};
    sw.startTimeTick();
    const timeout = 2;
    const alive = &p_self.threadProps[idx].alive;

    std.debug.print("[DEBUG] threadPool.WaitingRoom: Thread {d} entering loop\n", .{idx});
    while (p_self.isRunning() and alive.*) {
        if (!p_self.working) {
            std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.WR_TICKRATE_NS) }, .real) catch unreachable;
        }
        if (sw.timeSinceStartSec() > timeout) {
            sw.reset();
            sw.startTimeTick();
            std.debug.print("[INACTIVITY] threadPool.WaitingRoom: Thread {d} no activity in the last {d} seconds. Running {} alive {}\n", .{ idx, timeout, p_self.running, alive.* });
        }
        if (p_self.threadProps[idx].searchPing) {
            sw.reset();
            sw.startTimeTick();
            p_self.threadProps[idx].searchPing = false;
            p_self.threadProps[idx].status = .WORKING;
            var pack = p_self.packages[idx];
            schedulerl._startSearch(pack.scheduler, &pack.chessState, &p_self.threadInfos[idx], pack.features, pack.depth);
            p_self.threadProps[idx].status = .WAITING;
        }
    }
    p_self.running = false;
    const pack = p_self.packages[idx];
    std.debug.print("[EXIT] threadPool.WaitingRoom: Thread {d} exiting\n", .{idx});
    pack.scheduler.p_engine.respond("engineOp threadPool.waitingroom .EXITING");
}
