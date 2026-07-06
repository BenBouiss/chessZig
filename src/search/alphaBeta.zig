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
const chessl = @import("../chess.zig");
const nnuel = @import("../nnue.zig");

const threadingl = @import("threading.zig");
const schedulerl = @import("scheduler.zig");

const IMove = movel.IMove;
const pvContainer = movel.pvContainer;
const scoreType = typel.scoreType;
const threadInfo = threadingl.threadInfo;
const milliDepth = typel.milliDepth;

// https://github.com/nescitus/cpw-engine/blob/master/search.cpp
pub fn aspirationSearchEntrypoint(p_state: *boardl.boardState, p_info: *threadInfo, depth: u16, p_features: *const schedulerl.searchFeatures, ss: *searchStack, val: scoreType) scoreType {
    var ret: scoreType = val;
    const alpha = val - weightl.aspirationCoefficient;
    const beta = val + weightl.aspirationCoefficient;
    ret = searchEntrypoint(p_state, p_info, depth, p_features, ss, alpha, beta);
    if ((ret <= alpha or ret >= beta) and p_info.alive) {
        ret = searchEntrypoint(p_state, p_info, depth, p_features, ss, -weightl.simpleCheckMateScore, weightl.simpleCheckMateScore);
    }
    return ret;
}

pub fn searchEntrypoint(p_state: *boardl.boardState, p_info: *threadInfo, depth: u16, p_features: *const schedulerl.searchFeatures, ss: *searchStack, alpha: scoreType, beta: scoreType) scoreType {
    p_info.working = true;

    var pv: pvContainer = .{};
    ss.getFrame(0).pv = &pv;

    if (nnuel.nnueNet.inited and comptime configl.USE_NNUE) {
        p_state.frame.nnueAccumul = nnuel.computeAccPair(&nnuel.nnueNet.net, p_state);
    }
    const score = searchLoop(p_state, p_info, p_features, depth, 0, alpha, beta, ss, false, .PV);

    if (p_info.alive) {
        const move = pv.moves[0];
        p_info.currentBest.move = move;
        p_info.currentBest.scoring = score;
        p_info.currentBest.line.setLineFromPV(&pv);
        p_info.currentBest.depth = depth;
        p_info.depth = depth;
    }
    return score;
}
pub const searchType = enum { NonPV, PV };

pub fn quiescenceSearch(p_state: *boardl.boardState, p_info: *threadInfo, depth: u16, alpha: scoreType, beta: scoreType, ply: u16, ss: *searchStack) scoreType {
    // first vers adapt of the pseudo code: https://www.chessprogramming.org/Quiescence_Search

    var _alpha = alpha;
    var currS = ss.getFrame(ply);
    var bestMove: IMove = .{};
    const static_eval = correct_eval(p_state, ss, heuristicl.c_evaluate(p_state, p_state.whiteToMove()), ply);
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
        _alpha = best_value;
    }

    var gen: heuristicl.moveGenerator = heuristicl.moveGenerator.init();
    gen.fetchNext(p_state);
    const order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, .{}, currS.prevLineMove, true);

    var i: usize = 0;
    const historyBonus = heuristicl.computeHistoryBonus(depth);

    while (gen.pickNext(&order)) |move| : (i += 1) {
        if (i > weightl.moveReductionAmount) {
            break;
        }
        var _delta = BIG_DELTA;
        if (move.isPromotion()) {
            _delta += weightl.simpleQueenScore - 200;
        }
        // delta pruning
        if (static_eval < (_alpha - _delta) or heuristicl.losingCaptureT(p_state, move, -100)) {
            continue;
        }
        const from = move.getFrom();
        const fPiece = p_state.getPiece(from);

        p_state.makeMove(move);
        if (comptime configl.USE_NNUE) {
            nnuel.updateNnueOnMove(p_state, move);
        }
        const score = -quiescenceSearch(p_state, p_info, depth - 1, -beta, -_alpha, ply + 1, ss);

        _ = p_state.undoMove();
        p_state.frame = f;

        if (score > best_value) {
            best_value = score;
            bestMove = move;
        }
        if (score > _alpha) {
            _alpha = score;

            const to = move.getTo();
            const cPiece = p_state.getCapturePiece(move);
            historyl.updateCaptureHistory(fPiece, cPiece, to, historyBonus);
            if (score >= beta) {
                for (0..gen.moves.len) |j| {
                    const idx = order.indexes[j];
                    const _move = gen.moves.moves[idx];
                    if (j != i) {
                        const fromP = _move.getFrom();
                        const toP = _move.getTo();
                        historyl.updateCaptureHistory(p_state.getPiece(fromP), p_state.getCapturePiece(_move), toP, -historyBonus);
                    }
                }
                p_info.searchStat.n_cutoffs += 1;
                return score;
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
    //playedMove: IMove = .{},
    //pieceMoved: typel.e_piece = .nEmptySquare,
    pv: ?*movel.pvContainer = null,
};

// used to garanty getFrameOffset(0, 4) returns a default value
pub const negativeOffset: u16 = 4;
//index by ply
pub const searchStack = struct {
    e: [typel.MAX_PLY + configl.MAX_QUIESC_DEPTH + negativeOffset + 1]searchFrame = @splat(.{}),
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
pub fn searchLoop(p_state: *boardl.boardState, p_info: *threadingl.threadInfo, p_features: *const schedulerl.searchFeatures, depth: u16, ply: u16, alpha: scoreType, beta: scoreType, ss: *searchStack, wasExtended: bool, comptime t: searchType) scoreType {
    var _alpha = alpha;
    var _depth = depth;
    var extension: u16 = 0;
    var extended: bool = wasExtended;
    const white: bool = p_state.whiteToMove();
    var useLMR = false;
    if (p_state.isStaleMateRepetition()) {
        return weightl.simpleStalemateScore;
    }
    var finalScore: scoreType = -weightl.simpleCheckMateScore - 1;
    var bestMove: IMove = .{};
    var hashMove: IMove = .{};
    var hashType: hashl.nodeType = .ALL;
    var hashFlag: hashl.nodeType = .UPPER;
    const skipQuietMoves: bool = false;
    var hashEval: scoreType = 0;
    const res = hashl.hashTable.probeMatch(p_state.frame.key.code, @intCast(_depth), p_state, @intCast(p_info.searchStat.n_nodeExplored));
    var writer = res.writer;
    var ttHit: bool = false;
    if (res.entry) |_entry| {
        p_info.searchStat.n_hashRetrieve += 1;
        ttHit = true;
        //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
        hashEval = _entry.evaluation;
        hashType = _entry.nodeT();
        if (comptime t == .NonPV) {
            if (hashType == .ALL or (hashType == .LOWER and hashEval >= beta) or (hashType == .UPPER and hashEval >= _alpha)) {
                return hashEval;
            }
        } else {
            //if (hashType == .ALL and !wasExtended) {
            //    extension += 1;
            //    extended = true;
            //}
        }
        hashMove = _entry.bestMove;
    }
    const isCheck = p_state.isChecked();
    if (isCheck) {
        _depth += 1;
    }
    if (_depth == 0 or !p_info.alive) {
        p_info.searchStat.n_nodeExplored += 1;
        return quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, alpha, beta, ply, ss);
    }
    if (comptime t == .PV) {
        var pv: movel.pvContainer = .{};
        ss.getFrame(ply + 1).pv = &pv;
    }

    const f: boardl.boardFrame = .copy(p_state);
    var currS = ss.getFrame(ply);
    //const static_eval = if (hashMove.isValid()) (hashEval) else (correct_eval(p_state, ss, heuristicl.c_evaluate(p_state, white), ply));
    const static_eval = if (ttHit) (hashEval) else heuristicl.c_evaluate(p_state, white);
    const hashMoveIsCapture = hashMove.isCapture();
    currS.staticEval = .{ .s = static_eval, .t = .STD };

    var improving: bool = false;

    if (isCheck) {} else if (ss.getPrevFrame(ply, 2).staticEval.t != .NONE) {
        improving = currS.staticEval.s > ss.getPrevFrame(ply, 2).staticEval.s;
    } else if (ss.getPrevFrame(ply, 4).staticEval.t != .NONE) {
        improving = currS.staticEval.s > ss.getPrevFrame(ply, 4).staticEval.s;
    } else {
        improving = true;
    }
    var lmrDepth: milliDepth = weightl.lmr_baseDeficit;
    if (t == .PV) {
        lmrDepth += weightl.lmr_inPvMode;
    }
    if (!improving) {
        lmrDepth += weightl.lmr_notImproving;
    }
    if (hashMoveIsCapture) {
        lmrDepth += weightl.lmr_hashMoveCapture;
    }
    // never hit
    if (hashType == .LOWER) {
        lmrDepth += weightl.lmr_expectedCutOff;
    }

    // null move prunning here
    // R = 3
    const isEndGame = p_state.isEndGame();
    if (ply != 0) {
        // see chess programming video
        const augment: u16 = if (_depth > weightl.nullMoveDepthAugmentThreshold) @intCast(weightl.nullMoveDepthAugment) else 0;
        const R: u16 = augment + @as(u16, @intCast(if (improving) weightl.nullMoveReductionImproving else weightl.nullMoveReduction));
        if (_depth > R and !isCheck and !isEndGame) {
            //currS.playedMove = .{};
            //currS.pieceMoved = .nWhitePawn;
            p_state.makeNullMove();
            const score = -searchLoop(p_state, p_info, p_features, _depth - R, ply + R, -beta, 1 - beta, ss, extended, .NonPV);
            //const score = -searchLoop(p_state, p_info, p_features, _depth - R, ply + R, -_alpha - 1, -alpha, ss, extended, .NonPV);
            p_state.undoNullMove();
            p_state.frame = f;
            if (score >= beta) {
                p_info.searchStat.n_cutoffs += 1;
                return score;
            }
        }
    }

    //https://www.talkchess.com/forum3/viewtopic.php?f=7&t=74403
    // https://github.com/nescitus/cpw-engine/
    var canFutility: bool = false;
    //var futilityScore: scoreType = 0;
    //if (p_features.useFutility and !isCheck and @abs(alpha) < weightl.simpleCheckMateScore and _depth == 1 and comptime t == .NonPV) {
    //    const margin: scoreType = if (improving) heuristicl.futilityMargin else 100;
    //    futilityScore = static_eval + margin;
    //    canFutility = true;
    //}
    if (!isCheck and !chessl.isMate(alpha) and _depth <= 3 and (static_eval + weightl.futilityMargin[_depth]) <= _alpha and comptime t == .NonPV) {
        canFutility = true;
    }

    if (!isCheck and !hashMove.isValid() and comptime t == .NonPV) {
        if (_depth <= 3) {
            const margin: scoreType = if (improving) 0 else weightl.rfpImproving;
            if (static_eval >= (beta + weightl.rfpMargin[_depth] + margin)) {
                return (static_eval + beta) >> 1;
            }
        }
        //https://www.chessprogramming.org/Razoring limited razoring
        //const threshold = _alpha - 300 - (_depth - 1) * 60;
        //if (p_features.useRazoring) {
        //    const threshold: scoreType = if (improving) weightl.razoringThresholdImproving else weightl.razoringThresholdNotImproving;
        //    if (_depth == 3 and (static_eval + threshold) <= _alpha and p_state.getTotalPieceCount(!white) > 3) {
        //        _depth = 2;
        //    }
        //}

        // this version from the cpw cpp code using the qsearch method
        if (p_features.useRazoring) {
            const base: scoreType = if (improving) weightl.razoringBaseImproving else weightl.razoringBaseNotImproving;
            const threshold = _alpha - (_depth * _depth * weightl.razoringCoefficient) - base;
            if (static_eval < threshold and @abs(_alpha) < weightl.simpleCheckMateScore) {
                const val = quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, _alpha, beta, ply, ss);
                if (val < _alpha) {
                    return _alpha;
                }
            }
        }
    }

    var i: usize = 0;
    var tot: usize = 0;

    // staged
    var gen: heuristicl.moveGenerator = heuristicl.moveGenerator.init();
    gen.fetchNext(p_state);
    if (gen.moves.len == 0) {
        gen.fetchNext(p_state);
    }

    // https://www.chessprogramming.org/Internal_Iterative_Reductions
    const prevSS = ss.getPrevFrame(ply, 1);
    if (_depth >= weightl.IIRDepth and !hashMove.isValid() and !p_state.getLastMove().equal(prevSS.prevLineMove) and hashType == .LOWER and comptime t == .NonPV) {
        _depth -= 1;
    }

    var order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, hashMove, currS.prevLineMove, false);

    const p_beta = beta + weightl.probCutMargin;
    if (p_features.useProbCut and _depth > weightl.probCutMinimalDepth and !chessl.isMate(beta)) {
        if ((hashMove.isValid() and hashEval >= p_beta and hashMoveIsCapture) or (static_eval >= beta)) {
            const tresh = p_beta - static_eval;
            while (gen.pickNext(&order)) |move| {
                if (!heuristicl.SEE_threshold(p_state, move, tresh)) {
                    continue;
                }

                //const from = move.getFrom();
                //const fPiece = p_state.getPiece(from);
                //currS.playedMove = move;
                //currS.pieceMoved = fPiece;
                _ = p_state.makeMove(move);
                if (comptime configl.USE_NNUE) {
                    nnuel.updateNnueOnMove(p_state, move);
                }
                var score = -quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, -p_beta, -p_beta + 1, ply + 1, ss);
                if (score >= p_beta) {
                    score = -searchLoop(p_state, p_info, p_features, _depth - 4, ply + 1, -p_beta, -p_beta + 1, ss, extended, .NonPV);
                }
                _ = p_state.undoMove();
                p_state.frame = f;
                if (score >= p_beta) {
                    // save to TT
                    const probCutEntry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth - 4), score, .LOWER, move, white);
                    writer.writeShort(probCutEntry);
                    return score;
                }
            }
        }
        gen.idx = 0;
    }

    const fDepth = heuristicl.lmrFDepth(heuristicl.depthToMilliDepth(_depth));
    if (_depth >= weightl.LMRDepth and !isCheck) {
        useLMR = true;
    }
    const otherKingSq = p_state.getKingSq(!white);
    const safetyArea = chessl.safetyArea(otherKingSq);

    const historyBonus = heuristicl.computeHistoryBonus(_depth);
    var i_reset: bool = false;
    while (gen.pickNext(&order)) |move| : (i += 1) {
        if (!skipQuietMoves and i == (gen.moves.len - 1) and gen.extra == .CAPTURES) {
            gen.fetchNext(p_state);
            order = heuristicl.eval_move_sorting_mask(p_state, &gen.moves, ply, hashMove, currS.prevLineMove, false);
            i_reset = true;
        } else if (i_reset) {
            i = 0;
            i_reset = false;
        }

        var _lmrDepth = lmrDepth;
        const to = move.getTo();
        const from = move.getFrom();
        const fPiece = p_state.getPiece(from);
        const givesCheck = moveGenl.moveDeliverCheck(p_state, move);
        const isCapture = move.isCapture();
        const isThreat = (chessl.xToBitboard(to) & safetyArea) != 0;
        const isQuiet = gen.extra != .CAPTURES;
        const cPiece = p_state.getCapturePiece(move);

        if (chessl.isKingPiece(cPiece)) {
            // pseudo legal move gen
            return weightl.simpleCheckMateScore;
        }

        const isPromo = move.isPromotion();

        if (isQuiet) {
            if (canFutility) {
                if (!givesCheck and tot > weightl.moveReductionAmount and !isPromo) {
                    continue;
                }
            }
        } else {
            if (!wasExtended and to == p_state.getLastMove().getTo() and historyl.captureHistory[@intFromEnum(fPiece)][@intFromEnum(cPiece)][to] > weightl.captureExtensionThresh and comptime t == .PV) {
                extension += 1;
                extended = true;
            }
        }
        if (ply != 0 and depth <= weightl.SeePruningMaxDepth) {
            const margin = if (isQuiet) weightl.SeePruningQuietMargin else weightl.SeePruningCaptureMargin;
            if (!heuristicl.SEE_threshold(p_state, move, depth * margin)) {
                continue;
            }
        }
        if (givesCheck) {
            _lmrDepth += weightl.lmr_givesCheck;
        }
        if (isPromo) {
            _lmrDepth += weightl.lmr_isPromotion;
        }
        const scoreOrder = order.scores[i];
        if (scoreOrder >= weightl.lmr_scoreThreshold) {
            _lmrDepth += weightl.lmr_killerMove;
        } else if (isCapture and !isThreat) {
            _lmrDepth += weightl.lmr_badCapture;
        }
        _lmrDepth += (weightl.lmr_oldMulti * @as(scoreType, @intCast(std.math.log(usize, 10, @intCast(i + 1)))));

        //currS.playedMove = move;
        //currS.pieceMoved = fPiece;
        _ = p_state.makeMove(move);

        if (comptime configl.USE_NNUE) {
            nnuel.updateNnueOnMove(p_state, move);
        }

        var score: scoreType = 0;
        if (i == 0) {
            score = -searchLoop(p_state, p_info, p_features, _depth - 1 + extension, ply + 1, -beta, -_alpha, ss, extended, t);
        } else {
            if (useLMR and i > weightl.moveReductionAmount) {
                const d = _depth - 1 - @as(u16, (@intCast(@min((@max(_lmrDepth + fDepth, 0)) >> 10, _depth - 1))));
                score = -searchLoop(p_state, p_info, p_features, d + extension, ply + 1, -_alpha - 1, -_alpha, ss, extended, .NonPV);
            } else {
                score = _alpha + 1;
            }
            if (score > _alpha) {
                score = -searchLoop(p_state, p_info, p_features, _depth - 1 + extension, ply + 1, -_alpha - 1, -_alpha, ss, extended, .NonPV);
            }

            //https://web.archive.org/web/20150212051846/http://www.glaurungchess.com/lmr.html
            if (score > _alpha and comptime t == .PV) {
                score = -searchLoop(p_state, p_info, p_features, _depth - 1 + extension, ply + 1, -beta, -_alpha, ss, extended, .PV);
            }
        }

        _ = p_state.undoMove();
        p_state.frame = f;

        if ((tot == 0 and ply == 0) or finalScore < score) {
            finalScore = score;
            bestMove = move;
            //if (comptime t == .PV) {
            //    currS.pv.?.onBestMove(move, ss.getFrame(ply + 1).pv);
            //}
        }
        tot += 1;
        if (finalScore > _alpha) {
            _alpha = finalScore;
            hashFlag = .ALL;
            if (isQuiet) {
                historyl.updateHistoryHeurist(white, from, to, historyBonus);
            } else {
                historyl.updateCaptureHistory(fPiece, cPiece, to, historyBonus);
            }

            if (_alpha >= beta) {
                hashFlag = .LOWER;
                // save here the killer moves
                if (isQuiet) {
                    historyl.onKillerMove(move, ply);
                    for (0..gen.moves.len) |j| {
                        const idx = order.indexes[j];
                        const _move = gen.moves.moves[idx];
                        if (j != i) {
                            const fromP = _move.getFrom();
                            const toP = _move.getTo();
                            historyl.updateHistoryHeurist(white, fromP, toP, -historyBonus);
                        }
                    }
                } else {
                    // in capture mode
                    //historyl.updateCaptureHistory(fPiece, cPiece, to, historyBonus);
                    for (0..gen.moves.len) |j| {
                        const idx = order.indexes[j];
                        const _move = gen.moves.moves[idx];
                        if (j != i) {
                            const fromP = _move.getFrom();
                            const toP = _move.getTo();
                            historyl.updateCaptureHistory(p_state.getPiece(fromP), p_state.getCapturePiece(_move), toP, -historyBonus);
                        }
                    }
                }
                const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), _alpha, .LOWER, move, white);
                writer.writeShort(s_entry);
                p_info.searchStat.n_cutoffs += 1;
                return _alpha;
            }
            if (comptime t == .PV) {
                currS.pv.?.onBestMove(move, ss.getFrame(ply + 1).pv);
            }
        }
    }
    if (tot == 0) {
        if (isCheck) {
            _alpha = chessl.mated_in(_depth);
        } else {
            _alpha = weightl.simpleStalemateScore;
        }
    }
    //if (!isCheck and (!bestMove.isCapture() or !bestMove.isValid()) and !(_alpha >= beta and _alpha <= static_eval) and !(bestMove.isValid() and _alpha >= static_eval)) {
    //    const bonus =
    //        std.math.clamp(@divFloor((_alpha - static_eval) * depth, 8), -256, 256);
    //    if (ply > 1) {
    //        const prev1 = ss.getPrevFrame(ply, 1);
    //        const prev2 = ss.getPrevFrame(ply, 2);
    //        update_corrhist(&historyl.corrHist[@intFromEnum(prev2.pieceMoved)][prev2.playedMove.getTo()][@intFromEnum(prev1.pieceMoved)][prev1.playedMove.getTo()], bonus);
    //    }
    //}
    if (comptime t == .PV) {
        // .PV set to not store position that could be obtained after a possible nullmove. TODO: just filter out nullmove
        const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), _alpha, hashFlag, bestMove, white);
        writer.writeShort(s_entry);
    }
    return _alpha;
}
pub fn correct_eval(p_state: *const boardl.boardState, ss: *searchStack, eval: scoreType, ply: u16) scoreType {
    _ = p_state;
    _ = ply;
    _ = ss;
    return eval;
    //const _eval: scoreType = eval * @divFloor(200 - p_state.frame.halfMoveClock, 200);
    //var corr: scoreType = 0;
    //if (ply > 1) {
    //    const prev1 = ss.getPrevFrame(ply, 1);
    //    const prev2 = ss.getPrevFrame(ply, 2);
    //    corr += historyl.corrHist[@intFromEnum(prev2.pieceMoved)][prev2.playedMove.getTo()][@intFromEnum(prev1.pieceMoved)][prev1.playedMove.getTo()];
    //}

    //return std.math.clamp(_eval + @divFloor(1 * corr, 512), -weightl.simpleCheckMateThreshold + 1, weightl.simpleCheckMateThreshold - 1);
}
pub inline fn update_corrhist(val: *scoreType, score: scoreType) void {
    _ = val;
    _ = score;
    //val.* += score - @divFloor(val.* * @as(scoreType, @intCast(@abs(score))), 1024);
}
