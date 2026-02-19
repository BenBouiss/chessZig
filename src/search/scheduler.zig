const std = @import("std");

const enginel = @import("../engine.zig");
const movel = @import("../move.zig");
const chessl = @import("../chess.zig");
const moveGenl = @import("../move_generation.zig");
const perftl = @import("perft.zig");
const alphaBetal = @import("alphaBeta.zig");
const threadingl = @import("threading.zig");
const heuristicl = @import("../heuristic.zig");
const hashl = @import("../hashTable.zig");
const utilsl = @import("../utils.zig");
const configl = @import("../config.zig");

const moveContainer = movel.moveContainer;
const IMove = movel.IMove;
const moveLine = movel.moveLine;
const scoreType = heuristicl.scoreType;
const threadPackageArray = threadingl.threadPackageArray;

pub const searchStatus = enum { CONTINUE, INTERRUPTED, FINISHED };

pub const searchFeatures = struct {
    useHash: bool = configl.DEFAULT_USEHASHTABLE,
    useTexelEvaluation: bool = configl.DEFAULT_USETEXEL,
    useQuiescence: bool = configl.DEFAULT_USEQUIESC,
};
pub fn getSearchFeatures(p_engine: *enginel.engine) searchFeatures {
    var ret: searchFeatures = .{};
    ret.useHash = p_engine.options.useHashTable;
    ret.useTexelEvaluation = p_engine.options.useTexelEvaluation;
    return ret;
}

pub const uciSearcher = struct {
    config: enginel.goArgStruct = .{},
    schedul: scheduler = .{},
    bestMove: moveDecisionExt = .{},
    nThreads: u32 = 1,
    endCounter: u16 = 0,
    searching: bool = false,
    interrupt: bool = false,

    pub fn reset(p_self: *uciSearcher) void {
        p_self.endCounter = 0;
        p_self.interrupt = false;
        p_self.searching = false;
        p_self.bestMove = .{};
    }
    pub fn printInfo(self: uciSearcher) void {
        std.debug.print("searcher thread: {d}\n", .{self.nThreads});
    }
};
pub const moveDecisionExt = struct {
    move: IMove = .{},
    line: moveLine = .{},
    scoring: scoreType = 0,
    pub fn invertScore(p_self: *moveDecisionExt) void {
        p_self.scoring = -p_self.scoring;
    }
    pub fn isBetter(p_self: *moveDecisionExt, other: *moveDecisionExt) bool {
        return p_self.scoring > other.scoring;
    }
    pub fn copy(self: moveDecisionExt) moveDecisionExt {
        return .{ .move = self.move, .line = self.line, .scoring = self.scoring };
    }
};

const TIME_BUFFER_SIZE: usize = 20;
pub const timeManager = struct {
    timeBuffer: [TIME_BUFFER_SIZE]timeDecision = undefined,
    len: usize = 0,
    currentIndex: usize = 0,
    searchStartTime: i64 = 0,

    pub fn startSearchTick(p_self: *timeManager) void {
        p_self.searchStartTime = std.time.milliTimestamp();
    }
    pub fn timeSinceStartMs(p_self: *timeManager) i64 {
        return std.time.milliTimestamp() - p_self.searchStartTime;
    }
    pub fn timeSinceStartSec(p_self: *timeManager) i64 {
        return p_self.timeSinceStartMs() / std.time.ms_per_s;
    }
    pub fn reset(p_self: *timeManager) void {
        p_self.len = 0;
        p_self.currentIndex = 0;
        p_self.searchStartTime = 0;
    }
    pub fn append(p_self: *timeManager, item: timeDecision) void {
        p_self.timeBuffer[p_self.currentIndex] = item;
        p_self.len = @min(p_self.len + 1, TIME_BUFFER_SIZE);
        p_self.currentIndex = (p_self.len + 1) % TIME_BUFFER_SIZE;
    }
    pub fn avg(p_self: *timeManager) f64 {
        if (p_self.len == 0) {
            return 0.0;
        }
        var acc: f64 = 0.0;
        for (0..p_self.len) |i| {
            acc += @floatFromInt(p_self.timeBuffer[i]);
        }
        return acc / (p_self.len);
    }
    pub fn isOvertimeSearching(p_self: *timeManager, remainingMsTime: i64) bool {
        const _remainTime: f64 = @floatFromInt(remainingMsTime);
        const maxTime: i64 = @intFromFloat(_remainTime * configl.SCHEDULER_MAX_TIME_FRCT);
        return (p_self.timeSinceStartMs() > maxTime);
    }
    pub fn isOvertimeCritical(p_self: *timeManager, remainingMsTime: i64) bool {
        const _remainTime: f64 = @floatFromInt(remainingMsTime);
        const maxTime: i64 = @intFromFloat(_remainTime * configl.SCHEDULER_CRITICAL_TIME_FRCT);
        return (p_self.timeSinceStartMs() > maxTime);
    }
};
pub const timeDecision = struct {
    time: i64 = 0,
    depth: u16 = 0,
    checked: bool = false,
};

// Exploration phase for an engine with d as the default depth
//
// Launch expl d - 1
//  Check time
//
// Launch expl d
//  Check time
//
//     ...
//
// Launch expl max d
//  Check time
//
// on Check time: check if _currentTime - _start is below the max time fraction allowed in config if not we return the current best sol found (ie the one for the previous exploration)
//
// if during a search the waiting thread of the scheduler notices the time being in the red, the scheduler should be allowed to interrupt the search
pub const scheduler = struct {
    timeM: timeManager = .{},
    p_engine: *enginel.engine = undefined,
    engineSet: bool = false,
    p_threadPack: *threadPackageArray = undefined,
    alloc: std.mem.Allocator = undefined,
    finalChoice: moveDecisionExt = .{},
    searchDepth: u16 = 0,
    searchIncrement: u16 = 0,
    turn: bool = true,
    canIncreaseDepth: bool = false,

    pub fn setEngine(p_self: *scheduler, p_engine: *enginel.engine) void {
        p_self.p_engine = p_engine;
        p_self.engineSet = true;
        p_self.alloc = p_engine.alloc;
        p_self.turn = p_engine.state.whiteToMove();
    }
    pub fn setThreadPack(p_self: *scheduler, p_pack: *threadPackageArray) void {
        p_self.p_threadPack = p_pack;
    }
    pub fn sendFinal(p_self: *scheduler) void {
        if (!p_self.engineSet) {
            @panic("engine not set");
        }
        const msg = std.fmt.allocPrint(p_self.alloc, "bestmove {s}", .{p_self.finalChoice.move.getStr()}) catch unreachable;
        defer p_self.alloc.free(msg);
        if (p_self.isDebugMode()) {
            std.debug.print("[DEBUG] sendFinal: final choice {s} with scoring: {d} at depth {d}\n", .{ p_self.finalChoice.move.getStr(), p_self.finalChoice.scoring, p_self.searchDepth + p_self.searchIncrement });
        }
        p_self.p_engine.respond(utilsl.trimStr(msg));
    }
    pub fn sendUpdate(p_self: *scheduler) void {
        const res = threadingl.getCombinedFromPack(p_self.p_threadPack);
        const n_nodes: i64 = @intCast(res.n_nodeExplored);
        const timeDelta = p_self.timeM.timeSinceStartMs();

        const msg = std.fmt.allocPrint(p_self.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d}", .{ @divFloor(n_nodes, (timeDelta + 1)) * 1000, n_nodes, res.n_hashRetrieve, hashl.hashTable.n_insertion }) catch {
            return;
        };
        defer p_self.alloc.free(msg);
        p_self.p_engine.respond(msg);
        return;
    }
    pub fn startSearch(p_self: *scheduler, depth: u16) !void {
        if (p_self.isDebugMode()) {
            std.debug.print("[DEBUG] startSearch: starting search at depth: {d}\n", .{depth});
        }
        std.debug.assert(depth != 0);
        threadingl.zeroThreadPackArray(p_self.p_threadPack);
        p_self.timeM.startSearchTick();
        const feat = getSearchFeatures(p_self.p_engine);

        for (0..p_self.p_threadPack.len) |thread_id| {
            p_self.p_threadPack.items(.threadHandle)[thread_id] = try std.Thread.spawn(.{}, alphaBetal.searchEntrypoint, .{ &p_self.p_threadPack.items(.chessState)[thread_id], &p_self.p_threadPack.items(.moves)[thread_id], &p_self.p_threadPack.items(._tInfo)[thread_id], depth, feat });
        }
    }
    pub fn getSearchStatus(p_self: *scheduler) searchStatus {
        var searcher = p_self.p_engine.searcher;
        if (searcher.interrupt) {
            return .INTERRUPTED;
        }
        searcher.endCounter = 0;
        for (0..p_self.p_threadPack.len) |i| {
            searcher.endCounter += @intFromBool(!p_self.p_threadPack.items(._tInfo)[i].running);
        }
        if (searcher.endCounter == p_self.p_threadPack.len) {
            return .FINISHED;
        }
        return .CONTINUE;
    }
    pub fn handleInterrupt(p_self: *scheduler) void {
        for (0..p_self.p_threadPack.len) |i| {
            p_self.p_threadPack.items(._tInfo)[i].running = false;
        }
        threadingl.joinOnThreadPack(p_self.p_threadPack);
    }
    pub fn entryPointSearch(p_self: *scheduler, depth: u16) void {
        if (p_self.canIncreaseDepth) {
            p_self.searchDepth = @min(depth, depth - 1);
        } else {
            p_self.searchDepth = depth;
        }

        p_self.startSearch(p_self.searchDepth) catch {
            p_self.p_engine.searcher.searching = false;
            std.debug.print("[ERROR] waitingLoop: Cant start search\n", .{});
            return;
        };
        p_self.waitingLoop();
    }
    pub fn extractBest(p_self: *scheduler) void {
        const res = threadingl.getCombinedFromPack(p_self.p_threadPack);
        p_self.finalChoice = res.currentBest.copy();
    }
    pub fn waitingLoop(p_self: *scheduler) void {
        p_self.searchIncrement = 0;
        p_self.p_engine.searcher.searching = true;
        while (true) {
            std.Thread.sleep(configl.INFO_TICKRATE_NS);
            p_self.sendUpdate();
            const stat = p_self.getSearchStatus();
            if (stat == .INTERRUPTED) {
                p_self.handleInterrupt();
                break;
            }
            if (stat == .FINISHED) {
                // need logic here wether to launch new search if time available
                p_self.timeM.append(.{ .time = p_self.timeM.timeSinceStartMs(), .checked = p_self.p_engine.state.isLegal(p_self.turn) });
                if (!p_self.canExtendSearch()) {
                    p_self.extractBest();
                    p_self.sendFinal();
                    p_self.commitNewSearchDepth();
                    break;
                }
                p_self.searchIncrement += 1;
                if (p_self.isDebugMode()) {
                    std.debug.print("[DEBUG] waitingLoop: Increasing the search depth\n", .{});
                }
                p_self.startSearch(p_self.searchDepth + p_self.searchIncrement) catch {
                    p_self.extractBest();
                    p_self.sendFinal();
                    p_self.commitNewSearchDepth();
                    break;
                };
            }
            if (stat == .CONTINUE) {
                if (p_self.timeM.isOvertimeCritical(p_self.timeRemaining()) and p_self.canIncreaseDepth) {
                    p_self.handleInterrupt();
                    p_self.searchIncrement = 0;

                    p_self.searchDepth = @min(p_self.searchDepth, p_self.searchDepth - 2);
                    p_self.searchDepth = @max(0, p_self.searchDepth);

                    if (p_self.isDebugMode()) {
                        std.debug.print("[DEBUG] waitingLoop: CRITICALY LOW TIME! RE LAUNCHING AT DEPTH - 2\n", .{});
                    }
                    p_self.startSearch(p_self.searchDepth) catch {
                        return;
                    };
                }
            }
        }
        p_self.p_engine.searcher.searching = false;
        // TODO FIX ME: UCI style thingy here
        p_self.engineSet = false;
    }
    pub fn commitNewSearchDepth(p_self: *scheduler) void {
        // saves the new depth for future use, ie make the search deeper and deeper as the game goes on
        if (!p_self.canIncreaseDepth) {
            return;
        }
        if (p_self.timeM.isOvertimeSearching(p_self.timeRemaining()) and (p_self.p_engine.searcher.config.depth != 0)) {
            p_self.p_engine.searcher.config.depth += p_self.searchIncrement;
            p_self.p_engine.options.depthLevel = @max(1, p_self.p_engine.options.depthLevel - 1);
            if (p_self.isDebugMode()) {
                std.debug.print("[DEBUG] commitNewSearchDepth: The loop took too long decreasing depth by one for next iter (new depth: {d})\n", .{p_self.p_engine.searcher.config.depth});
            }
        } else {
            p_self.p_engine.options.depthLevel += p_self.searchIncrement;
        }
    }
    pub fn timeRemaining(p_self: *scheduler) i64 {
        if (p_self.turn) {
            return p_self.p_engine.searcher.config.wtime;
        }
        return p_self.p_engine.searcher.config.btime;
    }
    pub fn canExtendSearch(p_self: *scheduler) bool {
        if (!p_self.canIncreaseDepth) {
            return false;
        }
        if (p_self.timeM.isOvertimeSearching(p_self.timeRemaining())) {
            return false;
        }
        const prevTime: i64 = p_self.timeM.timeSinceStartMs();
        const floatTime: f64 = @floatFromInt(p_self.timeRemaining());
        const maxTime: i64 = @intFromFloat(floatTime * configl.SCHEDULER_MAX_TIME_FRCT);
        if (((prevTime * configl.SCHEDULER_GROWTH_TIME_EST) < maxTime) and (p_self.searchIncrement < configl.SCHEDULER_MAX_DEPTH_INCREASE_PER_ITR)) {
            return true;
        }
        return false;
    }
    pub inline fn isDebugMode(p_self: *scheduler) bool {
        return p_self.p_engine.status.debugMode;
    }
};

pub fn dispatchUciGoCmd(p_engine: *enginel.engine, cmdBuffer: []const u8) bool {
    if (p_engine.searcher.config.type == .PERFT) {
        return perftl.dispatchUciPerftCmd(p_engine);
    }
    var moveArray: moveContainer = undefined;

    if (p_engine.searcher.config.searchMoves) {
        var _moveArray = chessl.getMoveListFromStr(&p_engine.state, cmdBuffer, p_engine.alloc) catch {
            return false;
        };
        defer _moveArray.deinit(p_engine.alloc);

        moveArray = movel.arrayListMoveToMoveContainer(&_moveArray);
    } else {
        moveArray = moveGenl.generateLegalMoves(&p_engine.state);
    }

    const dispatchThread = std.Thread.spawn(.{}, dispatchUciGoThreads, .{ p_engine, moveArray }) catch {
        return false;
    };
    p_engine.workingThreads.append(p_engine.alloc, dispatchThread) catch {
        return false;
    };

    return true;
}
pub fn dispatchUciGoThreads(p_engine: *enginel.engine, moveArray: movel.moveContainer) void {
    var searcher = &p_engine.searcher;

    const _nThread = @min(searcher.nThreads, moveArray.len);
    if (_nThread == 0) {
        @panic("No thread or no moves available");
    }
    if (p_engine.status.debugMode) {
        std.debug.print("[DEBUG] dispatchUciGoThreads: nthread info: searcher: {d}, movearray: {d}\n", .{ searcher.nThreads, moveArray.len });
    }

    var _moveArray = moveArray;
    var pack = threadingl.getThreadPackArray(p_engine.alloc, &p_engine.state, &_moveArray, _nThread) catch {
        std.debug.print("[ERROR] dispatchUciGoThreads: Cant init thread pack array\n", .{});
        return;
    };
    defer threadingl.freeThreadPackArray(p_engine.alloc, &pack);

    p_engine.searcher.searching = true;

    if (p_engine.status.debugMode) {
        searcher.printInfo();
    }
    var sched = &searcher.schedul;
    sched.setThreadPack(&pack);
    if (searcher.config.depth == 0) {
        if (p_engine.status.debugMode) {
            std.debug.print("[DEBUG] executeGoCmd: No depth found  in the cmd string using the default engine option \n", .{});
        }
        searcher.config.depth = p_engine.options.depthLevel;
    }
    sched.canIncreaseDepth = !p_engine.options.fixDepth;
    if (p_engine.status.debugMode) {
        if (sched.canIncreaseDepth) {
            std.debug.print("[DEBUG] executeGoCmd: scheduler can modify the depth of search\n", .{});
        } else {
            std.debug.print("[DEBUG] executeGoCmd: scheduler cannot modify the depth of search\n", .{});
        }
    }

    //TODO FIX ME
    sched.setEngine(p_engine);
    sched.entryPointSearch(searcher.config.depth);
}

pub fn main() void {
    @panic("");
}
