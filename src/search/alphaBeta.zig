const std = @import("std");
const movel = @import("../move.zig");
const heuristicl = @import("../heuristic.zig");
const weightl = @import("../weights.zig");
const hashl = @import("../hashTable.zig");
const configl = @import("../config.zig");
const boardl = @import("../board.zig");

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

pub fn searchEntrypoint(p_state: *boardl.boardState, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, p_features: *const schedulerl.searchFeatures, prevLine: *const movel.line, ss: *searchStack) i8 {
    p_info.working = true;
    const alpha: scoreType = -weightl.simpleCheckMateScore;
    const beta: scoreType = weightl.simpleCheckMateScore;

    _ = p_startingMoves;
    var pv: pvContainer = .{};

    const score = zwsl.searchLoop(p_state, p_info, p_features, &pv, prevLine, depth, 0, alpha, beta, .PV, ss);

    const move = pv.pv_arr[0][0];
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

pub fn handleTerminalState(p_state: *boardl.boardState, p_info: *threadInfo, alpha: scoreType, beta: scoreType, p_features: *const schedulerl.searchFeatures, ply: u16, pv: *pvContainer, prevLine: *const movel.line, comptime t: searchType, ss: *searchStack) scoreType {
    if (p_features.useHash) {
        const entry = hashl.getEntryFromMatch(p_state.frame.key, 0);
        if (entry) |_entry| {
            p_info.searchStat.n_hashRetrieve += 1;
            return _entry.eval();
        }
    }
    p_info.searchStat.n_nodeExplored += 1;
    if (p_features.useQuiescence) {
        const ischeck = p_state.isChecked();
        // perform quiesc
        const score = quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, alpha, beta, ply, ischeck, pv, prevLine, t, ss);
        if (p_features.useHash) {
            const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.frame.key, 0, score);
            _ = hashl.hashTable.storeEntry(&s_entry, p_state.frame.key.code);
        }
        return score;
    }

    var currS = ss.getFrame(ply);
    const score = heuristicl.c_evaluate(p_state, &heuristicl.globalHeuristic, p_state.whiteToMove());
    currS.staticEval = .{ .s = score, .t = .STD };

    if (p_features.useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryFromMatchResult(p_state.frame.key, 0, score);
        _ = hashl.hashTable.storeEntry(&s_entry, p_state.frame.key.code);
    }
    return score;
}

pub fn quiescenceSearch(p_state: *boardl.boardState, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, ply: u16, wasChecked: bool, pv: *pvContainer, prevLine: *const movel.line, comptime t: searchType, ss: *searchStack) scoreType {
    // first vers adapt of the pseudo code: https://www.chessprogramming.org/Quiescence_Search
    if (comptime t == .PV) {
        pv.setLen(ply);
    }
    var _alpha = alpha;

    var currS = ss.getFrame(ply);
    const static_eval = heuristicl.c_evaluate(p_state, &heuristicl.globalHeuristic, p_state.whiteToMove());
    currS.staticEval = .{ .s = static_eval, .t = .STD };

    if (depth == 0 or !p_info.alive) {
        p_info.searchStat.n_nodeExplored += 1;
        return static_eval;
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
        if (comptime t == .PV) {
            pv.onBestMove(p_state.getLastMove(), ply - 1);
        }
        _alpha = best_value;
    }

    var gen: heuristicl.moveGenerator = heuristicl.moveGenerator.init();
    gen.fetchNext(p_state);
    const order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, prevLine, .{}, depth);
    var i: usize = 0;
    while (gen.pickNext(&order)) |move| : (i += 1) {
        var _delta = BIG_DELTA;
        if (move.isPromotion()) {
            _delta += weightl.simpleQueenScore - 200;
        }
        // delta pruning
        if (static_eval < (_alpha - _delta)) {
            return _alpha;
        }

        // if move nor capture nor checking
        // problem here where a checking sequence ie
        // black checked -> white not checked nor capture = end of quiescence, the search might need to continue

        p_state.makeMove(move);

        const score = -quiescenceSearch(p_state, p_info, depth - 1, -beta, -_alpha, ply + 1, wasChecked, pv, prevLine, t, ss);

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
                pv.onBestMove(move, ply);
            }
        }
    }
    return best_value;
}
pub const searchFrame = struct {
    staticEval: heuristicl.score = .{},
    ply: u16 = 0,
    valid: bool = false,
    // TODO: place the currentLine moves + prevLine moves inside of these structs in the stack
};

pub const MAX_PLY = 24;
// used to garanty getFrameOffset(0, 4) returns a default value
pub const negativeOffset: u16 = 4;
//index by ply
pub const searchStack = struct {
    e: [MAX_PLY + configl.MAX_QUIESC_DEPTH + negativeOffset]searchFrame = @splat(.{}),
    pub inline fn getFrame(self: *searchStack, ply: u16) *searchFrame {
        return &self.e[ply + negativeOffset];
    }
    pub inline fn getPrevFrame(self: *searchStack, ply: u16, offset: u16) *searchFrame {
        return &self.e[negativeOffset - offset + ply];
    }
};
