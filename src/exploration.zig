const std = @import("std");
const chess = @import("chess.zig");
const movel = @import("move.zig");
const benchmark = @import("benchmark.zig");
const moveGenl = @import("move_generation.zig");
const squarel = @import("square.zig");
const heuristicl = @import("heuristic.zig");
const utilsl = @import("utils.zig");

const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const typedMoveContainer = movel.typedMoveContainer;
const e_square = squarel.e_square;

const assert = std.debug.assert;

const e_simpleScore = enum(i64) { CheckMate = 9999, StaleMate = 0 };
pub const e_matchFlag = enum(u8) { Error, Continue, CheckMate, StaleMate };

pub const e_playerType = enum(u8) { Invalid = 0, Human, Bot };
pub const e_searchType = enum(u8) { Random, Simple, DepthBot };

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
const GLOBAL_ALLOC = GPA.allocator();

pub fn freePlayer(p_player: *Player) void {
    if (p_player.isInitialized) {
        p_player.move_decision_history.deinit(chess.get_global_alloc());
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
    _ = try p_state.makeMove(moveD.move);
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
    var moves: moveContainer = moveGenl.moveGeneration(p_state);
    moves.shuffle(p_state.randInt);

    var decision: moveDecision = .{};
    var curr_score: i64 = 0;
    const color_mask: i8 = getScoreMaskFromTurn(p_state.turn);
    const turn = p_state.turn;
    for (0..moves.len) |i| {
        _ = try p_state.makeMove(moves.moves[i]);
        if (!p_state.isLegal(turn)) {
            _ = try p_state.undoMove();
            continue;
        }
        curr_score = getEvaluation(p_state, p_player);
        _ = try p_state.undoMove();
        if (!decision.move.isValid() or
            (curr_score * color_mask > decision.scoring * color_mask))
        {
            decision.move = moves.moves[i];
            decision.scoring = curr_score;
        }
    }

    if (!decision.move.isValid()) {
        decision.scoring = heuristicl.simpleCheckMateScore * color_mask;
    }
    return decision;
}

pub fn simpleMoveBot(p_state: *chess.Board_state, player: Player) !moveDecision {
    const decision: moveDecision = try simpleBotMoveExploration(p_state, &player);
    std.debug.print("[DEBUG] simpleMoveBot: From {} move decision: {s} with scoring: {d} \n", .{ p_state.turn, decision.move.getStr(), decision.scoring });
    return decision;
}

pub fn explorationNDepth(p_state: *chess.Board_state, depth: u8, p_res: *benchmark.benchmarkResult) !void {
    if (depth <= 0) {
        //p_res.n_nodes += 1;
        p_res.addNode(&p_state.getLastMove());
        return;
    }
    var moves: moveContainer = moveGenl.moveGeneration(p_state);
    const fmoves = try moveGenl.filterMoveLegalFast(p_state, &moves);
    for (0..fmoves.len) |i| {
        //_ = try p_state.makeMoveFast(fmoves.moves[i]);
        _ = p_state.makeMoveFast(fmoves.moves[i]);
        try explorationNDepth(p_state, depth - 1, p_res);
        //_ = try p_state.undoMove();
        _ = p_state.undoMoveFast();
    }
    return;
}
//pub fn explorationNDepth(p_state: *chess.Board_state, depth: u8, p_res: *benchmark.benchmarkResult) !void {
//    if (depth <= 0) {
//        //p_res.n_nodes += 1;
//        p_res.addNode(&p_state.getLastMove());
//        return;
//    }
//    var moves: typedMoveContainer = moveGenl.moveGenerationTyped(p_state);
//
//    const fmovesQuiet = try moveGenl.filterMoveLegalFast(p_state, &moves.quietMoves);
//    for (0..fmovesQuiet.len) |i| {
//        _ = p_state.makeMoveFaster(fmovesQuiet.moves[i], .QUIET);
//        try explorationNDepth(p_state, depth - 1, p_res);
//        _ = p_state.undoMoveFaster();
//    }
//
//    const fmovesCapture = try moveGenl.filterMoveLegalFast(p_state, &moves.captureMoves);
//    for (0..fmovesCapture.len) |i| {
//        _ = p_state.makeMoveFaster(fmovesCapture.moves[i], .CAPTURE);
//        try explorationNDepth(p_state, depth - 1, p_res);
//        _ = p_state.undoMoveFaster();
//    }
//
//    const fmovesEnpassant = try moveGenl.filterMoveLegalFast(p_state, &moves.enPassantMoves);
//    for (0..fmovesEnpassant.len) |i| {
//        _ = p_state.makeMoveFaster(fmovesEnpassant.moves[i], .ENPASSANT);
//        try explorationNDepth(p_state, depth - 1, p_res);
//        _ = p_state.undoMoveFaster();
//    }
//
//    const fmovesPromotion = try moveGenl.filterMoveLegalFast(p_state, &moves.promotionMoves);
//    for (0..fmovesPromotion.len) |i| {
//        _ = p_state.makeMoveFaster(fmovesPromotion.moves[i], .PROMOTION);
//        try explorationNDepth(p_state, depth - 1, p_res);
//        _ = p_state.undoMoveFaster();
//    }
//
//    const fmovesCapturePromotion = try moveGenl.filterMoveLegalFast(p_state, &moves.capturePromotionMoves);
//    for (0..fmovesCapturePromotion.len) |i| {
//        _ = p_state.makeMoveFaster(fmovesCapturePromotion.moves[i], .CAPTUREPROMOTION);
//        try explorationNDepth(p_state, depth - 1, p_res);
//        _ = p_state.undoMoveFaster();
//    }
//
//    const fmovesDoublePush = try moveGenl.filterMoveLegalFast(p_state, &moves.enPassantMoves);
//    for (0..fmovesDoublePush.len) |i| {
//        _ = p_state.makeMoveFaster(fmovesDoublePush.moves[i], .DOUBLEPUSH);
//        try explorationNDepth(p_state, depth - 1, p_res);
//        _ = p_state.undoMoveFaster();
//    }
//
//    return;
//}
pub fn explorationNDepthThreadStart(p_state: *chess.Board_state, depth: u8, nThread: u8, p_res: *benchmark.benchmarkResult) !void {
    var moves: moveContainer = moveGenl.moveGeneration(p_state);
    const fmoves = try moveGenl.filterMoveLegalFast(p_state, &moves);
    var fmoves_arr = try fmoves.convertToArrayList(GLOBAL_ALLOC);
    defer fmoves_arr.deinit(GLOBAL_ALLOC);
    var _nThread: usize = @intCast(nThread);
    if (_nThread == 0) {
        _nThread = try std.Thread.getCpuCount();
    }
    _nThread = utilsl.min(usize, fmoves.len, _nThread);

    var threadedMoves = try utilsl.cutArrayListEvenly(IMove, GLOBAL_ALLOC, fmoves_arr, _nThread);
    //std.debug.print("Thread work distribution: \n", .{});
    //for (threadedMoves.items) |cell| {
    //    std.debug.print("Number of moves: {d}\n", .{cell.items.len});
    //}

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
        threads[thread_id] = try std.Thread.spawn(.{}, perftWorkerJob, .{
            &arr_state.array[thread_id],
            depth,
            &arr_benchmarks.array[thread_id],
            &threadedMoves.items[thread_id],
        });
    }
    for (0.._nThread) |thread_id| {
        threads[thread_id].join();
    }
    p_res.* = arr_benchmarks.combine();
    return;
}

pub fn perftWorkerJob(p_state: *chess.Board_state, depth: u8, p_res: *benchmark.benchmarkResult, p_startingMoves: *std.ArrayList(IMove)) void {
    for (0..p_startingMoves.items.len) |i| {
        _ = try p_state.makeMove(p_startingMoves.items[i]);
        try explorationNDepth(p_state, depth - 1, p_res);
        _ = try p_state.undoMove();
    }
}

pub fn randomMoveBot(p_state: *chess.Board_state) !moveDecision {
    var moves: moveContainer = moveGenl.moveGeneration(p_state);
    const fmoves = try moveGenl.filterMoveLegal(p_state, &moves);
    if (fmoves.len == 0) {
        return .{};
    }
    const move_idx = fmoves.sample(p_state.randInt);
    std.debug.print("[DEBUG] handleBotTurn: Move index sampled {d} / {d}\n", .{ move_idx, fmoves.len });
    fmoves.moves[move_idx].print();
    return .{ .move = fmoves.moves[move_idx].copy() };
}

pub fn humanMoveBot(p_state: *chess.Board_state) !moveDecision {
    std.debug.print("[DEBUG] humanMoveBot: \n", .{});
    var moves: moveContainer = moveGenl.moveGeneration(p_state);
    const fmoves = try moveGenl.filterMoveLegal(p_state, &moves);
    var userMove: IMove = undefined;

    // TODO Remove these debug lines
    const testMoveBB = moveGenl.moveGenBB(p_state);
    testMoveBB.print();

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
        //return .{ .move = p_state.move_history.items[p_state.move_history.items.len - 1].copy(), .scoring = color_mask * heuristicl.simpleHeuristic(p_state) };
        return .{ .move = p_state.move_history.moves[p_state.move_history.len - 1], .scoring = color_mask * getEvaluation(p_state, p_player) };
    }
    var all_moves: moveContainer = moveGenl.moveGeneration(p_state);
    all_moves.shuffle(p_state.randInt);
    const fmoves = try moveGenl.filterMoveLegalFast(p_state, &all_moves);

    var final_decision: moveDecision = .{};
    var decision: moveDecision = .{};
    const turn = p_state.turn;
    for (0..fmoves.len) |i| {
        const move = fmoves.moves[i];
        //if (move.isCapture()) {
        //    std.debug.print("[DEBUG] depthBotMoveExploration: turn: {} found a capture move for piece from {d} to {d}\n", .{ p_state.turn, move.getFrom(), move.getTo() });
        //    chess.print_boardstate(p_state);
        //}
        _ = try p_state.makeMove(move);

        //if (!p_state.isLegal(turn)) {
        //    _ = try p_state.undoMove();
        //    continue;
        //}

        decision = try depthBotMoveExploration(p_state, p_player, depth - 1);

        decision.invertScore();
        _ = try p_state.undoMove();

        if (!final_decision.move.isValid() or final_decision.scoring < decision.scoring) {
            //final_decision.move = all_moves.moves[i];
            final_decision.move = fmoves.moves[i];
            final_decision.scoring = decision.scoring;
        }
    }
    if (!final_decision.move.isValid()) {
        if (!p_state.isLegal(turn)) {
            final_decision.scoring = -@intFromEnum(e_simpleScore.CheckMate) * color_mask;
        } else {
            final_decision.scoring = @intFromEnum(e_simpleScore.StaleMate);
        }
    }
    return final_decision;
}
