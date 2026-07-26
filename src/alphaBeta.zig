const std = @import("std");
const movel = @import("move.zig");
const heuristicl = @import("heuristic.zig");
const weightl = @import("weights.zig");
const hashl = @import("hashTable.zig");
const configl = @import("config.zig");
const boardl = @import("board.zig");
const typel = @import("type.zig");
const moveGenl = @import("move_generation.zig");
const historyl = @import("history.zig");
const chessl = @import("chess.zig");
const nnuel = @import("nnue.zig");

const threadingl = @import("threading.zig");
const schedulerl = @import("scheduler.zig");

const IMove = movel.IMove;
const pvContainer = movel.pvContainer;
const scoreType = typel.scoreType;
const threadInfo = threadingl.threadInfo;
const milliDepth = typel.milliDepth;
const depthT = typel.depthT;
const e_color = typel.e_color;

pub fn searchEntrypoint(p_state: *boardl.boardState, p_info: *threadInfo, depth: depthT, ss: *searchStack, alpha: scoreType, beta: scoreType) scoreType {
    p_info.working = true;

    var pv: pvContainer = .{};
    ss.getFrame(0).pv = &pv;

    if (comptime configl.USE_NNUE) {
        p_state.frame.nnueAccumul = nnuel.computeAccPair(&nnuel.nnueNet.net, p_state);
    }
    var threadD: threadData = .{};
    const score = searchLoop(p_state, p_info, depth, 0, alpha, beta, ss, &threadD, false, false, .PV);

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

pub fn quiescenceSearch(p_state: *boardl.boardState, p_info: *threadInfo, alpha: scoreType, beta: scoreType, ply: depthT, ss: *searchStack) scoreType {
    // first vers adapt of the pseudo code: https://www.chessprogramming.org/Quiescence_Search

    var _alpha = alpha;
    var currS: *searchFrame = ss.getFrame(ply);
    //var bestMove: IMove = .{};
    //currS.staticEval = .{ .s = static_eval, .t = .STD };
    if (p_state.isStaleMateRepetition()) {
        return weightl.simpleStalemateScore;
    }
    const white: bool = p_state.whiteToMove();
    p_info.searchStat.n_nodeExplored += 1;
    if (ply >= typel.MAX_PLY or schedulerl.outOfTime(p_info)) {
        return correct_eval(p_state, ss, heuristicl.c_evaluate(p_state, white), ply);
    }

    if (ply > p_info.seldepth) {
        p_info.seldepth = ply;
    }
    const ttRes = hashl.hashTable.probeMatch(p_state.frame.key, 0, p_state, @intCast(p_info.searchStat.n_nodeExplored));
    var writer = ttRes.writer;
    var ttHit: bool = false;
    var hashEval: scoreType = 0;
    var hashMove: IMove = .{};
    var hashFlag: hashl.nodeType = .UPPER;
    var bestMove: IMove = .{};
    if (ttRes.entry) |_entry| {
        p_info.searchStat.n_hashRetrieve += 1;
        ttHit = true;
        //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
        hashEval = _entry.evaluation;
        const hashType = _entry.nodeT();
        if (hashType == .ALL or (hashType == .LOWER and hashEval >= beta) or (hashType == .UPPER and hashEval <= _alpha)) {
            return hashEval;
        }
        hashMove = _entry.bestMove;
    }
    const isChecked = p_state.isChecked();
    var bestScore: scoreType = typel.scoreNone;

    if (!isChecked) {
        const static_eval = if (ttHit) (hashEval) else (correct_eval(p_state, ss, heuristicl.c_evaluate(p_state, white), ply));
        bestScore = static_eval;

        if (bestScore > _alpha) {
            _alpha = bestScore;

            // stand pat https://www.chessprogramming.org/Quiescence_Search#StandPat
            if (bestScore >= beta) {
                return bestScore;
            }
        }
    }

    const f: boardl.boardFrame = .copy(p_state);
    var gen: moveGenl.typeMoveGenerator = .init();
    var movesPlayed: u8 = 0;

    while (gen.pickNext(p_state, ply, .{}, hashMove, weightl.moveGenMinSeeThreshold, !isChecked, ss)) |res| {
        if (@intFromEnum(gen.phase) > @intFromEnum(typel.e_moveGenFlag.CAPTURE) and !isChecked) {
            break;
        }
        const move = res.@"0";
        if (!p_state.legal(move)) continue;

        if (movesPlayed > weightl.moveQsearchAmount) {
            break;
        }

        const from = move.getFrom();
        const fPiece = p_state.getPiece(from);
        currS.playedMove = move;
        currS.pieceMoved = fPiece;
        p_state.makeMove(move);
        if (comptime configl.USE_NNUE) {
            nnuel.updateNnueOnMove(p_state, move);
        }
        const score = -quiescenceSearch(p_state, p_info, -beta, -_alpha, ply + 1, ss);

        _ = p_state.undoMove();
        p_state.frame = f;

        movesPlayed += 1;
        if (score > bestScore) {
            bestScore = score;
            if (score > _alpha) {
                bestMove = move;
                _alpha = score;
                if (score >= beta) {
                    hashFlag = .LOWER;
                    break;
                }
                hashFlag = .ALL;
            }
        }
        //if (!p_info.alive) return bestScore;
    }
    if (movesPlayed == 0 and isChecked) {
        _alpha = chessl.mated_in(ply);
    }

    const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, 0, _alpha, hashFlag, bestMove, white);
    writer.writeShort(s_entry);
    return _alpha;
}

pub const searchFrame = struct {
    pv: ?*movel.pvContainer = null,
    staticEval: heuristicl.score = .{},
    ply: depthT = 0,
    failHighCount: u16 = 0,
    prevLineMove: IMove = .{},
    playedMove: IMove = .{},
    killerMove: IMove = .{},
    pieceMoved: typel.e_piece = .nEmptySquare,
    followPv: bool = false,
};
pub const threadData = struct {
    excludedMove: IMove = .{},
};

// used to garanty getFrameOffset(0, 4) returns a default value
pub const negativeOffset: usize = 4;
//index by ply
pub const searchStack = struct {
    e: [typel.MAX_PLY + configl.MAX_QUIESC_DEPTH + negativeOffset + 1]searchFrame = @splat(.{}),
    pub inline fn getFrame(self: *searchStack, ply: depthT) *searchFrame {
        return &self.e[negativeOffset + @as(usize, @intCast(ply))];
    }
    pub inline fn getPrevFrame(self: *searchStack, ply: depthT, offset: usize) *searchFrame {
        return &self.e[negativeOffset - offset + @as(usize, @intCast(ply))];
    }
    pub inline fn setPrevLine(self: *searchStack, line: *const movel.line) void {
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
pub fn searchLoop(p_state: *boardl.boardState, p_info: *threadingl.threadInfo, depth: depthT, ply: depthT, alpha: scoreType, beta: scoreType, ss: *searchStack, threadD: *threadData, wasExtended: bool, cutnode: bool, comptime t: searchType) scoreType {
    var _alpha = alpha;
    var _beta = beta;
    var _depth = depth;
    const white: bool = p_state.whiteToMove();
    const whiteIdx: usize = chessl.whiteBoolToInt(white);
    const isRoot: bool = ply == 0;
    const mate_value = chessl.mate_in(ply);
    const isAllNode = !(cutnode or comptime t == .PV);
    std.debug.assert(!(t == .PV and cutnode));
    if (p_state.isStaleMateRepetition()) {
        return weightl.simpleStalemateScore;
    }
    var bestScore: scoreType = typel.scoreNone;
    var bestMove: IMove = .{};
    var hashMove: IMove = .{};
    var hashDepth: depthT = 0;
    //var hashType: hashl.nodeType = .ALL;
    var hashFlag: hashl.nodeType = .UPPER;
    var skipQuietMoves: bool = false;

    var hashEval: scoreType = 0;
    const excludedMove = threadD.excludedMove;
    //const singularExt: bool = excludedMove.isValid();
    threadD.excludedMove = .{};

    if (_depth <= 0 or schedulerl.outOfTime(p_info)) {
        return quiescenceSearch(p_state, p_info, _alpha, _beta, ply, ss);
    }
    p_info.searchStat.n_nodeExplored += 1;

    if (ply > p_info.seldepth) {
        p_info.seldepth = ply;
    }

    threadD.excludedMove = .{};

    // https://github.com/nescitus/cpw-engine/blob/master/search.cpp
    if (!isRoot) {
        if (mate_value < _beta) {
            _beta = mate_value;
            if (_alpha >= _beta) {
                return _alpha;
            }
        }
    }

    const ttRes = hashl.hashTable.probeMatch(p_state.frame.key, @intCast(_depth), p_state, @intCast(p_info.searchStat.n_nodeExplored));
    var writer = ttRes.writer;
    var ttHit: bool = false;
    if (ttRes.entry) |_entry| {
        p_info.searchStat.n_hashRetrieve += 1;
        ttHit = true;
        //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
        hashEval = _entry.evaluation;
        const hashType = _entry.nodeT();
        if (comptime t == .NonPV) {
            if (hashType == .ALL or (hashType == .LOWER and hashEval >= _beta) or (hashType == .UPPER and hashEval <= _alpha)) {
                return hashEval;
            }
        }
        //if (hashType == .LOWER and !extended) {
        //    extension += 1;
        //    extended = true;
        //}
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
    const hashMoveIsCapture = hashMove.isCapture();

    var currS = ss.getFrame(ply);
    const nextS = ss.getFrame(ply + 1);
    const prevSS = ss.getPrevFrame(ply, 1);

    var static_eval = typel.scoreNone;

    if (isCheck) {
        currS.staticEval = .{};
    } else {
        static_eval = if (ttHit) hashEval else correct_eval(p_state, ss, heuristicl.c_evaluate(p_state, white), ply);
        currS.staticEval = .{ .s = static_eval, .t = .STD };
    }

    currS.followPv = if (isRoot) true else prevSS.followPv and prevSS.playedMove.equal(prevSS.prevLineMove);
    const prevLineMove: IMove = if (currS.followPv) currS.prevLineMove else .{};

    const improving: bool = if (isCheck) (false) else if (ss.getPrevFrame(ply, 2).staticEval.t != .NONE) (currS.staticEval.s > ss.getPrevFrame(ply, 2).staticEval.s) else if (ss.getPrevFrame(ply, 4).staticEval.t != .NONE) (currS.staticEval.s > ss.getPrevFrame(ply, 4).staticEval.s) else (true);

    var lmrDepth: milliDepth = weightl.lmr_baseDeficit;
    if (comptime t == .PV) {
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
    const hasPieces = !p_state.onlyPawnsSide(white);
    if (!isCheck and comptime t == .NonPV) {
        if (!isRoot and hasPieces and prevSS.playedMove.isValid()) {
            // see chess programming video
            const augment: depthT = if (_depth > weightl.nullMoveDepthAugmentThreshold) @intCast(weightl.nullMoveDepthAugment) else 0;
            const R: depthT = augment + @as(depthT, @intCast(if (improving) weightl.nullMoveReductionImproving else weightl.nullMoveReduction));
            if (_depth > R) {
                currS.playedMove = .{};
                p_state.makeNullMove();
                // -b, 1 - b or -alpha-1, -alpha
                const score = -searchLoop(p_state, p_info, _depth - R, ply + 1, -_beta, 1 - _beta, ss, threadD, wasExtended, !cutnode, .NonPV);
                p_state.undoNullMove();
                p_state.frame = f;
                if (score >= _beta) {
                    p_info.searchStat.n_cutoffs += 1;
                    return score;
                }
            }
        }
        if (_depth <= weightl.rfpDepth) {
            const margin: scoreType = if (improving) weightl.rfpImproving else weightl.rfpNotImproving;
            if (static_eval >= (_beta + weightl.rfpCoeff * (_depth - @intFromBool(improving)) + weightl.rfpConst + margin)) {
                return @divFloor(static_eval + _beta, 2);
            }
        }

        //https://www.chessprogramming.org/Razoring limited razoring
        // this version from the cpw cpp code using the qsearch method
        if (!chessl.isMate(_alpha) and _depth <= weightl.razoringMaxDepth) {
            const base: scoreType = if (improving) weightl.razoringBaseImproving else weightl.razoringBaseNotImproving;
            const threshold = _alpha - (_depth * weightl.razoringCoefficient) - base;
            if (static_eval < threshold) {
                const val = quiescenceSearch(p_state, p_info, _alpha, _beta, ply, ss);
                if (val <= _alpha) {
                    return val;
                }
            }
        }
    }

    var canFutility: bool = false;
    //https://www.talkchess.com/forum3/viewtopic.php?f=7&t=74403
    // https://github.com/nescitus/cpw-engine/
    if (!isCheck and !chessl.isMate(_alpha) and _depth <= weightl.futilityDepth and (static_eval + weightl.futilityConst + weightl.futilityCoeff * _depth) <= _alpha) {
        canFutility = true;
    }

    // https://www.chessprogramming.org/Internal_Iterative_Reductions
    if (_depth >= weightl.IIRDepthMin and !hashMove.isValid() and !currS.followPv and !isAllNode) {
        _depth -= 1;
    }

    var gen: moveGenl.typeMoveGenerator = .init();

    ss.getFrame(ply + 2).failHighCount = 0;

    const p_beta = _beta + weightl.probCutMargin;
    if (_depth > weightl.probCutMinimalDepth and !chessl.isMate(_beta)) {
        if ((hashMove.isValid() and hashEval >= p_beta and hashMoveIsCapture) or (static_eval >= _beta)) {
            const tresh = p_beta - static_eval;
            while (gen.pickNext(p_state, ply, prevLineMove, hashMove, tresh, true, ss)) |res| {
                if (@intFromEnum(gen.phase) > @intFromEnum(typel.e_moveGenFlag.CAPTURE)) {
                    break;
                }
                const move = res.@"0";
                //const moveScore = res.@"1";
                if (!p_state.legal(move)) continue;
                if (move.equal(excludedMove)) continue;

                const from = move.getFrom();
                const fPiece = p_state.getPiece(from);
                currS.playedMove = move;
                currS.pieceMoved = fPiece;
                _ = p_state.makeMove(move);
                //hashl.hashTable.prefetchHash(p_state.frame.key);
                if (comptime configl.USE_NNUE) {
                    nnuel.updateNnueOnMove(p_state, move);
                }
                var score = -quiescenceSearch(p_state, p_info, -p_beta, -p_beta + 1, ply + 1, ss);
                if (score >= p_beta) {
                    score = -searchLoop(p_state, p_info, _depth - 4, ply + 1, -p_beta, -p_beta + 1, ss, threadD, wasExtended, false, t);
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
        gen.reset();
    }

    const useLMR = (_depth >= weightl.LMRDepth and !isCheck);

    const otherKingSq = p_state.getKingSq(!white);
    const safetyArea = chessl.safetyArea(otherKingSq);

    const historyBonus = heuristicl.computeHistoryBonus(_depth);
    var movesPlayed: u8 = 0;
    var phasePlay: u8 = 0;
    var prev = gen.phase;
    const fDepth = heuristicl.lmrFDepth(heuristicl.depthToMilliDepth(_depth));

    while (gen.pickNext(p_state, ply, prevLineMove, hashMove, weightl.moveGenMinSeeThreshold, skipQuietMoves, ss)) |res| {
        const move = res.@"0";
        const moveScore = res.@"1";
        if (move.equal(excludedMove)) continue;
        if (!p_state.legal(move)) continue;

        if (gen.phase == .TTMOVE) {
            p_info.searchStat.n_hashMoveDone += 1;
        }
        //if (!phaseReset and gen.extra == .QUIET) {
        if (prev != gen.phase) {
            prev = gen.phase;
            if (gen.phase == .BADCAPTURE) {
                // (capt + quiet) - quiet = capt
                phasePlay = movesPlayed - phasePlay;
            } else {
                phasePlay = 0;
            }
        }
        var extension: depthT = 0;
        var extended: bool = wasExtended;
        const idx = gen.idx - 1;
        const to = move.getTo();
        const from = move.getFrom();
        const fPiece = p_state.getPiece(from);
        const givesCheck = moveGenl.moveDeliverCheck(p_state, move, move.equal(hashMove));
        const isCapture = move.isCapture();
        const isThreat = (chessl.xToBitboard(to) & safetyArea) != 0;
        const cPiece = p_state.getCapturePiece(move);
        const isPromo = move.isPromotion();

        if (!isRoot and _depth <= weightl.SeePruningMaxDepth) {
            const margin = if (isCapture) weightl.SeePruningCaptureMargin else weightl.SeePruningQuietMargin;
            if (!heuristicl.SEE_threshold(p_state, move, _depth * margin)) {
                continue;
            }
        }

        if (isCapture) {
            if (!wasExtended and to == p_state.getLastMove().getTo() and historyl.captureHistory[@intFromEnum(fPiece)][@intFromEnum(cPiece)][to] > weightl.captureExtensionThresh and comptime t == .PV) {
                extension += 1;
                extended = true;
            }
        } else if (comptime t == .NonPV) {
            if (canFutility and movesPlayed > weightl.moveReductionAmount) {
                skipQuietMoves = true;
                //if (_depth <= weightl.futilityDepth and !isCheck and (static_eval + weightl.futilityConst + weightl.futilityCoeff * _depth) < alpha) {
                //    skipQuietMoves = true;
            }
            if (_depth <= weightl.lmpMaxDepth and movesPlayed >= weightl.lmpBase + @divFloor(_depth * _depth, 2 - @as(scoreType, @intFromBool(improving)))) {
                skipQuietMoves = true;
            }

            if (!isCheck and movesPlayed >= weightl.historyMinExplore) {
                const histScore: scoreType = historyl.historyHeuristic[chessl.whiteBoolToInt(white)][from][to];
                if (histScore < (weightl.historyThreshCoeff * _depth + weightl.historyThreshConst)) {
                    continue;
                }
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
            if (moveScore >= weightl.lmr_scoreThreshold) {
                _lmrDepth += weightl.lmr_killerMove;
            } else if (!isThreat and gen.phase == .BADCAPTURE) {
                _lmrDepth += weightl.lmr_badCapture;
            }
            if (nextS.failHighCount > weightl.lmr_highFailCount) {
                _lmrDepth += weightl.lmr_highFailScore;
            }
            _lmrDepth += historyl.lmrBase[movesPlayed];

            const d: depthT = @max(_depth - 1 - heuristicl.milliDepthToDepth(@max(_lmrDepth, 0)), 0);

            score = -searchLoop(p_state, p_info, d + extension, ply + 1, -_alpha - 1, -_alpha, ss, threadD, extended, true, .NonPV);
            if (score > _alpha) {
                fullSearch = true;
            }
        } else {
            // ignores the first move for the full search
            fullSearch = (phasePlay != 0) or comptime t == .NonPV;
        }
        if (fullSearch) {
            score = -searchLoop(p_state, p_info, _depth - 1 + extension, ply + 1, -_alpha - 1, -_alpha, ss, threadD, extended, !cutnode, .NonPV);
        }
        if ((phasePlay == 0 or score > _alpha) and comptime t == .PV) {
            score = -searchLoop(p_state, p_info, _depth - 1 + extension, ply + 1, -_beta, -_alpha, ss, threadD, extended, false, .PV);
        }

        _ = p_state.undoMove();
        p_state.frame = f;

        movesPlayed += 1;
        phasePlay += 1;
        if (score > bestScore) {
            bestScore = score;
            if (bestScore > _alpha) {
                bestMove = move;
                _alpha = bestScore;
                if (isCapture) {
                    updateHistory(&historyl.captureHistory[@intFromEnum(fPiece)][@intFromEnum(cPiece)][to], historyBonus);
                } else {
                    updateHistory(&historyl.historyHeuristic[whiteIdx][from][to], historyBonus);
                }

                if (_alpha >= _beta) {
                    hashFlag = .LOWER;
                    // save here the killer moves
                    if (isCapture) {
                        updateOnBetaCut(p_state, idx, -historyBonus, &gen, white, .CAPTURE);
                    } else {
                        currS.killerMove = move;
                        //historyl.onKillerMove(move, @intCast(ply));
                        updateOnBetaCut(p_state, idx, -historyBonus, &gen, white, .QUIET);
                    }
                    p_info.searchStat.n_cutoffs += 1;
                    currS.failHighCount += 1;
                    break;
                }
                hashFlag = .ALL;
                if (comptime t == .PV) {
                    currS.pv.?.onBestMove(move, ss.getFrame(ply + 1).pv);
                }
            }
        }
    }
    if (movesPlayed == 0) {
        if (isCheck) {
            _alpha = chessl.mated_in(ply);
        } else {
            _alpha = weightl.simpleStalemateScore;
        }
    }
    //if (!isCheck and (!bestMove.isCapture() or !bestMove.isValid()) and (hashFlag == .LOWER and bestScore > static_eval) and (hashFlag == .UPPER and bestScore < static_eval)) {
    if (!isCheck and (!bestMove.isCapture()) and !(hashFlag == .LOWER and bestScore <= static_eval) and !(!bestMove.isValid() and bestScore >= static_eval)) {
        const bonus =
            std.math.clamp(@divFloor((bestScore - static_eval) * depth, 8), -256, 256);

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
    if (hashFlag == .LOWER and gen.phase == .QUIET) {
        const prevMove = ss.getPrevFrame(ply, 1).playedMove;
        const prevPiece = ss.getPrevFrame(ply, 1).pieceMoved;

        const prevPrevMove = ss.getPrevFrame(ply, 2).playedMove;
        const prevPrevPiece = ss.getPrevFrame(ply, 2).pieceMoved;

        const prevMove4 = ss.getPrevFrame(ply, 4).playedMove;
        const prevPiece4 = ss.getPrevFrame(ply, 4).pieceMoved;
        const malus = -(historyBonus >> 2);
        for (0..gen.quiets.moves.len) |i| {
            const _move = gen.quiets.moves.moves[i];
            const to = _move.getTo();
            const piece: u8 = @intFromEnum(p_state.getPiece(_move.getFrom()));
            updateContinuation(&historyl.continuationHeuristic[@intFromEnum(prevPiece)][prevMove.getTo()][piece][to], malus);
            updateContinuation(&historyl.continuationHeuristic[@intFromEnum(prevPrevPiece)][prevPrevMove.getTo()][piece][to], malus);
            updateContinuation(&historyl.continuationHeuristic[@intFromEnum(prevPiece4)][prevMove4.getTo()][piece][to], malus);
        }
        const bestTo = bestMove.getTo();
        const bestPiece = @intFromEnum(p_state.getPiece(bestMove.getFrom()));

        updateContinuation(&historyl.continuationHeuristic[@intFromEnum(prevPiece)][prevMove.getTo()][bestPiece][bestTo], historyBonus);
        updateContinuation(&historyl.continuationHeuristic[@intFromEnum(prevPrevPiece)][prevPrevMove.getTo()][bestPiece][bestTo], historyBonus);
        updateContinuation(&historyl.continuationHeuristic[@intFromEnum(prevPiece4)][prevMove4.getTo()][bestPiece][bestTo], historyBonus);
    }
    // .PV set to not store position that could be obtained after a possible nullmove. TODO: just filter out nullmove
    //if (hashFlag == .LOWER or comptime t == .PV) {
    const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), _alpha, hashFlag, bestMove, white);
    writer.writeShort(s_entry);
    //}
    return _alpha;
}
pub fn updateOnBetaCut(p_state: *const boardl.boardState, cutoffIdx: usize, bonus: scoreType, gen: *const moveGenl.typeMoveGenerator, white: bool, comptime t: typel.e_moveGenFlag) void {
    const cont: *const moveGenl.movesScores = if (comptime t == .QUIET) &gen.quiets else &gen.captures;
    const whiteIdx: usize = chessl.whiteBoolToInt(white);

    for (0..cont.moves.len) |j| {
        const _move = cont.moves.moves[j];
        if (j != cutoffIdx) {
            const fromP = _move.getFrom();
            const toP = _move.getTo();
            if (comptime t == .CAPTURE) {
                const fPiece = p_state.getPiece(fromP);
                const cPiece = p_state.getCapturePiece(_move);
                updateHistory(&historyl.captureHistory[@intFromEnum(fPiece)][@intFromEnum(cPiece)][toP], bonus);
            } else if (comptime t == .QUIET) {
                updateHistory(&historyl.historyHeuristic[whiteIdx][fromP][toP], bonus);
            }
        }
    }
}
pub fn correct_eval(p_state: *const boardl.boardState, ss: *searchStack, eval: scoreType, ply: depthT) scoreType {
    const _eval: scoreType = @divFloor(eval * (200 - p_state.frame.halfMoveClock), 200);
    const offset = chessl.whiteBoolToInt(p_state.whiteToMove());

    var corr: scoreType = historyl.pawnCorrHist[offset][historyl.pawnHashIndexToIdx(p_state.frame.pawnKey)];
    corr += historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.WHITE)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.WHITE)])];
    corr += historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.BLACK)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.BLACK)])];

    const prev1 = ss.getPrevFrame(ply, 1);
    const prev2 = ss.getPrevFrame(ply, 2);
    if (prev1.playedMove.isValid() and prev2.playedMove.isValid()) {
        corr += historyl.corrHist[@intFromEnum(prev2.pieceMoved)][prev2.playedMove.getTo()][@intFromEnum(prev1.pieceMoved)][prev1.playedMove.getTo()];
    }

    return std.math.clamp(_eval + @divFloor(weightl.corrHistW * corr, 512), -weightl.simpleCheckMateThreshold + 1, weightl.simpleCheckMateThreshold - 1);
}
pub inline fn update_corrhist(val: *scoreType, bonus: scoreType) void {
    val.* += bonus - @divFloor(val.* * @as(scoreType, @intCast(@abs(bonus))), 1024);
}

pub inline fn updateHistory(val: *scoreType, bonus: scoreType) void {
    val.* += bonus - @divFloor(val.* * @as(scoreType, @intCast(@abs(bonus))), configl.MAX_HIST_HEURISTIC_VALUE);
}

pub inline fn updateContinuation(val: *scoreType, bonus: scoreType) void {
    val.* += bonus - @divFloor(val.* * @as(scoreType, @intCast(@abs(bonus))), configl.MAX_CONTINUATION_HEURISTIC_VALUE);
}
