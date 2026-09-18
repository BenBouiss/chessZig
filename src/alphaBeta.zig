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
    ss.resetPv();
    var pv: movel.line = .{};
    ss.getFrame(0).pv = &pv;

    const score = searchLoop(p_state, p_info, depth, 0, alpha, beta, ss, threadD, false, .PV);

    if (p_info.alive) {
        p_info.currentBest.move = pv.moves[0];
        p_info.currentBest.scoring = score;
        // TODO: pass the line buffer to the search stack, saves this call for each iid iteration
        p_info.currentBest.line.setLineFromPV(&pv);
        p_info.depth = depth;
    }
    return score;
}
pub const searchType = enum { NonPV, PV };

pub fn quiescenceSearch(p_state: *boardl.boardState, p_info: *threadInfo, alpha: scoreType, beta: scoreType, ply: depthT, ss: *searchStack) scoreType {
    const white: bool = p_state.whiteToMove();

    if (p_state.isStaleMate()) {
        // from patricia, stalemate considered bad if currently better material wise.
        const matBalance = heuristicl.c_materialImbalance(p_state, white);
        if (matBalance > 100) {
            return -25;
        }
        return 25;
    }
    if (schedulerl.outOfTime(p_info) or ply >= typel.MAX_PLY) {
        return correct_eval(p_state, ss, heuristicl.c_evaluate(p_state, white), ply);
    }

    p_info.searchStat.n_nodeExplored += 1;

    if (ply > p_info.seldepth) {
        p_info.seldepth = ply;
    }
    const ttRes = hashl.hashTable.probeMatch(p_state.frame.key, p_state, @intCast(p_info.searchStat.n_nodeExplored));
    var writer = ttRes.writer;
    var ttHit: bool = false;

    var hashSearchEval: scoreType = typel.scoreNone;
    var hashStatEval: scoreType = typel.scoreNone;

    var hashMove: IMove = .{};
    var hashFlag: hashl.nodeType = .UPPER;
    var hashType: hashl.nodeType = .UPPER;
    var bestMove: IMove = .{};

    if (ttRes.entry) |_entry| {
        p_info.searchStat.n_hashRetrieve += 1;
        //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
        ttHit = true;
        hashSearchEval = hashl.ttEvalToEval(_entry.searchScore, @intCast(ply));
        hashStatEval = _entry.staticEval;
        hashType = _entry.nodeT();

        if (hashType == .ALL or (hashType == .LOWER and hashSearchEval >= beta) or (hashType == .UPPER and hashSearchEval <= alpha)) {
            return hashSearchEval;
        }
        hashMove = _entry.bestMove;
    }
    const isChecked = p_state.isChecked();
    var bestScore: scoreType = typel.scoreNone;
    var static_eval: scoreType = typel.scoreNone;
    var raw_eval: scoreType = typel.scoreNone;
    var _alpha = alpha;

    if (!isChecked) {
        if (hashStatEval == typel.scoreNone) {
            raw_eval = heuristicl.c_evaluate(p_state, white);
        } else {
            raw_eval = hashStatEval;
        }
        static_eval = correct_eval(p_state, ss, raw_eval, ply);
        bestScore = static_eval;

        if (hashSearchEval != typel.scoreNone) {
            if (hashType == .ALL or (hashType == .UPPER and hashSearchEval < static_eval) or (hashType == .LOWER and hashSearchEval > static_eval)) {
                bestScore = hashSearchEval;
            }
        }

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
    var currS: *searchFrame = ss.getFrame(ply);

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

        p_state.undoMove();
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
    }
    if (movesPlayed == 0 and isChecked) {
        bestScore = chessl.mated_in(ply);
    }

    const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, 0, hashFlag, bestMove, raw_eval, hashl.evalToTTEval(bestScore, ply));
    writer.writeShort(s_entry);
    return bestScore;
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
    rootMoves: [chessl.MAX_POSSIBLE_MOVE]movel.rootMoveInfo = @splat(.{}),
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
    e: [typel.MAX_PLY + negativeOffset + 1]searchFrame = @splat(.{}),
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
            self.e[negativeOffset + i].prevLineMove = line.moves[i];
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
pub fn searchLoop(p_state: *boardl.boardState, p_info: *threadInfo, depth: depthT, ply: depthT, alpha: scoreType, beta: scoreType, ss: *searchStack, threadD: *threadData, cutnode: bool, comptime t: searchType) scoreType {
    const white: bool = p_state.whiteToMove();
    const isRoot: bool = ply == 0;
    if (p_state.isStaleMate()) {
        const matBalance = heuristicl.c_materialImbalance(p_state, white);
        if (matBalance > 100) {
            return -25;
        }
        return 25;
    }
    if (schedulerl.outOfTime(p_info) or ply >= typel.MAX_PLY) {
        return correct_eval(p_state, ss, heuristicl.c_evaluate(p_state, white), ply);
    }

    if (depth <= 0) {
        return quiescenceSearch(p_state, p_info, alpha, beta, ply, ss);
    }
    var _depth = depth;
    const whiteIdx: usize = chessl.whiteBoolToInt(white);
    var pv: movel.line = .init();
    //std.debug.assert(!(t == .PV and cutnode));

    var bestMove: IMove = .{};
    var skipQuietMoves: bool = false;

    const excludedMove = threadD.excludedMove;
    const singularExt: bool = excludedMove.isValid();

    p_info.searchStat.n_nodeExplored += 1;

    if (ply > p_info.seldepth) {
        p_info.seldepth = ply;
    }

    var _beta = beta;
    // https://github.com/nescitus/cpw-engine/blob/master/search.cpp
    if (!isRoot) {
        const mate_value = chessl.mate_in(ply);
        if (mate_value < _beta) {
            _beta = mate_value;
            if (alpha >= _beta) {
                return alpha;
            }
        }
    }
    var hashFlag: hashl.nodeType = .UPPER;

    var hashSearchEval: scoreType = typel.scoreNone;
    var hashStatEval: scoreType = typel.scoreNone;

    var hashMove: IMove = .{};
    var hashDepth: depthT = 0;
    var hashType: hashl.nodeType = .UPPER;

    const ttRes = hashl.hashTable.probeMatch(p_state.frame.key, p_state, @intCast(p_info.searchStat.n_nodeExplored));
    var writer = ttRes.writer;
    var ttHit: bool = false;
    if (ttRes.entry) |_entry| {
        p_info.searchStat.n_hashRetrieve += 1;
        ttHit = true;
        //https://www.chessprogramming.org/Transposition_Table#Using_the_Transposition_Table
        hashSearchEval = hashl.ttEvalToEval(_entry.searchScore, ply);
        hashStatEval = _entry.staticEval;
        hashType = _entry.nodeT();
        hashDepth = @intCast(_entry._depth);
        if (hashDepth >= _depth and comptime t == .NonPV) {
            if (hashType == .ALL or (hashType == .LOWER and hashSearchEval >= _beta) or (hashType == .UPPER and hashSearchEval <= alpha)) {
                return hashSearchEval;
            }
        }
        hashMove = _entry.bestMove;
    }

    var currS = ss.getFrame(ply);
    const nextS = ss.getFrame(ply + 1);
    const prevSS = ss.getPrevFrame(ply, 1);
    //const prevNode = p_info.searchStat.n_nodeExplored;

    const f: boardl.boardFrame = .copy(p_state);
    const hashMoveIsCapture = hashMove.isCapture();

    const isChecked = p_state.isChecked();
    var bestScore: scoreType = typel.scoreNone;
    var static_eval: scoreType = typel.scoreNone;
    var raw_eval: scoreType = typel.scoreNone;

    if (!isChecked) {
        if (singularExt) {
            static_eval = currS.staticEval.s;
        } else {
            if (hashStatEval == typel.scoreNone) {
                raw_eval = heuristicl.c_evaluate(p_state, white);
            } else {
                raw_eval = hashStatEval;
            }
            static_eval = correct_eval(p_state, ss, raw_eval, ply);
            //if (!ttHit) {
            //    const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, 0, .INVALID, .{}, raw_eval, typel.scoreNone);
            //    writer.writeShort(s_entry);
            //}
        }
    }
    if (isChecked or singularExt) {
        currS.staticEval = .{};
    } else {
        // only consider the tt entry if useful
        // https://github.com/Adam-Kulju/Patricia/
        if (ttHit) {
            if (hashType == .ALL or (hashType == .UPPER and hashSearchEval < static_eval) or (hashType == .LOWER and hashSearchEval > static_eval)) {
                static_eval = hashSearchEval;
            }
        }
        currS.staticEval = .{ .s = static_eval, .t = .STD };
    }

    currS.followPv = if (isRoot) true else (prevSS.followPv and prevSS.playedMove.equal(prevSS.prevLineMove));
    const prevLineMove: IMove = if (currS.followPv) currS.prevLineMove else .{};

    const improving: bool = if (isChecked or isRoot) (false) else if (ss.getPrevFrame(ply, 2).staticEval.s != typel.scoreNone) (static_eval > ss.getPrevFrame(ply, 2).staticEval.s) else (static_eval > ss.getPrevFrame(ply, 4).staticEval.s);

    if (!singularExt and !isChecked and comptime t == .NonPV) {
        if (_depth <= weightl.rfpDepth) {
            const margin: scoreType = if (improving) weightl.rfpImproving else weightl.rfpNotImproving;
            if (static_eval >= (_beta + weightl.rfpCoeff * (_depth - @intFromBool(improving)) + weightl.rfpConst + margin)) {
                return @divFloor(static_eval + _beta, 2);
            }
        }
        //https://www.chessprogramming.org/Razoring limited razoring
        // this version from the cpw cpp code using the qsearch method
        if (_depth <= weightl.razoringMaxDepth) {
            const base: scoreType = if (improving) weightl.razoringBaseImproving else weightl.razoringBaseNotImproving;
            if ((static_eval + base + _depth * weightl.razoringCoefficient) <= alpha) {
                const val = quiescenceSearch(p_state, p_info, alpha, alpha + 1, ply, ss);
                if (val <= alpha) {
                    return val;
                }
            }
        }

        // null move prunning here
        // R = 3
        const hasPieces = !p_state.onlyPawns();

        if (!isRoot and hasPieces and p_state.getLastMove().isValid() and static_eval >= _beta) {
            // see chess programming video
            const augment: depthT = if (_depth > weightl.nullMoveDepthAugmentThreshold) @intCast(weightl.nullMoveDepthAugment) else 0;
            const R: depthT = augment + @as(depthT, @intCast(if (improving) weightl.nullMoveReductionImproving else weightl.nullMoveReduction));
            if (_depth > R) {
                currS.playedMove = .{};
                p_state.makeNullMove();
                // -b, 1 - b or -alpha-1, -alpha
                var score = -searchLoop(p_state, p_info, _depth - R, ply + 1, -_beta, 1 - _beta, ss, threadD, !cutnode, .NonPV);
                p_state.undoNullMove();
                p_state.frame = f;

                if (score >= _beta) {
                    if (chessl.isMateWin(score)) {
                        score = _beta;
                    }
                    p_info.searchStat.n_cutoffs += 1;
                    return score;
                }
            }
        }
    }

    //https://www.talkchess.com/forum3/viewtopic.php?f=7&t=74403
    // https://github.com/nescitus/cpw-engine/

    // https://www.chessprogramming.org/Internal_Iterative_Reductions
    if (_depth >= weightl.IIRDepthMin and !hashMove.isValid() and !currS.followPv and (cutnode or comptime t == .PV)) {
        _depth -= 1;
    }

    var gen: moveGenl.typeMoveGenerator = .init();

    ss.getFrame(ply + 1).killerMove = .{};
    ss.getFrame(ply + 2).failHighCount = 0;

    const p_beta = _beta + weightl.probCutMargin;
    if (cutnode and _depth > weightl.probCutMinimalDepth and !chessl.isMate(_beta) and ((ttHit and hashSearchEval >= p_beta and hashMoveIsCapture) or (static_eval >= _beta))) {
        const tresh = p_beta - static_eval;
        while (gen.pickNext(p_state, ply, prevLineMove, hashMove, tresh, true, ss)) |res| {
            if (@intFromEnum(gen.phase) > @intFromEnum(typel.e_moveGenFlag.CAPTURE)) {
                break;
            }
            const move = res.@"0";
            if (move.equal(excludedMove) or !p_state.legal(move)) continue;

            const from = move.getFrom();
            const fPiece = p_state.getPiece(from);
            currS.playedMove = move;
            currS.pieceMoved = fPiece;
            p_state.makeMove(move);
            //hashl.hashTable.prefetchHash(p_state.frame.key);
            if (comptime configl.USE_NNUE) {
                nnuel.updateNnueOnMove(p_state, move);
            }
            var score = -quiescenceSearch(p_state, p_info, -p_beta, -p_beta + 1, ply + 1, ss);
            if (score >= p_beta) {
                score = -searchLoop(p_state, p_info, _depth - 4, ply + 1, -p_beta, -p_beta + 1, ss, threadD, false, .NonPV);
            }
            p_state.undoMove();
            p_state.frame = f;

            if (score >= p_beta) {
                // save to TT
                if (!singularExt) {
                    const probCutEntry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth - 4), .LOWER, move, raw_eval, hashl.evalToTTEval(bestScore, ply));
                    writer.writeShort(probCutEntry);
                }
                return score;
            }
        }
        gen.reset();
    }

    const otherKingSq = p_state.getKingSq(!white);
    const safetyArea = chessl.safetyArea(otherKingSq);

    const historyBonus = historyl.computeHistoryBonus(_depth);
    var movesPlayed: u8 = 0;
    //var captures: [weightl.searchMoveBufferSize]IMove = undefined;
    //var nCaptures: usize = 0;

    //var quiets: [weightl.searchMoveBufferSize]IMove = undefined;
    //var nQuiets: usize = 0;

    var _alpha = alpha;
    var lmrR: milliDepth = weightl.lmr_baseDeficit;
    if (comptime t == .PV) {
        lmrR += weightl.lmr_inPvMode;
        //lmrR -= typel.oneDepthMilliDepth;
    }

    if (!improving) {
        lmrR += weightl.lmr_notImproving;
        //lmrR += typel.oneDepthMilliDepth;
    }
    if (hashMoveIsCapture) {
        lmrR += weightl.lmr_hashMoveCapture;
    }

    if (ttHit and hashDepth >= _depth) {
        lmrR += weightl.lmr_hashMoveIsGood;
    }
    if (isChecked) {
        lmrR += weightl.lmr_inCheck;
    }

    if (cutnode) {
        lmrR += weightl.lmr_expectedCutOff;
        //lmrR += typel.oneDepthMilliDepth;
    }
    while (gen.pickNext(p_state, ply, prevLineMove, hashMove, weightl.moveGenMinSeeThreshold, skipQuietMoves, ss)) |res| {
        const move = res.@"0";
        if (move.equal(excludedMove) or !p_state.legal(move)) continue;
        const moveScore = res.@"1";

        var extension: depthT = 0;
        const to = move.getTo();
        const from = move.getFrom();
        const fPiece = p_state.getPiece(from);
        const givesCheck = moveGenl.moveDeliverCheck(p_state, move, move.equal(hashMove));
        const isCapture = move.isCapture();
        const isThreat = ((chessl.xToBitboard(to) & safetyArea) != 0) or givesCheck;
        const cPiece = p_state.getPiece(to);
        const isPromo = move.isPromotion();

        const histScore: scoreType = historyl.historyHeuristic[whiteIdx][from][to];

        if (isCapture) {
            //if (nCaptures < weightl.searchMoveBufferSize) {
            //    captures[nCaptures] = move;
            //    nCaptures += 1;
            //}
            if (to == p_state.getLastMove().getTo() and historyl.captureHistory[@intFromEnum(fPiece)][@intFromEnum(cPiece)][to] > weightl.captureExtensionThresh and comptime t == .PV) {
                extension += 1;
            }
        } else {
            //if (nQuiets < weightl.searchMoveBufferSize) {
            //    quiets[nQuiets] = move;
            //    nQuiets += 1;
            //}
            if (bestScore > typel.scoreNone and comptime t == .NonPV) {
                const fut = (static_eval + weightl.futilityConst + weightl.futilityCoeff * _depth);
                if (!isChecked and _depth <= weightl.futilityDepth and fut <= _alpha and movesPlayed > weightl.moveReductionAmount) {
                    skipQuietMoves = true;
                    //continue;
                }

                if (_depth <= weightl.lmpMaxDepth and movesPlayed >= weightl.lmpBase + @divFloor(_depth * _depth, 2 - @as(scoreType, @intFromBool(improving)))) {
                    skipQuietMoves = true;
                    //continue;
                }
                if (!isChecked and movesPlayed >= weightl.historyMinExplore and _depth < weightl.historyMaxDepth and histScore < (weightl.historyThreshCoeff * _depth + weightl.historyThreshConst)) {
                    //skipQuietMoves = true;
                    continue;
                }
            }
        }

        // TODO: change condition
        if (!isRoot) {
            if (bestScore > typel.scoreNone and _depth <= weightl.SeePruningMaxDepth) {
                const margin = if (isCapture) weightl.SeePruningCaptureMargin else weightl.SeePruningQuietMargin;
                if (!heuristicl.SEE_threshold(p_state, move, _depth * margin)) {
                    continue;
                }
            }
            // https://talkchess.com/viewtopic.php?t=55734
            // https://int0x80.ca/posts/chess-engines/13-extensions
            if (!singularExt and move.equal(hashMove) and _depth > weightl.singularExtensionMinDepth and !chessl.isMate(hashSearchEval) and hashDepth >= (_depth - weightl.singularExtensionDeltaTTDepth) and hashType != .UPPER) {
                const singularD: depthT = @divFloor(_depth - 1, 2);

                //const singularBeta: scoreType = hashSearchEval - _depth;
                const singularBeta: scoreType = hashSearchEval - 25;
                threadD.excludedMove = move;
                const score = searchLoop(p_state, p_info, singularD, ply, singularBeta - 1, singularBeta, ss, threadD, cutnode, .NonPV);
                threadD.excludedMove = .{};

                if (score < singularBeta) {
                    if ((score + weightl.singularMarginDoubleExt) < singularBeta and comptime t == .NonPV) {
                        extension += 2;
                    } else {
                        extension += 1;
                    }
                } else if (singularBeta >= _beta) {
                    return singularBeta;
                } else if (cutnode) {
                    extension -= 1;
                }
            }
        }

        currS.playedMove = move;
        currS.pieceMoved = fPiece;
        p_state.makeMove(move);
        hashl.hashTable.prefetchHash(p_state.frame.key);

        if (comptime configl.USE_NNUE) {
            nnuel.updateNnueOnMove(p_state, move);
        }

        var fullSearch: bool = false;
        var score: scoreType = 0;
        const newDepth: depthT = @min(_depth - 1 + extension, typel.MAX_PLY - 2);

        // rewrite of main search handling
        // https://github.com/Adam-Kulju/Patricia/
        //if (!isChecked and _depth >= weightl.LMRDepth and movesPlayed > (weightl.moveReductionAmount - @intFromBool(t == .NonPV))) {
        //if (!isChecked and _depth >= weightl.LMRDepth and movesPlayed > @intFromBool(t == .PV)) {
        if (_depth >= weightl.LMRDepth and movesPlayed > weightl.moveReductionAmount) {
            var _lmrR = lmrR;
            const R = historyl.lmrBase[@intCast(_depth)][movesPlayed];
            if (isCapture) {
                _lmrR += @divFloor(R, 2);
            } else {
                _lmrR += (R - heuristicl.depthToMilliDepth(@divFloor(histScore, weightl.lmr_histDiv)));
            }

            if (givesCheck) {
                _lmrR += weightl.lmr_givesCheck;
            }
            if (isPromo) {
                _lmrR += weightl.lmr_isPromotion;
            }
            if (!isCapture and moveScore >= weightl.lmr_scoreThreshold) {
                _lmrR += weightl.lmr_killerMove;
            } else if (!isThreat and gen.phase == .BADCAPTURE) {
                _lmrR += weightl.lmr_badCapture;
            }
            if (nextS.failHighCount > weightl.lmr_highFailCount) {
                _lmrR += weightl.lmr_highFailScore;
            }

            const d: depthT = std.math.clamp(heuristicl.milliDepthToDepth(_lmrR), 0, newDepth - 1);
            score = -searchLoop(p_state, p_info, newDepth - d, ply + 1, -_alpha - 1, -_alpha, ss, threadD, true, .NonPV);
            fullSearch = score > _alpha and d > 0;
        } else {
            // ignores the first move for the full search
            fullSearch = (movesPlayed != 0) or comptime t == .NonPV;
        }
        if (fullSearch) {
            score = -searchLoop(p_state, p_info, newDepth, ply + 1, -_alpha - 1, -_alpha, ss, threadD, !cutnode, .NonPV);
        }
        if ((movesPlayed == 0 or score > _alpha) and comptime t == .PV) {
            pv.reset();
            nextS.pv = &pv;
            score = -searchLoop(p_state, p_info, newDepth, ply + 1, -_beta, -_alpha, ss, threadD, false, .PV);
        }

        p_state.undoMove();
        p_state.frame = f;
        //if (!p_info.alive) return bestScore;
        //if (isRoot) {
        //    threadD.findRootMove(move).nodes += p_info.searchStat.n_nodeExplored - prevNode;
        //}
        movesPlayed += 1;
        if (score > bestScore) {
            bestScore = score;
            if (bestScore > _alpha) {
                bestMove = move;
                _alpha = bestScore;
                if (comptime t == .PV) {
                    currS.pv.?.onBestMove(move, nextS.pv);
                }
                if (_alpha >= _beta) {
                    hashFlag = .LOWER;
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
            if (isChecked) {
                bestScore = chessl.mated_in(ply);
            } else {
                bestScore = 0;
            }
        } else {
            bestScore = _alpha;
        }
    }
    if (!isChecked and (!bestMove.isCapture() or !bestMove.isValid()) and !(hashFlag == .LOWER and bestScore <= static_eval) and !(!bestMove.isValid() and bestScore >= static_eval)) {
        const bonus =
            std.math.clamp(@divFloor((bestScore - static_eval) * _depth, 8), -256, 256);

        const offset = chessl.whiteBoolToInt(white);
        const pHash = historyl.pawnHashIndexToIdx(p_state.frame.pawnKey);
        historyl.pawnCorrHist[offset][pHash] = updateCorrhist(historyl.pawnCorrHist[offset][pHash], bonus);

        const npWHash = historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.WHITE)]);
        historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.WHITE)][npWHash] = updateCorrhist(historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.WHITE)][npWHash], bonus);

        const npBHash = historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.BLACK)]);
        historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.BLACK)][npBHash] = updateCorrhist(historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.BLACK)][npBHash], bonus);

        const prev1 = ss.getPrevFrame(ply, 1);
        const prev2 = ss.getPrevFrame(ply, 2);
        if (prev1.playedMove.isValid() and prev2.playedMove.isValid()) {
            const to1 = prev1.playedMove.getTo();
            const to2 = prev2.playedMove.getTo();
            historyl.corrHist[@intFromEnum(prev2.pieceMoved)][to2][@intFromEnum(prev1.pieceMoved)][to1] = updateCorrhist(historyl.corrHist[@intFromEnum(prev2.pieceMoved)][to2][@intFromEnum(prev1.pieceMoved)][to1], bonus);
        }
    }
    if (hashFlag == .LOWER) {
        //const malus = -@divFloor(historyBonus, 4);
        const malus = -historyBonus;
        const _historyBonus = historyBonus - malus;
        if (bestMove.isQuietMove()) {
            currS.killerMove = bestMove;
            const prevMove = ss.getPrevFrame(ply, 1).playedMove;
            const prevPiece = @intFromEnum(ss.getPrevFrame(ply, 1).pieceMoved);
            const prevMoveTo = prevMove.getTo();

            const prevPrevMove = ss.getPrevFrame(ply, 2).playedMove;
            const prevPrevPiece = @intFromEnum(ss.getPrevFrame(ply, 2).pieceMoved);
            const prevPrevMoveTo = prevPrevMove.getTo();

            const prevMove4 = ss.getPrevFrame(ply, 4).playedMove;
            const prevPiece4 = @intFromEnum(ss.getPrevFrame(ply, 4).pieceMoved);
            const prevMove4To = prevMove4.getTo();

            //for (0..nQuiets) |i| {
            //    const _move = quiets[i];

            for (0..gen.quiets.moves.len) |i| {
                const move = gen.quiets.moves.moves[i];
                const to = move.getTo();
                const from = move.getFrom();
                const piece: u8 = @intFromEnum(p_state.getPiece(from));

                historyl.continuationHeuristic[prevPiece][prevMoveTo][piece][to] = updateHistory(historyl.continuationHeuristic[prevPiece][prevMoveTo][piece][to], malus);

                historyl.continuationHeuristic[prevPrevPiece][prevPrevMoveTo][piece][to] = updateHistory(historyl.continuationHeuristic[prevPrevPiece][prevPrevMoveTo][piece][to], malus);

                historyl.continuationHeuristic[prevPiece4][prevMove4To][piece][to] = updateHistory(historyl.continuationHeuristic[prevPiece4][prevMove4To][piece][to], malus);

                historyl.historyHeuristic[whiteIdx][from][to] = updateHistory(historyl.historyHeuristic[whiteIdx][from][to], malus);
            }
            const bestTo = bestMove.getTo();
            const bestFrom = bestMove.getFrom();
            const bestPiece = @intFromEnum(p_state.getPiece(bestFrom));
            historyl.historyHeuristic[whiteIdx][bestFrom][bestTo] = updateHistory(historyl.historyHeuristic[whiteIdx][bestFrom][bestTo], _historyBonus);

            historyl.continuationHeuristic[prevPiece][prevMoveTo][bestPiece][bestTo] = updateHistory(historyl.continuationHeuristic[prevPiece][prevMoveTo][bestPiece][bestTo], _historyBonus);
            historyl.continuationHeuristic[prevPrevPiece][prevPrevMoveTo][bestPiece][bestTo] = updateHistory(historyl.continuationHeuristic[prevPrevPiece][prevPrevMoveTo][bestPiece][bestTo], _historyBonus);

            historyl.continuationHeuristic[prevPiece4][prevMove4To][bestPiece][bestTo] = updateHistory(historyl.continuationHeuristic[prevPiece4][prevMove4To][bestPiece][bestTo], _historyBonus);
        } else {
            const from = bestMove.getFrom();
            const to = bestMove.getTo();
            const fPiece = @intFromEnum(p_state.getPiece(from));
            const cPiece = @intFromEnum(p_state.getPiece(to));
            historyl.captureHistory[fPiece][cPiece][to] = updateHistory(historyl.captureHistory[fPiece][cPiece][to], _historyBonus);
        }

        // for (0..nCaptures) |i| {
        //     // checking for hashMove unecessary because if beta cutoff with hash no captures generated
        //     const move = captures[i];

        for (0..gen.captures.moves.len) |i| {
            const move = gen.captures.moves.moves[i];
            const from = move.getFrom();
            const to = move.getTo();
            const fPiece = @intFromEnum(p_state.getPiece(from));
            const cPiece = @intFromEnum(p_state.getPiece(to));
            historyl.captureHistory[fPiece][cPiece][to] = updateHistory(historyl.captureHistory[fPiece][cPiece][to], malus);
        }
    } else if (hashFlag == .ALL) {
        const bestTo = bestMove.getTo();
        const bestFrom = bestMove.getFrom();
        const bestPiece = @intFromEnum(p_state.getPiece(bestFrom));
        if (bestMove.isCapture()) {
            const cPiece = @intFromEnum(p_state.getPiece(bestTo));
            historyl.captureHistory[bestPiece][cPiece][bestTo] = updateHistory(historyl.captureHistory[bestPiece][cPiece][bestTo], historyBonus);
        } else {
            historyl.historyHeuristic[whiteIdx][bestFrom][bestTo] = updateHistory(historyl.historyHeuristic[whiteIdx][bestFrom][bestTo], historyBonus);
        }
    }
    if (!singularExt) {
        const s_entry: hashl.Hash_entry = hashl.buildEntryMatchExt(p_state.frame.key, @intCast(_depth), hashFlag, bestMove, raw_eval, hashl.evalToTTEval(bestScore, ply));
        writer.writeShort(s_entry);
    }
    return bestScore;
}

pub fn correct_eval(p_state: *const boardl.boardState, ss: *searchStack, eval: scoreType, ply: depthT) scoreType {
    const offset = chessl.whiteBoolToInt(p_state.whiteToMove());

    var corr: scoreType = historyl.pawnCorrHist[offset][historyl.pawnHashIndexToIdx(p_state.frame.pawnKey)];
    corr += historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.WHITE)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.WHITE)])];
    corr += historyl.nonPawnCorrHist[offset][@intFromEnum(e_color.BLACK)][historyl.pawnHashIndexToIdx(p_state.frame.nonPawnKey[@intFromEnum(e_color.BLACK)])];

    const prev1 = ss.getPrevFrame(ply, 1);
    const prev2 = ss.getPrevFrame(ply, 2);
    if (prev1.playedMove.isValid() and prev2.playedMove.isValid()) {
        const p1 = prev1.playedMove.getTo();
        const p2 = prev2.playedMove.getTo();
        corr += historyl.corrHist[@intFromEnum(prev2.pieceMoved)][p2][@intFromEnum(prev1.pieceMoved)][p1];
    }

    return std.math.clamp(eval + @divFloor(weightl.corrHistW * corr, 512), -weightl.simpleCheckMateThreshold + 1, weightl.simpleCheckMateThreshold - 1);
}
pub inline fn updateCorrhist(val: scoreType, bonus: scoreType) scoreType {
    //return val + bonus - @as(scoreType, @intCast(@divFloor(@as(i64, @intCast(val)) * @as(i64, @intCast(@abs(bonus))), 1024)));

    //const v = @as(i64, @intCast(val));
    //const b = @as(i64, @intCast(bonus));
    //return @truncate(v + b - @divFloor(v * @as(i64, @intCast(@abs(b))), 1024));
    //return val + bonus - @as(scoreType, @intCast(@divFloor(@as(i64, @intCast(val)) * @as(i64, @intCast(@abs(bonus))), 1024)));
    return val + bonus - @divFloor(val * @as(scoreType, @intCast(@abs(bonus))), 1024);
}

pub inline fn updateHistory(val: scoreType, bonus: scoreType) scoreType {
    return val + bonus - @divFloor(val * @as(scoreType, @intCast(@abs(bonus))), configl.MAX_HIST_HEURISTIC_VALUE);
    //return val + bonus - @as(scoreType, @intCast(@divFloor(@as(i64, @intCast(val)) * @as(i64, @intCast(@abs(bonus))), configl.MAX_HIST_HEURISTIC_VALUE)));
    //return val + bonus - @divFloor(val * @as(scoreType, @intCast(@abs(bonus))), configl.MAX_HIST_HEURISTIC_VALUE);
}
