const std = @import("std");
const chess = @import("chess.zig");
const movel = @import("move.zig");
const benchmark = @import("benchmark.zig");
const moveGenl = @import("move_generation.zig");
const heuristicl = @import("heuristic.zig");
const IMove = movel.IMove;
const moveContainer = movel.moveContainer;
const e_square = chess.e_square;
const assert = std.debug.assert;

const e_simpleScore = enum(i64) { CheckMate = 9999, StaleMate = 0 };
pub const e_matchFlag = enum(u8) { Error, Continue, CheckMate, StaleMate };

const e_botType = enum(u8) { Random, Simple };

pub const e_playerType = enum(u8) { Invalid = 0, Human, RandomBot, SimpleBot, DepthBot };

pub fn freePlayer(p_player: *Player) void {
    if (p_player.isInitialized) {
        p_player.move_decision_history.deinit(chess.get_global_alloc());
        p_player.isInitialized = false;
    }
}

pub const Player = struct {
    type: e_playerType = .Invalid,
    searchDepth: u8 = 0,
    move_decision_history: std.ArrayList(moveDecision),
    isInitialized: bool = false,

    pub fn init(p_self: *Player, allocator: std.mem.Allocator) !void {
        if (p_self.isInitialized) {
            return;
        }
        p_self.move_decision_history = try std.ArrayList(moveDecision).initCapacity(allocator, 30);
        p_self.isInitialized = true;
    }
    pub fn setType(p_self: *Player, player_type: e_playerType) void {
        p_self.type = player_type;
    }
    pub fn setDepth(p_self: *Player, depth: u8) void {
        p_self.searchDepth = depth;
    }
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
        .RandomBot => {
            moveD = try randomMoveBot(p_state);
        },

        .SimpleBot => {
            moveD = try simpleMoveBot(p_state);
        },
        .DepthBot => {
            moveD = try depthMoveBot(p_state, player);
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

pub fn getEvaluation(p_state: *chess.Board_state) i64 {
    return heuristicl.simpleHeuristic(p_state);
}

pub fn getScoreMaskFromTurn(color: chess.e_color) i8 {
    if (color == .WHITE) {
        return 1;
    }
    return -1;
}

pub fn simpleBotMoveExploration(p_state: *chess.Board_state) !moveDecision {
    var moves: moveContainer = try moveGenl.moveGeneration(p_state);
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
        curr_score = getEvaluation(p_state);
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

pub fn simpleMoveBot(p_state: *chess.Board_state) !moveDecision {
    const decision: moveDecision = try simpleBotMoveExploration(p_state);
    std.debug.print("[DEBUG] simpleMoveBot: From {} move decision: {s} with scoring: {d} \n", .{ p_state.turn, decision.move.getStr(), decision.scoring });
    return decision;
}

pub fn explorationNDepth(p_state: *chess.Board_state, depth: u8, p_res: *benchmark.benchmarkResult) !void {
    if (depth == 0) {
        p_res.addNode(p_state.getLastMove());
        return;
    }
    var moves: moveContainer = try moveGenl.moveGeneration(p_state);
    //const fmoves = try moveGenl.filterMoveLegal(p_state, &moves);
    const fmoves = try moveGenl.filterMoveLegalFast(p_state, &moves);
    //if (fmoves.len != ffmoves.len) {
    //    fmoves.printDifference(ffmoves);
    //    chess.print_boardstate(p_state);
    //    chess.askContinue();
    //}
    for (0..fmoves.len) |i| {
        _ = try p_state.makeMove(fmoves.moves[i]);
        try explorationNDepth(p_state, depth - 1, p_res);
        _ = try p_state.undoMove();
    }
    return;
}

pub fn randomMoveBot(p_state: *chess.Board_state) !moveDecision {
    var moves: moveContainer = try moveGenl.moveGeneration(p_state);
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
    var moves: moveContainer = try moveGenl.moveGeneration(p_state);
    const fmoves = try moveGenl.filterMoveLegal(p_state, &moves);
    var userMove: IMove = undefined;

    while (true) {
        userMove = try chess.askUserMove(p_state);
        if (userMove.isIn(fmoves)) {
            return .{ .move = userMove, .scoring = 0 };
        }
    }
}

pub fn depthMoveBot(p_state: *chess.Board_state, player: Player) !moveDecision {
    const color_mask: i8 = getScoreMaskFromTurn(p_state.turn);
    var decision: moveDecision = try depthBotMoveExploration(p_state, player.searchDepth);

    decision.scoring = decision.scoring * color_mask;
    std.debug.print("[DEBUG] depthMoveBot: Move found {s}, score = {d} for player {}\n", .{ decision.move.getStr(), decision.scoring, p_state.turn });
    return decision;
}

pub fn depthBotMoveExploration(p_state: *chess.Board_state, depth: u8) !moveDecision {
    const color_mask: i8 = getScoreMaskFromTurn(p_state.turn);

    if (depth <= 0) {
        return .{ .move = p_state.move_history.items[p_state.move_history.items.len - 1].copy(), .scoring = color_mask * heuristicl.simpleHeuristic(p_state) };
    }
    var all_moves: moveContainer = try moveGenl.moveGeneration(p_state);
    all_moves.shuffle(p_state.randInt);

    var final_decision: moveDecision = .{};
    var decision: moveDecision = .{};
    const turn = p_state.turn;
    for (0..all_moves.len) |i| {
        _ = try p_state.makeMove(all_moves.moves[i]);

        if (!p_state.isLegal(turn)) {
            _ = try p_state.undoMove();
            continue;
        }

        decision = try depthBotMoveExploration(p_state, depth - 1);

        decision.invertScore();
        _ = try p_state.undoMove();

        if (!final_decision.move.isValid() or final_decision.scoring < decision.scoring) {
            final_decision.move = all_moves.moves[i];
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
