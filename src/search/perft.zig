const std = @import("std");
const mainl = @import("../main.zig");
const chess = @import("../chess.zig");
const movel = @import("../move.zig");
const benchmarkl = @import("../benchmark.zig");
const moveGenl = @import("../move_generation.zig");
const squarel = @import("../square.zig");
const heuristicl = @import("../heuristic.zig");
const utilsl = @import("../utils.zig");
const hashl = @import("../hashTable.zig");
const enginel = @import("../engine.zig");
const configl = @import("../config.zig");

const threadingl = @import("threading.zig");
const alphaBetal = @import("alphaBeta.zig");

const build_options = @import("build_options");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const typedMoveContainer = movel.typedMoveContainer;
const e_square = squarel.e_square;
const scoreType = heuristicl.scoreType;
const engine = enginel.engine;
const threadPackageArray = threadingl.threadPackageArray;
const threadInfo = threadingl.threadInfo;
const benchmarkResult = benchmarkl.benchmarkResult;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
const GLOBAL_ALLOC = GPA.allocator();

const useHash = build_options.useHash;
const useDebug = build_options.useDebug;

const assert = std.debug.assert;

pub fn dispatchUciPerftCmd(p_engine: *enginel.engine) bool {
    const dispatchThread = std.Thread.spawn(.{}, dispatchUciPerftThreads, .{p_engine}) catch {
        return false;
    };
    p_engine.workingThreads.append(p_engine.alloc, dispatchThread) catch {
        return false;
    };
    return true;
}

pub fn dispatchUciPerftThreads(p_engine: *enginel.engine) void {
    var moveArray = moveGenl.generateLegalMoves(&p_engine.state);
    const searcher = p_engine.searcher;
    const _nThread: u32 = @min(searcher.nThreads, moveArray.len);
    if (_nThread == 0) {
        @panic("No thread or no moves available");
    }
    var pack = threadingl.getThreadPackArray(p_engine.alloc, &p_engine.state, &moveArray, _nThread) catch {
        @panic("Cant init thread pack array");
    };
    defer threadingl.freeThreadPackArray(p_engine.alloc, &pack);

    p_engine.searcher.searching = true;

    const feats: perftSearchFeatures = .{ .useBatched = searcher.config.useBatched, .useHash = p_engine.options.useHashTable };
    if (p_engine.status.debugMode) {
        searcher.printInfo();
        if (feats.useHash) {
            std.debug.print("[DEBUG] dispatchUciPerftThreads: use hash is enabled! \n", .{});
        }
    }
    _ = dispatchPerftPackage(p_engine, &pack, searcher.config.depth, feats);
    _ = waitThreadFinish(p_engine, &pack) catch {
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
pub fn waitThreadFinish(p_engine: *engine, p_threadPack: *threadPackageArray) !bool {
    const _start: u64 = @intCast(std.time.milliTimestamp());
    while (!p_engine.searcher.interrupt and p_engine.searcher.endCounter != p_engine.searcher.nThreads) {
        std.Thread.sleep(configl.INFO_TICKRATE_NS);
        const res = threadingl.getCombinedFromPack(p_threadPack);
        const _end: u64 = @intCast(std.time.milliTimestamp());
        const msg = std.fmt.allocPrint(p_engine.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d}", .{ @divFloor(res.searchStat.n_nodeExplored, (_end - _start + 1)) * 1000, res.searchStat.n_nodeExplored, res.searchStat.n_hashRetrieve, hashl.hashTable.n_insertion }) catch {
            continue;
        };
        defer p_engine.alloc.free(msg);
        p_engine.respond(msg);
        p_engine.searcher.endCounter = 0;
        for (0..p_threadPack.len) |i| {
            p_engine.searcher.endCounter += @intFromBool(!p_threadPack.items(._tInfo)[i].working);
        }
    }
    if (p_engine.status.debugMode) {
        std.debug.print("[DEBUG] waitThreadFinish: exiting\n", .{});
    }
    p_engine.searcher.searching = false;
    if (p_engine.searcher.endCounter != p_engine.searcher.nThreads) {
        for (0..p_threadPack.len) |i| {
            p_threadPack.items(._tInfo)[i].alive = false;
        }
        threadingl.joinOnThreadPack(p_threadPack);
    }
    return true;
}

const perftSearchFeatures = struct {
    useBatched: bool = false,
    useHash: bool = false,
};

pub fn perftUciEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, feats: perftSearchFeatures) void {
    p_info.working = true;
    defer p_info.working = false;
    defer p_info.alive = false;

    if (depth == 0) {
        p_info.searchStat.n_nodeExplored += 1;
        return;
    }
    for (0..p_startingMoves.items.len) |i| {
        const move = p_startingMoves.items[i];

        _ = p_state.makeMove(move);

        _ = perftUciDepth(p_state, p_info, @intCast(depth - 1), feats);

        _ = p_state.undoMove();
    }
}
pub fn perftUciDepth(p_state: *chess.Board_state, p_info: *threadInfo, depth: u8, feats: perftSearchFeatures) u64 {
    if (depth <= 0 or !p_info.alive) {
        p_info.searchStat.n_nodeExplored += 1;
        return 1;
    }

    if (p_state.isStaleMateRepetition()) {
        p_info.searchStat.n_nodeExplored += 1;
        return 1;
    }
    //var fmoves: moveContainer = undefined;
    //fmoves.len = 0;
    const fmoves = moveGenl.generateLegalMoves(p_state);

    if (feats.useBatched and depth == 1) {
        p_info.searchStat.n_nodeExplored += fmoves.len;
        return fmoves.len;
    }
    if (feats.useHash) {
        const entry = hashl.getEntryFromPerft(p_state.key, depth);
        if (entry.valid) {
            p_info.searchStat.n_hashRetrieve += @intCast(entry.moveA());

            p_info.searchStat.n_nodeExplored += entry.moveA();
            return entry.moveA();
        }
    }

    var count: u64 = 0;
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];
        _ = p_state.makeMove(move);

        count += perftUciDepth(p_state, p_info, depth - 1, feats);

        _ = p_state.undoMove();
    }
    if (feats.useHash) {
        const entry: hashl.Hash_entry = hashl.buildEntryFromPerftResult(p_state.key, depth, count);
        _ = hashl.hashTable.storeEntry(&entry);
    }

    return count;
}

// non uci depth
//

pub fn perftThreadStart(p_state: *chess.Board_state, depth: u8, nThread: u8, batched: bool) !threadInfo {
    var moves = moveGenl.generateLegalMoves(p_state);
    var _nThread: usize = @intCast(nThread);
    if (_nThread == 0) {
        _nThread = try std.Thread.getCpuCount();
    }
    _nThread = utilsl.min(usize, moves.len, _nThread);
    var pack = threadingl.getThreadPackArray(GLOBAL_ALLOC, p_state, &moves, @intCast(_nThread)) catch {
        @panic("Cant init thread pack array");
    };
    defer threadingl.freeThreadPackArray(GLOBAL_ALLOC, &pack);

    for (0..pack.items(._tInfo).len) |thread_id| {
        pack.items(.threadHandle)[thread_id] = try std.Thread.spawn(.{}, perftWorkerJob, .{ &pack.items(.chessState)[thread_id], depth, &pack.items(._tInfo)[thread_id], &pack.items(.moves)[thread_id], batched });
    }
    threadingl.joinOnThreadPack(&pack);
    return threadingl.getCombinedFromPack(&pack);
}
pub fn perftWorkerJob(p_state: *chess.Board_state, depth: u8, p_info: *threadInfo, p_startingMoves: *std.ArrayList(IMove), batched: bool) void {
    for (0..p_startingMoves.items.len) |i| {
        const move = p_startingMoves.items[i];
        _ = p_state.makeMove(move);
        p_info.searchStat.n_nodeExplored += explorationNDepthPerft(p_state, depth - 1, batched, p_info);
        _ = p_state.undoMove();
    }
}
pub fn explorationNDepthPerft(p_state: *chess.Board_state, depth: u8, batched: bool, p_info: *threadInfo) u64 {
    if (depth <= 0) {
        return 1;
    }
    if (p_state.isStaleMateRepetition()) {
        return 1;
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    if (depth == 1 and batched) {
        return fmoves.len;
    }
    if (comptime useHash) {
        const entry = hashl.getEntryFromPerft(p_state.key, depth);
        if (entry.valid) {
            p_info.searchStat.n_hashRetrieve += @intCast(entry.moveA());
            return entry.moveA();
        }
    }
    var count: u64 = 0;
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];

        _ = p_state.makeMove(move);
        count += explorationNDepthPerft(p_state, depth - 1, batched, p_info);
        _ = p_state.undoMove();
    }
    if (comptime useHash) {
        const entry: hashl.Hash_entry = hashl.buildEntryFromPerftResult(p_state.key, depth, count);
        _ = hashl.hashTable.storeEntry(&entry);
    }
    return count;
}
pub fn perft_debug_loop(p_state: *chess.Board_state, depth: u8, batched: bool, p_res: *benchmarkResult) u64 {
    if (depth <= 0) {
        p_res.addNode(&p_state.getLastMove());
        return 1;
    }
    if (p_state.isStaleMateRepetition()) {
        return 1;
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    if (depth == 1 and batched) {
        return fmoves.len;
    }
    if (comptime useHash) {
        const entry = hashl.getEntryFromPerft(p_state.key, depth);
        if (entry.valid) {
            p_res.searchStat.n_hashRetrieve += @intCast(entry.moveA());
            return entry.moveA();
        }
    }
    var count: u64 = 0;
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];

        _ = p_state.makeMove(move);
        count += perft_debug_loop(p_state, depth - 1, batched, p_res);
        _ = p_state.undoMove();
    }
    if (comptime useHash) {
        const entry: hashl.Hash_entry = hashl.buildEntryFromPerftResult(p_state.key, depth, count);
        _ = hashl.hashTable.storeEntry(&entry);
    }
    return count;
}
