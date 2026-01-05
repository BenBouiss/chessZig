const std = @import("std");

const chess = @import("chess.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const configl = @import("config.zig");
const heuristicl = @import("heuristic.zig");

const build_options = @import("build_options");
const useDebug = build_options.useDebug;

const e_piece = chess.e_piece;
const e_square = squarel.e_square;
const useHash = build_options.useHash;
const scoreType = heuristicl.scoreType;

pub const Key = struct {
    code: u64 = 0,
};

// note the gain in space is not visible in the debug build
const entryVal = union { moveAmount: u64, evaluation: scoreType };

pub const Hash_entry = struct {
    key: Key = .{},

    val: entryVal = undefined,
    //moveAmount: u64 = 0,
    //evaluation: scoreType = 0,

    exploredDeph: u8 = 0,
    age: u8 = 0,

    valid: bool = false,
    lock: bool = false,
    pub inline fn moveA(self: Hash_entry) u64 {
        return self.val.moveAmount;
    }

    pub inline fn eval(self: Hash_entry) scoreType {
        return self.val.evaluation;
    }
};

pub fn buildEntryFromPerftResult(key: Key, depth: u8, moveAmount: u64) Hash_entry {
    //return .{ .key = key, .exploredDeph = depth, .moveAmount = moveAmount, .valid = true };
    return .{ .key = key, .exploredDeph = depth, .val = .{ .moveAmount = moveAmount }, .valid = true };
}
pub fn buildEntryFromMatchResult(key: Key, depth: u8, eval: scoreType) Hash_entry {
    //return .{ .key = key, .exploredDeph = depth, .valid = true, .evaluation = eval };
    return .{ .key = key, .exploredDeph = depth, .val = .{ .evaluation = eval }, .valid = true };
}
pub const Hash_bucket = struct {
    entries: [configl.ITEM_PER_BUCKET]Hash_entry,
    //TODO find a way to put entries outside of this struct as the following 2 bytes are now worth the pointer to entries in mem 8 bytes
    len: u8 = 0,
    lock: bool = false,
    //hashTableOffset: u64,
    //has_collision: bool = false,
    pub fn printSize(p_self: *Hash_bucket) void {
        std.debug.print("[DEBUG] printSize: hash bucket = {d} bytes\n", .{@sizeOf(Hash_bucket)});
        std.debug.print("[DEBUG] printSize: entries size is {d} bytes\n", .{@sizeOf(Hash_entry)});
        std.debug.print("[DEBUG] printSize: entries val size is {d} bytes\n", .{@sizeOf(entryVal)});
        _ = p_self;
    }
    pub fn addEntry(p_self: *Hash_bucket, p_entry: *const Hash_entry) void {
        p_self.entries[p_self.len] = p_entry.*;
        p_self.len = ((p_self.len + 1) % configl.ITEM_PER_BUCKET);
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
    pub fn getEntryMatch(p_self: *Hash_bucket, hash: u64, depth: u8) Hash_entry {
        for (0..p_self.len) |i| {
            const entry = p_self.entries[i];
            if (entry.key.code == hash and entry.exploredDeph >= depth) {
                return entry;
            }
        }
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
    MBsize: u32 = 0,
    size: u64 = 0,
    n_insertion: u64 = 0,
    initialized: bool = false,

    pub fn init(alloc: std.mem.Allocator, MBsize: u32) !Hash_table {
        var total_size: u64 = @intCast(MBsize * 1000000);
        total_size = @divFloor(total_size, @sizeOf(Hash_bucket));
        var ret: Hash_table = undefined;
        ret.MBsize = MBsize;
        ret.size = total_size;
        ret.n_insertion = 0;

        ret.entries = (try alloc.alloc(Hash_bucket, total_size));

        for (0..total_size) |i| {
            ret.entries[i].lock = false;
            ret.entries[i].len = 0;
        }
        ret.initialized = true;

        std.debug.print("[PRE] Initializing hash table with a size of {d} buckets !\n", .{total_size});
        ret.entries[0].printSize();
        return ret;
    }
    pub fn free(p_self: *Hash_table, alloc: std.mem.Allocator) void {
        std.debug.print("[FREE] Freeing the entries in the hashtable \n", .{});
        if (p_self.initialized) {
            alloc.free(p_self.entries);
            p_self.initialized = false;
        }
    }
    pub inline fn getHashIndex(self: Hash_table, hash: u64) u64 {
        //return hash >> @intCast(64 - self.nBits);
        return hash % self.entries.len;
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
        if (p_bucket.len == configl.ITEM_PER_BUCKET) {
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
    @panic("bucket is full! :)");
}

pub fn getEntryFromPerft(key: Key, depth: u8) Hash_entry {
    const p_bucket: *Hash_bucket = hashTable.getBucketFromFullHashIndex(key.code);
    return p_bucket.getEntryPerft(key.code, depth);
}
pub fn getEntryFromMatch(key: Key, depth: u8) Hash_entry {
    const p_bucket: *Hash_bucket = hashTable.getBucketFromFullHashIndex(key.code);
    return p_bucket.getEntryMatch(key.code, depth);
}

pub const Zobrist_Keys = struct {
    pieceKeys: [12][64]Key = std.mem.zeroes([12][64]Key),
    turnKey: [chess.NUMBER_PLAYER]Key = std.mem.zeroes([chess.NUMBER_PLAYER]Key),
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
pub var hashTable: Hash_table = .{ .entries = undefined };

pub fn _initZobrist(alloc: std.mem.Allocator, seed: u64) void {
    var rngIntGenerator = std.Random.DefaultPrng.init(seed);
    zobristKeys = Zobrist_Keys.init(alloc);
    const rng = rngIntGenerator.random();
    initZobristKeys(rng);
}
pub fn isHashTable_init() bool {
    return hashTable.initialized;
}
pub fn _initOrReallocHashTable(alloc: std.mem.Allocator, sizeHashTable: u32) void {
    // size in MB

    if (hashTable.MBsize == sizeHashTable and hashTable.initialized) {
        return;
    }

    std.debug.print("[DEBUG] _initOrReallocHashTable: Building using hash logic!\n", .{});
    if (hashTable.initialized) {
        hashTable.free(alloc);
    }
    hashTable = Hash_table.init(alloc, sizeHashTable) catch |err| {
        std.debug.print("[ERROR] _initHash: memory error during alloc {}\n", .{err});
        @panic("Mem error");
    };
}

pub fn _initHash(alloc: std.mem.Allocator, seed: u64, bitsHashTable: u8) void {
    _initZobrist(alloc, seed);
    _ = bitsHashTable;
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

    var retKey = zobristKeys.turnKey[@intFromBool(p_board.whiteToMove())];
    for (0..(chess.N_PIECES_TYPES) * 2) |i| {
        var bb = p_board.pieceBB[i];
        while (bb != chess.EMPTY) {
            const sq: u8 = chess.bitscan(bb);
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

pub fn convertEPIdxBoardToZobrist(enPassantIdx: u8) u8 {
    if (enPassantIdx == 0) {
        return chess.INVALID_ENPASSANT_FILE;
    }
    return chess.getSqIdxFile(enPassantIdx);
}
