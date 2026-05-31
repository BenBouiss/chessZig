const std = @import("std");
const mainl = @import("../main.zig");
const movel = @import("../move.zig");
const moveGenl = @import("../move_generation.zig");
const hashl = @import("../hashTable.zig");
const enginel = @import("../engine.zig");
const configl = @import("../config.zig");
const timel = @import("../time.zig");
const boardl = @import("../board.zig");

const threadingl = @import("threading.zig");
const alphaBetal = @import("alphaBeta.zig");

const IMove = movel.IMove;
const engine = enginel.engine;
const threadPackageArray = threadingl.threadPackageArray;
const threadInfo = threadingl.threadInfo;

pub fn dispatchUciPerftCmd(p_engine: *enginel.engine, config: enginel.goArgStruct) bool {
    const dispatchThread = std.Thread.spawn(.{}, dispatchUciPerftThreads, .{ p_engine, config }) catch {
        return false;
    };
    p_engine.workingThreads.append(p_engine.alloc, dispatchThread) catch {
        return false;
    };
    return true;
}

pub fn dispatchUciPerftThreads(p_engine: *enginel.engine, config: enginel.goArgStruct) void {
    var moveArray = moveGenl.generateLegalMoves(&p_engine.state);
    const _nThread: u32 = @min(p_engine.options.nThreads, moveArray.len);
    if (_nThread == 0) {
        @panic("No thread or no moves available");
    }
    var pack = threadingl.getThreadPackArray(p_engine.alloc, &p_engine.state, &moveArray, _nThread) catch {
        @panic("Cant init thread pack array");
    };
    defer threadingl.freeThreadPackArray(p_engine.alloc, &pack);

    p_engine.status.benchmarking = true;
    defer p_engine.status.benchmarking = false;
    p_engine.searcher.searching = true;

    const feats: perftSearchFeatures = .{ .useBatched = config.useBatched, .useHash = p_engine.options.useHashTable };
    if (p_engine.status.debugMode) {
        if (feats.useHash) {
            std.debug.print("[DEBUG] dispatchUciPerftThreads: use hash is enabled! \n", .{});
        }
    }
    _ = dispatchPerftPackage(p_engine, &pack, config.depth, feats);
    _ = waitThreadFinish(p_engine, &pack, config) catch {
        std.debug.print("[ERROR] wait thread\n", .{});
        return;
    };
}

fn dispatchPerftPackage(p_engine: *engine, p_threadPack: *threadPackageArray, depth: u16, feats: perftSearchFeatures) bool {
    const _nThread: usize = p_threadPack.len;

    for (0.._nThread) |thread_id| {
        if (p_engine.status.debugMode) {
            std.debug.print("[DEBUG] dispatchPerftPackage: Launching thread n° {d}, depth: {d}\n", .{ thread_id, depth });
        }
        p_threadPack.items(._tInfo)[thread_id].working = true;
        p_threadPack.items(._tInfo)[thread_id].alive = true;
        p_threadPack.items(.threadHandle)[thread_id] = std.Thread.spawn(.{}, perftUciEntrypoint, .{ &p_threadPack.items(.chessState)[thread_id], &p_threadPack.items(.moves)[thread_id], &p_threadPack.items(._tInfo)[thread_id], depth, feats }) catch {
            std.debug.print("[ERROR] dispatchPerftPackage: thread n° {d}\n", .{thread_id});
            return false;
        };
    }
    return true;
}
pub fn waitThreadFinish(p_engine: *engine, p_threadPack: *threadPackageArray, config: enginel.goArgStruct) !bool {
    var sw: timel.stopWatch = .{};
    sw.startTimeTick();
    var endCounter: usize = 0;
    while (!p_engine.searcher.interrupt and endCounter != p_engine.options.nThreads) {
        try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.INFO_TICKRATE_NS) }, .real);
        const res = threadingl.getCombinedFromPack(p_threadPack);
        const msg = std.fmt.allocPrint(p_engine.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d}", .{ @divFloor(res.searchStat.n_nodeExplored, @as(u64, @intCast(sw.timeSinceStartMs() + 1))) * 1000, res.searchStat.n_nodeExplored, res.searchStat.n_hashRetrieve, hashl.hashTable.stat.insertion }) catch {
            continue;
        };
        defer p_engine.alloc.free(msg);
        p_engine.respond(msg);
        endCounter = 0;
        for (0..p_threadPack.len) |i| {
            endCounter += @intFromBool(!p_threadPack.items(._tInfo)[i].working);
        }
    }
    if (p_engine.status.debugMode) {
        std.debug.print("[DEBUG] waitThreadFinish: exiting\n", .{});
    }
    p_engine.searcher.searching = false;
    if (endCounter != p_engine.options.nThreads) {
        for (0..p_threadPack.len) |i| {
            p_threadPack.items(._tInfo)[i].alive = false;
        }
        threadingl.joinOnThreadPack(p_threadPack);
    }

    const res = threadingl.getCombinedFromPack(p_threadPack);
    const msg = std.fmt.allocPrint(p_engine.alloc, "info depth: {d} nodes {d} retrieved: {d} stored: {d}", .{ config.depth, res.searchStat.n_nodeExplored, res.searchStat.n_hashRetrieve, hashl.hashTable.stat.insertion }) catch {
        return true;
    };
    defer p_engine.alloc.free(msg);
    p_engine.respond(msg);
    return true;
}

const perftSearchFeatures = struct {
    useBatched: bool = false,
    useHash: bool = false,
};

pub fn perftUciEntrypoint(p_state: *boardl.boardState, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, feats: perftSearchFeatures) void {
    p_info.working = true;
    defer p_info.working = false;
    defer p_info.alive = false;

    if (depth == 0) {
        p_info.searchStat.n_nodeExplored += 1;
        return;
    }
    const f: boardl.boardFrame = .copy(p_state);
    for (0..p_startingMoves.items.len) |i| {
        const move = p_startingMoves.items[i];

        p_state.makeMovePerft(move);

        _ = perftUciDepth(p_state, p_info, @intCast(depth - 1), feats);

        p_state.undoMove();
        p_state.frame = f;
    }
}
pub fn perftUciDepth(p_state: *boardl.boardState, p_info: *threadInfo, depth: u8, feats: perftSearchFeatures) u64 {
    if (depth <= 0 or !p_info.alive) {
        p_info.searchStat.n_nodeExplored += 1;
        return 1;
    }

    if (p_state.isStaleMateRepetition()) {
        p_info.searchStat.n_nodeExplored += 1;
        return 1;
    }

    const fmoves = moveGenl.generateLegalMoves(p_state);

    if (feats.useBatched and depth == 1) {
        p_info.searchStat.n_nodeExplored += fmoves.len;
        return fmoves.len;
    }
    var writer: hashl.hashWriter = .{};
    if (feats.useHash) {
        const res = hashl.hashTable.probePerft(p_state.frame.key.code, depth);
        writer = res.writer;
        if (res.entry) |entry| {
            p_info.searchStat.n_hashRetrieve += @intCast(entry.moveA());
            p_info.searchStat.n_nodeExplored += entry.moveA();
            return entry.moveA();
        }
        //const entry = hashl.getEntryFromPerft(p_state.frame.key, depth);
        //if (entry) |_entry| {
        //    p_info.searchStat.n_hashRetrieve += @intCast(_entry.moveA());
        //    p_info.searchStat.n_nodeExplored += _entry.moveA();
        //    return _entry.moveA();
        //}
    }

    var count: u64 = 0;

    const f: boardl.boardFrame = .copy(p_state);
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];
        p_state.makeMovePerft(move);

        count += perftUciDepth(p_state, p_info, depth - 1, feats);

        p_state.undoMove();
        p_state.frame = f;
    }
    if (feats.useHash) {
        const entry: hashl.Hash_entry = hashl.buildEntryFromPerftResult(p_state.frame.key, depth, count);
        writer.write(entry, .perft);
        //_ = hashl.hashTable.storeEntry(entry, p_state.frame.key.code);
    }

    return count;
}

// non uci depth
//

pub fn perftThreadStart(p_state: *boardl.boardState, alloc: std.mem.Allocator, depth: u8, nThread: u8, batched: bool) !threadInfo {
    var moves = moveGenl.generateLegalMoves(p_state);
    var _nThread: usize = @intCast(nThread);
    if (_nThread == 0) {
        _nThread = try std.Thread.getCpuCount();
    }
    _nThread = @min(moves.len, _nThread);
    var pack = threadingl.getThreadPackArray(alloc, p_state, &moves, @intCast(_nThread)) catch {
        @panic("Cant init thread pack array");
    };
    defer threadingl.freeThreadPackArray(alloc, &pack);

    for (0..pack.items(._tInfo).len) |thread_id| {
        pack.items(.threadHandle)[thread_id] = try std.Thread.spawn(.{}, perftWorkerJob, .{ &pack.items(.chessState)[thread_id], depth, &pack.items(._tInfo)[thread_id], &pack.items(.moves)[thread_id], batched });
    }
    threadingl.joinOnThreadPack(&pack);
    return threadingl.getCombinedFromPack(&pack);
}
pub fn perftWorkerJob(p_state: *boardl.boardState, depth: u8, p_info: *threadInfo, p_startingMoves: *std.ArrayList(IMove), batched: bool) void {
    const f: boardl.boardFrame = .copy(p_state);
    for (0..p_startingMoves.items.len) |i| {
        const move = p_startingMoves.items[i];
        _ = p_state.makeMovePerft(move);
        p_info.searchStat.n_nodeExplored += explorationNDepthPerft(p_state, depth - 1, batched, p_info);
        _ = p_state.undoMove();
        p_state.frame = f;
    }
}
pub fn explorationNDepthPerft(p_state: *boardl.boardState, depth: u8, batched: bool, p_info: *threadInfo) u64 {
    if (depth <= 0) {
        return 1;
    }
    if (p_state.isStaleMateRepetition()) {
        return 1;
    }

    const fmoves: movel.moveContainer = moveGenl.generateLegalMoves(p_state);
    if (depth == 1 and batched) {
        return fmoves.len;
    }

    var count: u64 = 0;
    const f: boardl.boardFrame = .copy(p_state);
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];
        _ = p_state.makeMovePerft(move);
        count += explorationNDepthPerft(p_state, depth - 1, batched, p_info);
        _ = p_state.undoMove();
        p_state.frame = f;
    }
    return count;
}
