const std = @import("std");
const build_options = @import("build_options");

const boardStatusl = @import("board_status.zig");
const chessl = @import("chess.zig");
const movel = @import("move.zig");
const heuristicl = @import("heuristic.zig");
const hashl = @import("hashTable.zig");
const typel = @import("type.zig");
const squarel = @import("square.zig");
const configl = @import("config.zig");

const e_piece = typel.e_piece;
const e_pieceType = typel.e_pieceType;
const e_color = typel.e_color;
const e_square = typel.e_square;
const scoreType = typel.scoreType;

const IMove = movel.IMove;

const useDebug = build_options.useDebug;

pub const board = struct {
    pieceBB: [chessl.N_PIECES_TYPES]u64 = @splat(0),
    pieceArray: [chessl.N_SQUARES]e_piece = @splat(e_piece.nEmptySquare),
    c_occupiedBB: [2]u64 = @splat(0),
    pieceCount: [chessl.N_PIECES]i8 = @splat(0),
    wKingSq: e_square = .a1,
    bKingSq: e_square = .a1,
    turnCount: u16 = 1,
    _whiteToMove: bool = false,

    pub inline fn occupiedBB(self: board) u64 {
        return self.c_occupiedBB[0] | self.c_occupiedBB[1];
    }

    pub inline fn occupiedBB_col(self: board, color: e_color) u64 {
        return self.c_occupiedBB[@intFromEnum(color)];
    }

    pub inline fn placePiece(self: *board, piece: e_piece, sq: u8) void {
        const c = chessl.e_colorFromPiece(piece);
        if (c == .WHITE) {
            self._placePiece(piece, sq, true);
        } else {
            self._placePiece(piece, sq, false);
        }
    }
    pub inline fn _placePiece(self: *board, piece: e_piece, sq: u8, comptime white: bool) void {
        const bb = chessl.xToBitboard(sq);
        self.c_occupiedBB[chessl.whiteBoolToInt(white)] ^= bb;
        self.pieceBB[@intFromEnum(chessl.e_pieceTo_e_pieceType((piece)))] ^= bb;
        self.pieceArray[sq] = piece;
        self.pieceCount[@intFromEnum(piece)] += 1;
    }
    pub inline fn removePiece(self: *board, sq: u8) void {
        const piece = self.getPiece(sq);
        const c = chessl.e_colorFromPiece(piece);
        if (c == .WHITE) {
            return self._removePiece(piece, sq, true);
        }
        return self._removePiece(piece, sq, false);
    }

    pub inline fn _removePiece(self: *board, piece: e_piece, sq: u8, comptime white: bool) void {
        const bb = chessl.xToBitboard(sq);
        self.c_occupiedBB[chessl.whiteBoolToInt(white)] ^= bb;
        self.pieceBB[@intFromEnum(chessl.e_pieceTo_e_pieceType(piece))] ^= bb;
        self.pieceCount[@intFromEnum(piece)] -= 1;
        self.pieceArray[sq] = .nEmptySquare;
    }
    pub inline fn movePiece(self: *board, from: u8, to: u8) void {
        const piece = self.getPiece(from);
        const c = chessl.e_colorFromPiece(piece);
        if (c == .WHITE) {
            return self._movePiece(piece, from, to, true);
        }
        return self._movePiece(piece, from, to, false);
    }
    pub inline fn _movePiece(self: *board, piece: e_piece, from: u8, to: u8, comptime white: bool) void {
        const moveBB = chessl.xToBitboard(from) | chessl.xToBitboard(to);
        self.c_occupiedBB[chessl.whiteBoolToInt(white)] ^= moveBB;
        self.pieceBB[@intFromEnum(chessl.e_pieceTo_e_pieceType(piece))] ^= moveBB;
        self.pieceArray[from] = .nEmptySquare;
        self.pieceArray[to] = piece;
    }

    pub inline fn _movePieceBis(self: *board, pieceFrom: e_piece, from: u8, pieceTo: e_piece, to: u8, comptime white: bool) void {
        const fromBB = chessl.xToBitboard(from);
        const toBB = chessl.xToBitboard(to);
        self.c_occupiedBB[chessl.whiteBoolToInt(white)] ^= (fromBB | toBB);
        self.pieceBB[@intFromEnum(chessl.e_pieceTo_e_pieceType(pieceFrom))] ^= fromBB;
        self.pieceBB[@intFromEnum(chessl.e_pieceTo_e_pieceType(pieceTo))] ^= toBB;

        self.pieceCount[@intFromEnum(pieceFrom)] -= 1;
        self.pieceCount[@intFromEnum(pieceTo)] += 1;

        self.pieceArray[from] = .nEmptySquare;
        self.pieceArray[to] = pieceTo;
    }
    pub inline fn getPiece(self: board, sq: u8) e_piece {
        return self.pieceArray[sq];
    }

    pub inline fn getPieceCount(self: board, piece: e_piece) i8 {
        return self.pieceCount[@intFromEnum(piece)];
    }

    pub inline fn getSidePieceCount(self: board, color: e_color) u8 {
        return chessl.popcount(self.c_occupiedBB[@intFromEnum(color)]);
    }
    pub inline fn invertTurn(self: *board) void {
        self._whiteToMove = !self._whiteToMove;
    }
    pub inline fn nextTurn(self: *board) void {
        self.turnCount += 1;
        self.invertTurn();
    }
    pub inline fn undoTurn(self: *board) void {
        self.turnCount -= 1;
        self.invertTurn();
    }
};
pub const boardFrame = struct {
    pinnedBB: u64 = 0,
    checkersBB: u64 = 0,

    key: hashl.Key = 0,
    pawnKey: hashl.Key = 0,
    // WHITE, BLACK
    nonPawnKey: [2]hashl.Key = @splat(0),

    phase: scoreType = 0,
    lastMove: IMove = .{},
    victim: e_piece = .nEmptySquare,
    enPassantIdx: u8 = 0,
    halfMoveClock: u8 = 0,
    stat: boardStatusl.status = .{},
    psqtEval: scoreType = 0,
    pub inline fn copy(state: *const boardState) boardFrame {
        return state.frame;
    }
};

pub const boardState = struct {
    b: board = .{},
    frame: boardFrame = .{},
    moveHistory: movel.matchMoveContainer = .{},

    pub inline fn copy(p_self: *const boardState) boardState {
        return p_self.*;
    }
    pub inline fn whiteToMove(self: *const boardState) bool {
        return self.b._whiteToMove;
    }

    pub fn get_fen(self: *const boardState) [chessl.MAX_FEN_LENGTH]u8 {
        var ret = std.mem.zeroes([chessl.MAX_FEN_LENGTH]u8);
        var miscOffset: u8 = 0;
        var emptyNumber: u8 = 0;
        var board_offset = chessl.N_SQUARES - 8;
        for (0..chessl.N_SQUARES) |i| {
            if (i % chessl.ROW_SIZE == 0 and i != 0) {
                if (emptyNumber != 0) {
                    ret[miscOffset] = '0' + emptyNumber;
                    emptyNumber = 0;
                    miscOffset += 1;
                }
                ret[miscOffset] = '/';
                miscOffset += 1;
                board_offset -= 16;
            }
            const piece = self.getPiece(board_offset);
            if (piece != .nEmptySquare) {
                if (emptyNumber != 0) {
                    ret[miscOffset] = '0' + emptyNumber;
                    emptyNumber = 0;
                    miscOffset += 1;
                }
                const pieceStr = chessl.getStrFromPiece(piece);
                ret[miscOffset] = pieceStr;
                miscOffset += 1;
            } else {
                emptyNumber += 1;
            }
            board_offset += 1;
        }
        if (emptyNumber != 0) {
            ret[miscOffset] = '0' + emptyNumber;
            miscOffset += 1;
        }
        //const endPiece = N_SQUARES - (1 + miscOffset);
        const endPiece = miscOffset;
        ret[endPiece] = ' ';
        if (self.whiteToMove()) {
            ret[endPiece + 1] = 'w';
        } else {
            ret[endPiece + 1] = 'b';
        }
        ret[endPiece + 2] = ' ';
        var castleOffset: u8 = 0;
        if (self.frame.stat.canKingsideCastle(true)) {
            ret[endPiece + 3 + castleOffset] = 'H';
            castleOffset += 1;
        }
        if (self.frame.stat.canQueensideCastle(true)) {
            ret[endPiece + 3 + castleOffset] = 'A';
            castleOffset += 1;
        }
        if (self.frame.stat.canKingsideCastle(false)) {
            ret[endPiece + 3 + castleOffset] = 'h';
            castleOffset += 1;
        }
        if (self.frame.stat.canQueensideCastle(false)) {
            ret[endPiece + 3 + castleOffset] = 'a';
            castleOffset += 1;
        }
        var endCastlOffset: u8 = endPiece + 3 + castleOffset;
        var endEnPassantOffset: u8 = 0;
        if (castleOffset == 0) {
            ret[endCastlOffset] = '-';
            endCastlOffset += 1;
        }
        ret[endCastlOffset] = ' ';

        if (self.frame.enPassantIdx == 0) {
            ret[endCastlOffset + 1] = '-';
            endEnPassantOffset = endCastlOffset + 1;
        } else {
            const sqStr = chessl.strFromLERF(@enumFromInt(self.frame.enPassantIdx));
            ret[endCastlOffset + 1] = sqStr[0];
            ret[endCastlOffset + 2] = sqStr[1];
            endEnPassantOffset = endCastlOffset + 2;
        }
        ret[endEnPassantOffset + 1] = ' ';
        var buffer: [20]u8 = undefined;
        const halfMove = std.fmt.bufPrint(&buffer, "{}", .{self.frame.halfMoveClock}) catch {
            return ret;
        };
        var offset: u8 = 0;
        for (halfMove) |letter| {
            ret[endEnPassantOffset + 2 + offset] = letter;
            offset += 1;
        }
        const endHalfMoveOffset: u8 = offset + endEnPassantOffset + 2;
        ret[endHalfMoveOffset] = ' ';
        offset = 0;
        const fullMoveClock = std.fmt.bufPrint(&buffer, "{}", .{self.b.turnCount}) catch {
            return ret;
        };
        for (fullMoveClock) |letter| {
            ret[endHalfMoveOffset + 1 + offset] = letter;
            offset += 1;
        }
        return ret;
    }
    pub inline fn getPiece(p_self: *const boardState, sq: u8) e_piece {
        return p_self.b.pieceArray[sq];
    }

    pub fn placePiece(p_self: *boardState, piece: e_piece, square: e_square) bool {
        const one_mask: u64 = chessl.sqToBitboard(square);
        if (p_self.b.occupiedBB() & one_mask != 0) {
            return false;
        }

        p_self.b.pieceBB[@intFromEnum(chessl.e_pieceTo_e_pieceType(piece))] |= one_mask;
        p_self.b.pieceCount[@intFromEnum(piece)] += 1;
        p_self.b.pieceArray[@intFromEnum(square)] = piece;
        if (@intFromEnum(piece) < chessl.N_PIECES_TYPES) {
            p_self.b.c_occupiedBB[@intFromEnum(e_color.WHITE)] |= one_mask;
            p_self.frame.phase += typel.phases_arr[@intFromEnum(piece)];
        } else {
            p_self.b.c_occupiedBB[@intFromEnum(e_color.BLACK)] |= one_mask;
            p_self.frame.phase += typel.phases_arr[@intFromEnum(piece) - chessl.N_PIECES_TYPES];
        }
        if (piece == .nWhiteKing) {
            p_self.b.wKingSq = square;
        } else if (piece == .nBlackKing) {
            p_self.b.bKingSq = square;
        }
        return true;
    }

    pub inline fn undoMove(p_self: *boardState) void {
        if (p_self.whiteToMove()) {
            _undoMove(p_self, false);
        } else {
            _undoMove(p_self, true);
        }
    }

    pub inline fn _undoMove(p_self: *boardState, comptime white: bool) void {
        p_self.moveHistory.popMoveVoid();
        const move = p_self.frame.lastMove;
        if (move.isCapture()) {
            undoMoveCapture_cst(p_self, move, white);
        } else {
            undoMoveQuiet_cst(p_self, move, white);
        }
        p_self.b.undoTurn();
    }
    pub fn undoMoveCapture_cst(p_self: *boardState, move: IMove, comptime white: bool) void {
        // test to reduce the undoMove load
        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        const victim = p_self.frame.victim;
        const toSq: u8 = move.getTo();
        const fromSq: u8 = move.getFrom();
        const toBB = chessl.xToBitboard(toSq);
        const fromBB = chessl.xToBitboard(fromSq);
        const moveBB = toBB | fromBB;
        const usIdx = chessl.cst_whiteBoolToInt(white);
        const enemyIdx = usIdx ^ 1;

        var piece = p_self.getPiece(toSq);
        var _piece = chessl.e_pieceTo_e_pieceTypeCst(piece, white);

        p_self.b.pieceBB[@intFromEnum(_piece)] ^= moveBB;
        if (move.isPromotion()) {
            // this is the promotion piece
            p_self.b.pieceBB[@intFromEnum(_piece)] ^= fromBB;
            p_self.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] ^= fromBB;
            p_self.b.pieceCount[@intFromEnum(piece)] -= 1;
            piece = if (comptime white) (.nWhitePawn) else (.nBlackPawn);
            _piece = .PAWN;
            p_self.b.pieceCount[@intFromEnum(piece)] += 1;
        }
        p_self.b.c_occupiedBB[usIdx] ^= (moveBB);
        p_self.b.pieceArray[fromSq] = piece;

        p_self.b.pieceBB[@intFromEnum(chessl.e_pieceTo_e_pieceTypeCst(victim, !white))] ^= toBB;
        p_self.b.c_occupiedBB[enemyIdx] ^= toBB;

        p_self.b.pieceArray[toSq] = victim;
        p_self.b.pieceCount[@intFromEnum(victim)] += 1;

        if (move.isEnpassant()) {
            const victimSq: e_square = chessl.enPassantVictimSq(fromSq, toSq);
            const victimBB: u64 = chessl.sqToBitboard(victimSq);
            const bisBB = victimBB | toBB;
            p_self.b.pieceArray[toSq] = .nEmptySquare;
            p_self.b.pieceArray[@intFromEnum(victimSq)] = victim;
            p_self.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] ^= bisBB;
            p_self.b.c_occupiedBB[enemyIdx] ^= bisBB;
        } else if (_piece == .KING) {
            if (comptime white) {
                p_self.b.wKingSq = @enumFromInt(fromSq);
            } else {
                p_self.b.bKingSq = @enumFromInt(fromSq);
            }
        }
        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
    }
    pub fn undoMoveQuiet_cst(p_self: *boardState, move: IMove, comptime white: bool) void {
        // test to reduce the undoMove load

        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }

        const toSq: u8 = move.getTo();
        const toBB = chessl.xToBitboard(toSq);
        const fromSq: u8 = move.getFrom();
        const fromBB = chessl.xToBitboard(fromSq);
        const moveBB = toBB | fromBB;
        const usIdx = chessl.cst_whiteBoolToInt(white);

        var piece = p_self.getPiece(toSq);
        var _piece = chessl.e_pieceTo_e_pieceTypeCst(piece, white);

        p_self.b.pieceBB[@intFromEnum(_piece)] ^= moveBB;
        if (move.isPromotion()) {
            // this is the promotion piece
            p_self.b.pieceCount[@intFromEnum(piece)] -= 1;
            p_self.b.pieceBB[@intFromEnum(_piece)] ^= fromBB;
            // fromPiece is the pawn
            piece = if (comptime white) (.nWhitePawn) else (.nBlackPawn);
            _piece = .PAWN;
            p_self.b.pieceCount[@intFromEnum(piece)] += 1;
            p_self.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] ^= fromBB;
        }
        p_self.b.c_occupiedBB[usIdx] ^= (moveBB);
        p_self.b.pieceArray[toSq] = .nEmptySquare;
        p_self.b.pieceArray[fromSq] = piece;

        if (_piece == .KING) {
            if (comptime white) {
                p_self.b.wKingSq = @enumFromInt(fromSq);
            } else {
                p_self.b.bKingSq = @enumFromInt(fromSq);
            }
            if (move.isCastle()) {
                const r: e_piece = (if (comptime white) .nWhiteRook else .nBlackRook);
                const isKingC = move.isKingSideCastle();
                const rStart: e_square = if (isKingC) (if (comptime white) (.h1) else (.h8)) else (if (comptime white) (.a1) else (.a8));
                const rEnd: e_square = if (isKingC) (if (comptime white) (.f1) else (.f8)) else (if (comptime white) (.d1) else (.d8));
                const mask: u64 = if (isKingC) (if (comptime white) (boardStatusl.wCastleKRookBit) else (boardStatusl.bCastleKRookBit)) else (if (comptime white) (boardStatusl.wCastleQRookBit) else (boardStatusl.bCastleQRookBit));
                p_self.b.pieceBB[@intFromEnum(e_pieceType.ROOK)] ^= mask;
                p_self.b.c_occupiedBB[usIdx] ^= (mask);
                p_self.b.pieceArray[@intFromEnum(rStart)] = r;
                p_self.b.pieceArray[@intFromEnum(rEnd)] = .nEmptySquare;
            }
        }

        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
    }

    pub inline fn undoNullMove(p_self: *boardState) void {
        p_self.b.undoTurn();
    }

    pub inline fn makeNullMove(p_self: *boardState) void {
        if (p_self.whiteToMove()) {
            p_self.makeNullMove_cst(true);
        } else {
            p_self.makeNullMove_cst(false);
        }
        p_self.b.nextTurn();
    }
    pub fn makeNullMove_cst(p_self: *boardState, comptime white: bool) void {
        p_self.frame.lastMove = .{};
        p_self.frame.victim = .nEmptySquare;
        p_self.frame.key ^= hashl.zobristKeys.playKey;
        if (p_self.frame.enPassantIdx != 0) {
            p_self.frame.key ^= hashl.zobristKeys.enPassantKey;
            p_self.frame.enPassantIdx = 0;
        }
        chessl.onMoveStaged(p_self, !white);
    }
    pub inline fn makeMove(p_self: *boardState, move: IMove) void {
        if (p_self.whiteToMove()) {
            p_self._makeMove(move, true, true);
        } else {
            p_self._makeMove(move, false, true);
        }
    }
    pub inline fn makeMovePerft(p_self: *boardState, move: IMove) void {
        if (p_self.whiteToMove()) {
            p_self._makeMove(move, true, false);
        } else {
            p_self._makeMove(move, false, false);
        }
    }

    pub fn _makeMove(p_self: *boardState, move: IMove, comptime white: bool, comptime updatePSQT: bool) void {
        //const t = move.getType();
        //switch (t) {
        //    .STANDARD => {
        //        p_self.generalMakeMove(move, white, .STANDARD, updatePSQT);
        //    },
        //    .CASTLE => {
        //        p_self.generalMakeMove(move, white, .CASTLE, updatePSQT);
        //    },
        //    .PROMOTION => {
        //        p_self.generalMakeMove(move, white, .PROMOTION, updatePSQT);
        //    },
        //    .EP => {
        //        p_self.generalMakeMove(move, white, .EP, updatePSQT);
        //    },
        //}
        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        if (move.isCapture()) {
            p_self.makeMoveCapture_cst(move, white, updatePSQT);
        } else {
            p_self.makeMoveQuiet_cst(move, white, updatePSQT);
        }
        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        chessl.onMoveStaged(p_self, !white);
        p_self.b.nextTurn();
    }
    pub fn generalMakeMove(p_self: *boardState, move: IMove, comptime white: bool, comptime t: typel.e_moveType, comptime updatePSQT: bool) void {
        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        const prevCastle: u8 = p_self.frame.stat.castlingKey();
        const prevEp: u8 = p_self.frame.enPassantIdx;

        p_self.frame.lastMove = move;
        p_self.frame.enPassantIdx = 0;
        const to = move.getTo();
        const from = move.getFrom();
        const isCapture = if (comptime t == .CASTLE) false else (if (comptime t != .EP) (move.isCapture()) else true);
        var toPiece = p_self.getPiece(from);
        var isPawn: bool = false;

        const usIdx = chessl.cst_whiteBoolToInt(white);

        if (comptime t == .EP) {
            const victimSq: e_square = chessl.enPassantVictimSq(from, to);
            const victim: e_piece = if (comptime white) .nBlackPawn else .nWhitePawn;
            p_self.b._removePiece(victim, @intFromEnum(victimSq), !white);
            p_self.frame.victim = victim;
        } else if (isCapture and comptime t != .CASTLE) {
            const victim = p_self.getPiece(to);
            p_self.b._removePiece(victim, to, !white);
            p_self.frame.victim = victim;
            if (chessl.isRookPiece(victim)) {
                p_self.frame.stat.onRookMove(chessl.xToBitboard(to), !white);
            }
        } else {
            p_self.frame.victim = .nEmptySquare;
        }
        if (comptime t == .PROMOTION) {
            toPiece = chessl.flagPromotionToPiece(move.getFlag(), white);
            p_self.b._movePieceBis(if (comptime white) .nWhitePawn else .nBlackPawn, from, toPiece, to, white);
        } else {
            p_self.b._movePiece(toPiece, from, to, white);
        }
        if (comptime t == .CASTLE) {
            const isKingC = move.isKingSideCastle();
            const r: e_piece = (if (comptime white) .nWhiteRook else .nBlackRook);
            const rStart: e_square = if (isKingC) (if (comptime white) (.h1) else (.h8)) else (if (comptime white) (.a1) else (.a8));
            const rEnd: e_square = if (isKingC) (if (comptime white) (.f1) else (.f8)) else (if (comptime white) (.d1) else (.d8));
            const mask: u64 = if (isKingC) (if (comptime white) (boardStatusl.wCastleKRookBit) else (boardStatusl.bCastleKRookBit)) else (if (comptime white) (boardStatusl.wCastleQRookBit) else (boardStatusl.bCastleQRookBit));

            p_self.b.pieceArray[@intFromEnum(rStart)] = .nEmptySquare;
            p_self.b.pieceArray[@intFromEnum(rEnd)] = r;
            p_self.b.pieceBB[@intFromEnum(e_pieceType.ROOK)] ^= mask;
            p_self.b.c_occupiedBB[usIdx] ^= mask;
        }
        if (chessl.isKingPiece(toPiece) or comptime t == .CASTLE) {
            if (comptime white) {
                p_self.b.wKingSq = @enumFromInt(to);
            } else {
                p_self.b.bKingSq = @enumFromInt(to);
            }
            p_self.frame.stat.onKingMove(white);
        } else if (chessl.isPawnPiece(toPiece)) {
            isPawn = true;
            if (move.isDoublePush()) {
                p_self.frame.enPassantIdx = if (comptime white) (from + 8) else (from - 8);
            }
        } else if (chessl.isRookPiece(toPiece)) {
            p_self.frame.stat.onRookMove(chessl.xToBitboard(from), white);
        }
        if (isCapture or isPawn or comptime t == .PROMOTION) {
            p_self.frame.halfMoveClock = 0;
        } else {
            p_self.frame.halfMoveClock += 1;
        }

        if (isCapture) {
            const keys = chessl.updateKeyOnMove(move, toPiece, &p_self.frame, prevCastle, prevEp, true, white);
            p_self.frame.key = keys.key;
            p_self.frame.nonPawnKey = keys.nonPawnKey;
            p_self.frame.pawnKey = keys.pawnKey;
            if (comptime updatePSQT and !configl.USE_NNUE) {
                p_self.frame.psqtEval += heuristicl.updatePSQTOnMove(white, true, move, comptime t == .PROMOTION, false, toPiece, p_self.getPhase(), &p_self.frame);
            }
        } else {
            const keys = chessl.updateKeyOnMove(move, toPiece, &p_self.frame, prevCastle, prevEp, false, white);
            p_self.frame.key = keys.key;
            p_self.frame.nonPawnKey = keys.nonPawnKey;
            p_self.frame.pawnKey = keys.pawnKey;
            if (comptime updatePSQT and !configl.USE_NNUE) {
                p_self.frame.psqtEval += heuristicl.updatePSQTOnMove(white, false, move, comptime t == .PROMOTION, comptime t == .CASTLE, toPiece, p_self.getPhase(), &p_self.frame);
            }
        }

        _ = p_self.moveHistory.append(move, p_self.frame.key, isPawn);

        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        chessl.onMoveStaged(p_self, !white);
    }
    pub fn makeMoveCapture_cst(p_self: *boardState, move: IMove, comptime white: bool, comptime updatePSQT: bool) void {
        const prevCastle: u8 = p_self.frame.stat.castlingKey();
        const prevEp: u8 = p_self.frame.enPassantIdx;

        p_self.frame.lastMove = move;
        const victim = p_self.getCapturePiece(move);
        const _victim = chessl.e_pieceTo_e_pieceTypeCst(victim, !white);
        p_self.frame.victim = victim;
        p_self.frame.enPassantIdx = 0;
        p_self.frame.halfMoveClock = 0;

        const to = move.getTo();
        const from = move.getFrom();
        const toBB = chessl.xToBitboard(to);
        const fromBB = chessl.xToBitboard(from);
        const moveBB = toBB | fromBB;

        const usIdx = chessl.cst_whiteBoolToInt(white);
        const enemyIdx = usIdx ^ 1;

        var toPiece = p_self.getFromPiece(move);
        var _toPiece = chessl.e_pieceTo_e_pieceTypeCst(toPiece, white);
        const isPromo: bool = move.isPromotion();
        if (_victim == .ROOK) {
            p_self.frame.stat.onRookMove(toBB, !white);
        }

        p_self.frame.phase -= typel.phases_arr[@intFromEnum(_victim)];
        p_self.b.pieceCount[@intFromEnum(victim)] -= 1;

        p_self.b.pieceArray[from] = .nEmptySquare;
        p_self.b.pieceBB[@intFromEnum(_toPiece)] ^= moveBB;
        p_self.b.c_occupiedBB[usIdx] ^= moveBB;
        if (_toPiece == .PAWN) {
            if (move.isEnpassant()) {
                const epSq: e_square = chessl.enPassantVictimSq(from, to);
                const epBB = chessl.sqToBitboard(epSq);
                p_self.b.pieceArray[@intFromEnum(epSq)] = e_piece.nEmptySquare;
                p_self.b.c_occupiedBB[enemyIdx] ^= epBB;
                p_self.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] ^= epBB;
            } else {
                p_self.b.c_occupiedBB[enemyIdx] ^= toBB;
                p_self.b.pieceBB[@intFromEnum(_victim)] ^= toBB;
                if (isPromo) {
                    p_self.b.pieceCount[@intFromEnum(toPiece)] -= 1;
                    toPiece = chessl.flagPromotionToPiece(move.getFlag(), white);
                    _toPiece = chessl.e_pieceTo_e_pieceTypeCst(toPiece, white);
                    p_self.frame.phase += typel.phases_arr[@intFromEnum(_toPiece)];
                    p_self.b.pieceCount[@intFromEnum(toPiece)] += 1;
                    p_self.b.pieceBB[@intFromEnum(_toPiece)] ^= toBB;
                    p_self.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] ^= toBB;
                }
            }
        } else {
            p_self.b.c_occupiedBB[enemyIdx] ^= toBB;
            p_self.b.pieceBB[@intFromEnum(_victim)] ^= toBB;

            if (_toPiece == .ROOK) {
                p_self.frame.stat.onRookMove(fromBB, white);
            } else if (_toPiece == .KING) {
                if (comptime white) {
                    p_self.b.wKingSq = @enumFromInt(to);
                } else {
                    p_self.b.bKingSq = @enumFromInt(to);
                }
                p_self.frame.stat.onKingMove(white);
            }
        }
        p_self.b.pieceArray[to] = toPiece;

        const keys = chessl.updateKeyOnMove(move, toPiece, &p_self.frame, prevCastle, prevEp, true, white);
        p_self.frame.key = keys.key;
        p_self.frame.nonPawnKey = keys.nonPawnKey;
        p_self.frame.pawnKey = keys.pawnKey;

        if (comptime updatePSQT and !configl.USE_NNUE) {
            p_self.frame.psqtEval += heuristicl.updatePSQTOnMove(white, true, move, isPromo, false, toPiece, p_self.getPhase(), &p_self.frame);
        }

        _ = p_self.moveHistory.append(move, p_self.frame.key);
    }
    pub fn makeMoveQuiet_cst(p_self: *boardState, move: IMove, comptime white: bool, comptime updatePSQT: bool) void {
        const prevCastle: u8 = p_self.frame.stat.castlingKey();
        const prevEp: u8 = p_self.frame.enPassantIdx;

        p_self.frame.lastMove = move;
        p_self.frame.victim = .nEmptySquare;
        p_self.frame.enPassantIdx = 0;

        const to = move.getTo();
        const from = move.getFrom();
        const toBB = chessl.xToBitboard(to);
        const fromBB = chessl.xToBitboard(from);
        const moveBB = (fromBB | toBB);
        var toPiece = p_self.getPiece(from);
        var _toPiece = chessl.e_pieceTo_e_pieceTypeCst(toPiece, white);

        const usIdx = chessl.cst_whiteBoolToInt(white);

        var isCastle: bool = false;
        const isPromo: bool = move.isPromotion();

        p_self.b.pieceArray[from] = .nEmptySquare;
        p_self.b.pieceBB[@intFromEnum(_toPiece)] ^= moveBB;
        p_self.b.c_occupiedBB[usIdx] ^= moveBB;

        if (_toPiece == .PAWN) {
            p_self.frame.halfMoveClock = 0;
            if (isPromo) {
                p_self.b.pieceCount[@intFromEnum(toPiece)] -= 1;
                toPiece = chessl.flagPromotionToPiece(move.getFlag(), white);
                _toPiece = chessl.e_pieceTo_e_pieceTypeCst(toPiece, white);
                p_self.frame.phase += typel.phases_arr[@intFromEnum(_toPiece)];
                p_self.b.pieceCount[@intFromEnum(toPiece)] += 1;
                p_self.b.pieceBB[@intFromEnum(_toPiece)] ^= toBB;
                p_self.b.pieceBB[@intFromEnum(e_pieceType.PAWN)] ^= toBB;
            } else if (move.isDoublePush()) {
                // middle between from and to
                p_self.frame.enPassantIdx = if (comptime white) (from + 8) else (from - 8);
            }
        } else {
            p_self.frame.halfMoveClock += 1;
            if (_toPiece == .KING) {
                if (comptime white) {
                    p_self.b.wKingSq = @enumFromInt(to);
                } else {
                    p_self.b.bKingSq = @enumFromInt(to);
                }
                if (move.isCastle()) {
                    isCastle = true;
                    const isKingC = move.isKingSideCastle();
                    const r: e_piece = (if (comptime white) .nWhiteRook else .nBlackRook);
                    const rStart: e_square = if (isKingC) (if (comptime white) (.h1) else (.h8)) else (if (comptime white) (.a1) else (.a8));
                    const rEnd: e_square = if (isKingC) (if (comptime white) (.f1) else (.f8)) else (if (comptime white) (.d1) else (.d8));
                    const mask: u64 = if (isKingC) (if (comptime white) (boardStatusl.wCastleKRookBit) else (boardStatusl.bCastleKRookBit)) else (if (comptime white) (boardStatusl.wCastleQRookBit) else (boardStatusl.bCastleQRookBit));

                    p_self.b.pieceArray[@intFromEnum(rStart)] = .nEmptySquare;
                    p_self.b.pieceArray[@intFromEnum(rEnd)] = r;
                    p_self.b.pieceBB[@intFromEnum(e_pieceType.ROOK)] ^= mask;
                    p_self.b.c_occupiedBB[usIdx] ^= mask;
                }
                p_self.frame.stat.onKingMove(white);
            } else if (_toPiece == .ROOK) {
                p_self.frame.stat.onRookMove(fromBB, white);
            }
        }
        p_self.b.pieceArray[to] = toPiece;
        const keys = chessl.updateKeyOnMove(move, toPiece, &p_self.frame, prevCastle, prevEp, false, white);

        p_self.frame.key = keys.key;
        p_self.frame.nonPawnKey = keys.nonPawnKey;
        p_self.frame.pawnKey = keys.pawnKey;

        if (comptime updatePSQT and !configl.USE_NNUE) {
            p_self.frame.psqtEval += heuristicl.updatePSQTOnMove(white, false, move, isPromo, isCastle, toPiece, p_self.getPhase(), &p_self.frame);
        }
        _ = p_self.moveHistory.append(move, p_self.frame.key);
    }

    pub inline fn getLastMove(self: *const boardState) IMove {
        return self.frame.lastMove;
    }

    pub inline fn getFromPiece(self: *const boardState, move: IMove) e_piece {
        return self.getPiece(move.getFrom());
    }
    pub inline fn getCapturePiece(self: *const boardState, move: IMove) e_piece {
        if (move.isEnpassant()) {
            return chessl.pawnFromColor(!chessl.isPieceWhite(self.getFromPiece(move)));
        }
        return self.getPiece(move.getTo());
    }
    pub inline fn getPhase(self: *const boardState) scoreType {
        const _phase = @max(0, typel.totalPhase - self.frame.phase);
        return @divFloor((_phase * 256) + 12, typel.totalPhase);
        // ((24 - p) * 256) + (24 / 2)) / 24
    }
    pub inline fn isEndGame(self: *const boardState) bool {
        const nWhiteP = self.getPieceCount(.nWhiteBishop) + self.getPieceCount(.nWhiteKnight) + self.getPieceCount(.nWhiteRook) + self.getPieceCount(.nWhiteQueen);
        const nBlackP = self.getPieceCount(.nBlackBishop) + self.getPieceCount(.nBlackKnight) + self.getPieceCount(.nBlackRook) + self.getPieceCount(.nBlackQueen);
        return (nWhiteP < 2) and (nBlackP < 2);
    }
    pub inline fn onlyPawns(self: *const boardState) bool {
        return (self.getPieceBB_t(.PAWN) | self.getPieceBB_t(.KING)) == self.b.occupiedBB();
    }
    pub inline fn onlyPawnsSide(self: *const boardState, white: bool) bool {
        const p = if (white) (self.getPieceCount(.nWhiteBishop) + self.getPieceCount(.nWhiteKnight) + self.getPieceCount(.nWhiteRook) + self.getPieceCount(.nWhiteQueen)) else (self.getPieceCount(.nBlackBishop) + self.getPieceCount(.nBlackKnight) + self.getPieceCount(.nBlackRook) + self.getPieceCount(.nBlackQueen));
        return (p == 0);
    }

    pub inline fn getKingSq(self: *const boardState, white: bool) e_square {
        if (white) {
            return self.b.wKingSq;
        }
        return self.b.bKingSq;
    }
    pub inline fn getKingBB(self: *const boardState, white: bool) u64 {
        return chessl.sqToBitboard(self.getKingSq(white));
    }

    pub inline fn canKingSideCastle(self: boardState, comptime white: bool) bool {
        if (comptime white) {
            return self.frame.stat.canKingsideCastle(white) and (chessl.canMove(.e1, .h1, self.b.occupiedBB()));
        }
        return (self.frame.stat.canKingsideCastle(white) and (chessl.canMove(.e8, .h8, self.b.occupiedBB())));
    }
    pub inline fn canQueenSideCastle(self: boardState, comptime white: bool) bool {
        if (comptime white) {
            return self.frame.stat.canQueensideCastle(true) and (chessl.canMove(.e1, .a1, self.b.occupiedBB()));
        }
        return self.frame.stat.canQueensideCastle(false) and (chessl.canMove(.e8, .a8, self.b.occupiedBB()));
    }

    pub inline fn canKingSideCastleAtt(self: boardState, white: bool, attackedSquares: u64) bool {
        if (white) {
            return self.frame.stat.canKingsideCastle(true) and chessl.canMove(.e1, .h1, self.b.occupiedBB()) and ((attackedSquares & chessl.inBetween(.d1, .h1)) == chessl.EMPTY);
        }
        return self.frame.stat.canKingsideCastle(false) and chessl.canMove(.e8, .h8, self.b.occupiedBB()) and ((attackedSquares & chessl.inBetween(.d8, .h8)) == chessl.EMPTY);
    }
    pub inline fn canQueenSideCastleAtt(self: boardState, white: bool, attackedSquares: u64) bool {
        if (white) {
            return self.frame.stat.canQueensideCastle(true) and chessl.canMove(.e1, .a1, self.b.occupiedBB()) and ((attackedSquares & chessl.inBetween(.f1, .b1)) == chessl.EMPTY);
        }
        return self.frame.stat.canQueensideCastle(false) and chessl.canMove(.e8, .a8, self.b.occupiedBB()) and ((attackedSquares & chessl.inBetween(.f8, .b8)) == chessl.EMPTY);
    }

    pub inline fn getPieceCount(self: boardState, piece: e_piece) i8 {
        return self.b.pieceCount[@intFromEnum(piece)];
    }
    pub inline fn getPieceBB(self: boardState, piece: e_piece) u64 {
        return self.getPieceBB_t(chessl.e_pieceTo_e_pieceType(piece)) & self.b.c_occupiedBB[chessl.whiteBoolToInt(chessl.isPieceWhite(piece))];
    }
    pub inline fn getPieceBB_t(self: boardState, piece: e_pieceType) u64 {
        return self.b.pieceBB[@intFromEnum(piece)];
    }
    pub inline fn getTotalPieceCount(self: *const boardState, white: bool) i8 {
        if (white) {
            return self.getPieceCount(.nWhitePawn) + self.getPieceCount(.nWhiteBishop) + self.getPieceCount(.nWhiteKnight) + self.getPieceCount(.nWhiteRook) + self.getPieceCount(.nWhiteQueen);
        }
        return self.getPieceCount(.nBlackPawn) + self.getPieceCount(.nBlackBishop) + self.getPieceCount(.nBlackKnight) + self.getPieceCount(.nBlackRook) + self.getPieceCount(.nBlackQueen);
    }

    pub fn getBigPieceCount(self: *const boardState, white: bool) i8 {
        // putting inline in front of this causes the razoring in zws to segfault even if the razoring is not used ???
        if (white) {
            return self.getPieceCount(.nWhiteBishop) + self.getPieceCount(.nWhiteKnight) + self.getPieceCount(.nWhiteRook) + self.getPieceCount(.nWhiteQueen);
        }
        return self.getPieceCount(.nBlackBishop) + self.getPieceCount(.nBlackKnight) + self.getPieceCount(.nBlackRook) + self.getPieceCount(.nBlackQueen);
    }
    //https://home.hccnet.nl/h.g.muller/deepfut.html
    pub fn getNthBestPiece(self: *const boardState, white: bool, n: u8) e_piece {
        var _n: i32 = @intCast(n);
        const colorOffset: usize = if (white) 0 else chessl.N_PIECES_TYPES;
        for (1..chessl.N_PIECES_TYPES) |idx| {
            // 1: skips the king
            const pieceIdx = colorOffset + (chessl.N_PIECES_TYPES - 1) - idx;
            _n -= self.b.pieceCount[pieceIdx];
            if (_n <= 0) {
                return @enumFromInt(pieceIdx);
            }
        }
        // returns the king if no piece found
        return @enumFromInt(colorOffset + chessl.N_PIECES_TYPES - 1);
    }
    pub inline fn occupiedBB(self: boardState) u64 {
        return self.b.c_occupiedBB[0] | self.b.c_occupiedBB[1];
    }

    pub inline fn occupiedBB_col(self: boardState, color: e_color) u64 {
        return self.b.c_occupiedBB[@intFromEnum(color)];
    }

    pub inline fn getSidePieceCount(self: boardState, color: e_color) u8 {
        return chessl.popcount(self.b.c_occupiedBB[@intFromEnum(color)]);
    }
    pub fn legal(self: *const boardState, move: IMove) bool {
        const white = self.whiteToMove();
        const from = move.getFrom();
        const to = move.getTo();
        const fPiece = chessl.e_pieceTo_e_pieceType(self.getPiece(from));
        const isCapture = move.isCapture();
        const occ = self.b.occupiedBB();
        const kingSq = self.getKingSq(white);
        const checked = self.isChecked();

        const enemy = self.b.c_occupiedBB[chessl.whiteBoolToInt(!white)];
        if (fPiece == .KING) {
            if (move.isCastle()) {
                if (checked) return false;
                const allAttacks = chessl.getAllAttackMask(self, occ ^ chessl.sqToBitboard(kingSq), !white);
                if (move.isKingSideCastle()) {
                    return self.canKingSideCastleAtt(white, allAttacks);
                }
                return self.canQueenSideCastleAtt(white, allAttacks);
            }
            return chessl.getAllAttackerFromSq(self, occ ^ chessl.xToBitboard(from), white, @enumFromInt(to)) == 0;
        }
        if (move.isEnpassant()) {
            return chessl.getAllAttackerFromSq(self, occ ^ (chessl.xToBitboard(from) | chessl.xToBitboard(to) | chessl.sqToBitboard(chessl.enPassantVictimSq(from, to))), white, kingSq) == 0;
        }
        if (isCapture) {
            // ignores the replace bit at to
            if (chessl.xToBitboard(to) & enemy == 0) {
                return false;
            }
            return (chessl.slider_getAllAttackerFromSq(self, occ ^ chessl.xToBitboard(from), white, kingSq) & ~chessl.xToBitboard(to)) == 0;
        }
        return (chessl.slider_getAllAttackerFromSq(self, occ ^ chessl.xToBitboard(from) ^ chessl.xToBitboard(to), white, kingSq) & ~chessl.xToBitboard(to)) == 0;
    }
    pub fn isLegal(p_self: *const boardState, white: bool) bool {
        // slow only used for print purposes
        const king_attacks = chessl.getAllAttackerFromSq(p_self, p_self.b.occupiedBB(), white, p_self.getKingSq(white));
        return king_attacks == 0;
    }
    pub inline fn isChecked(p_self: *const boardState) bool {
        return p_self.frame.checkersBB != 0;
    }
    pub fn isInsufficientMaterial(p_self: *const boardState) bool {
        // TODO: implement complex heuristic at https://www.chessprogramming.org/Draw_Evaluation
        if (p_self.getPieceBB_t(.PAWN) != 0 or p_self.getPieceBB_t(.QUEEN) != 0 or p_self.getPieceBB_t(.ROOK) != 0) {
            return false;
        }
        const nWBishop = p_self.getPieceCount(.nWhiteBishop);
        const nWKnight = p_self.getPieceCount(.nWhiteKnight);

        const nBBishop = p_self.getPieceCount(.nBlackBishop);
        const nBKnight = p_self.getPieceCount(.nBlackKnight);

        //const nBMinor = nBBishop + nBKnight;
        //if ((nBMinor == 0 and nWBishop == 2) or (nWMinor == 0 and nBBishop == 2)) {
        //    return false;
        //}
        //if ((nBMinor == 0 and nWKnight == 3) or (nWMinor == 0 and nBKnight == 3)) {
        //    return false;
        //}
        if ((nWBishop >= 2 or nWKnight >= 2) or (nBBishop >= 2 or nBKnight >= 2)) {
            return false;
        }
        return true;
    }

    pub fn isInsufficientMaterialSide(p_self: *const boardState, white: bool) bool {
        const color_offset: usize = if (white) 0 else (chessl.N_PIECES_TYPES);

        if (p_self.getPieceCount(@enumFromInt(@intFromEnum(e_piece.nWhitePawn) + color_offset)) != 0) {
            return false;
        }
        if (p_self.getPieceCount(@enumFromInt(@intFromEnum(e_piece.nWhiteQueen) + color_offset)) != 0) {
            return false;
        }
        if (p_self.getPieceCount(@enumFromInt(@intFromEnum(e_piece.nWhiteRook) + color_offset)) != 0) {
            return false;
        }
        // TODO: add the cases KBB vs K or others
        // or a better way
        return true;
    }

    pub fn isMovePseudoLegal(self: *const boardState, move: IMove) bool {
        // mainly used to verify if a hash move is possible in the current board config good to check for key collision
        if (!move.isValid()) {
            return false;
        }
        const white = self.whiteToMove();
        if (white) {
            return self._isMovePseudoLegal(move, true);
        }
        return self._isMovePseudoLegal(move, false);
    }
    pub fn _isMovePseudoLegal(self: *const boardState, move: IMove, comptime white: bool) bool {
        const from = move.getFrom();
        const to = move.getTo();
        const fromBB = chessl.xToBitboard(from);
        const toBB = chessl.xToBitboard(to);
        const us = self.b.c_occupiedBB[chessl.cst_whiteBoolToInt(white)];
        const enemy = self.b.c_occupiedBB[chessl.cst_whiteBoolToInt(!white)];
        const occ = us | enemy;
        if ((fromBB & us == 0) or (toBB & us != 0)) {
            return false;
        }
        const p = self.getPiece(from);
        if (p == .nEmptySquare) {
            return false;
        }
        const pT = chessl.e_pieceTo_e_pieceType(p);
        if (move.isPromotion() and pT != .PAWN) {
            return false;
        }
        if (move.isCapture()) {
            if (move.isEnpassant()) {
                if (self.frame.enPassantIdx == 0 or pT != .PAWN) {
                    return false;
                }
                const victimSq: e_square = chessl.enPassantVictimSq(from, to);
                return (@intFromEnum(victimSq) == self.frame.enPassantIdx);
            } else {
                if (toBB & enemy == 0) {
                    // catches case where trying to capture own piece
                    return false;
                }
            }
        } else {
            if (move.isCastle()) {
                if (pT != .KING) return false;
                if (move.isKingSideCastle()) {
                    return self.canKingSideCastle(white);
                } else {
                    return self.canQueenSideCastle(white);
                }
            }
            if (move.isDoublePush()) {
                if (pT != .PAWN) return false;
                if (fromBB & chessl.maskOutPawnDoublePush(white, ~occ) == 0) {
                    return false;
                }
            }
            if (toBB & occ != 0) {
                return false;
            }
        }

        const movesBB = chessl.getRelevantMove(p, @enumFromInt(from), occ) catch {
            return false;
        };
        if ((toBB & movesBB) == 0) {
            return false;
        }
        const checked = self.isChecked();
        // necessary since legal() only checks for sliders after a piece move
        if (checked and !chessl.isKingPiece(p)) {
            const checkers = self.frame.checkersBB & occ;
            if (checkers & (checkers - 1) != 0) {
                return false;
            }
            return (self.frame.checkersBB & toBB) != 0;
        }
        return true;
    }

    pub inline fn isStaleMateRepetition(p_self: *const boardState) bool {
        return p_self.frame.halfMoveClock >= 100 or p_self.moveHistory.checkRepetitions(p_self.frame.halfMoveClock);
    }
    pub inline fn isStaleMate(p_self: *const boardState) bool {
        return p_self.isStaleMateRepetition() or p_self.isInsufficientMaterial();
    }
};

pub const viriGame = struct {
    b: packedBoard align(1),
    bestMove: viriPackedMove align(1),
    pad: u32 align(1) = 0,
};
// ref https://github.com/cosmobobak/viriformat
pub const packedBoard = struct {
    occ: u64 align(1) = chessl.ONE,
    pieces: [16]u8 align(1) = @splat(0),
    enP_side: u8 = 0,

    halfMove: u8 = 0,
    fullMove: u16 align(1) = 0,
    score: i16 align(1) = 0,
    outcome: u8 = 0, // 0 b, 1 draw, 2 w
    pad: u8 = 0,
    pub fn init(state: *const boardState) packedBoard {
        var ret: packedBoard = .{ .occ = state.b.occupiedBB(), .halfMove = state.frame.halfMoveClock, .fullMove = state.b.turnCount };
        var offset: usize = 0;
        for (0..64) |sq| {
            const p = state.getPiece(@intCast(sq));
            if (p == .nEmptySquare) {
                continue;
            }
            const w = chessl.isPieceWhite(p);
            var _p: u8 = @intFromEnum(chessl.e_pieceTo_e_pieceType(p));

            if (chessl.isRookPiece(p)) {
                if (w) {
                    if (sq == 0 and state.frame.stat.canQueensideCastle(true) or (sq == 7 and state.frame.stat.canKingsideCastle(true))) {
                        _p = 6;
                    }
                } else {
                    if (sq == 56 and state.frame.stat.canQueensideCastle(false) or (sq == 63 and state.frame.stat.canKingsideCastle(false))) {
                        _p = 6;
                    }
                }
            }
            const val: u8 = _p | (@as(u8, chessl.whiteBoolToInt(!w)) << 3);

            if (offset % 2 == 0) {
                ret.pieces[offset >> 1] = val;
            } else {
                ret.pieces[offset >> 1] |= (val << 4);
            }
            offset += 1;
        }
        const w: u8 = chessl.whiteBoolToInt(!state.whiteToMove());
        const enP: u8 = if (state.frame.enPassantIdx == 0) 64 else @intCast(state.frame.enPassantIdx);
        ret.enP_side = (w << 7) | enP;
        return ret;
    }
};
pub const viriPackedMove = struct {
    move: viriMove align(1) = .{},
    score: i16 align(1) = 0,
};
pub const viriMove = struct {
    m_move: u16 align(1) = 0,
    // 6 bit from, 6 bit to, 2 bit promo piece, 2 bit enP capture=1, castling = 2, promotions 3
    pub fn init(move: IMove) viriMove {
        var to = move.getTo();
        const from = move.getFrom();
        var flag: u6 = 0;
        if (move.isPromotion()) {
            const p: u6 = @intCast((move.getFlag() - @intFromEnum(typel.e_moveFlags.KNIGHTPROMO)) % 4);
            flag |= p | @as(u6, 3 << 2);
        } else if (move.isCastle()) {
            flag |= @as(u6, 2 << 2);
            if (move.isKingSideCastle()) {
                to += 1;
            } else {
                to -= 2;
            }
        } else if (move.isEnpassant()) {
            flag |= @as(u6, 1 << 2);
        }
        return .{ .m_move = (@as(u16, @intCast(flag)) << 12) | (@as(u16, @intCast(to)) << 6) | (@as(u16, @intCast(from))) };
    }
};
pub const castleS = struct {
    kingFrom: e_square = .a1,
    kingTo: e_square = .a1,
    rookFrom: e_square = .a1,
    rookTo: e_square = .a1,
    pub inline fn init(white: bool, kingSide: bool) castleS {
        if (white) {
            if (kingSide) {
                return .{ .kingFrom = .e1, .kingTo = .g1, .rookFrom = .h1, .rookTo = .f1 };
            } else {
                return .{ .kingFrom = .e1, .kingTo = .c1, .rookFrom = .a1, .rookTo = .d1 };
            }
        } else {
            if (kingSide) {
                return .{ .kingFrom = .e8, .kingTo = .g8, .rookFrom = .h8, .rookTo = .f8 };
            } else {
                return .{ .kingFrom = .e8, .kingTo = .c8, .rookFrom = .a8, .rookTo = .d8 };
            }
        }
    }
};
pub const boardStack = struct {
    stack: [movel.MAX_MATCH_LENGTH]boardFrame = undefined,
    len: usize = 0,

    pub inline fn push(p_self: *boardStack, frame: boardFrame) void {
        if (comptime useDebug) {
            if (p_self.len == movel.MAX_MATCH_LENGTH) {
                @panic("Board stack is full, forgot to pop?");
            }
        }
        p_self.stack[p_self.len] = frame;
        p_self.len += 1;
    }
    pub inline fn pop(p_self: *boardStack) boardFrame {
        if (comptime useDebug) {
            if (p_self.len == 0) {
                @panic("Popping from empty boardframe, forgot to push?");
            }
        }
        p_self.len -= 1;
        return p_self.stack[p_self.len];
    }
};
