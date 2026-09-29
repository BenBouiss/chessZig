const movel = @import("move.zig");
const schedulerl = @import("scheduler.zig");
const configl = @import("config.zig");
const mainl = @import("main.zig");
const timel = @import("time.zig");
const lockl = @import("lock.zig");
const boardl = @import("board.zig");
const typel = @import("type.zig");
const hashl = @import("hashTable.zig");
const chessl = @import("chess.zig");
const nnuel = @import("nnue.zig");
const historyl = @import("history.zig");

const std = @import("std");
const depthT = typel.depthT;
const IMove = movel.IMove;
const scoreType = typel.scoreType;

/// Benchmark function to test the node generation speed in
/// "real world" settings mainly computing heuristics...
pub const searchStatistic = struct {
    n_cutoffs: u64 = 0,
    n_hashRetrieve: u64 = 0,
    n_nodeExplored: u64 = 0,
    pub fn add(self: *searchStatistic, other: searchStatistic) void {
        self.n_cutoffs += other.n_cutoffs;
        self.n_hashRetrieve += other.n_hashRetrieve;
        self.n_nodeExplored += other.n_nodeExplored;
    }
    pub fn print(self: searchStatistic) void {
        std.debug.print("cutoff={d}\nhash retrieve={d}\nnodes={d}\n", .{ self.n_cutoffs, self.n_hashRetrieve, self.n_nodeExplored });
    }
};

pub const threadInfo = struct {
    currentBest: schedulerl.moveDecisionExt = .{},
    depth: depthT = 0,
    seldepth: depthT = 0,
    alive: bool = false,
    searchStat: searchStatistic = .{},
    stopWatch: timel.stopWatch = .{},
    criticalTimeMs: i64 = 0,
    criticalNodeLim: u64 = std.math.maxInt(u64),

    // maxTimeMs
    // check every 1024
    checkTime: u64 = 0,
    d: ?*threadData = null,
};
pub const threadData = struct {
    excludedMove: movel.IMove = .{},
    rootMoves: [chessl.MAX_POSSIBLE_MOVE]movel.rootMoveInfo = @splat(.{}),
    nnueStack: nnuel.accumulatorPairStack = .{},

    pawnCorrHist: [2][16384]scoreType = std.mem.zeroes([2][16384]scoreType),
    nonPawnCorrHist: [2][2][16384]scoreType = std.mem.zeroes([2][2][16384]scoreType),
    historyHeuristic: [2][64][64]scoreType = std.mem.zeroes([2][64][64]scoreType),
    captureHistory: [13][13][64]scoreType = std.mem.zeroes([13][13][64]scoreType),
    continuationHeuristic: [13][64]historyl.pieceHistory = std.mem.zeroes([13][64]historyl.pieceHistory),
    corrHist: [12][64][12][64]scoreType = std.mem.zeroes([12][64][12][64]scoreType),

    nodeCount: [64][64]u64 = std.mem.zeroes([64][64]u64),
    pub fn reset(self: *threadData) void {
        self.pawnCorrHist = std.mem.zeroes([2][16384]scoreType);
        self.nonPawnCorrHist = std.mem.zeroes([2][2][16384]scoreType);

        self.historyHeuristic = std.mem.zeroes([2][64][64]scoreType);
        self.captureHistory = std.mem.zeroes([13][13][64]scoreType);
        self.continuationHeuristic = std.mem.zeroes([13][64]historyl.pieceHistory);
        self.corrHist = std.mem.zeroes([12][64][12][64]scoreType);
    }
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
        ret.searchStat.add(info.searchStat);
        if (i == 0 or (ret.currentBest.score < info.currentBest.score)) {
            ret.currentBest = info.currentBest;
        }
    }
    return ret;
}

pub fn freeThreadPackArray(alloc: std.mem.Allocator, p_array: *threadPackageArray) void {
    for (0..p_array.len) |i| {
        var cell: std.ArrayList(movel.IMove) = p_array.items(.moves)[i];
        cell.deinit(alloc);
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
    depth: depthT = 0,
    features: schedulerl.searchFeatures = .{},
    time: schedulerl.timeInfo = .{},
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
    threadProps: [configl.MAX_THREAD]threadP = @splat(.{}),
    threadInfos: [configl.MAX_THREAD]threadInfo = @splat(.{}),
    packages: [configl.MAX_THREAD]searchPackage = @splat(.{}),
    nThread: usize = 0,
    running: bool = false,
    working: bool = false,
    lock: lockl.lock = .{},
    debugMode: bool = false,

    computedPlies: i64 = 0,
    nPlyCompute: u64 = 0,

    pub fn isRunning(p_self: *threadPool) bool {
        p_self.lock.acquireLock();
        defer p_self.lock.releaseLock();
        return p_self.running;
    }
    pub fn timeSpentSearchingUs(p_self: *threadPool) i64 {
        //
        var ret: i64 = 0;
        for (0..p_self.threadProps.len) |i| {
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
    pub inline fn waitOnFinish(p_self: *threadPool) void {
        while (p_self.getNumberOfWorking() != 0 and p_self.isRunning()) {}
    }
    pub fn getNumberOfWorking(p_self: *const threadPool) usize {
        var ret: usize = 0;
        for (0..p_self.nThread) |i| {
            ret += @intFromBool(p_self.threadProps[i].status == .WORKING);
        }
        return ret;
    }
    pub fn submit(p_self: *threadPool, pack: searchPackage) threadPoolerr!void {
        if (p_self.working) {
            return threadPoolerr.alreadySearching;
        }
        for (0..p_self.nThread) |i| {
            p_self.packages[i] = pack;
            p_self.threadInfos[i].alive = true;
            p_self.threadProps[i].searchPing = true;
            p_self.threadProps[i].status = .WORKING;
        }
    }
    pub fn getInfos(p_self: *const threadPool) []const threadInfo {
        return p_self.threadInfos[0..p_self.nThread];
    }
    pub fn getSearchStatus(p_self: *const threadPool) schedulerl.searchStatus {
        const working = p_self.getNumberOfWorking();
        if (working == 0) {
            return .FINISHED;
        }
        return .CONTINUE;
    }
    pub fn getCombinedInfo(p_self: *const threadPool) threadInfo {
        var ret: threadInfo = .{};
        for (0..p_self.nThread) |i| {
            const info = p_self.threadInfos[i];
            ret.searchStat.add(info.searchStat);
            if (i == 0 or (ret.currentBest.score < info.currentBest.score)) {
                ret.currentBest = info.currentBest;
                ret.depth = info.depth;
            }
        }
        return ret;
    }
    pub fn resetDatas(p_self: *threadPool) void {
        for (0..p_self.nThread) |i| {
            const info = &p_self.threadInfos[i];
            if (info.d) |d| {
                d.reset();
            }
        }
    }
};
pub const threadPoolerr = error{ timedOut, alreadySearching };

pub fn waitingRoom(p_self: *threadPool, idx: usize) void {
    var props = &p_self.threadProps[idx];
    props.status = .WAITING;
    props.alive = true;
    props.timeWorkingUs = 0;
    var d: threadData = .{};
    p_self.threadInfos[idx].d = &d;
    while (p_self.isRunning() and props.alive) {
        std.atomic.spinLoopHint();
        if (props.searchPing) {
            var sw: timel.stopWatch = .init(true);
            props.searchPing = false;
            props.status = .WORKING;
            var pack = p_self.packages[idx];
            const res = schedulerl._startSearch(&pack.chessState, &p_self.threadInfos[idx], pack.features, pack.depth, pack.time, &hashl.hashTable, &d);
            props.timeWorkingUs += sw.timeSinceStartUs();
            props.status = .WAITING;

            p_self.nPlyCompute += 1;
            p_self.computedPlies += res.depth;
        }
    }
    p_self.running = false;
}
