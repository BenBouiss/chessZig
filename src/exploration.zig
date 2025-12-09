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
const build_options = @import("build_options");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const typedMoveContainer = movel.typedMoveContainer;
const e_square = squarel.e_square;
const GLOBAL_ALLOC = mainl.GLOBAL_ALLOC;

const useHash = build_options.useHash;
const useDebug = build_options.useDebug;

const assert = std.debug.assert;

const e_simpleScore = enum(i64) { CheckMate = 9999, StaleMate = 0 };
pub const e_matchFlag = enum(u8) { Error, Continue, CheckMate, StaleMate, StaleMateRepetition };

pub const e_playerType = enum(u8) { Invalid = 0, Human, Bot };
pub const e_searchType = enum(u8) { Random, Simple, DepthBot };

pub fn freePlayer(p_player: *Player) void {
    if (p_player.isInitialized) {
        p_player.move_decision_history.deinit(GLOBAL_ALLOC);
        p_player.isInitialized = false;
    }
}

pub const Player = struct {
    type: e_playerType = .Invalid,
    isInitialized: bool = false,
    search_option: searchOption = .{},

    pub fn print(self: Player) void {
        std.debug.print("Player info:\nType: {}, seach_option(type, depth, heuristic): {} / {d} / {d} {}\n", .{ self.type, self.search_option.searchType, self.search_option.searchDeph, @intFromEnum(self.search_option.heuristicType), self.search_option.heuristicType });
    }
    pub fn setType(p_self: *Player, player_type: e_playerType) void {
        p_self.type = player_type;
        p_self.isInitialized = true;
    }
    pub fn setSearchType(p_self: *Player, search_type: e_searchType) void {
        p_self.search_option.searchType = search_type;
    }

    pub fn setSearchDepth(p_self: *Player, depth: u8) void {
        p_self.search_option.searchDeph = depth;
    }
    pub fn setHeuristicType(p_self: *Player, heuristic: heuristicl.e_heuristicType) void {
        p_self.search_option.heuristicType = heuristic;
        switch (heuristic) {
            .Simple => {
                p_self.search_option.heuristicFunc = &heuristicl.simpleHeuristic;
            },
            .Bitmap => {
                p_self.search_option.heuristicFunc = &heuristicl.simpleHeuristic;
            },
        }
    }
};

pub const searchOption = struct {
    searchType: e_searchType = .Random,
    searchDeph: u8 = 1,
    heuristicType: heuristicl.e_heuristicType = .Simple,
    heuristicFunc: *const fn (*chess.Board_state) i64 = &heuristicl.mockHeuristic,
};

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
    line: movel.moveContainer = .{},
    scoring: i64 = 0,
    timeTake: u64 = 0, //seconds
    pub fn invertScore(p_self: *moveDecisionExt) void {
        p_self.scoring = -p_self.scoring;
    }
    pub fn isBetter(p_self: *moveDecisionExt, other: *moveDecisionExt) bool {
        return p_self.scoring > other.scoring;
    }
};

pub fn handlePlayer(p_state: *chess.Board_state, player: Player) !e_matchFlag {
    var moveD: moveDecision = undefined;
    const _turn = p_state.turn_count;
    switch (player.type) {
        .Invalid => {
            std.debug.print("Found invalid player at turn: {d} \n", .{p_state.turn_count});
            return .Error;
        },
        .Human => {
            moveD = try humanMoveBot(p_state);
        },
        .Bot => {
            moveD = try handleBotTurn(p_state, player);
        },
    }

    assert(_turn == p_state.turn_count);
    if (!moveD.move.isValid()) {
        if (p_state.isLegal(p_state.turn)) {
            return .StaleMate;
        }
        return .CheckMate;
    }

    //p_state.stack.push(&p_state.makeFrame());
    _ = p_state.makeMoveUpdate(moveD.move);
    if (comptime useDebug) {
        chess.sanityCheckBoardState(p_state);
    }
    if (p_state.isStaleMateRepetition()) {
        return .StaleMateRepetition;
    }
    return .Continue;
}

pub fn handleBotTurn(p_state: *chess.Board_state, player: Player) !moveDecision {
    switch (player.search_option.searchType) {
        .Random => {
            return try randomMoveBot(p_state);
        },
        .Simple => {
            return try simpleMoveBot(p_state, player);
        },
        .DepthBot => {
            return try depthMoveBot(p_state, player);
        },
    }
}

pub fn getEvaluation(p_state: *chess.Board_state, p_player: *const Player) i64 {
    //return heuristicl.simpleHeuristic(p_state);
    return p_player.search_option.heuristicFunc(p_state);
}

pub fn getScoreMaskFromTurn(color: chess.e_color) i8 {
    if (color == .WHITE) {
        return 1;
    }
    return -1;
}

pub fn simpleBotMoveExploration(p_state: *chess.Board_state, p_player: *const Player) !moveDecision {
    const fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);

    var decision: moveDecision = .{};
    var curr_score: i64 = 0;
    const color_mask: i8 = getScoreMaskFromTurn(p_state.turn);

    for (0..fmoves.len) |i| {
        p_state.stack.push(&p_state.makeFrame());
        const move: IMove = fmoves.moves[i];
        _ = p_state.makeMoveUpdate(move);

        curr_score = getEvaluation(p_state, p_player);

        _ = p_state.undoMoveRestore();
        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);

        if (i == 0 or
            (curr_score * color_mask > decision.scoring * color_mask))
        {
            decision.move = move;
            decision.scoring = curr_score;
        }
    }

    if (fmoves.len == 0) {
        decision.scoring = heuristicl.simpleCheckMateScore * color_mask;
    }
    return decision;
}

pub fn simpleMoveBot(p_state: *chess.Board_state, player: Player) !moveDecision {
    const decision: moveDecision = try simpleBotMoveExploration(p_state, &player);
    std.debug.print("[DEBUG] simpleMoveBot: From {} move decision: {s} with scoring: {d} \n", .{ p_state.turn, decision.move.getStr(), decision.scoring });
    return decision;
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

pub fn randomMoveBot(p_state: *chess.Board_state) !moveDecision {
    const fmoves = moveGenl.generateLegalMoves(p_state);
    if (fmoves.len == 0) {
        return .{};
    }
    const move_idx = fmoves.sample(p_state.randInt);
    std.debug.print("[DEBUG] handleBotTurn: Move index sampled {d} / {d}\n", .{ move_idx, fmoves.len });
    fmoves.moves[move_idx].print();
    return .{ .move = fmoves.moves[move_idx].copy() };
}

pub fn humanMoveBot(p_state: *chess.Board_state) !moveDecision {
    //std.debug.print("[DEBUG] humanMoveBot: \n", .{});
    const fmoves = moveGenl.generateLegalMoves(p_state);
    var userMove: IMove = undefined;

    // TODO Remove these debug lines

    while (true) {
        userMove = try chess.askUserMove(p_state);
        if (userMove.isIn(fmoves)) {
            return .{ .move = userMove, .scoring = 0 };
        }
    }
}

pub fn depthMoveBot(p_state: *chess.Board_state, player: Player) !moveDecision {
    const color_mask: i8 = getScoreMaskFromTurn(p_state.turn);
    var decision: moveDecision = try depthBotMoveExploration(p_state, &player, player.search_option.searchDeph);

    decision.scoring = decision.scoring * color_mask;
    std.debug.print("[DEBUG] depthMoveBot: Move found {s}, score = {d} for player {}\n", .{ decision.move.getStr(), decision.scoring, p_state.turn });
    return decision;
}

pub fn depthBotMoveExploration(p_state: *chess.Board_state, p_player: *const Player, depth: u8) !moveDecision {
    const color_mask: i8 = getScoreMaskFromTurn(p_state.turn);

    if (depth <= 0) {
        return .{ .move = p_state.getLastMove(), .scoring = color_mask * getEvaluation(p_state, p_player) };
    }
    if (p_state.isStaleMateRepetition()) {
        return .{ .move = p_state.getLastMove(), .scoring = heuristicl.simpleStalemateScore };
    }

    var fmoves: moveContainer = moveGenl.generateLegalMoves(p_state);
    fmoves.shuffle(p_state.randInt);

    var final_decision: moveDecision = .{};
    var decision: moveDecision = .{};
    const turn = p_state.turn;
    for (0..fmoves.len) |i| {
        const move: IMove = fmoves.moves[i];
        p_state.stack.push(&p_state.makeFrame());
        _ = p_state.makeMoveUpdate(move);

        decision = try depthBotMoveExploration(p_state, p_player, depth - 1);

        decision.invertScore();

        _ = p_state.undoMoveRestore();
        const popped = (p_state.stack.pop());
        p_state.loadFrame(&popped);

        if (i == 0 or final_decision.scoring < decision.scoring) {
            final_decision.move = fmoves.moves[i];
            final_decision.scoring = decision.scoring;
        }
    }
    if (fmoves.len == 0) {
        if (!p_state.isLegal(turn)) {
            final_decision.scoring = -@intFromEnum(e_simpleScore.CheckMate) * color_mask;
        } else {
            final_decision.scoring = @intFromEnum(e_simpleScore.StaleMate);
        }
    }
    return final_decision;
}

pub const uciSearcher = struct {
    config: enginel.goArgStruct = .{},
    interrupt: bool = false,
    nThreads: u16 = 1,
    endCounter: u16 = 0,
    bestMove: moveDecisionExt = .{},
    searching: bool = false,
    pub fn reset(p_self: *uciSearcher) void {
        p_self.endCounter = 0;
        p_self.interrupt = false;
        p_self.searching = false;
        p_self.bestMove = .{};
    }
};
pub const threadInfo = struct {
    currentBest: moveDecisionExt = .{},
    n_nodeExplored: u64 = 0,
    depth: u8 = 0,
    currentMove: moveDecisionExt = .{},
    currentMoveNumber: u64 = 0,
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
            ret.n_nodeExplored = info.n_nodeExplored;
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
    if (p_engine.searcher.config.eval) {
        const score = heuristicl.simpleHeuristic(&p_engine.state);
        const msg = std.fmt.allocPrint(p_engine.alloc, "eval: {d}", .{score}) catch unreachable;
        p_engine.respond(msg);
        return true;
    }
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
    if (p_engine.status.debugMode) {
        std.debug.print("[DEBUG] dispatchUciGoThreads: nthread info: searcher: {d}, movearray: {d}\n", .{ searcher.nThreads, moveArray.len });
    }

    var threadedMoves = moveArray.cutEvenly(p_engine.alloc, _nThread) catch {
        std.debug.print("[ERROR] dispatchUciGoThreads: move container init\n", .{});
        return;
    };

    defer {
        for (threadedMoves.items) |*cell| {
            cell.deinit(GLOBAL_ALLOC);
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
    for (0.._nThread) |thread_id| {
        threads[thread_id] = std.Thread.spawn(.{}, threadUciEntrypoint, .{ &arr_state.array[thread_id], &threadedMoves.items[thread_id], &arr_threadInfo.items[thread_id], searcher.config.depth }) catch unreachable;
    }
    _ = waitThreadFinish(p_engine, &arr_threadInfo, &threads);
}

pub fn waitThreadFinish(p_engine: *enginel.engine, p_arr: *threadInfo_container, p_threads: *[]std.Thread) bool {
    var _start: u64 = 0;
    var _end: u64 = 0;
    _start = @intCast(std.time.milliTimestamp());
    while (!p_engine.searcher.interrupt and p_engine.searcher.endCounter != p_engine.searcher.nThreads) {
        std.Thread.sleep(enginel.INFO_TICKRATE_NS);
        const res = p_arr.combine();
        _end = @intCast(std.time.milliTimestamp());
        const msg = std.fmt.allocPrint(p_engine.alloc, "info nps: {d}", .{@divFloor(res.n_nodeExplored, (_end - _start + 1)) * 1000}) catch {
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
        defer p_engine.alloc.free(msg);
        p_engine.respond(msg);
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
            p_info.currentBest.move = move;
        }
    }
    p_info.running = false;
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
    //fmoves.shuffle(p_state.randInt);
    var final_decision: moveDecisionExt = .{};
    //var decision: moveDecisionExt = .{};
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
            final_decision.move = fmoves.moves[i];
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
