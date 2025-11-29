const std = @import("std");

const chess = @import("chess.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const build_options = @import("build_options");
const useDebug = build_options.useDebug;

const e_piece = chess.e_piece;
const e_color = chess.e_color;
const e_square = squarel.e_square;
const useHash = build_options.useHash;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

pub const Key = struct {
    code: u64 = 0,
    //?? index: u32 source hqperft
};

const ITEM_PER_BUCKET = 6;
pub const Hash_entry = struct {
    key: Key = .{},
    moveAmount: u64 = 0,
    evaluation: i32 = 0,
    exploredDeph: u8 = 0,
    valid: bool = false,
    age: u8 = 0,
    lock: bool = false,
};

pub fn buildEntryFromPerftResult(key: Key, depth: u8, moveAmount: u64) Hash_entry {
    return .{ .key = key, .exploredDeph = depth, .moveAmount = moveAmount, .valid = true };
}
pub const Hash_bucket = struct {
    entries: [ITEM_PER_BUCKET]Hash_entry,
    len: u8 = 0,
    hashTableOffset: u64,
    has_collision: bool = false,
    lock: bool = false,
    pub fn addEntry(p_self: *Hash_bucket, p_entry: *const Hash_entry) void {
        //p_self.acquireLock();
        p_self.entries[p_self.len] = p_entry.*;
        p_self.len = ((p_self.len + 1) % ITEM_PER_BUCKET);
        //if (comptime useDebug) {
        //    _ = checkHashCollision(p_self, p_entry);
        //}
        //p_self.releaseLock();
    }
    pub fn checkHashCollision(self: Hash_bucket, p_entry: *const Hash_entry) bool {
        for (0..self.len) |i| {
            if (self.entries[i].key.code != p_entry) {
                self.has_collision = true;
                return true;
            }
        }
        return false;
    }
    pub fn getEntryPerft(p_self: *Hash_bucket, hash: u64, depth: u8) Hash_entry {
        //p_self.acquireLock();
        for (0..p_self.len) |i| {
            const entry = p_self.entries[i];
            if (entry.key.code == hash and entry.exploredDeph == depth) {
                //p_self.releaseLock();
                return entry;
            }
        }
        //p_self.releaseLock();
        return .{ .valid = false };
    }
    fn acquireLock(p_self: *Hash_bucket) void {
        while (p_self.lock) {}
        p_self.lock = true;
    }
    fn releaseLock(p_self: *Hash_bucket) void {
        p_self.lock = false;
    }
};

pub const Hash_table = struct {
    entries: []Hash_bucket,
    nBits: u8,
    size: u64,
    n_insertion: u64 = 0,

    pub fn init(alloc: std.mem.Allocator, nBits: u8) !Hash_table {
        const total_size: u64 = chess.ONE << @intCast(nBits);
        std.debug.print("[PRE] Initializing hash table with a size of {d} buckets !\n", .{total_size});
        var ret: Hash_table = undefined;
        ret.nBits = nBits;
        ret.size = total_size;
        ret.entries = try alloc.alloc(Hash_bucket, total_size);

        return ret;
    }
    pub fn free(p_self: *Hash_table, alloc: std.mem.Allocator) void {
        alloc.free(p_self.entries);
    }
    pub inline fn getHashIndex(self: Hash_table, hash: u64) u64 {
        return hash >> @intCast(64 - self.nBits);
    }
    pub fn getBucketFromFullHashIndex(self: Hash_table, hash: u64) *Hash_bucket {
        const index = self.getHashIndex(hash);
        return &self.entries[index];
    }
    pub fn getBucketFromHashIndex(self: Hash_table, offset: u64) *Hash_bucket {
        return &self.entries[offset];
    }

    pub fn storeEntry(p_self: *Hash_table, p_entry: *const Hash_entry) bool {
        const index = p_entry.key.code;
        p_self.n_insertion += 1;
        var p_bucket = p_self.getBucketFromFullHashIndex(index);
        if (p_bucket.len == ITEM_PER_BUCKET) {
            _ = strategyEntryRemoval(p_bucket, p_entry);
        }
        //p_bucket.hashTableOffset = p_self.getHashIndex(p_entry.key.code);
        p_bucket.addEntry(p_entry);
        return true;
    }
};

pub fn strategyEntryRemoval(p_bucket: *Hash_bucket, p_entry: *const Hash_entry) bool {
    _ = p_bucket;
    _ = p_entry;
    @panic("bucket is full!");
}

pub fn getEntryFromPerft(key: Key, depth: u8) Hash_entry {
    const p_bucket: *Hash_bucket = hashTable.getBucketFromFullHashIndex(key.code);
    return p_bucket.getEntryPerft(key.code, depth);
}

pub const Zobrist_Keys = struct {
    pieceKeys: [12][64]Key = std.mem.zeroes([12][64]Key),
    turnKey: [chess.NUMBER_PLAYER]Key = std.mem.zeroes([chess.NUMBER_PLAYER]Key),
    // taken from hqperft
    playKey: Key = .{},
    castlingKeys: [16]Key = std.mem.zeroes([16]Key),
    enPassantKeys: [64]Key = std.mem.zeroes([64]Key),
    pub fn init(alloc: std.mem.Allocator) *Zobrist_Keys {
        var ret = alloc.create(Zobrist_Keys) catch unreachable;
        ret.pieceKeys = std.mem.zeroes([12][64]Key);
        @memset(&ret.turnKey, .{});
        @memset(&ret.castlingKeys, .{});
        @memset(&ret.enPassantKeys, .{});
        ret.playKey = .{};
        return ret;
    }
    pub fn free(p_self: *Zobrist_Keys, alloc: std.mem.Allocator) void {
        alloc.destroy(p_self);
    }
};

pub var zobristKeys: *Zobrist_Keys = undefined;
pub var hashTable: Hash_table = undefined;

pub fn _initHash(seed: u64, sizeHashTable: u8) void {
    var rngIntGenerator = std.Random.DefaultPrng.init(seed);
    zobristKeys = Zobrist_Keys.init(GLOBAL_ALLOC);

    const rng = rngIntGenerator.random();
    if (useHash) {
        std.debug.print("Building using hash logic!\n", .{});
        hashTable = Hash_table.init(GLOBAL_ALLOC, sizeHashTable) catch |err| {
            std.debug.print("[ERROR] _initHash: memory error during alloc {}\n", .{err});
            @panic("Mem error");
        };
    }
    initZobristKeys(rng);
    return;
}

pub fn initZobristKeys(rng: std.Random) void {
    for (0..12) |i| {
        for (0..64) |j| {
            zobristKeys.pieceKeys[i][j] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };
        }
    }

    zobristKeys.turnKey[0] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };
    zobristKeys.turnKey[1] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };

    for (0..16) |j| {
        zobristKeys.castlingKeys[j] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };
    }

    for (0..64) |j| {
        zobristKeys.enPassantKeys[j] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };
    }
    zobristKeys.playKey = zobristKeys.turnKey[0];
    updateKey(&zobristKeys.playKey, &zobristKeys.turnKey[1]);
}
pub fn fullComputeZobristKeys(p_board: *chess.Board_state) Key {
    // for better perfs look for incremental xor key update using the previous move

    var retKey = zobristKeys.turnKey[@intFromEnum(p_board.turn)];
    for (0..(chess.N_PIECES_TYPES) * 2) |i| {
        var bb = p_board.pieceBB[i];
        while (bb != chess.EMPTY) {
            const sq: u8 = @intCast(chess.bitscan(bb));
            bb &= bb - 1;
            retKey.code ^= zobristKeys.pieceKeys[i][sq].code;
        }
    }
    retKey.code ^= zobristKeys.castlingKeys[p_board.castling].code;
    retKey.code ^= zobristKeys.enPassantKeys[p_board.enPassantIdx].code;

    return retKey;
}

pub fn updateKey(keyDst: *Key, keySrc: *Key) void {
    keyDst.code ^= keySrc.code;
}

pub fn updateKeyOnMakeMove(p_board: *chess.Board_state, move: *const movel.IMove) void {
    // This function relies on the move not beeing already made (ie: all bitboard and arrPiece are "old");
    // most of this method has been grafted to the makeMove funcs as this branches are aleady computed during a move make.
    //  Thus this function double checks what is already checked.
    const toSq = move.getTo();
    const fromSq = move.getFrom();
    const piece = move.getFromPiece();
    const victim = move.getCapturePiece();
    var enPassantIdx: u8 = 0;

    var castlePiece: e_piece = .nWhiteRook;

    if (p_board.turn == .BLACK) {
        castlePiece = .nBlackRook;
    }

    //std.debug.print("[DEBUG] updateKeyOnMakeMove: Initial key: {x} re-calculated: {x} for move: {s}-{}-{}-{}\n", .{ p_board.key.code, fullComputeZobristKeys(p_board).code, move.getStr(), move.getFlag(), move.getFromPiece(), move.getCapturePiece() });

    if (victim != .nEmptySquare) {
        updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(victim)][toSq]);
    }
    if (chess.isKingPiece(piece)) {
        const kingTo: i8 = @intCast(toSq);
        const kingFrom: i8 = @intCast(fromSq);
        if (kingTo == (kingFrom + 2)) {
            // king side castle
            updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(castlePiece)][@intCast(kingTo - 1)]);
            updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(castlePiece)][@intCast(kingTo + 1)]);
        } else if (kingTo == (kingFrom - 2)) {
            // queen side castle
            updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(castlePiece)][@intCast(kingTo + 1)]);
            updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(castlePiece)][@intCast(kingTo - 2)]);
        }
    } else if (chess.isPawnPiece(piece)) {
        if (move.isPromotion()) {
            const promPiece = chess.flagPromotionToPiece(move.getFlag(), p_board.turn);

            updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(piece)][toSq]);
            updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(promPiece)][toSq]);
        } else if (move.isDoublePush()) {
            enPassantIdx = (fromSq + toSq) / 2;
        } else if (move.isEnpassant()) {
            const victimSq: e_square = chess.getSqFromCoord(chess.getSqIdxRank(fromSq), chess.getSqIdxFile(toSq));
            updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(victim)][@intFromEnum(victimSq)]);
            updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(victim)][toSq]);
            //std.debug.print("[DEBUG] updateKeyOnMakeMove: updating on en passant move victim: {}, victimSq: {}, toSq: {d}\n", .{ victim, victimSq, toSq });
        }
    }

    //std.debug.print("[DEBUG] updateKeyOnMakeMove: old: {d}, old-c: {d}, new: {d}\n", .{ p_board.enPassantIdx, enP, enPassantIdx });

    // flag type of keys

    updateKey(&p_board.key, &zobristKeys.playKey);
    updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(piece)][fromSq]);
    updateKey(&p_board.key, &zobristKeys.pieceKeys[@intFromEnum(piece)][toSq]);

    updateKey(&p_board.key, &zobristKeys.castlingKeys[p_board.castling]);
    updateKey(&p_board.key, &zobristKeys.castlingKeys[p_board.castling & chess.MASK_CASTLING[@intCast(toSq)] & chess.MASK_CASTLING[@intCast(fromSq)]]);

    updateKey(&p_board.key, &zobristKeys.enPassantKeys[p_board.enPassantIdx]);
    updateKey(&p_board.key, &zobristKeys.enPassantKeys[enPassantIdx]);

    //updateKey(&p_board.key, &zobristKeys.turnKey[@intFromEnum(nextTurn)]);

    //std.debug.print("[DEBUG] updateKeyOnMakeMove: end key: {x} \n", .{p_board.key.code});
}

pub fn convertEPIdxBoardToZobrist(enPassantIdx: u8) u8 {
    if (enPassantIdx == 0) {
        return chess.INVALID_ENPASSANT_FILE;
    }
    return chess.getSqIdxFile(enPassantIdx);
}

//pub fn reconstructionTest(p_state: *chess.Board_state) void {
//    const deltaKey = p_state.key;
//    var board_2 = chess.getBoardFromFen(chess.DEFAULT_FEN, GLOBAL_ALLOC);
//    for (0..p_state.move_history.len) |i| {
//        const move = p_state.move_history.moves[i];
//        updateKeyOnMakeMove(&board_2, &move);
//        _ = board_2.makeMoveUpdate(move);
//    }
//    std.debug.print("[DEBUG] reconstructionTest: original: {x}, reconstructed: {x}\n", .{ deltaKey.code, board_2.key.code });
//    //if (deltaKey.code != board_2.key.code) {
//    //    chess.print_boardstate(p_state);
//    //    chess.print_boardstate(&board_2);
//    //    @panic("???");
//    //}
//}
