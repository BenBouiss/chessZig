const std = @import("std");
const build_options = @import("build_options");

const boardStatusl = @import("board_status.zig");
const chessl = @import("chess.zig");
const movel = @import("move.zig");
const heuristicl = @import("heuristic.zig");
const hashl = @import("hashTable.zig");
const typel = @import("type.zig");
const squarel = @import("square.zig");

const e_piece = typel.e_piece;
const e_color = typel.e_color;
const e_square = typel.e_square;

const IMove = movel.IMove;
const bitboard = typel.bitboard;

const useStaged = build_options.useStaged;
const useDebug = build_options.useDebug;

pub const board = struct {
    pieceBB: [chessl.N_PIECES]bitboard = std.mem.zeroes([chessl.N_PIECES]bitboard),
    pieceArray: [chessl.N_SQUARES]chessl.e_piece = std.mem.zeroes([chessl.N_SQUARES]chessl.e_piece),
    c_occupiedBB: [2]bitboard = std.mem.zeroes([2]bitboard),
    pieceCount: [chessl.N_PIECES]i8 = std.mem.zeroes([chessl.N_PIECES]i8),
    wKingSq: e_square = .a1,
    bKingSq: e_square = .a1,
    turnCount: u16 = 0,
    _whiteToMove: bool = false,

    info: *boardFrame = undefined,

    pub fn init() board {
        var ret: board = .{};
        @memset(&ret.pieceArray, e_piece.nEmptySquare);
        return ret;
    }
    pub inline fn toMove(self: board) e_color {
        return @enumFromInt(@intFromBool(self.info.stat.whiteToMove()));
    }
    pub inline fn iToMove(self: board) u1 {
        return @intFromEnum(self.toMove());
    }
    pub inline fn occupiedBB(self: board) bitboard {
        return self.c_occupiedBB[0] | self.c_occupiedBB[1];
    }

    pub inline fn placePiece(self: *board, piece: e_piece, sq: u8) void {
        const c = pieceToColor(piece);
        if (c == .WHITE) {
            self._placePiece(piece, sq, true);
        } else {
            self._placePiece(piece, sq, false);
        }
    }
    pub inline fn _placePiece(self: *board, piece: e_piece, sq: u8, comptime white: bool) void {
        const bb = chessl.xToBitboard(sq);
        self.c_occupiedBB[@intFromBool(white)] ^= bb;
        self.pieceBB[@intFromEnum(piece)] ^= bb;
        self.pieceArray[sq] = piece;
        self.pieceCount[@intFromEnum(piece)] += 1;
    }
    pub inline fn removePiece(self: *board, sq: u8) void {
        const piece = self.getPiece(sq);
        const c = pieceToColor(piece);
        if (c == .WHITE) {
            return self._removePiece(piece, sq, true);
        }
        return self._removePiece(piece, sq, false);
    }

    pub inline fn _removePiece(self: *board, piece: e_piece, sq: u8, comptime white: bool) void {
        const bb = chessl.xToBitboard(sq);
        self.c_occupiedBB[@intFromBool(white)] ^= bb;
        self.pieceBB[@intFromEnum(piece)] ^= bb;
        self.pieceCount[@intFromEnum(piece)] -= 1;
        self.pieceArray[sq] = .nEmptySquare;
    }
    pub inline fn movePiece(self: *board, from: u8, to: u8) void {
        const piece = self.getPiece(from);
        const c = pieceToColor(piece);
        if (c == .WHITE) {
            return self._movePiece(piece, from, to, true);
        }
        return self._movePiece(piece, from, to, false);
    }
    pub inline fn _movePiece(self: *board, piece: e_piece, from: u8, to: u8, comptime white: bool) void {
        const moveBB = chessl.xToBitboard(from) | chessl.xToBitboard(to);
        self.c_occupiedBB[@intFromBool(white)] ^= moveBB;
        self.pieceBB[@intFromEnum(piece)] ^= moveBB;
        self.pieceArray[from] = .nEmptySquare;
        self.pieceArray[to] = piece;
    }

    pub inline fn _movePieceBis(self: *board, pieceFrom: e_piece, from: u8, pieceTo: e_piece, to: u8, comptime white: bool) void {
        const fromBB = chessl.xToBitboard(from);
        const toBB = chessl.xToBitboard(to);
        self.c_occupiedBB[@intFromBool(white)] ^= (fromBB | toBB);
        self.pieceBB[@intFromEnum(pieceFrom)] ^= fromBB;
        self.pieceBB[@intFromEnum(pieceTo)] ^= toBB;

        self.pieceCount[@intFromEnum(pieceFrom)] -= 1;
        self.pieceCount[@intFromEnum(pieceTo)] += 1;

        self.pieceArray[from] = .nEmptySquare;
        self.pieceArray[to] = pieceTo;
    }
    pub inline fn getPiece(self: board, sq: u8) e_piece {
        return self.pieceArray[sq];
    }
    pub inline fn getPieceBB(self: board, piece: e_piece) e_piece {
        return self.pieceArray[@intFromEnum(piece)];
    }
    pub inline fn getPieceCount(self: board, piece: e_piece) e_piece {
        return self.pieceCount[@intFromEnum(piece)];
    }
    pub inline fn getKingSq(self: board, white: bool) e_square {
        if (white) {
            return self.wKingSq;
        }
        return self.bKingSq;
    }

    pub inline fn getKingBB(self: board, white: bool) bitboard {
        return chessl.sqToBitboard(self.getKingSq(white));
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

    pub fn printCount(self: board) void {
        std.debug.print("{any}\n", .{self.pieceCount});
    }
};
pub inline fn pieceToColor(piece: e_piece) e_color {
    if (@intFromEnum(piece) < chessl.N_PIECES_TYPES) {
        return .WHITE;
    }
    return .BLACK;
}
pub const moveStore = struct {
    lastMove: IMove = .{},
};

pub const boardFrame = struct {
    pinnedBB: u64 = 0,
    checkersBB: u64 = 0,
    key: hashl.Key = .{},
    phase: usize = 0,
    lastMove: IMove = .{},
    victim: e_piece = .nEmptySquare,
    enPassantIdx: u8 = 0,
    halfMoveClock: u8 = 0,
    stat: boardStatusl.status = .{},
    psqtEval: heuristicl.scoreType = 0,
    pub inline fn copy(state: *const boardState) boardFrame {
        return state.frame;
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

pub const boardState = struct {
    b: board = .{},
    frame: boardFrame = .{},
    moveHistory: movel.matchMoveContainer = .{},

    pub fn init() boardState {
        const ret: boardState = .{ .b = .init() };

        return ret;
    }
    pub fn free(p_self: *boardState, alloc: std.mem.Allocator) void {
        _ = alloc;
        _ = p_self;
    }
    pub inline fn copy(p_self: *const boardState) boardState {
        return p_self.*;
    }
    pub inline fn whiteToMove(self: *const boardState) bool {
        return self.b._whiteToMove;
        //return self.frame.stat.whiteToMove();
    }
    pub inline fn makeFrame(self: *const boardState) boardFrame {
        return self.frame;
    }

    pub fn duplicateNTimes(self: boardState, alloc: std.mem.Allocator, n: usize) !chessl.Board_stateContainer {
        var ret: []boardState = try alloc.alloc(boardState, n);
        for (0..n) |i| {
            ret[i] = self;
            if (comptime useDebug) {
                chessl.sanityCheckBoardState(&ret[i]);
            }
        }
        return .{ .array = ret, .len = ret.len };
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

        p_self.b.pieceBB[@intFromEnum(piece)] |= one_mask;
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
        const toBB = chessl.xToBitboard(toSq);
        const fromSq: u8 = move.getFrom();
        const fromBB = chessl.xToBitboard(fromSq);

        var piece = p_self.getPiece(toSq);

        p_self.b.pieceBB[@intFromEnum(piece)] ^= toBB;
        if (move.isPromotion()) {
            // this is the promotion piece
            p_self.b.pieceCount[@intFromEnum(piece)] -= 1;
            // fromPiece is the pawn
            if (comptime white) {
                piece = e_piece.nWhitePawn;
            } else {
                piece = e_piece.nBlackPawn;
            }
            p_self.b.pieceCount[@intFromEnum(piece)] += 1;
        }
        p_self.b.pieceBB[@intFromEnum(piece)] ^= fromBB;
        p_self.b.c_occupiedBB[@intFromBool(white)] ^= (fromBB | toBB);
        p_self.b.pieceArray[fromSq] = piece;

        p_self.b.pieceBB[@intFromEnum(victim)] ^= toBB;
        p_self.b.c_occupiedBB[@intFromBool(!white)] ^= toBB;

        p_self.b.pieceArray[toSq] = victim;
        p_self.b.pieceCount[@intFromEnum(victim)] += 1;

        if (move.isEnpassant()) {
            const victimSq: e_square = chessl.enPassantVictimSq(fromSq, toSq);
            const victimBB: u64 = chessl.sqToBitboard(victimSq);
            const bisBB = victimBB | toBB;
            p_self.b.pieceArray[toSq] = .nEmptySquare;
            p_self.b.pieceArray[@intFromEnum(victimSq)] = victim;
            p_self.b.pieceBB[@intFromEnum(victim)] ^= bisBB;
            p_self.b.c_occupiedBB[@intFromBool(!white)] ^= bisBB;
        } else if (chessl.isKingPiece(piece)) {
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

        var piece = p_self.getPiece(toSq);

        p_self.b.pieceBB[@intFromEnum(piece)] ^= toBB;
        if (move.isPromotion()) {
            // this is the promotion piece
            p_self.b.pieceCount[@intFromEnum(piece)] -= 1;
            // fromPiece is the pawn
            piece = if (comptime white) (.nWhitePawn) else (.nBlackPawn);
            p_self.b.pieceCount[@intFromEnum(piece)] += 1;
        }
        p_self.b.pieceBB[@intFromEnum(piece)] ^= fromBB;
        p_self.b.c_occupiedBB[@intFromBool(white)] ^= (fromBB | toBB);
        p_self.b.pieceArray[toSq] = .nEmptySquare;
        p_self.b.pieceArray[fromSq] = piece;

        if (chessl.isKingPiece(piece)) {
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
                p_self.b.pieceBB[@intFromEnum(r)] ^= mask;
                p_self.b.c_occupiedBB[@intFromBool(white)] ^= (mask);
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
        hashl.updateKey(&p_self.frame.key, hashl.zobristKeys.playKey);
        hashl.updateKey(&p_self.frame.key, hashl.zobristKeys.enPassantKeys[p_self.frame.enPassantIdx]);

        p_self.frame.enPassantIdx = 0;
        p_self.frame.halfMoveClock = 0;

        hashl.updateKey(&p_self.frame.key, hashl.zobristKeys.enPassantKeys[0]);

        if (comptime useStaged) {
            chessl.onMoveStaged(p_self, !white);
        }
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
        if (move.isCapture()) {
            p_self.makeMoveCapture_cst(move, white, updatePSQT);
        } else {
            p_self.makeMoveQuiet_cst(move, white, updatePSQT);
        }
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
        var toPiece = p_self.b.getPiece(from);
        var isPawn: bool = false;
        if (comptime t == .EP) {
            const victimSq: e_square = chessl.enPassantVictimSq(from, to);
            const victim: e_piece = if (comptime white) .nBlackPawn else .nWhitePawn;
            p_self.b._removePiece(victim, @intFromEnum(victimSq), !white);
            p_self.frame.victim = victim;
        } else if (isCapture and comptime t != .CASTLE) {
            const victim = p_self.b.getPiece(to);
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
            p_self.b.pieceBB[@intFromEnum(r)] ^= mask;
            p_self.b.c_occupiedBB[@intFromBool(white)] ^= mask;
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
        if (isCapture or t == .PROMOTION or isPawn) {
            p_self.frame.halfMoveClock = 0;
        } else {
            p_self.frame.halfMoveClock += 1;
        }

        if (isCapture) {
            p_self.frame.key.code = chessl.updateKeyOnMove(white, move, comptime t == .PROMOTION, comptime t == .CASTLE, true, toPiece, &p_self.frame, prevCastle, prevEp);
            if (comptime updatePSQT) {
                p_self.frame.psqtEval += heuristicl.updatePSQTOnMove(white, true, move, comptime t == .PROMOTION, comptime t == .CASTLE, toPiece, p_self.getPhase(), &p_self.frame);
            } else {
                p_self.frame.psqtEval += heuristicl.updatePSQTOnMove(white, false, move, comptime t == .PROMOTION, comptime t == .CASTLE, toPiece, p_self.getPhase(), &p_self.frame);
            }
            p_self.frame.key.code = chessl.updateKeyOnMove(white, move, comptime t == .PROMOTION, comptime t == .CASTLE, false, toPiece, &p_self.frame, prevCastle, prevEp);
        }

        _ = p_self.moveHistory.append(move, p_self.frame.key, isPawn);

        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        if (comptime useStaged) {
            chessl.onMoveStaged(p_self, !white);
        }
    }
    pub fn makeMoveCapture_cst(p_self: *boardState, move: IMove, comptime white: bool, comptime updatePSQT: bool) void {
        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        const prevCastle: u8 = p_self.frame.stat.castlingKey();
        const prevEp: u8 = p_self.frame.enPassantIdx;

        p_self.frame.lastMove = move;
        const victim = p_self.getCapturePiece(move);
        p_self.frame.victim = victim;
        p_self.frame.enPassantIdx = 0;
        p_self.frame.halfMoveClock = 0;

        const to = move.getTo();
        const from = move.getFrom();
        const toBB = chessl.xToBitboard(to);
        const fromBB = chessl.xToBitboard(from);
        var toPiece = p_self.getFromPiece(move);
        var isPromo: bool = false;
        var isPawn: bool = false;
        if (chessl.isRookPiece(victim)) {
            p_self.frame.stat.onRookMove(toBB, !white);
        }

        p_self.frame.phase -= if (comptime white) (typel.phases_arr[@intFromEnum(victim) - chessl.N_PIECES_TYPES]) else typel.phases_arr[@intFromEnum(victim)];
        p_self.b.pieceCount[@intFromEnum(victim)] -= 1;

        p_self.b.pieceArray[from] = .nEmptySquare;
        p_self.b.pieceBB[@intFromEnum(toPiece)] ^= fromBB;
        p_self.b.c_occupiedBB[@intFromBool(white)] ^= (fromBB | toBB);
        if (chessl.isPawnPiece(toPiece)) {
            isPawn = true;
            if (move.isEnpassant()) {
                const epSq: e_square = chessl.enPassantVictimSq(from, to);
                p_self.b.pieceArray[@intFromEnum(epSq)] = e_piece.nEmptySquare;
                p_self.b.c_occupiedBB[@intFromBool(!white)] ^= chessl.sqToBitboard(epSq);
            } else {
                p_self.b.c_occupiedBB[@intFromBool(!white)] ^= toBB;
                if (move.isPromotion()) {
                    isPromo = true;
                    p_self.b.pieceCount[@intFromEnum(toPiece)] -= 1;
                    toPiece = chessl.flagPromotionToPiece(move.getFlag(), white);
                    p_self.b.pieceCount[@intFromEnum(toPiece)] += 1;
                    p_self.frame.phase += if (comptime white) (typel.phases_arr[@intFromEnum(toPiece)]) else typel.phases_arr[@intFromEnum(toPiece) - chessl.N_PIECES_TYPES];
                }
            }
        } else {
            p_self.b.c_occupiedBB[@intFromBool(!white)] ^= toBB;
            if (chessl.isRookPiece(toPiece)) {
                p_self.frame.stat.onRookMove(fromBB, white);
            } else if (chessl.isKingPiece(toPiece)) {
                if (comptime white) {
                    p_self.b.wKingSq = @enumFromInt(to);
                } else {
                    p_self.b.bKingSq = @enumFromInt(to);
                }
                p_self.frame.stat.onKingMove(white);
            }
        }
        p_self.b.pieceArray[to] = toPiece;
        p_self.b.pieceBB[@intFromEnum(toPiece)] ^= toBB;
        p_self.b.pieceBB[@intFromEnum(victim)] &= p_self.b.c_occupiedBB[@intFromBool(!white)];

        p_self.frame.key.code = chessl.updateKeyOnMove(white, move, isPromo, false, true, toPiece, &p_self.frame, prevCastle, prevEp);
        if (comptime updatePSQT) {
            p_self.frame.psqtEval += heuristicl.updatePSQTOnMove(white, true, move, isPromo, false, toPiece, p_self.getPhase(), &p_self.frame);
        }

        _ = p_self.moveHistory.append(move, p_self.frame.key, isPawn);
        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        if (comptime useStaged) {
            chessl.onMoveStaged(p_self, !white);
        }
    }
    pub fn makeMoveQuiet_cst(p_self: *boardState, move: IMove, comptime white: bool, comptime updatePSQT: bool) void {
        // test to reduce the makeMove load
        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        const prevCastle: u8 = p_self.frame.stat.castlingKey();
        const prevEp: u8 = p_self.frame.enPassantIdx;

        p_self.frame.lastMove = move;
        p_self.frame.victim = .nEmptySquare;
        p_self.frame.enPassantIdx = 0;

        const to = move.getTo();
        const from = move.getFrom();
        const toBB = chessl.xToBitboard(to);
        const fromBB = chessl.xToBitboard(from);
        var toPiece = p_self.getPiece(from);
        var isCastle: bool = false;
        var isPromo: bool = false;

        p_self.b.pieceArray[from] = .nEmptySquare;
        p_self.b.pieceBB[@intFromEnum(toPiece)] ^= fromBB;
        p_self.b.c_occupiedBB[@intFromBool(white)] ^= (fromBB | toBB);

        var isPawn: bool = false;
        if (chessl.isPawnPiece(toPiece)) {
            isPawn = true;
            p_self.frame.halfMoveClock = 0;
            if (move.isPromotion()) {
                isPromo = true;
                p_self.b.pieceCount[@intFromEnum(toPiece)] -= 1;
                toPiece = chessl.flagPromotionToPiece(move.getFlag(), white);
                p_self.b.pieceCount[@intFromEnum(toPiece)] += 1;
                p_self.frame.phase += if (comptime white) (typel.phases_arr[@intFromEnum(toPiece)]) else typel.phases_arr[@intFromEnum(toPiece) - chessl.N_PIECES_TYPES];
            } else if (move.isDoublePush()) {
                // middle between from and to
                p_self.frame.enPassantIdx = if (comptime white) (from + 8) else (from - 8);
            }
        } else {
            p_self.frame.halfMoveClock += 1;
            if (chessl.isKingPiece(toPiece)) {
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
                    p_self.b.pieceBB[@intFromEnum(r)] ^= mask;
                    p_self.b.c_occupiedBB[@intFromBool(white)] ^= mask;
                }
                p_self.frame.stat.onKingMove(white);
            } else if (chessl.isRookPiece(toPiece)) {
                p_self.frame.stat.onRookMove(fromBB, white);
            }
        }

        p_self.b.pieceArray[to] = toPiece;
        p_self.b.pieceBB[@intFromEnum(toPiece)] ^= toBB;

        p_self.frame.key.code = chessl.updateKeyOnMove(white, move, isPromo, isCastle, false, toPiece, &p_self.frame, prevCastle, prevEp);
        if (comptime updatePSQT) {
            p_self.frame.psqtEval += heuristicl.updatePSQTOnMove(white, false, move, isPromo, isCastle, toPiece, p_self.getPhase(), &p_self.frame);
        }

        _ = p_self.moveHistory.append(move, p_self.frame.key, isPawn);

        if (comptime useDebug) {
            chessl.sanityCheckBoardState(p_self);
        }
        if (comptime useStaged) {
            chessl.onMoveStaged(p_self, !white);
        }
    }

    pub inline fn getLastMove(self: boardState) IMove {
        return self.frame.lastMove;
    }

    pub inline fn getFromPiece(self: *const boardState, move: IMove) e_piece {
        return self.getPiece(move.getFrom());
    }
    pub inline fn getCapturePiece(self: *const boardState, move: IMove) e_piece {
        if (move.isEnpassant()) {
            return chessl.pawnFromColor(!chessl.getColorFromPiece(self.getFromPiece(move)));
        }
        return self.getPiece(move.getTo());
    }
    pub inline fn getPhase(self: *const boardState) usize {
        var ret: heuristicl.scoreType = @intCast(typel.totalPhase);
        ret -= @intCast(self.frame.phase);
        return @intCast(@max(0, ret));
        //return @intCast(@max(0, heuristicl.computePhase(self)));
    }
    pub fn isEndGame(self: *const boardState) bool {
        const nWhiteP = self.getPieceCount(.nWhiteBishop) + self.getPieceCount(.nWhiteKnight) + self.getPieceCount(.nWhiteRook) + self.getPieceCount(.nWhiteQueen);
        const nBlackP = self.getPieceCount(.nBlackBishop) + self.getPieceCount(.nBlackKnight) + self.getPieceCount(.nBlackRook) + self.getPieceCount(.nBlackQueen);
        return (nWhiteP < 3) and (nBlackP < 3);
    }

    pub inline fn getKingBB(self: boardState, white: bool) u64 {
        if (white) {
            return self.getPieceBB(.nWhiteKing);
        }
        return self.getPieceBB(.nBlackKing);
    }
    pub inline fn getKingSq(self: *const boardState, white: bool) e_square {
        if (white) {
            return self.b.wKingSq;
        }
        return self.b.bKingSq;
    }
    pub fn isCastleLegalPreMove(p_self: *const boardState, white: bool, move: IMove, all_attacks: u64) bool {
        const kingBB = p_self.getKingBB(white);
        if (move.isKingSideCastle()) {
            if ((all_attacks & (kingBB | (kingBB << 1) | (kingBB << 2))) != 0) {
                return false;
            }
        } else {
            if ((all_attacks & (kingBB | (kingBB >> 1) | (kingBB >> 2))) != 0) {
                return false;
            }
        }
        return true;
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
            return self.frame.stat.canKingsideCastle(true) and chessl.canMove(.e1, .h1, self.b.occupiedBB()) and ((attackedSquares & chessl.inBetween(.e1, .h1)) == chessl.EMPTY);
        }
        return self.frame.stat.canKingsideCastle(false) and chessl.canMove(.e8, .h8, self.b.occupiedBB()) and ((attackedSquares & chessl.inBetween(.e8, .h8)) == chessl.EMPTY);
    }
    pub inline fn canQueenSideCastleAtt(self: boardState, white: bool, attackedSquares: u64) bool {
        if (white) {
            return self.frame.stat.canQueensideCastle(true) and chessl.canMove(.e1, .a1, self.b.occupiedBB()) and ((attackedSquares & chessl.inBetween(.e1, .b1)) == chessl.EMPTY);
        }
        return self.frame.stat.canQueensideCastle(false) and chessl.canMove(.e8, .a8, self.b.occupiedBB()) and ((attackedSquares & chessl.inBetween(.e8, .b8)) == chessl.EMPTY);
    }

    pub inline fn getPieceCount(self: boardState, piece: e_piece) i8 {
        return self.b.pieceCount[@intFromEnum(piece)];
    }
    pub inline fn getPieceBB(self: boardState, piece: e_piece) u64 {
        return self.b.pieceBB[@intFromEnum(piece)];
    }
    pub inline fn getTotalPieceCount(self: *const boardState, white: bool) i8 {
        // putting inline in front of this causes the razoring in zws to segfault even if the razoring is not used ???
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
    pub fn getNthBestPiece(self: *const boardState, colorOffset: usize, n: u8) e_piece {
        var _n: i32 = @intCast(n);
        for (1..chessl.N_PIECES_TYPES) |idx| {
            // 1: skips the king
            const pieceIdx = colorOffset + (chessl.N_PIECES_TYPES - 1) - idx;
            const count = self.b.pieceCount[pieceIdx];
            _n -= count;
            if (_n <= 0) {
                return @enumFromInt(pieceIdx);
            }
        }
        // returns the king if no piece found
        return @enumFromInt(colorOffset + chessl.N_PIECES_TYPES - 1);
    }
    pub inline fn firstPiece(self: *const boardState, white: bool) e_piece {
        if (white) {
            return self.getNthBestPiece(0, 1);
        } else {
            return self.getNthBestPiece(chessl.N_PIECES_TYPES, 1);
        }
    }
    pub inline fn secondPiece(self: *const boardState, white: bool) e_piece {
        if (white) {
            return self.getNthBestPiece(0, 2);
        } else {
            return self.getNthBestPiece(chessl.N_PIECES_TYPES, 2);
        }
    }
    pub inline fn getSidePieceCount(self: boardState, color: e_color) u8 {
        return chessl.popcount(self.b.c_occupiedBB[@intFromEnum(color)]);
    }

    pub fn isLegal(p_self: *const boardState, white: bool) bool {
        // faster than previous _islegal going from ~100-150k nodes/s to 250-300k nodes per sec
        const king_attacks = chessl.getAllAttackerFromKing(p_self, white);
        return king_attacks == 0;
    }
    pub inline fn isChecked(p_self: *const boardState) bool {
        if (comptime useStaged) {
            return p_self.frame.checkersBB != 0;
        }
        return p_self.isLegal(p_self.whiteToMove());
    }
    pub fn isInsufficientMaterial(p_self: *const boardState) bool {
        return p_self.isInsufficientMaterialSide(false) and p_self.isInsufficientMaterialSide(true);
    }
    pub fn isInsufficientMaterialSide(p_self: *const boardState, white: bool) bool {
        var color_offset: usize = 0;
        if (!white) {
            color_offset = chessl.N_PIECES_TYPES;
        }
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

    pub fn isLegalFast(p_self: *const boardState, all_attack: u64, move: IMove, p_kingSq: *const squarel.squareInfo, p_checks: *const squarel.checkContainer, diagPieceBB: u64, linePieceBB: u64) bool {
        const kingBB = chessl.sqToBitboard(p_kingSq.sq);
        const isAttacked: bool = (kingBB & all_attack) != 0;
        const to: e_square = @enumFromInt(move.getTo());
        const from: e_square = @enumFromInt(move.getFrom());
        if (from != p_kingSq.sq) {
            if (p_checks.isDoubleCheck()) {
                return false;
            }
            const pinnedBB = chessl.isPiecePinned(p_self.b.occupiedBB(), from, p_kingSq, diagPieceBB, linePieceBB);
            if (pinnedBB != chessl.EMPTY) {
                // piece is pinned path
                if (p_checks.isCheck() and (pinnedBB != p_checks.squares[0].getBB())) {
                    return false;
                }
                const capturedPinned = (chessl.bitscan(pinnedBB) == @intFromEnum(to));
                return ((pinnedBB == chessl.isPiecePinned(p_self.b.occupiedBB() ^ (chessl.ONE << @intCast(@intFromEnum(from))), to, p_kingSq, diagPieceBB, linePieceBB)) or capturedPinned);
            }

            if (!isAttacked) {
                return true;
            }
            //blocking or capturing as non king
            const last_pin = chessl.isPiecePinned(p_self.b.occupiedBB(), to, p_kingSq, diagPieceBB, linePieceBB);
            var _to = to;
            if (move.isEnpassant()) {
                _to = chessl.enPassantVictimSq(@intFromEnum(from), @intFromEnum(to));
            }

            return ((last_pin == p_checks.squares[0].getBB()) or (p_checks.squares[0].sq == _to));
        }
        const toKing = squarel.squareInfo.init(to);
        const pinInfo = (chessl.isPiecePinned(p_self.b.occupiedBB(), from, &toKing, diagPieceBB, linePieceBB));
        // either no pinning piece is found or the pinned piece can be captured
        const isNotPinned = (pinInfo == chessl.EMPTY) or ((pinInfo ^ toKing.getBB()) == chessl.EMPTY);
        const isToSecure = ((all_attack & toKing.getBB()) == 0);
        return (isNotPinned and isToSecure);
    }

    pub inline fn isFiftyMoveRepetition(self: *const boardState) bool {
        return self.frame.halfMoveClock >= 50;
    }
    pub inline fn isStaleThreeFold(self: *const boardState) bool {
        return self.moveHistory.checkRepetitions();
    }
    pub fn isStaleMateRepetition(p_self: *const boardState) bool {
        return p_self.isFiftyMoveRepetition() or p_self.isStaleThreeFold();
    }
};
pub fn isEndGame(self: board) bool {
    const nWhiteP = self.getPieceCount(.nWhiteBishop) + self.getPieceCount(.nWhiteKnight) + self.getPieceCount(.nWhiteRook) + self.getPieceCount(.nWhiteQueen);
    const nBlackP = self.getPieceCount(.nBlackBishop) + self.getPieceCount(.nBlackKnight) + self.getPieceCount(.nBlackRook) + self.getPieceCount(.nBlackQueen);
    return (nWhiteP < 3) and (nBlackP < 3);
}

pub fn get_fen(b: board) [chessl.MAX_FEN_LENGTH]u8 {
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
        const piece = b.getPiece(board_offset);
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
    //const endPiece = N_SQUARES - (1 + miscOffset);
    const endPiece = miscOffset;
    ret[endPiece] = ' ';
    if (b.toMove() == .WHITE) {
        ret[endPiece + 1] = 'w';
    } else {
        ret[endPiece + 1] = 'b';
    }
    ret[endPiece + 2] = ' ';
    var castleOffset: u8 = 0;
    if (b.info.stat.canKingsideCastle(true)) {
        ret[endPiece + 3 + castleOffset] = 'H';
        castleOffset += 1;
    }
    if (b.info.stat.canQueensideCastle(true)) {
        ret[endPiece + 3 + castleOffset] = 'A';
        castleOffset += 1;
    }
    if (b.info.stat.canKingsideCastle(false)) {
        ret[endPiece + 3 + castleOffset] = 'h';
        castleOffset += 1;
    }
    if (b.info.stat.canQueensideCastle(false)) {
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

    if (b.info.enPassantIdx == 0) {
        ret[endCastlOffset + 1] = '-';
        endEnPassantOffset = endCastlOffset + 1;
    } else {
        const sqStr = chessl.strFromLERF(@enumFromInt(b.info.enPassantIdx));
        ret[endCastlOffset + 1] = sqStr[0];
        ret[endCastlOffset + 2] = sqStr[1];
        endEnPassantOffset = endCastlOffset + 2;
    }
    ret[endEnPassantOffset + 1] = ' ';
    var buffer: [20]u8 = undefined;
    const halfMove = std.fmt.bufPrint(&buffer, "{}", .{b.info.halfMoveClock}) catch {
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
    const fullMoveClock = std.fmt.bufPrint(&buffer, "{}", .{b.turnCount}) catch {
        return ret;
    };
    for (fullMoveClock) |letter| {
        ret[endHalfMoveOffset + 1 + offset] = letter;
        offset += 1;
    }
    return ret;
}
