const std = @import("std");
const movel = @import("../move.zig");
const heuristicl = @import("../heuristic.zig");
const weightl = @import("../weights.zig");
const hashl = @import("../hashTable.zig");
const configl = @import("../config.zig");
const boardl = @import("../board.zig");
const typel = @import("../type.zig");
const moveGenl = @import("../move_generation.zig");
const historyl = @import("../history.zig");

const threadingl = @import("threading.zig");
const schedulerl = @import("scheduler.zig");

const IMove = movel.IMove;
const pvContainer = movel.pvContainer;
const scoreType = heuristicl.scoreType;
const threadInfo = threadingl.threadInfo;

pub fn searchEntrypoint(p_state: *boardl.boardState, p_startingMoves: *std.ArrayList(IMove), p_info: *threadInfo, depth: u16, p_features: *const schedulerl.searchFeatures, ss: *searchStack) i8 {
    p_info.working = true;
    const alpha: scoreType = -weightl.simpleCheckMateScore;
    const beta: scoreType = weightl.simpleCheckMateScore;

    _ = p_startingMoves;
    var pv: pvContainer = .{};
    ss.getFrame(0).pv = &pv;

    const score = searchLoop(p_state, p_info, p_features, depth, 0, alpha, beta, .PV, ss);

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
        _ = hashl.hashTable.storeEntry(s_entry, p_state.frame.key.code, .search);
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

//https://www.chessprogramming.org/Principal_Variation_Search#cite_note-23
pub fn searchLoop(p_state: *boardl.boardState, p_info: *threadingl.threadInfo, p_features: *const schedulerl.searchFeatures, depth: u16, ply: u16, alpha: scoreType, beta: scoreType, comptime t: searchType, ss: *searchStack) scoreType {
    var _alpha = alpha;
    const _depth = depth;
    const white: bool = p_state.whiteToMove();
    if (p_state.isStaleMateRepetition()) {
        return weightl.simpleStalemateScore;
    }
    var finalScore: scoreType = 0;
    var bestMove: IMove = .{};
    var hashMove: IMove = .{};
    var hashFlag: hashl.nodeType = .UPPER;
    const skipQuietMoves: bool = false;
    var writer: hashl.hashWriter = .init(p_state.frame.key.code);
    if (p_features.useHash and depth > 2 and comptime t == .NonPV) {
        const res = hashl.hashTable.probeMatch(p_state.frame.key.code, @intCast(depth), p_state);
        writer = res.writer;
        if (res.entry) |_entry| {
            p_info.searchStat.n_hashRetrieve += 1;
            //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
            if (comptime t == .NonPV) {
                const tmp = _entry.val.search.nodeT();
                const eval = _entry.eval();
                if (tmp == .ALL) {
                    return eval;
                } else if (tmp == .LOWER) {
                    if (eval >= beta) {
                        return eval;
                    }
                } else if (tmp == .UPPER) {
                    if (eval >= _alpha) {
                        return eval;
                    }
                }
            }
            hashMove = _entry.val.search.bestMove;
        }
    }

    if (_depth == 0 or !p_info.alive) {
        return handleTerminalState(p_state, p_info, alpha, beta, p_features, ply, t, ss);
    }
    if (comptime t == .PV) {
        var pv: movel.pvContainer = .{};
        ss.getFrame(ply + 1).pv = &pv;
    }

    const f: boardl.boardFrame = .copy(p_state);
    var currS = ss.getFrame(ply);
    const static_eval = heuristicl.c_evaluate(p_state, &heuristicl.globalHeuristic, white);
    currS.staticEval = .{ .s = static_eval, .t = .STD };

    const isCheck = p_state.isChecked();

    var improving: bool = false;
    if (isCheck) {
        //
    } else if (ss.getPrevFrame(ply, 2).staticEval.t != .NONE) {
        improving = currS.staticEval.s > ss.getPrevFrame(ply, 2).staticEval.s;
    } else if (ss.getPrevFrame(ply, 4).staticEval.t != .NONE) {
        improving = currS.staticEval.s > ss.getPrevFrame(ply, 4).staticEval.s;
    } else {
        improving = true;
    }

    // null move prunning here
    // R = 3
    const isEndGame = p_state.isEndGame();
    if (p_features.useNullPrune and ply != 0) {
        // see chess programming video
        const R: u16 = if (improving) 3 else 4;
        if (_depth > R and !isCheck and !isEndGame) {
            p_state.makeNullMove();
            const score = -searchLoop(p_state, p_info, p_features, _depth - R, ply + R, -beta, 1 - beta, .NonPV, ss);
            p_state.undoNullMove();
            p_state.frame = f;
            if (score >= beta) {
                p_info.searchStat.n_cutoffs += 1;
                return score;
            }
        }
    }

    // staged
    var gen: heuristicl.moveGenerator = heuristicl.moveGenerator.init();
    gen.fetchNext(p_state);
    // captures are now in
    var useLMR = false;
    var hashMoveIsQuiet: bool = false;
    if (hashMove.isValid()) {
        if (hashMove.isQuietMove()) {
            gen.moves.append(hashMove);
            hashMoveIsQuiet = true;
        }
    }
    var order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, hashMove, _depth, currS.prevLineMove, false);

    if (p_features.useLMR and _depth >= 3 and !isCheck) {
        heuristicl.computeLateMoveReduc(p_state, &order, _depth, &gen.moves, improving);
        useLMR = true;
    }
    //https://www.talkchess.com/forum3/viewtopic.php?f=7&t=74403
    var canFutility: bool = false;
    var futilityScore: scoreType = 0;
    if (p_features.useFutility and !isCheck and @abs(alpha) < weightl.simpleCheckMateScore and _depth == 1 and comptime t == .NonPV) {
        const margin: scoreType = if (improving) heuristicl.futilityMargin else 100;
        //futilityScore = heuristicl.c_materialImbalance(p_state, &heuristicl.globalHeuristic, white) + margin;
        futilityScore = static_eval + margin;
        canFutility = true;
    }

    if (!isCheck and comptime t == .NonPV) {
        //https://www.chessprogramming.org/Razoring limited razoring
        const margin: scoreType = if (improving) 300 else 100;

        //if (p_features.useRazoring and _depth == 3 and (static_eval + margin) <= _alpha and p_state.getTotalPieceCount(!white) > 3) {
        //    _depth = 2;
        //}
        // this version from the cpw cpp code using the qsearch method
        if (p_features.useRazoring and depth <= 3) {
            const threshold = _alpha - 300 - (depth - 1) * 60;
            if (static_eval < threshold) {
                const q = quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, _alpha, beta, ply, isCheck, .NonPV, ss);
                if (q < threshold) {
                    return alpha;
                }
            }
        }
        if (p_features.useRFP and _depth == 2) {
            if (static_eval >= (beta + margin)) {
                return (static_eval + beta) >> 1;
            }
        }
    }

    var i: usize = 0;
    var tot: usize = 0;

    if (gen.moves.len == 0) {
        gen.fetchNext(p_state);
        order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, hashMove, _depth, currS.prevLineMove, false);
        if (useLMR) {
            heuristicl.computeLateMoveReduc(p_state, &order, _depth, &gen.moves, improving);
        }
    }
    var i_reset: bool = false;
    while (gen.pickNext(&order)) |move| : (i += 1) {
        //if (gen.extra == .CAPTURES) {
        //    const cPiece = p_state.getPiece(move.getTo());
        //    if (chess.isKingPiece(cPiece)) {
        //        continue;
        //    }
        //}
        if (!skipQuietMoves and i == (gen.moves.len - 1) and gen.extra == .CAPTURES) {
            gen.fetchNext(p_state);
            order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, hashMove, _depth, currS.prevLineMove, false);

            if (useLMR) {
                heuristicl.computeLateMoveReduc(p_state, &order, _depth, &gen.moves, improving);
            }
            i_reset = true;
        } else if (i_reset) {
            i = 0;
            i_reset = false;
            if (hashMoveIsQuiet) {
                continue;
            }
        }
        const to = move.getTo();
        const from = move.getFrom();

        if (canFutility) {
            if (!moveGenl.moveDeliverCheck(p_state, move) and (futilityScore + heuristicl.mat_gain(p_state, move)) < _alpha and tot > 4 and !move.isPromotion()) {
                continue;
            }
        }

        _ = p_state.makeMove(move);

        var score: scoreType = 0;
        if (i == 0) {
            score = -searchLoop(p_state, p_info, p_features, _depth - 1, ply + 1, -beta, -_alpha, t, ss);
        } else {
            if (useLMR and (order.depths[i] < (_depth - 1))) {
                score = -searchLoop(p_state, p_info, p_features, order.depths[i], ply + 1, -_alpha - 1, -_alpha, .NonPV, ss);
            } else {
                score = _alpha + 1;
            }
            if (score > _alpha) {
                score = -searchLoop(p_state, p_info, p_features, _depth - 1, ply + 1, -_alpha - 1, -_alpha, .NonPV, ss);
            }

            //https://web.archive.org/web/20150212051846/http://www.glaurungchess.com/lmr.html
            if (score > _alpha and comptime t == .PV) {
                score = -searchLoop(p_state, p_info, p_features, _depth - 1, ply + 1, -beta, -_alpha, .PV, ss);
            }
        }

        _ = p_state.undoMove();
        p_state.frame = f;

        if (tot == 0 or finalScore < score) {
            finalScore = score;
            bestMove = move;
            if (ply == 0) {
                currS.pv.?.onBestMove(move, ss.getFrame(ply + 1).pv);
            }
        }
        if (finalScore > _alpha) {
            _alpha = finalScore;
            hashFlag = .ALL;
            if (comptime t == .PV) {
                currS.pv.?.onBestMove(move, ss.getFrame(ply + 1).pv);
            }
            if (!(gen.extra == .CAPTURES)) {
                historyl.updateHistoryHeurist(white, from, to, heuristicl.computeHistoryBonus(_depth));
            }
        }
        if (_alpha >= beta) {
            const bonus = heuristicl.computeHistoryBonus(_depth);
            // save here the killer moves
            if (!move.isCapture()) {
                historyl.onKillerMove(move, ply);
                historyl.updateHistoryHeurist(white, from, to, bonus);
                //historyl.counterMoves[from][to] = move;
            }
            for (0..gen.moves.len) |j| {
                const idx = order.indexes[j];
                const _move = gen.moves.moves[idx];
                if (j != i) {
                    if (!_move.isCapture()) {
                        historyl.updateHistoryHeurist(white, _move.getFrom(), _move.getTo(), -bonus);
                    }
                }
            }
            if (p_features.useHash) {
                const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), _alpha, .LOWER, move);
                writer.writeShort(s_entry);
            }

            p_info.searchStat.n_cutoffs += 1;
            return _alpha;
        }
        tot += 1;
    }
    if (tot == 0) {
        if (isCheck) {
            _alpha = -(weightl.simpleCheckMateScore + @as(scoreType, @intCast(_depth)));
        } else {
            _alpha = weightl.simpleStalemateScore;
        }
    }
    if (p_features.useHash) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), _alpha, hashFlag, bestMove);
        writer.writeShort(s_entry);
    }

    return _alpha;
}
