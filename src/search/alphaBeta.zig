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
const e_color = typel.e_color;

pub fn searchEntrypoint(p_state: *boardl.boardState, p_info: *threadInfo, depth: u16, p_features: *const schedulerl.searchFeatures, ss: *searchStack, alpha: scoreType, beta: scoreType) scoreType {
    p_info.working = true;

    var pv: pvContainer = .{};
    ss.getFrame(0).pv = &pv;

    if (nnuel.nnueNet.inited and comptime configl.USE_NNUE) {
        p_state.frame.nnueAccumul = nnuel.computeAccPair(&nnuel.nnueNet.net, p_state);
    }
    var threadD: threadData = .{};
    const score = searchLoop(p_state, p_info, p_features, depth, 0, alpha, beta, ss, &threadD, false, false, .PV);

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
    if (p_state.isStaleMateRepetition()) {
        return weightl.simpleStalemateScore;
    }
    if (depth == 0) {
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

    //var gen: moveGenl.moveGenerator = .init();
    var gen: moveGenl.typeMoveGenerator = .init();

    var i: usize = 0;
    const historyBonus = heuristicl.computeHistoryBonus(depth);

    while (gen.pickNext(p_state, ply, .{}, currS.prevLineMove, true, true)) |move| : (i += 1) {
        if (!p_state.legal(move)) continue;
        const from = move.getFrom();
        const fPiece = p_state.getPiece(from);
        const cPiece = p_state.getCapturePiece(move);
        //if (chessl.isKingPiece(cPiece)) {
        //    // pseudo legal move gen
        //    return weightl.simpleCheckMateScore;
        //}
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
        currS.playedMove = move;
        currS.pieceMoved = fPiece;

        p_state.makeMove(move);
        hashl.hashTable.prefetchHash(p_state.frame.key);
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
            historyl.updateCaptureHistory(fPiece, cPiece, to, historyBonus);
            if (score >= beta) {
                currS.failHighCount += 1;
                for (0..gen._moves.moves.len) |j| {
                    const _move = gen._moves.moves.moves[j];
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
    followPv: bool = false,
    prevLineMove: IMove = .{},
    playedMove: IMove = .{},
    pieceMoved: typel.e_piece = .nEmptySquare,
    pv: ?*movel.pvContainer = null,
    failHighCount: u16 = 0,
};
pub const threadData = struct {
    excludedMove: IMove = .{},
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
pub fn searchLoop(p_state: *boardl.boardState, p_info: *threadingl.threadInfo, p_features: *const schedulerl.searchFeatures, depth: u16, ply: u16, alpha: scoreType, beta: scoreType, ss: *searchStack, threadD: *threadData, wasExtended: bool, cutnode: bool, comptime t: searchType) scoreType {
    var _alpha = alpha;
    var _beta = beta;
    var _depth = depth;
    var extension: u16 = 0;
    var extended: bool = wasExtended;
    const white: bool = p_state.whiteToMove();
    const isRoot: bool = ply == 0;
    const mate_value = chessl.mate_in(ply);
    //const isAllNode = !(t == .PV or cutnode);
    if (p_state.isStaleMateRepetition()) {
        return weightl.simpleStalemateScore;
    }
    var bestScore: scoreType = -weightl.simpleCheckMateScore - 1;
    var bestMove: IMove = .{};
    var hashMove: IMove = .{};
    var hashDepth: u16 = 0;
    var hashType: hashl.nodeType = .ALL;
    var hashFlag: hashl.nodeType = .UPPER;
    var skipQuietMoves: bool = false;

    var hashEval: scoreType = 0;
    const excludedMove = threadD.excludedMove;
    //const singularExt: bool = if (excludedMove.isValid()) true else false;
    threadD.excludedMove = .{};

    if (_depth == 0 or schedulerl.outOfTime(p_info)) {
        p_info.searchStat.n_nodeExplored += 1;
        return quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, _alpha, _beta, ply, ss);
    }
    // https://github.com/nescitus/cpw-engine/blob/master/search.cpp
    if (!isRoot) {
        if (mate_value < _beta) {
            _beta = mate_value;
            if (_alpha >= _beta) {
                return _alpha;
            }
        }
    }

    const res = hashl.hashTable.probeMatch(p_state.frame.key, @intCast(_depth), p_state, @intCast(p_info.searchStat.n_nodeExplored));
    var writer = res.writer;
    var ttHit: bool = false;
    if (res.entry) |_entry| {
        p_info.searchStat.n_hashRetrieve += 1;
        ttHit = true;
        //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
        hashEval = _entry.evaluation;
        hashType = _entry.nodeT();
        if (comptime t == .NonPV) {
            if (hashType == .ALL or (hashType == .LOWER and hashEval >= _beta) or (hashType == .UPPER and hashEval >= _alpha)) {
                return hashEval;
            }
        } else {
            //if (hashType == .ALL) {
            //    extension += 1;
            //    extended = true;
            //}
        }
        hashMove = _entry.bestMove;
        hashDepth = @intCast(_entry._depth);
    }
    const isCheck = p_state.isChecked();
    if (isCheck) {
        _depth += 1;
    }

    if (comptime t == .PV) {
        var pv: movel.pvContainer = .{};
        ss.getFrame(ply + 1).pv = &pv;
    }

    const f: boardl.boardFrame = .copy(p_state);
    var currS = ss.getFrame(ply);
    const nextS = ss.getFrame(ply + 1);
    const prevSS = ss.getPrevFrame(ply, 1);
    const static_eval = if (ttHit) (hashEval) else correct_eval(p_state, ss, heuristicl.c_evaluate(p_state, white), ply);

    const hashMoveIsCapture = hashMove.isCapture();
    currS.staticEval = .{ .s = static_eval, .t = .STD };
    currS.followPv = if (isRoot) true else prevSS.followPv and p_state.getLastMove().equal(prevSS.prevLineMove);

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
    if (cutnode) {
        lmrDepth += weightl.lmr_expectedCutOff;
    }

    // null move prunning here
    // R = 3
    // const isEndGame = p_state.isEndGame();
    //and !p_state.onlyPawnsSide(white)
    if (!isRoot and !p_state.onlyPawnsSide(white)) {
        // see chess programming video
        const augment: u16 = if (_depth > weightl.nullMoveDepthAugmentThreshold) @intCast(weightl.nullMoveDepthAugment) else 0;
        const R: u16 = augment + @as(u16, @intCast(if (improving) weightl.nullMoveReductionImproving else weightl.nullMoveReduction));
        if (_depth > R and !isCheck) {
            currS.playedMove = .{};
            currS.pieceMoved = .nWhitePawn;
            p_state.makeNullMove();
            const score = -searchLoop(p_state, p_info, p_features, _depth - R, ply + R, -_beta, 1 - _beta, ss, threadD, extended, !cutnode, .NonPV);
            p_state.undoNullMove();
            p_state.frame = f;
            if (score >= _beta) {
                p_info.searchStat.n_cutoffs += 1;
                return score;
            }
        }
    }

    var canFutility: bool = false;
    //https://www.talkchess.com/forum3/viewtopic.php?f=7&t=74403
    // https://github.com/nescitus/cpw-engine/
    //var canFutility: bool = false;
    //var futilityScore: scoreType = 0;
    //if (p_features.useFutility and !isCheck and @abs(alpha) < weightl.simpleCheckMateScore and _depth == 1 and comptime t == .NonPV) {
    //    const margin: scoreType = if (improving) heuristicl.futilityMargin else 100;
    //    futilityScore = static_eval + margin;
    //    canFutility = true;
    //}
    if (!isCheck and !chessl.isMate(alpha) and _depth <= weightl.futilityDepth and (static_eval + weightl.futilityConst + weightl.futilityCoeff * _depth) <= _alpha) {
        canFutility = true;
    }
    //if (!isCheck and !chessl.isMate(alpha) and _depth <= weightl.futilityDepth and (static_eval + weightl.futilityMargin[_depth]) <= _alpha and comptime t == .NonPV) {
    //    canFutility = true;
    //}

    //TODO: change margin from array to coeff and increase depth
    if (!isCheck and !hashMove.isValid() and comptime t == .NonPV) {
        //TODO: change margin from array to coeff and increase depth
        if (_depth <= weightl.rfpDepth) {
            const margin: scoreType = if (improving) 0 else weightl.rfpImproving;
            //if (static_eval >= (_beta + weightl.rfpMargin[_depth] + margin)) {
            if (static_eval >= (_beta + weightl.rfpCoeff * _depth + weightl.rfpConst + margin)) {
                return (static_eval + _beta) >> 1;
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
                const val = quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, _alpha, _beta, ply, ss);
                if (val < _alpha) {
                    return _alpha;
                }
            }
        }
    }

    // https://www.chessprogramming.org/Internal_Iterative_Reductions
    if (_depth >= weightl.IIRDepth and !hashMove.isValid() and !currS.followPv and (hashType == .LOWER and t == .NonPV)) {
        //if (_depth >= weightl.IIRDepth and !hashMove.isValid() and !currS.followPv and !isAllNode) {
        _depth -= 1;
    }

    // staged
    //var gen: moveGenl.moveGenerator = .init();
    var gen: moveGenl.typeMoveGenerator = .init();

    ss.getFrame(ply + 2).failHighCount = 0;

    const p_beta = _beta + weightl.probCutMargin;
    if (p_features.useProbCut and _depth > weightl.probCutMinimalDepth and !chessl.isMate(_beta)) {
        if ((hashMove.isValid() and hashEval >= p_beta and hashMoveIsCapture) or (static_eval >= _beta)) {
            const tresh = p_beta - static_eval;
            while (gen.pickNext(p_state, ply, hashMove, currS.prevLineMove, false, true)) |move| {
                if (!p_state.legal(move)) continue;
                if (!heuristicl.SEE_threshold(p_state, move, tresh) or move.equal(excludedMove)) {
                    continue;
                }

                const from = move.getFrom();
                const fPiece = p_state.getPiece(from);
                currS.playedMove = move;
                currS.pieceMoved = fPiece;
                _ = p_state.makeMove(move);
                hashl.hashTable.prefetchHash(p_state.frame.key);
                if (comptime configl.USE_NNUE) {
                    nnuel.updateNnueOnMove(p_state, move);
                }
                var score = -quiescenceSearch(p_state, p_info, configl.MAX_QUIESC_DEPTH, -p_beta, -p_beta + 1, ply + 1, ss);
                if (score >= p_beta) {
                    score = -searchLoop(p_state, p_info, p_features, _depth - 4, ply + 1, -p_beta, -p_beta + 1, ss, threadD, extended, false, t);
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

    const useLMR = (_depth >= weightl.LMRDepth and !isCheck);

    const otherKingSq = p_state.getKingSq(!white);
    const safetyArea = chessl.safetyArea(otherKingSq);

    const historyBonus = heuristicl.computeHistoryBonus(_depth);
    var movesPlayed: u8 = 0;
    var phasePlay: u8 = 0;
    var phaseReset: bool = false;
    const fDepth = heuristicl.lmrFDepth(heuristicl.depthToMilliDepth(_depth));

    while (gen.pickNext(p_state, ply, hashMove, currS.prevLineMove, false, skipQuietMoves)) |move| {
        if (move.equal(excludedMove)) {
            continue;
        }
        if (!p_state.legal(move)) continue;
        //if (!phaseReset and gen.extra == .QUIET) {
        if (!phaseReset and gen.phase == .QUIET) {
            phaseReset = true;
            phasePlay = 0;
        }

        const idx = gen.idx - 1;
        const to = move.getTo();
        const from = move.getFrom();
        const fPiece = p_state.getPiece(from);
        const givesCheck = moveGenl.moveDeliverCheck(p_state, move);
        const isCapture = move.isCapture();
        const isThreat = (chessl.xToBitboard(to) & safetyArea) != 0;
        const cPiece = p_state.getCapturePiece(move);
        const isPromo = move.isPromotion();

        if (!isRoot and depth <= weightl.SeePruningMaxDepth) {
            const margin = if (!isCapture) weightl.SeePruningQuietMargin else weightl.SeePruningCaptureMargin;
            if (!heuristicl.SEE_threshold(p_state, move, depth * margin)) {
                continue;
            }
        }

        if (!isCapture) {
            if (comptime t == .NonPV) {
                if (canFutility and !givesCheck and phasePlay > weightl.moveReductionAmount and !isPromo) {
                    continue;
                    //if (_depth <= weightl.futilityDepth and !isCheck and (static_eval + weightl.futilityConst + weightl.futilityCoeff * _depth) < alpha) {
                    //    skipQuietMoves = true;
                }
                if (depth <= weightl.lmpMaxDepth and phasePlay >= weightl.lmpBase + @divFloor(_depth * _depth, 2 - @as(scoreType, @intFromBool(improving)))) {
                    skipQuietMoves = true;
                }

                if (!isCheck and phasePlay >= weightl.historyMinExplore) {
                    const histScore: scoreType = historyl.historyHeuristic[chessl.whiteBoolToInt(white)][from][to];
                    if (histScore < (weightl.historyThreshCoeff * _depth + weightl.historyThreshConst)) {
                        continue;
                    }
                }
            }
        } else if (isCapture) {
            if (!wasExtended and to == p_state.getLastMove().getTo() and historyl.captureHistory[@intFromEnum(fPiece)][@intFromEnum(cPiece)][to] > weightl.captureExtensionThresh and comptime t == .PV) {
                extension += 1;
                extended = true;
            }
        }

        currS.playedMove = move;
        currS.pieceMoved = fPiece;
        _ = p_state.makeMove(move);
        hashl.hashTable.prefetchHash(p_state.frame.key);

        if (comptime configl.USE_NNUE) {
            nnuel.updateNnueOnMove(p_state, move);
        }

        var fullSearch: bool = false;
        var score: scoreType = 0;

        // rewrite of main search handling
        // https://github.com/Adam-Kulju/Patricia/
        if (useLMR and phasePlay > weightl.moveReductionAmount) {
            var _lmrDepth = lmrDepth + fDepth;
            if (givesCheck) {
                _lmrDepth += weightl.lmr_givesCheck;
            }
            if (isPromo) {
                _lmrDepth += weightl.lmr_isPromotion;
            }
            const scoreOrder = gen._moves.scores[idx];
            if (scoreOrder >= weightl.lmr_scoreThreshold) {
                _lmrDepth += weightl.lmr_killerMove;
            } else if (isCapture and !isThreat and scoreOrder < 0) {
                _lmrDepth += weightl.lmr_badCapture;
            }
            if (nextS.failHighCount > weightl.lmr_highFailCount) {
                _lmrDepth += weightl.lmr_highFailScore;
            }
            _lmrDepth += historyl.lmrBase[movesPlayed];

            const d = _depth - 1 - @as(u16, (@intCast(@min((@max(_lmrDepth, 0)) >> 10, _depth - 1))));
            score = -searchLoop(p_state, p_info, p_features, d + extension, ply + 1, -_alpha - 1, -_alpha, ss, threadD, extended, true, .NonPV);
            if (score > _alpha) {
                //fullSearch = _lmrDepth < 0;
                fullSearch = true;
            }
        } else {
            // ignores the first move for the full search
            fullSearch = (phasePlay != 0) or t == .NonPV;
        }
        if (fullSearch) {
            score = -searchLoop(p_state, p_info, p_features, _depth - 1 + extension, ply + 1, -_alpha - 1, -_alpha, ss, threadD, extended, !cutnode, .NonPV);
        }
        if ((phasePlay == 0 or score > _alpha) and comptime t == .PV) {
            score = -searchLoop(p_state, p_info, p_features, _depth - 1 + extension, ply + 1, -_beta, -_alpha, ss, threadD, extended, false, .PV);
        }

        _ = p_state.undoMove();
        p_state.frame = f;

        if (movesPlayed == 0 or score > bestScore) {
            bestScore = score;
            bestMove = move;
        }
        movesPlayed += 1;
        phasePlay += 1;

        if (bestScore > _alpha) {
            _alpha = bestScore;
            bestMove = move;
            hashFlag = .ALL;
            if (isCapture) {
                historyl.updateCaptureHistory(fPiece, cPiece, to, historyBonus);
            } else {
                historyl.updateHistoryHeurist(white, from, to, historyBonus);
            }

            if (_alpha >= _beta) {
                hashFlag = .LOWER;
                // save here the killer moves
                if (isCapture) {
                    updateOnBetaCut(p_state, idx, -historyBonus, &gen, white, .CAPTURE);
                } else {
                    historyl.onKillerMove(move, ply);
                    updateOnBetaCut(p_state, idx, -historyBonus, &gen, white, .QUIET);
                }
                p_info.searchStat.n_cutoffs += 1;
                break;
            }
            if (comptime t == .PV) {
                currS.pv.?.onBestMove(move, ss.getFrame(ply + 1).pv);
            }
        }
    }
    if (movesPlayed == 0) {
        if (isCheck) {
            _alpha = chessl.mated_in(_depth);
        } else {
            _alpha = weightl.simpleStalemateScore;
        }
    }
    if (!isCheck and (!bestMove.isCapture()) and (hashFlag == .LOWER and bestScore > static_eval) and (hashFlag == .UPPER and bestScore < static_eval)) {
        const bonus =
            std.math.clamp(@divFloor((_alpha - static_eval) * depth, 8), -256, 256);

        const offset = chessl.whiteBoolToInt(white);
        update_corrhist(&historyl.pawnCorrHist[offset][historyl.pawnHashIndexToIdx(p_state.frame.pawnKey)], bonus);

        update_corrhist(&historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.WHITE)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.WHITE)])], bonus);
        update_corrhist(&historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.BLACK)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.BLACK)])], bonus);

        const prev1 = ss.getPrevFrame(ply, 1);
        const prev2 = ss.getPrevFrame(ply, 2);
        if (prev1.playedMove.isValid() and prev2.playedMove.isValid()) {
            update_corrhist(&historyl.corrHist[@intFromEnum(prev2.pieceMoved)][prev2.playedMove.getTo()][@intFromEnum(prev1.pieceMoved)][prev1.playedMove.getTo()], bonus);
        }
    }
    // .PV set to not store position that could be obtained after a possible nullmove. TODO: just filter out nullmove
    if (hashFlag == .LOWER or comptime t == .PV) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), _alpha, hashFlag, bestMove, white);
        writer.writeShort(s_entry);
    }
    return _alpha;
}
pub fn updateOnBetaCut(p_state: *const boardl.boardState, cutoffIdx: usize, bonus: scoreType, gen: *const moveGenl.typeMoveGenerator, white: bool, comptime t: typel.e_moveGenFlag) void {
    for (0..gen._moves.moves.len) |j| {
        const _move = gen._moves.moves.moves[j];
        if (j != cutoffIdx) {
            const fromP = _move.getFrom();
            const toP = _move.getTo();
            if (comptime t == .CAPTURE) {
                historyl.updateCaptureHistory(p_state.getPiece(fromP), p_state.getCapturePiece(_move), toP, bonus);
            } else if (comptime t == .QUIET) {
                historyl.updateHistoryHeurist(white, fromP, toP, bonus);
            }
        }
    }
}
pub fn correct_eval(p_state: *const boardl.boardState, ss: *searchStack, eval: scoreType, ply: u16) scoreType {
    const _eval: scoreType = @divFloor(eval * (200 - p_state.frame.halfMoveClock), 200);
    var corr: scoreType = 0;
    const offset = chessl.whiteBoolToInt(p_state.whiteToMove());

    corr += historyl.pawnCorrHist[offset][historyl.pawnHashIndexToIdx(p_state.frame.pawnKey)];
    corr += historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.WHITE)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.WHITE)])];
    corr += historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.BLACK)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.BLACK)])];

    const prev1 = ss.getPrevFrame(ply, 1);
    const prev2 = ss.getPrevFrame(ply, 2);
    if (prev1.playedMove.isValid() and prev2.playedMove.isValid()) {
        corr += historyl.corrHist[@intFromEnum(prev2.pieceMoved)][prev2.playedMove.getTo()][@intFromEnum(prev1.pieceMoved)][prev1.playedMove.getTo()];
    }

    return std.math.clamp(_eval + @divFloor(66 * corr, 512), -weightl.simpleCheckMateThreshold + 1, weightl.simpleCheckMateThreshold - 1);
}
pub inline fn update_corrhist(val: *scoreType, bonus: scoreType) void {
    val.* += bonus - @divFloor(val.* * @as(scoreType, @intCast(@abs(bonus))), 1024);
}
