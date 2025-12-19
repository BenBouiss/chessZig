const std = @import("std");
const mainl = @import("main.zig");
const chess = @import("chess.zig");
const movel = @import("move.zig");
const benchmark = @import("benchmark.zig");
const moveGenl = @import("move_generation.zig");
const squarel = @import("square.zig");
const heuristicl = @import("heuristic.zig");
const utilsl = @import("utils.zig");
const hashl = @import("hashTable.zig");
const enginel = @import("engine.zig");
const configl = @import("config.zig");
const build_options = @import("build_options");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const typedMoveContainer = movel.typedMoveContainer;
const e_square = squarel.e_square;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
const GLOBAL_ALLOC = GPA.allocator();

const useHash = build_options.useHash;
const useDebug = build_options.useDebug;

const assert = std.debug.assert;

const e_simpleScore = enum(i64) { CheckMate = 9999, StaleMate = 0 };
pub const e_matchFlag = enum(u8) { Error, Continue, CheckMate, StaleMate, StaleMateRepetition };

pub const moveDecision = struct {
    move: IMove = .{},
    scoring: i64 = 0,
    timeTake: u64 = 0, //seconds
    pub fn invertScore(p_self: *moveDecision) void {
        p_self.scoring = -p_self.scoring;
    }
};
pub const moveDecisionExt = struct {
    move: IMove = .{},
    line: movel.matchMoveContainer = .{},
    scoring: i64 = 0,
    timeTake: u64 = 0, //seconds
    pub fn invertScore(p_self: *moveDecisionExt) void {
        p_self.scoring = -p_self.scoring;
    }
    pub fn isBetter(p_self: *moveDecisionExt, other: *moveDecisionExt) bool {
        return p_self.scoring > other.scoring;
    }
};

pub fn getScoreMaskFromTurn(color: chess.e_color) i8 {
    if (color == .WHITE) {
        return 1;
    }
    return -1;
}

pub fn explorationNDepthPerft(p_state: *chess.Board_state, depth: u8, batched: bool, p_res: *benchmark.benchmarkResult) u64 {
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
            p_res.n_hashRetrieve += @intCast(entry.moveAmount);
            return entry.moveAmount;
        }
    }
    var count: u64 = 0;
    for (0..fmoves.len) |i| {
        p_state.stack.push(&p_state.makeFrame());
        const move: IMove = fmoves.moves[i];

        _ = p_state.makeMoveUpdate(move);

        count += explorationNDepthPerft(p_state, depth - 1, batched, p_res);

        _ = p_state.undoMoveRestore();
        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);
    }
    if (comptime useHash) {
        const entry: hashl.Hash_entry = hashl.buildEntryFromPerftResult(p_state.key, depth, count);
        _ = hashl.hashTable.storeEntry(&entry);
    }
    return count;
}
pub fn explorationNDepthThreadStart(p_state: *chess.Board_state, depth: u8, nThread: u8, p_res: *benchmark.benchmarkResult, batched: bool) !void {
    var moves: moveContainer = moveGenl.moveGeneration(p_state);
    const fmoves = try moveGenl.filterMoveLegal(p_state, &moves);
    var fmoves_arr = try fmoves.convertToArrayList(GLOBAL_ALLOC);
    defer fmoves_arr.deinit(GLOBAL_ALLOC);
    var _nThread: usize = @intCast(nThread);
    if (_nThread == 0) {
        _nThread = try std.Thread.getCpuCount();
    }
    _nThread = utilsl.min(usize, fmoves.len, _nThread);

    var threadedMoves = try utilsl.cutArrayListEvenly(IMove, GLOBAL_ALLOC, fmoves_arr, _nThread);
    defer {
        for (threadedMoves.items) |*cell| {
            cell.deinit(GLOBAL_ALLOC);
        }
        threadedMoves.deinit(GLOBAL_ALLOC);
    }

    var arr_benchmarks = try p_res.duplicateNTimes(GLOBAL_ALLOC, _nThread);
    defer arr_benchmarks.free(GLOBAL_ALLOC);

    var arr_state = try p_state.duplicateNTimes(GLOBAL_ALLOC, _nThread);
    defer arr_state.free(GLOBAL_ALLOC);

    var threads: []std.Thread = try GLOBAL_ALLOC.alloc(std.Thread, _nThread);
    defer GLOBAL_ALLOC.free(threads);

    for (0.._nThread) |thread_id| {
        threads[thread_id] = try std.Thread.spawn(.{}, perftWorkerJob, .{ &arr_state.array[thread_id], depth, &arr_benchmarks.array[thread_id], &threadedMoves.items[thread_id], batched });
    }
    for (0.._nThread) |thread_id| {
        threads[thread_id].join();
    }
    p_res.* = arr_benchmarks.combine();
    return;
}

pub fn perftWorkerJob(p_state: *chess.Board_state, depth: u8, p_res: *benchmark.benchmarkResult, p_startingMoves: *std.ArrayList(IMove), batched: bool) void {
    for (0..p_startingMoves.items.len) |i| {
        p_state.stack.push(&p_state.makeFrame());
        const move = p_startingMoves.items[i];

        _ = p_state.makeMoveUpdate(move);

        p_res.n_nodes += explorationNDepthPerft(p_state, depth - 1, batched, p_res);
        _ = p_state.undoMoveRestore();

        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);
    }
}

pub const uciSearcher = struct {
    config: enginel.goArgStruct = .{},
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
pub const threadInfo = struct {
    currentBest: moveDecisionExt = .{},
    currentMove: moveDecisionExt = .{},
    n_nodeExplored: u64 = 0,
    n_hashRetrieve: u64 = 0,
    currentMoveNumber: u64 = 0,
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

pub fn dispatchUciGoCmd(p_engine: *enginel.engine, cmdBuffer: []const u8) bool {
    var moveArray: moveContainer = undefined;
    //if (p_engine.searcher.config.type == .EVAL) {
    //    const score = heuristicl.simpleHeuristic(&p_engine.state);
    //    const msg = std.fmt.allocPrint(p_engine.alloc, "eval: {d}", .{score}) catch unreachable;
    //    p_engine.respond(msg);
    //    return true;
    //}
    if (p_engine.searcher.config.searchMoves) {
        var _moveArray = chess.getMoveListFromStr(&p_engine.state, cmdBuffer, p_engine.alloc) catch {
            return false;
        };
        defer _moveArray.deinit(p_engine.alloc);
        if (p_engine.status.debugMode) {
            std.debug.print("[DEBUG] dispatchUciGoCmd: searchmoves moves found, len = {d}\n", .{_moveArray.items.len});
            for (0.._moveArray.items.len) |i| {
                std.debug.print("{s}, ", .{_moveArray.items[i].getStr()});
            }
            std.debug.print("\n", .{});
        }
        moveArray = movel.arrayListMoveToMoveContainer(&_moveArray);
    } else {
        moveArray = moveGenl.generateLegalMoves(&p_engine.state);
    }
    if (p_engine.status.debugMode) {
        std.debug.print("[DEBUG] dispatchUciGoCmd: Move found to study: ", .{});
        moveArray.print();
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
    const searcher = p_engine.searcher;
    const _nThread = @min(searcher.nThreads, moveArray.len);
    if (_nThread == 0) {
        @panic("No thread or no moves available");
    }
    if (p_engine.status.debugMode) {
        std.debug.print("[DEBUG] dispatchUciGoThreads: nthread info: searcher: {d}, movearray: {d}\n", .{ searcher.nThreads, moveArray.len });
    }

    var threadedMoves = moveArray.cutEvenly(p_engine.alloc, _nThread) catch {
        std.debug.print("[ERROR] dispatchUciGoThreads: move container init\n", .{});
        return;
    };

    defer {
        for (threadedMoves.items) |*cell| {
            cell.deinit(p_engine.alloc);
        }
        threadedMoves.deinit(p_engine.alloc);
    }
    var arr_threadInfo: threadInfo_container = threadInfo_container.init(p_engine.alloc, _nThread) catch {
        std.debug.print("ERROR threadInfo container init\n", .{});
        return;
    };

    var threads: []std.Thread = p_engine.alloc.alloc(std.Thread, _nThread) catch {
        std.debug.print("ERROR thread init\n", .{});
        return;
    };
    defer p_engine.alloc.free(threads);
    var arr_state = p_engine.state.duplicateNTimes(p_engine.alloc, _nThread) catch {
        std.debug.print("ERROR board state container init\n", .{});
        return;
    };
    defer arr_state.free(p_engine.alloc);

    p_engine.searcher.searching = true;

    const feats: perftSearchFeatures = .{ .useBatched = searcher.config.useBatched, .useHash = p_engine.options.useHashTable };
    if (p_engine.status.debugMode) {
        searcher.printInfo();
        if (feats.useHash) {
            std.debug.print("[DEBUG] dispatchUciGoThreads: use hash is enabled! \n", .{});
        }
    }
    for (0.._nThread) |thread_id| {
        if (searcher.config.type == .PERFT) {
            threads[thread_id] = std.Thread.spawn(.{}, threadUciPerftEntrypoint, .{ &arr_state.array[thread_id], &threadedMoves.items[thread_id], &arr_threadInfo.items[thread_id], searcher.config.depth, feats }) catch unreachable;
        } else {
            threads[thread_id] = std.Thread.spawn(.{}, threadUciEntrypointLine, .{ &arr_state.array[thread_id], &threadedMoves.items[thread_id], &arr_threadInfo.items[thread_id], searcher.config.depth }) catch unreachable;
        }
    }
    _ = waitThreadFinish(p_engine, &arr_threadInfo, &threads) catch {
        std.debug.print("ERROR wait thread\n", .{});
        return;
    };
}

pub fn waitThreadFinish(p_engine: *enginel.engine, p_arr: *threadInfo_container, p_threads: *[]std.Thread) !bool {
    var _start: u64 = 0;
    var _end: u64 = 0;
    _start = @intCast(std.time.milliTimestamp());
    while (!p_engine.searcher.interrupt and p_engine.searcher.endCounter != p_engine.searcher.nThreads) {
        std.Thread.sleep(configl.INFO_TICKRATE_NS);
        const res = p_arr.combine();
        _end = @intCast(std.time.milliTimestamp());
        const msg = std.fmt.allocPrint(p_engine.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d}", .{ @divFloor(res.n_nodeExplored, (_end - _start + 1)) * 1000, res.n_nodeExplored, res.n_hashRetrieve, hashl.hashTable.n_insertion }) catch {
            continue;
        };
        defer p_engine.alloc.free(msg);
        p_engine.respond(msg);
        p_engine.searcher.endCounter = 0;
        for (0..p_arr.len) |i| {
            p_engine.searcher.endCounter += @intFromBool(!p_arr.items[i].running);
        }
    }
    p_engine.searcher.searching = false;
    if (p_engine.searcher.endCounter != p_engine.searcher.nThreads) {
        for (0..p_arr.len) |i| {
            p_arr.items[i].running = false;
        }
        for (0..p_threads.len) |thread_id| {
            p_threads.*[thread_id].join();
        }
    } else {
        const bestMove = p_arr.getBestMove();
        p_engine.searcher.bestMove = bestMove;

        const msg = std.fmt.allocPrint(p_engine.alloc, "bestmove {s}", .{bestMove.move.getStr()}) catch unreachable;
        p_engine.respond(utilsl.trimStr(msg));
        defer p_engine.alloc.free(msg);
        if (p_engine.searcher.config.type == .EVAL) {
            const msg_score = std.fmt.allocPrint(p_engine.alloc, "score {d} at depth {d}", .{ bestMove.scoring, p_engine.searcher.config.depth }) catch unreachable;
            defer p_engine.alloc.free(msg_score);
            p_engine.respond(msg_score);
        }
        if (p_engine.status.debugMode) {
            var lineStr = try bestMove.line.getLineString(p_engine.alloc);
            const msg_score = std.fmt.allocPrint(p_engine.alloc, "line found: {s}", .{lineStr._slice()}) catch unreachable;
            defer p_engine.alloc.free(msg_score);
            defer lineStr.free(p_engine.alloc);
            p_engine.respond(msg_score);
        }
    }
    defer p_arr.free(p_engine.alloc);
    return true;
}

pub fn threadUciEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16) void {
    p_info.running = true;

    for (0..p_startingMoves.items.len) |i| {
        p_state.stack.push(&p_state.makeFrame());
        const move = p_startingMoves.items[i];

        _ = p_state.makeMoveUpdate(move);

        var decision = searchUciDepth(p_state, p_info, depth - 1);

        decision.invertScore();

        _ = p_state.undoMoveRestore();

        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);
        if (i == 0 or p_info.currentBest.scoring < decision.scoring) {
            p_info.currentBest = decision;
            p_info.currentBest.move = move.copy();
        }
    }
    p_info.running = false;
}

const perftSearchFeatures = struct {
    useBatched: bool = false,
    useHash: bool = false,
};
pub fn threadUciPerftEntrypoint(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, feats: perftSearchFeatures) void {
    p_info.running = true;
    if (depth == 0) {
        p_info.running = false;
        p_info.n_nodeExplored += 1;
        return;
    }

    for (0..p_startingMoves.items.len) |i| {
        p_state.stack.push(&p_state.makeFrame());
        const move = p_startingMoves.items[i];

        _ = p_state.makeMoveUpdate(move);

        _ = perftUciDepth(p_state, p_info, @intCast(depth - 1), feats);

        _ = p_state.undoMoveRestore();

        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);
    }
    p_info.running = false;
}
pub fn threadUciEntrypointLine(p_state: *chess.Board_state, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16) void {
    p_info.running = true;

    for (0..p_startingMoves.items.len) |i| {
        p_state.stack.push(&p_state.makeFrame());
        const move = p_startingMoves.items[i];
        var currentDecision: moveDecisionExt = .{};
        _ = p_state.makeMoveUpdate(move);

        _ = currentDecision.line.append(move, p_state.key);

        assert(currentDecision.line.len == 1);

        var decision = searchUciDepthLine(p_state, p_info, depth - 1, &currentDecision);

        decision.invertScore();

        _ = p_state.undoMoveRestore();

        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);

        //var lineStr = decision.line.getLineString(GLOBAL_ALLOC) catch unreachable;
        //defer lineStr.free(GLOBAL_ALLOC);
        //std.debug.print("[DEBUG] threadUciEntrypointLine: for move: {s}, line found: {s} scoring: {d}, line length: {d}\n", .{ move.getStr(), lineStr._slice(), decision.scoring, decision.line.len });
        if (i == 0 or p_info.currentBest.scoring < decision.scoring) {
            p_info.currentBest = decision;
            p_info.currentBest.move = move;
        }
    }
    p_info.running = false;
}
pub fn searchUciDepthLine(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16, currentLine: *moveDecisionExt) moveDecisionExt {
    const color_mask: i8 = getScoreMaskFromTurn(p_state.turn);
    if (depth <= 0 or !p_info.running) {
        p_info.n_nodeExplored += 1;
        const score = color_mask * heuristicl.pastHeuristic(p_state);
        //const score = color_mask * heuristicl.simpleHeuristic(p_state);
        currentLine.scoring = score;
        return currentLine.*;
    }
    if (p_state.isStaleMateRepetition()) {
        currentLine.scoring = heuristicl.simpleStalemateScore;
        return currentLine.*;
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    const turn = p_state.turn;
    var final_decision: moveDecisionExt = .{};
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];
        p_state.stack.push(&p_state.makeFrame());
        _ = p_state.makeMoveUpdate(move);

        _ = currentLine.line.append(move, p_state.key);

        var decision = searchUciDepthLine(p_state, p_info, depth - 1, currentLine);
        decision.invertScore();

        _ = p_state.undoMoveRestore();
        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);

        if (i == 0 or final_decision.scoring < decision.scoring) {
            final_decision.scoring = decision.scoring;
            final_decision.line.merge(&decision.line);
            //final_decision.line = decision.line;
        }
        currentLine.line.popMoveInplace();
    }
    if (fmoves.len == 0) {
        final_decision.line.merge(&currentLine.line);
        //final_decision.line = currentLine.line;
        if (!p_state.isLegal(turn)) {
            final_decision.scoring = -(@intFromEnum(e_simpleScore.CheckMate) + depth);
        } else {
            final_decision.scoring = @intFromEnum(e_simpleScore.StaleMate);
        }
    }
    return final_decision;
}
pub fn searchUciDepth(p_state: *chess.Board_state, p_info: *threadInfo, depth: u16) moveDecisionExt {
    const color_mask: i8 = getScoreMaskFromTurn(p_state.turn);
    if (depth <= 0 or !p_info.running) {
        p_info.n_nodeExplored += 1;
        const lastMove = p_state.getLastMove();
        const score = color_mask * heuristicl.simpleHeuristic(p_state);
        const retMove: moveDecisionExt = .{ .move = lastMove, .scoring = score };
        return retMove;
    }
    if (p_state.isStaleMateRepetition()) {
        const retMove: moveDecisionExt = .{ .move = p_state.getLastMove(), .scoring = heuristicl.simpleStalemateScore };

        return retMove;
    }

    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    var final_decision: moveDecisionExt = .{};
    const turn = p_state.turn;
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];
        p_state.stack.push(&p_state.makeFrame());
        _ = p_state.makeMoveUpdate(move);

        var decision = searchUciDepth(p_state, p_info, depth - 1);

        decision.invertScore();

        _ = p_state.undoMoveRestore();
        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);

        if (i == 0 or final_decision.scoring < decision.scoring) {
            final_decision.move = move.copy();
            final_decision.scoring = decision.scoring;
        }
    }
    if (fmoves.len == 0) {
        if (!p_state.isLegal(turn)) {
            final_decision.scoring = -@intFromEnum(e_simpleScore.CheckMate);
        } else {
            final_decision.scoring = @intFromEnum(e_simpleScore.StaleMate);
        }
    }
    return final_decision;
}

pub fn perftUciDepth(p_state: *chess.Board_state, p_info: *threadInfo, depth: u8, feats: perftSearchFeatures) u64 {
    if (depth <= 0 or !p_info.running) {
        p_info.n_nodeExplored += 1;
        return 1;
    }

    if (p_state.isStaleMateRepetition()) {
        p_info.n_nodeExplored += 1;
        return 1;
    }
    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    if (feats.useBatched and depth == 1) {
        p_info.n_nodeExplored += fmoves.len;
        return fmoves.len;
    }
    if (feats.useHash) {
        const entry = hashl.getEntryFromPerft(p_state.key, depth);
        if (entry.valid) {
            p_info.n_hashRetrieve += @intCast(entry.moveAmount);

            p_info.n_nodeExplored += entry.moveAmount;
            return entry.moveAmount;
        }
    }

    var count: u64 = 0;
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];
        p_state.stack.push(&p_state.makeFrame());
        _ = p_state.makeMoveUpdate(move);

        count += perftUciDepth(p_state, p_info, depth - 1, feats);

        _ = p_state.undoMoveRestore();
        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);
    }
    if (feats.useHash) {
        const entry: hashl.Hash_entry = hashl.buildEntryFromPerftResult(p_state.key, depth, count);
        _ = hashl.hashTable.storeEntry(&entry);
    }

    return count;
}
