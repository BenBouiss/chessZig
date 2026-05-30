const std = @import("std");
const movel = @import("../move.zig");
const heuristicl = @import("../heuristic.zig");
const weightl = @import("../weights.zig");
const hashl = @import("../hashTable.zig");
const configl = @import("../config.zig");
const boardl = @import("../board.zig");
const typel = @import("../type.zig");

const threadingl = @import("threading.zig");
const schedulerl = @import("scheduler.zig");
const zwsl = @import("zws.zig");

const IMove = movel.IMove;
const pvContainer = movel.pvContainer;
const scoreType = heuristicl.scoreType;
const threadInfo = threadingl.threadInfo;

pub fn getScoreMaskFromTurn(white: bool) scoreType {
    if (white) {
        return 1;
    }
    return -1;
}

pub fn searchEntrypoint(p_state: *boardl.boardState, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, p_features: *const schedulerl.searchFeatures, ss: *searchStack) i8 {
    p_info.working = true;
    const alpha: scoreType = -weightl.simpleCheckMateScore;
    const beta: scoreType = weightl.simpleCheckMateScore;

    _ = p_startingMoves;
    var pv: pvContainer = .{};
    ss.getFrame(0).pv = &pv;

    const score = zwsl.searchLoop(p_state, p_info, p_features, depth, 0, alpha, beta, .PV, ss);

    const move = pv.moves[0];

    p_info.currentBest.move = move;
    p_info.currentBest.scoring = score;
    p_info.currentBest.line.setLineFromPV(&pv);

    if (p_info.alive) {
        return 0;
    }
    // 1 is error
    return 1;
}
pub const searchType = enum { NonPV, PV };

pub fn handleTerminalState(p_state: *boardl.boardState, p_info: *threadInfo, alpha: scoreType, beta: scoreType, p_features: *const schedulerl.searchFeatures, ply: u16, comptime t: searchType, ss: *searchStack) scoreType {
    if (p_features.useHash and comptime t == .NonPV) {
        const entry = hashl.getEntryFromMatch(p_state.frame.key, 0);
        if (entry) |_entry| {
            p_info.searchStat.n_hashRetrieve += 1;
            return _entry.eval();
        }
    }
    p_info.searchStat.n_nodeExplored += 1;
    const ischeck = p_state.isChecked();
    // perform quiesc
    const score = quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, alpha, beta, ply, ischeck, t, ss);
    if (p_features.useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.frame.key, 0, score);
        _ = hashl.hashTable.storeEntry(s_entry, p_state.frame.key.code);
    }
    return score;
}

pub fn quiescenceSearch(p_state: *boardl.boardState, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, ply: u16, wasChecked: bool, comptime t: searchType, ss: *searchStack) scoreType {
    // first vers adapt of the pseudo code: https://www.chessprogramming.org/Quiescence_Search

    var _alpha = alpha;

    var currS = ss.getFrame(ply);
    const static_eval = heuristicl.c_evaluate(p_state, &heuristicl.globalHeuristic, p_state.whiteToMove());
    currS.staticEval = .{ .s = static_eval, .t = .STD };

    if (depth == 0 or !p_info.alive) {
        p_info.searchStat.n_nodeExplored += 1;
        return static_eval;
    }

    if (comptime t == .PV) {
        var pv: movel.pvContainer = .{};
        ss.getFrame(ply + 1).pv = &pv;
    }
    var best_value = static_eval;
    // stand pat https://www.chessprogramming.org/Quiescence_Search#StandPat
    if (best_value >= beta) {
        p_info.searchStat.n_cutoffs += 1;
        return best_value;
    }

    //https://www.chessprogramming.org/Delta_Pruning
    const BIG_DELTA = weightl.simpleQueenScore;
    const f: boardl.boardFrame = .copy(p_state);

    if (best_value > _alpha) {
        _alpha = best_value;
    }

    var gen: heuristicl.moveGenerator = heuristicl.moveGenerator.init();
    gen.fetchNext(p_state);
    const order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, .{}, depth, currS.prevLineMove, true);

    var i: usize = 0;
    while (gen.pickNext(&order)) |move| : (i += 1) {
        var _delta = BIG_DELTA;
        if (move.isPromotion()) {
            _delta += weightl.simpleQueenScore - 200;
        }
        // delta pruning
        if (static_eval < (_alpha - _delta)) {
            continue;
            //return _alpha;
        }

        // if move nor capture nor checking
        // problem here where a checking sequence ie
        // black checked -> white not checked nor capture = end of quiescence, the search might need to continue

        p_state.makeMove(move);

        const score = -quiescenceSearch(p_state, p_info, depth - 1, -beta, -_alpha, ply + 1, wasChecked, t, ss);

        _ = p_state.undoMove();
        p_state.frame = f;

        if (i == 0 or score > best_value) {
            best_value = score;
        }
        if (score >= beta) {
            p_info.searchStat.n_cutoffs += 1;
            return score;
        }
        if (score > _alpha) {
            _alpha = score;
            if (comptime t == .PV) {
                currS.pv.?.onBestMove(move, ss.getFrame(ply + 1).pv);
            }
        }
    }
    return best_value;
}
pub const searchFrame = struct {
    staticEval: heuristicl.score = .{},
    ply: u16 = 0,
    valid: bool = false,
    prevLineMove: IMove = .{},
    pv: ?*movel.pvContainer = null,
};

// used to garanty getFrameOffset(0, 4) returns a default value
pub const negativeOffset: u16 = 4;
//index by ply
pub const searchStack = struct {
    e: [typel.MAX_PLY + configl.MAX_QUIESC_DEPTH + negativeOffset]searchFrame = @splat(.{}),
    pub inline fn getFrame(self: *searchStack, ply: u16) *searchFrame {
        return &self.e[ply + negativeOffset];
    }
    pub inline fn getPrevFrame(self: *searchStack, ply: u16, offset: u16) *searchFrame {
        return &self.e[negativeOffset - offset + ply];
    }
    pub fn setPrevLine(self: *searchStack, line: *const movel.line) void {
        for (0..line.len) |i| {
            self.e[i + negativeOffset].prevLineMove = line.moves[i];
        }
    }
    pub fn printPV(self: *const searchStack) void {
        for (negativeOffset..self.e.len) |i| {
            if (!self.e[i].prevLineMove.isValid()) {
                break;
            }
            std.debug.print("{s} ", .{self.e[i].prevLineMove.getStr()});
        }
        std.debug.print("\n", .{});
    }
};
