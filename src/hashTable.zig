const std = @import("std");

const chess = @import("chess.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");
const configl = @import("config.zig");
const heuristicl = @import("heuristic.zig");
const mainl = @import("main.zig");

const build_options = @import("build_options");
const useDebug = build_options.useDebug;

const e_piece = chess.e_piece;
const e_square = squarel.e_square;
const useHash = build_options.useHash;
const scoreType = heuristicl.scoreType;
const IMove = movel.IMove;
const TT_strat = configl.TT_strat;

pub const Key = struct {
    code: u64 = 0,
};

// note: the gain in space is not visible in the debug build
// will try to implement the chess programming version where way more stuff is stored
const entryComponents = union { moveAmount: u64, search: searchEntry };

// Types of nodes:
//  ALL: Upper bound: less than alpha
//  UPPER: or Exact Complete evaluation of a position done a depth 0 to be compared with alpha
//  LOWER: Lower bound: greater or equal than beta. Induced a beta cutoff to be compared with beta
//
pub const nodeType = enum { UPPER, ALL, LOWER };

pub const searchEntry = struct {
    evaluation: scoreType = 0,
    t: nodeType = .ALL,
    // bestMove also known as hash move (I think) is to be explored first
    bestMove: IMove = .{},
    // this is for the replacing strat, might be optionnal with alway replace
    //age: usize,
};

pub const Hash_entry = struct {
    key: Key = .{},
    val: entryComponents = undefined,
    exploredDepth: u8 = undefined,
    age: u8 = 0,

    valid: bool = false,
    pub inline fn moveA(self: *const Hash_entry) u64 {
        return self.val.moveAmount;
    }

    pub inline fn eval(self: *const Hash_entry) scoreType {
        return self.val.search.evaluation;
    }
    pub inline fn copy(self: *const Hash_entry) Hash_entry {
        return .{ .age = self.age, .val = self.val, .exploredDepth = self.exploredDepth, .key = self.key };
    }
};

pub fn buildEntryFromPerftResult(key: Key, depth: u8, moveAmount: u64) Hash_entry {
    return .{ .key = key, .exploredDepth = depth, .val = .{ .moveAmount = moveAmount }, .valid = true };
}
pub fn buildEntryFromMatchResult(key: Key, depth: u8, eval: scoreType) Hash_entry {
    return .{ .key = key, .exploredDepth = depth, .val = .{ .search = .{ .evaluation = eval } }, .valid = true };
}

pub fn buildEntryMatchExt(key: Key, depth: u8, eval: scoreType, nodeT: nodeType, bestMove: IMove) Hash_entry {
    return .{ .key = key, .exploredDepth = depth, .val = .{ .search = .{ .evaluation = eval, .t = nodeT, .bestMove = bestMove } }, .valid = true };
}
pub const Hash_bucket = struct {
    entries: [configl.ITEM_PER_BUCKET]Hash_entry = undefined,
    len: u8 = 0,
    pub fn print(p_self: *const Hash_bucket) void {
        std.debug.print("Bucket properties len = {d}, total len = {d}\n", .{ p_self.len, p_self.entries.len });
        for (0..p_self.len) |i| {
            const _e = p_self.entries[i];
            std.debug.print("item {d} code:{d}, valid:{}, depth:{d}, eval:{any}\n", .{ i, _e.key.code, _e.valid, _e.exploredDepth, _e.val });
        }
    }
    pub fn printSize(p_self: *Hash_bucket) void {
        std.debug.print("[DEBUG] printSize: hash bucket = {d} bytes\n", .{@sizeOf(Hash_bucket)});
        std.debug.print("[DEBUG] printSize: entries size is {d} bytes\n", .{@sizeOf(Hash_entry)});
        std.debug.print("[DEBUG] printSize: entries val size is {d} bytes\n", .{@sizeOf(entryComponents)});
        _ = p_self;
    }
    pub fn addEntry(p_self: *Hash_bucket, p_entry: *const Hash_entry, strategy: TT_strat) void {
        switch (strategy) {
            .ALWAYS_REPLACE => {
                p_self.addEntry_AR(p_entry);
            },
            .KEEP_DEEPER => {
                p_self.addEntry_deep(p_entry);
            },
        }
    }
    pub fn addEntry_deep(p_self: *Hash_bucket, p_entry: *const Hash_entry) void {
        var idxS: usize = 0;
        var sDepth: u8 = 255;
        // if a better entry exists for this hash key we exit
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const entry = p_self.entries[i];
            if (!entry.valid) {
                p_self.entries[i] = p_entry.*;
                p_self.len = @min(p_self.len + 1, p_self.entries.len);
                return;
            }
            if (entry.key.code == p_entry.key.code) {
                if (entry.exploredDepth > p_entry.exploredDepth) {
                    return;
                }
                p_self.entries[i] = p_entry.*;
                return;
            }

            if (entry.exploredDepth < sDepth) {
                idxS = i;
                sDepth = entry.exploredDepth;
            }
        }

        p_self.entries[idxS] = p_entry.*;
        //p_self.len = @min(p_self.len + 1, p_self.entries.len);
    }
    pub fn addEntry_AR(p_self: *Hash_bucket, p_entry: *const Hash_entry) void {
        p_self.entries[p_self.len] = p_entry.*;
        p_self.len = (p_self.len + 1) % configl.ITEM_PER_BUCKET;
    }
    pub fn getEntryPerft(p_self: *Hash_bucket, hash: u64, depth: u8) Hash_entry {
        for (0..p_self.len) |i| {
            const entry = p_self.entries[i];
            if (entry.key.code == hash and entry.exploredDepth == depth) {
                return entry;
            }
        }
        return .{ .valid = false };
    }
    pub fn getEntryMatch(p_self: *Hash_bucket, hash: u64, depth: u8) ?*Hash_entry {
        for (0..p_self.len) |i| {
            const entry = &p_self.entries[i];
            // note: now that only one instance of the key gets stored, the highest depth is the first one to get hit
            if (entry.key.code == hash) {
                if (entry.exploredDepth >= depth) {
                    hashTable.stat.hit += 1;
                    return entry;
                }
                break;
            }
        }
        hashTable.stat.miss += 1;
        return null;
    }
};

pub const hashTableStat = struct {
    hit: u64 = 0,
    miss: u64 = 0,
    insertion: u64 = 0,
};
pub const Hash_table = struct {
    entries: []Hash_bucket,
    MBsize: u32 = 0,
    closestBit: u8 = 0,
    size: u64 = 0,
    initialized: bool = false,
    stat: hashTableStat = .{},
    mask: u64 = 0,

    pub fn init(alloc: std.mem.Allocator, MBsize: u32, verbose: bool) !Hash_table {
        var ret: Hash_table = undefined;
        ret.MBsize = MBsize;

        var total_size: u64 = @intCast(MBsize * 1000000);
        total_size = @divFloor(total_size, @sizeOf(Hash_bucket));

        ret.closestBit = chess.l_getMsbIdx(total_size);
        ret.size = chess.xToBitboard(ret.closestBit);
        ret.mask = ret.size - 1;

        ret.stat.insertion = 0;

        ret.entries = (try alloc.alloc(Hash_bucket, ret.size));

        for (0..ret.size) |i| {
            ret.entries[i].len = 0;
            for (0..configl.ITEM_PER_BUCKET) |j| {
                ret.entries[i].entries[j] = .{};
            }
        }
        ret.initialized = true;

        if (verbose) {
            std.debug.print("[PRE] Initializing hash table with a size of {d} buckets closest bit {d}!\n", .{ ret.size, ret.closestBit });
            ret.entries[0].printSize();
        }
        return ret;
    }
    pub fn free(p_self: *Hash_table, alloc: std.mem.Allocator, verbose: bool) void {
        if (verbose) {
            std.debug.print("[FREE] Freeing the entries in the hashtable \n", .{});
        }
        if (p_self.initialized) {
            alloc.free(p_self.entries);
            p_self.initialized = false;
        }
    }
    pub inline fn getHashIndex(self: Hash_table, hash: u64) u64 {
        //return hash % self.entries.len;
        //return hash >> @intCast(64 - self.closestBit);
        return hash & self.mask;
    }
    pub fn getBucketFromFullHashIndex(self: Hash_table, hash: u64) *Hash_bucket {
        const index = self.getHashIndex(hash);
        return &self.entries[index];
    }

    pub fn overwriteEvaluationEntries(p_self: *Hash_table, p_entry: *const Hash_entry, score: scoreType) void {
        const index = p_entry.key.code;
        var p_bucket = p_self.getBucketFromFullHashIndex(index);
        for (0..p_bucket.len) |i| {
            var ent = &p_bucket.entries[i];
            if (ent.key.code == p_entry.key.code) {
                ent.val.search.evaluation = score;
            }
        }
    }
    pub fn storeEntry(p_self: *Hash_table, p_entry: *const Hash_entry) bool {
        p_self.stat.insertion += 1;
        var p_bucket = p_self.getBucketFromFullHashIndex(p_entry.key.code);
        p_bucket.addEntry(p_entry, configl.DEFAULT_TT_STRAT);
        return true;
    }
    pub fn countNonEmpty(p_self: *Hash_table) u64 {
        var ret: u64 = 0;
        for (p_self.entries) |e| {
            ret += @intFromBool(e.len != 0);
        }
        return ret;
    }
    pub fn countValids(p_self: *Hash_table) u64 {
        var ret: u64 = 0;
        for (p_self.entries) |e| {
            ret += @intCast(e.len);
        }
        return ret;
    }

    pub fn getMostUtilized(p_self: *Hash_table) u8 {
        var ret: u8 = 0;
        for (0..p_self.entries.len) |i| {
            const e = p_self.entries[i];
            ret = @max(ret, e.len);
            if (ret == configl.ITEM_PER_BUCKET) {
                break;
            }
        }
        return ret;
    }
};

pub fn getEntryFromPerft(key: Key, depth: u8) Hash_entry {
    const p_bucket: *Hash_bucket = hashTable.getBucketFromFullHashIndex(key.code);
    return p_bucket.getEntryPerft(key.code, depth);
}
pub inline fn getEntryFromMatch(key: Key, depth: u8) ?*Hash_entry {
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
pub fn _initOrReallocHashTable(alloc: std.mem.Allocator, sizeHashTable: u32, verbose: bool) void {
    // size in MB

    if (verbose) {
        std.debug.print("[DEBUG] _initOrReallocHashTable: Building using hash logic!\n", .{});
    }
    if (hashTable.initialized) {
        hashTable.free(alloc, verbose);
    }
    hashTable = Hash_table.init(alloc, sizeHashTable, verbose) catch |err| {
        std.debug.print("[ERROR] _initHash: memory error during alloc {}\n", .{err});
        @panic("Mem error");
    };
}

pub fn _initHash(alloc: std.mem.Allocator, seed: u64, bitsHashTable: u8) void {
    _initZobrist(alloc, seed);
    _ = bitsHashTable;
    return;
}
pub fn _freeHash(alloc: std.mem.Allocator, verbose: bool) void {
    hashTable.free(alloc, verbose);
    zobristKeys.free(alloc);
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
pub fn printTTStats() void {
    const n = hashTable.countNonEmpty();
    const frac: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(hashTable.entries.len)) * 100;
    std.log.info("TT: {d:.2}% of buckets used, non empty {d} total {} buckets", .{ frac, n, hashTable.entries.len });

    const nvalid = hashTable.countValids();
    const frac2: f64 = @as(f64, @floatFromInt(nvalid)) / @as(f64, @floatFromInt(hashTable.entries.len * configl.ITEM_PER_BUCKET)) * 100;
    std.log.info("TT: total utilization {d:.2}%", .{frac2});

    const util = hashTable.getMostUtilized();
    std.log.info("TT: most entries in a bucket {d}", .{util});

    std.log.info("TT: insertions {d} hit {d} miss {d}", .{ hashTable.stat.insertion, hashTable.stat.hit, hashTable.stat.miss });
}
