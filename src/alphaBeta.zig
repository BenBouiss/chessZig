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
const scoreType = typel.scoreType;
const threadInfo = threadingl.threadInfo;
const milliDepth = typel.milliDepth;
const depthT = typel.depthT;
const e_color = typel.e_color;

pub fn searchEntrypoint(p_state: *boardl.boardState, p_info: *threadInfo, depth: depthT, ss: *searchStack, alpha: scoreType, beta: scoreType, threadD: *threadData) scoreType {
    p_info.working = true;

    ss.resetPv();
    var pv: movel.line = .{};
    ss.getFrame(0).pv = &pv;

    if (comptime configl.USE_NNUE) {
        p_state.frame.nnueAccumul = nnuel.computeAccPair(&nnuel.nnueNet.net, p_state);
    }
    const score = searchLoop(p_state, p_info, depth, 0, alpha, beta, ss, threadD, false, false, .PV);

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
    const white: bool = p_state.whiteToMove();
    if (p_state.isStaleMateRepetition()) {
        //return weightl.simpleStalemateScore;
        const matBalance = heuristicl.c_materialImbalance(p_state, white);
        if (matBalance > 100) {
            return -25;
        } else if (matBalance < 100) {
            return 25;
        }
        return -1;
    }

    var _alpha = alpha;
    var currS: *searchFrame = ss.getFrame(ply);
    //var bestMove: IMove = .{};
    //currS.staticEval = .{ .s = static_eval, .t = .STD };

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
    var hashType: hashl.nodeType = .UPPER;
    var bestMove: IMove = .{};
    if (ttRes.entry) |_entry| {
        p_info.searchStat.n_hashRetrieve += 1;
        ttHit = true;
        //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
        hashEval = hashl.ttEvalToEval(_entry.evaluation, @intCast(ply));
        hashType = _entry.nodeT();
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

    const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, 0, hashl.evalToTTEval(_alpha, ply), hashFlag, bestMove, white);
    writer.writeShort(s_entry);
    return _alpha;
}

pub const searchFrame = struct {
    pv: ?*movel.line = null,
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
    rootMoves: [chessl.MAX_POSSIBLE_MOVE]movel.rootMoveInfo = undefined,
    pub fn printRooMoves(self: *const threadData) void {
        for (0..self.rootMoves.len) |i| {
            const move = self.rootMoves[i];
            if (!move.move.isValid()) {
                break;
            }
            std.debug.print("move: {s} n: {d}\n", .{ move.move.getStr(), move.nodes });
        }
    }
    pub fn findRootMove(self: *threadData, move: IMove) *movel.rootMoveInfo {
        for (&self.rootMoves) |*moveInfo| {
            if (moveInfo.move.equal(move)) {
                return moveInfo;
            }
            if (!moveInfo.move.isValid()) {
                break;
            }
        }
        return &self.rootMoves[0];
    }
};

// used to garanty getFrameOffset(0, 4) returns a default value
pub const negativeOffset: usize = 4;
//index by ply
pub const searchStack = struct {
    e: [typel.MAX_PLY + configl.MAX_QUIESC_DEPTH + negativeOffset + 1]searchFrame = @splat(.{}),
    pub inline fn getFrame(self: *searchStack, ply: depthT) *searchFrame {
        return &self.e[negativeOffset + @as(usize, @intCast(ply))];
    }
    pub inline fn resetPv(self: *searchStack) void {
        for (0..self.e.len) |i| {
            self.e[i].pv = null;
        }
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
    const white: bool = p_state.whiteToMove();
    const isRoot: bool = ply == 0;
    if (!isRoot and p_state.isStaleMateRepetition()) {
        //return weightl.simpleStalemateScore;
        const matBalance = heuristicl.c_materialImbalance(p_state, white);
        if (matBalance > 100) {
            return -25;
        } else if (matBalance < 100) {
            return 25;
        }
        return -1;
    }
    if (schedulerl.outOfTime(p_info)) {
        return weightl.simpleStalemateScore;
    }
    if (depth <= 0) {
        return quiescenceSearch(p_state, p_info, alpha, beta, ply, ss);
    }
    var _alpha = alpha;
    var _beta = beta;
    var _depth = depth;
    const whiteIdx: usize = chessl.whiteBoolToInt(white);
    const mate_value = chessl.mate_in(ply);
    const isAllNode = !(cutnode or comptime t == .PV);
    var pv: movel.line = .init();
    std.debug.assert(!(t == .PV and cutnode));

    var bestMove: IMove = .{};
    var bestScore: scoreType = typel.scoreNone;
    var skipQuietMoves: bool = false;

    const excludedMove = threadD.excludedMove;
    const singularExt: bool = excludedMove.isValid();

    p_info.searchStat.n_nodeExplored += 1;

    if (ply > p_info.seldepth) {
        p_info.seldepth = ply;
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
    var hashFlag: hashl.nodeType = .UPPER;

    var hashEval: scoreType = 0;
    var hashMove: IMove = .{};
    var hashDepth: depthT = 0;
    var hashType: hashl.nodeType = .UPPER;
    const ttRes = hashl.hashTable.probeMatch(p_state.frame.key, @intCast(_depth), p_state, @intCast(p_info.searchStat.n_nodeExplored));
    var writer = ttRes.writer;
    var ttHit: bool = false;
    if (ttRes.entry) |_entry| {
        p_info.searchStat.n_hashRetrieve += 1;
        ttHit = true;
        //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
        hashEval = hashl.ttEvalToEval(_entry.evaluation, ply);
        hashType = _entry.nodeT();
        if (!singularExt and comptime t == .NonPV) {
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

    var currS = ss.getFrame(ply);
    const nextS = ss.getFrame(ply + 1);
    const prevSS = ss.getPrevFrame(ply, 1);
    //const prevNode = p_info.searchStat.n_nodeExplored;

    const f: boardl.boardFrame = .copy(p_state);
    const hashMoveIsCapture = hashMove.isCapture();

    var static_eval = typel.scoreNone;

    if (isCheck or singularExt) {
        currS.staticEval = .{};
    } else {
        static_eval = if (ttHit) hashEval else correct_eval(p_state, ss, heuristicl.c_evaluate(p_state, white), ply);
        currS.staticEval = .{ .s = static_eval, .t = .STD };
    }

    currS.followPv = if (isRoot) true else prevSS.followPv and prevSS.playedMove.equal(prevSS.prevLineMove);
    const prevLineMove: IMove = if (currS.followPv) currS.prevLineMove else .{};

    const improving: bool = if (isCheck) (false) else if (ss.getPrevFrame(ply, 2).staticEval.t != .NONE) (currS.staticEval.s > ss.getPrevFrame(ply, 2).staticEval.s) else if (ss.getPrevFrame(ply, 4).staticEval.t != .NONE) (currS.staticEval.s > ss.getPrevFrame(ply, 4).staticEval.s) else (true);

    //const fDepth = heuristicl.lmrFDepth(heuristicl.depthToMilliDepth(_depth));
    //var lmrR: milliDepth = weightl.lmr_baseDeficit + heuristicl.lmrFDepth(heuristicl.depthToMilliDepth(_depth));
    var lmrR: milliDepth = weightl.lmr_baseDeficit;
    //var lmrR: milliDepth = typel.oneDepthMilliDepth;
    //var lmrR: milliDepth = typel.oneDepthMilliDepth + heuristicl.lmrFDepth(heuristicl.depthToMilliDepth(_depth));
    if (comptime t == .PV) {
        lmrR += weightl.lmr_inPvMode;
        //lmrR -= typel.oneDepthMilliDepth;
    }

    //if (isCheck) {
    //    //lmrR += .lmr_inCheck;
    //    lmrR -= typel.oneDepthMilliDepth;
    //}

    if (!improving) {
        lmrR += weightl.lmr_notImproving;
        //lmrR += typel.oneDepthMilliDepth;
    }
    if (hashMoveIsCapture) {
        lmrR += weightl.lmr_hashMoveCapture;
        //lmrR += typel.oneDepthMilliDepth;
    }
    if (cutnode) {
        lmrR += weightl.lmr_expectedCutOff;
        //lmrR += typel.oneDepthMilliDepth;
    }

    // const isEndGame = p_state.isEndGame();
    //and !p_state.onlyPawnsSide(white)
    const hasPieces = !p_state.onlyPawns();
    if (!singularExt and !isCheck and comptime t == .NonPV) {
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

        // null move prunning here
        // R = 3
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
    if (!singularExt and _depth > weightl.probCutMinimalDepth and !chessl.isMate(_beta)) {
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
                    pv.reset();
                    ss.getFrame(ply + 1).pv = &pv;
                    score = -searchLoop(p_state, p_info, _depth - 4, ply + 1, -p_beta, -p_beta + 1, ss, threadD, wasExtended, false, t);
                }
                _ = p_state.undoMove();
                p_state.frame = f;
                if (score >= p_beta) {
                    // save to TT
                    const probCutEntry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth - 4), hashl.evalToTTEval(score, ply), .LOWER, move, white);
                    writer.writeShort(probCutEntry);
                    return score;
                }
            }
        }
        gen.reset();
    }

    const otherKingSq = p_state.getKingSq(!white);
    const safetyArea = chessl.safetyArea(otherKingSq);

    const historyBonus = heuristicl.computeHistoryBonus(_depth);
    var movesPlayed: u8 = 0;
    var phasePlay: u8 = 0;
    var prev = gen.phase;

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
        //const cPiece = p_state.getPiece(to);
        const isPromo = move.isPromotion();

        const histScore: scoreType = historyl.historyHeuristic[whiteIdx][from][to];

        if (!isRoot) {
            //if (bestScore > typel.scoreNone and _depth <= weightl.SeePruningMaxDepth) {
            if (_depth <= weightl.SeePruningMaxDepth) {
                const margin = if (isCapture) weightl.SeePruningCaptureMargin else weightl.SeePruningQuietMargin;
                if (!heuristicl.SEE_threshold(p_state, move, _depth * margin)) {
                    continue;
                }
            }
            // https://talkchess.com/viewtopic.php?t=55734
            // https://int0x80.ca/posts/chess-engines/13-extensions
            //_ = singularExt;
            if (!singularExt and move.equal(hashMove) and _depth > weightl.singularExtensionMinDepth and !chessl.isMate(hashEval) and hashDepth >= (_depth - weightl.singularExtensionDeltaTTDepth) and hashType != .UPPER) {
                const singularD: depthT = @divFloor(_depth - 1, 2);
                //const singularBeta: scoreType = hashEval - _depth;
                const singularBeta: scoreType = hashEval - 25;

                threadD.excludedMove = move;
                //const score = searchLoop(p_state, p_info, singularD, ply, singularBeta - 1, singularBeta, ss, threadD, extended, cutnode, .NonPV);
                const score = searchLoop(p_state, p_info, singularD, ply, singularBeta - 1, singularBeta, ss, threadD, extended, cutnode, .NonPV);
                threadD.excludedMove = .{};

                if (score < singularBeta) {
                    if ((score + weightl.singularMarginDoubleExt) < singularBeta and comptime t == .NonPV) {
                        extension += 2;
                        extended = true;
                    } else {
                        extension += 1;
                        extended = true;
                    }
                } else if (singularBeta >= _beta) {
                    return singularBeta;
                } else if (cutnode) {
                    extension -= 1;
                }
            }
        }

        if (isCapture) {
            if (!wasExtended and to == p_state.getLastMove().getTo() and historyl.captureHistory[@intFromEnum(fPiece)][@intFromEnum(cPiece)][to] > weightl.captureExtensionThresh and comptime t == .PV) {
                extension += 1;
                extended = true;
            }
            //} else if (bestScore > typel.scoreNone and comptime t == .NonPV) {
        } else if (comptime t == .NonPV) {
            if (canFutility and movesPlayed > weightl.moveReductionAmount) {
                skipQuietMoves = true;
                //if (_depth <= weightl.futilityDepth and !isCheck and (static_eval + weightl.futilityConst + weightl.futilityCoeff * _depth) < alpha) {
                //    skipQuietMoves = true;
            }
            if (_depth <= weightl.lmpMaxDepth and movesPlayed >= weightl.lmpBase + @divFloor(_depth * _depth, 2 - @as(scoreType, @intFromBool(improving)))) {
                skipQuietMoves = true;
                //continue;
            }

            if (!isCheck and movesPlayed >= weightl.historyMinExplore) {
                if (histScore < (weightl.historyThreshCoeff * _depth + weightl.historyThreshConst)) {
                    //skipQuietMoves = true;
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
        const newDepth: depthT = _depth - 1 + extension;

        // rewrite of main search handling
        // https://github.com/Adam-Kulju/Patricia/
        if (!isCheck and _depth >= weightl.LMRDepth and phasePlay > weightl.moveReductionAmount) {
            var _lmrR = lmrR;

            //_lmrR += historyl.lmrBase[movesPlayed];
            //const R = heuristicl.depthToMilliDepth(historyl.lmrBase[@intCast(_depth)][movesPlayed]);
            const R = historyl.lmrBase[@intCast(@min(typel.MAX_PLY, depth))][movesPlayed];
            //const R = historyl.lmrBase[@intCast(_depth)][movesPlayed] * 1024;

            //if (isCapture) {
            //    _lmrR += @divFloor(R, 2);
            //} else {
            //    _lmrR += (R - heuristicl.depthToMilliDepth(@divFloor(histScore, weightl.lmr_histDiv)));
            //}
            _lmrR += R;
            if (givesCheck) {
                _lmrR += weightl.lmr_givesCheck;
            }
            if (isPromo) {
                _lmrR += weightl.lmr_isPromotion;
            }
            if (moveScore >= weightl.lmr_scoreThreshold) {
                _lmrR += weightl.lmr_killerMove;
            } else if (isCapture and !isThreat and gen.phase == .BADCAPTURE) {
                _lmrR += weightl.lmr_badCapture;
            }

            //if (move.equal(currS.killerMove)) {
            //    //_lmrR -= typel.oneDepthMilliDepth;
            //    _lmrR -= weightl.lmr_killerMove;
            //}
            //if (isCapture and !isThreat and gen.phase == .BADCAPTURE) {
            //    _lmrR += weightl.lmr_badCapture;
            //}

            if (nextS.failHighCount > weightl.lmr_highFailCount) {
                _lmrR += weightl.lmr_highFailScore;
                //_lmrR += typel.oneDepthMilliDepth;
            }

            const d: depthT = std.math.clamp(heuristicl.milliDepthToDepth(_lmrR), 0, newDepth - 1);

            score = -searchLoop(p_state, p_info, newDepth - d, ply + 1, -_alpha - 1, -_alpha, ss, threadD, extended, true, .NonPV);

            if (score > _alpha and d > 0) {
                fullSearch = true;
            }
        } else {
            // ignores the first move for the full search
            fullSearch = (phasePlay != 0) or comptime t == .NonPV;
        }
        if (fullSearch) {
            score = -searchLoop(p_state, p_info, newDepth, ply + 1, -_alpha - 1, -_alpha, ss, threadD, extended, !cutnode, .NonPV);
        }
        if ((phasePlay == 0 or score > _alpha) and comptime t == .PV) {
            pv.reset();
            ss.getFrame(ply + 1).pv = &pv;
            score = -searchLoop(p_state, p_info, newDepth, ply + 1, -_beta, -_alpha, ss, threadD, extended, false, .PV);
        }

        _ = p_state.undoMove();
        p_state.frame = f;
        //if (isRoot) {
        //    threadD.findRootMove(move).nodes += p_info.searchStat.n_nodeExplored - prevNode;
        //}

        if (movesPlayed == 0 and isRoot and comptime t == .PV) {
            currS.pv.?.add(move);
        }
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
                if (comptime t == .PV) {
                    currS.pv.?.onBestMove(move, nextS.pv);
                    //std.debug.assert(move.equal(currS.pv.?.moves[0]));
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
            }
        }
    }
    if (movesPlayed == 0) {
        if (!singularExt) {
            if (isCheck) {
                _alpha = chessl.mated_in(ply);
            } else {
                _alpha = weightl.simpleStalemateScore;
            }
        }
    }
    //if (!isCheck and (!bestMove.isCapture() or !bestMove.isValid()) and (hashFlag == .LOWER and bestScore > static_eval) and (hashFlag == .UPPER and bestScore < static_eval)) {
    if (!singularExt and !isCheck and (!bestMove.isCapture()) and !(hashFlag == .LOWER and bestScore <= static_eval) and !(!bestMove.isValid() and bestScore >= static_eval)) {
        const bonus =
            std.math.clamp(@divFloor((bestScore - static_eval) * depth, 8), -256, 256);

        const offset = chessl.whiteBoolToInt(white);
        updateCorrhist(&historyl.pawnCorrHist[offset][historyl.pawnHashIndexToIdx(p_state.frame.pawnKey)], bonus);
        updateCorrhist(&historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.WHITE)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.WHITE)])], bonus);
        updateCorrhist(&historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.BLACK)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.BLACK)])], bonus);

        const prev1 = ss.getPrevFrame(ply, 1);
        const prev2 = ss.getPrevFrame(ply, 2);
        if (prev1.playedMove.isValid() and prev2.playedMove.isValid()) {
            updateCorrhist(&historyl.corrHist[@intFromEnum(prev2.pieceMoved)][prev2.playedMove.getTo()][@intFromEnum(prev1.pieceMoved)][prev1.playedMove.getTo()], bonus);
        }
    }
    if (!singularExt and hashFlag == .LOWER and gen.phase == .QUIET) {
        const prevMove = ss.getPrevFrame(ply, 1).playedMove;
        const prevPiece = ss.getPrevFrame(ply, 1).pieceMoved;

        const prevPrevMove = ss.getPrevFrame(ply, 2).playedMove;
        const prevPrevPiece = ss.getPrevFrame(ply, 2).pieceMoved;

        const prevMove4 = ss.getPrevFrame(ply, 4).playedMove;
        const prevPiece4 = ss.getPrevFrame(ply, 4).pieceMoved;
        const malus = -@divFloor(historyBonus, 4);
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
    if (!singularExt) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), hashl.evalToTTEval(bestScore, ply), hashFlag, bestMove, white);
        writer.writeShort(s_entry);
    }
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
                const cPiece: u8 = @intFromEnum(p_state.getCapturePiece(_move));
                //const to = _move.getTo();
                //const cPiece: u8 = @intFromEnum(p_state.getPiece(to));
                updateHistory(&historyl.captureHistory[@intFromEnum(fPiece)][cPiece][toP], bonus);
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
pub inline fn updateCorrhist(val: *scoreType, bonus: scoreType) void {
    val.* += bonus - @divFloor(val.* * @as(scoreType, @intCast(@abs(bonus))), weightl.corrHistMax);
}

pub inline fn updateHistory(val: *scoreType, bonus: scoreType) void {
    val.* += bonus - @divFloor(val.* * @as(scoreType, @intCast(@abs(bonus))), configl.MAX_HIST_HEURISTIC_VALUE);
}

pub inline fn updateContinuation(val: *scoreType, bonus: scoreType) void {
    val.* += bonus - @divFloor(val.* * @as(scoreType, @intCast(@abs(bonus))), configl.MAX_CONTINUATION_HEURISTIC_VALUE);
}
