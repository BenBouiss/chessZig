const std = @import("std");
const chess = @import("chess.zig");
const movel = @import("move.zig");
const moveGenl = @import("move_generation.zig");
const heuristicl = @import("heuristic.zig");
const utilsl = @import("utils.zig");
const hashl = @import("hashTable.zig");
const enginel = @import("engine.zig");
const configl = @import("config.zig");
const threadingl = @import("search/threading.zig");

const alphaBetal = @import("search/alphaBeta.zig");
const perftl = @import("search/perft.zig");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const scoreType = heuristicl.scoreType;
const moveLine = movel.moveLine;

const threadInfo = threadingl.threadInfo;
const threadInfo_container = threadingl.threadInfo_container;

pub const e_matchFlag = enum(u8) { Error, Continue, CheckMate, StaleMate, StaleMateRepetition };

pub const moveDecision = struct {
    move: IMove = .{},
    scoring: scoreType = 0,
    timeTake: u64 = 0, //seconds
    pub fn invertScore(p_self: *moveDecision) void {
        p_self.scoring = -p_self.scoring;
    }
};
pub fn getScoreMaskFromTurn(white: bool) i8 {
    if (white) {
        return 1;
    }
    return -1;
}

pub fn dispatchUciGoCmd(p_engine: *enginel.engine, cmdBuffer: []const u8) bool {
    var moveArray: moveContainer = undefined;

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
    if (searcher.config.type == .PERFT) {
        _ = perftl.dispatchUciPerftCmd(p_engine);
        return;
    }
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
    for (0.._nThread) |thread_id| {
        pack.items(.threadHandle)[thread_id] = std.Thread.spawn(.{}, alphaBetal.searchEntrypoint, .{ &pack.items(.chessState)[thread_id], &pack.items(.moves)[thread_id], &pack.items(._tInfo)[thread_id], searcher.config.depth }) catch unreachable;
    }
    _ = waitThreadFinish(p_engine, &pack) catch {
        std.debug.print("ERROR wait thread\n", .{});
        return;
    };
}

pub fn waitThreadFinish(p_engine: *enginel.engine, p_arr: *threadingl.threadPackageArray) !bool {
    const _start: u64 = @intCast(std.time.milliTimestamp());
    while (!p_engine.searcher.interrupt and p_engine.searcher.endCounter != p_engine.searcher.nThreads) {
        std.Thread.sleep(configl.INFO_TICKRATE_NS);
        const res = threadingl.getCombinedFromPack(p_arr);
        const _end: u64 = @intCast(std.time.milliTimestamp());
        const msg = std.fmt.allocPrint(p_engine.alloc, "info nps: {d} nodes {d} retrieved: {d} stored: {d}", .{ @divFloor(res.n_nodeExplored, (_end - _start + 1)) * 1000, res.n_nodeExplored, res.n_hashRetrieve, hashl.hashTable.n_insertion }) catch {
            continue;
        };
        defer p_engine.alloc.free(msg);
        p_engine.respond(msg);
        p_engine.searcher.endCounter = 0;
        for (0..p_arr.len) |i| {
            p_engine.searcher.endCounter += @intFromBool(!p_arr.items(._tInfo)[i].running);
        }
    }
    p_engine.searcher.searching = false;
    if (p_engine.searcher.endCounter != p_engine.searcher.nThreads) {
        for (0..p_arr.len) |i| {
            p_arr.items(._tInfo)[i].running = false;
        }
        threadingl.joinOnThreadPack(p_arr);
    } else {
        const res = threadingl.getCombinedFromPack(p_arr);
        const bestMove = res.currentBest;
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
            const msg_score = std.fmt.allocPrint(p_engine.alloc, "line found: {s} (score: {d})", .{ lineStr._slice(), bestMove.scoring }) catch unreachable;
            defer p_engine.alloc.free(msg_score);
            defer lineStr.free(p_engine.alloc);
            p_engine.respond(msg_score);
        }
    }
    return true;
}
