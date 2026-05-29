const std = @import("std");
const chess = @import("chess.zig");
const movel = @import("move.zig");
const boardl = @import("board.zig");
const configl = @import("config.zig");
const heuristicl = @import("heuristic.zig");

const build_options = @import("build_options");

const e_piece = chess.e_piece;
const scoreType = heuristicl.scoreType;
const TT_strat = configl.TT_strat;

pub const Key = struct {
    code: u64 = 0,
};

// note: the gain in space is not visible in the debug build
// will try to implement the chess programming version where way more stuff is stored
const entryComponents = packed union { search: searchEntry, perft: perftEntry };

pub const subKeyType = u48;
pub const KEY_SHIFT = 64 - @bitSizeOf(subKeyType);
pub inline fn keyToUpperKey(key: u64) subKeyType {
    return @intCast(key >> KEY_SHIFT);
}

pub const perftEntry = packed struct {
    moveAmount: u48 = 0,
    pad: u2 = 0,
};

// Types of nodes:
//  ALL: Upper bound: less than alpha
//  UPPER: or Exact Complete evaluation of a position done a depth 0 to be compared with alpha
//  LOWER: Lower bound: greater or equal than beta. Induced a beta cutoff to be compared with beta
//
pub const nodeType = enum(u2) { UPPER, ALL, LOWER };

// https://deepwiki.com/official-stockfish/Stockfish/4.3-transposition-table
// bound type 2 bit
// depth 8 bit
// valid 1 bit
// age 5 bit ? counted as the >> 3 of the n_insertion & age_mask similar to the tens of insertions interpreted as an age
// tot 16 bit
const DEPTH_MASK = 0x3FC;
const DEPTH_SHIFT = 2;

const NODETYPE_mask = 0x3;
const VALID_MASK = 0x400;
const VALID_SHIFT = 10;

const AGE_SHIFT = 11;
const AGE_MASK = 0xF800;

pub const searchEntry = packed struct {
    evaluation: scoreType = 0,
    //val: u16 = 0,
    bound: nodeType = .UPPER,
    bestMove: movel.IMove = .{},

    pub inline fn nodeT(self: searchEntry) nodeType {
        return self.bound;
    }
};

pub const Hash_entry = packed struct {
    val: entryComponents = undefined,
    _valid: bool = false,
    key: subKeyType = 0,
    _depth: u8 = 0,
    _age: u8 = 0,

    pub inline fn moveA(self: *const Hash_entry) u64 {
        return @intCast(self.val.perft.moveAmount);
    }
    pub inline fn eval(self: *const Hash_entry) scoreType {
        return self.val.search.evaluation;
    }
    pub inline fn age(self: *const Hash_entry) u8 {
        return self._age;
    }
    pub inline fn depth(self: *const Hash_entry) u8 {
        return self.val.search.depth();
    }
    pub inline fn nodeT(self: *const Hash_entry) nodeType {
        return self.val.search.nodeT();
    }
    pub inline fn valid(self: *const Hash_entry) bool {
        return self._valid;
    }

    pub inline fn copy(self: *const Hash_entry) Hash_entry {
        return .{ .val = self.val, .key = self.key };
    }
};

pub inline fn buildEntryFromPerftResult(key: Key, depth: u8, moveAmount: u64) Hash_entry {
    return .{ ._valid = true, ._depth = depth, .key = keyToUpperKey(key.code), ._age = @intCast(hashTable.gen >> 8), .val = .{ .perft = .{ .moveAmount = @intCast(moveAmount) } } };
}
pub inline fn buildEntryFromMatchResult(key: Key, depth: u8, eval: scoreType) Hash_entry {
    return .{ ._valid = true, ._depth = depth, .key = keyToUpperKey(key.code), ._age = @truncate(hashTable.gen >> 4), .val = .{ .search = .{ .evaluation = eval, .bound = .ALL } } };
}

pub inline fn buildEntryMatchExt(key: Key, depth: u8, eval: scoreType, nodeT: nodeType, bestMove: movel.IMove) Hash_entry {
    return .{ ._valid = true, ._depth = depth, .key = keyToUpperKey(key.code), ._age = @truncate(hashTable.gen >> 4), .val = .{ .search = .{ .evaluation = eval, .bound = nodeT, .bestMove = bestMove } } };
}

pub const getResult = struct {
    nextIdx: u8 = 0,
    entry: ?Hash_entry = .{},
};
pub const probeResult = struct {
    writer: hashWriter = .{},
    entry: ?Hash_entry = .{},
};
pub const hashWriter = struct {
    bucket: *Hash_bucket = undefined,
    idx: u8 = 0,

    pub inline fn init(key: u64) hashWriter {
        return .{ .bucket = hashTable.getBucketFromFullHashIndex(key) };
    }
    pub inline fn writeShort(self: *hashWriter, entry: Hash_entry) void {
        self.bucket.entries[self.idx] = entry;
        hashTable.stat.insertion += 1;
    }

    pub inline fn write(self: *hashWriter, entry: Hash_entry) void {
        const stat = self.bucket.addEntry(entry, configl.DEFAULT_TT_STRAT);
        if (stat) {
            hashTable.stat.insertion += 1;
        }
    }
};
pub const Hash_bucket = struct {
    entries: [configl.ITEM_PER_BUCKET]Hash_entry = undefined,
    len: u8 = 0,

    pub fn printSize(p_self: *Hash_bucket) void {
        std.debug.print("[DEBUG] printSize: hash bucket = {d} bytes\n", .{@sizeOf(Hash_bucket)});
        std.debug.print("[DEBUG] printSize: entries size is {d} bytes\n", .{@sizeOf(Hash_entry)});
        std.debug.print("[DEBUG] printSize: entries val size is {d} bytes\n", .{@sizeOf(entryComponents)});
        std.debug.print("[DEBUG] printSize: is of perft entry is {d} bytes\n", .{@sizeOf(perftEntry)});
        std.debug.print("[DEBUG] printSize: is of search entry is {d} bytes\n", .{@sizeOf(searchEntry)});
        _ = p_self;
    }
    pub fn addEntry(p_self: *Hash_bucket, entry: Hash_entry, strategy: TT_strat) bool {
        switch (strategy) {
            .ALWAYS_REPLACE => {
                return p_self.addEntry_AR(entry);
            },
            .ALWAYS_REPLACE_OLDEST => {
                return p_self.addEntry_oldest(entry);
            },
            .KEEP_DEEPER => {
                return p_self.addEntry_deep(entry);
            },
        }
    }

    pub fn addEntry_deep(p_self: *Hash_bucket, n_entry: Hash_entry) bool {
        var idxS: usize = 0;
        var sDepth: u8 = 255;
        const reqDepth = n_entry._depth;
        // if a better entry exists for this hash key we exit
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const entry = p_self.entries[i];
            const currDepth = entry._depth;
            if (!entry.valid() or (entry.age() + configl.OLD_THRESHOLD) < n_entry.age()) {
                p_self.entries[i] = n_entry;
                p_self.len = @min(p_self.len + 1, p_self.entries.len);
                return true;
            }
            if (entry.key == n_entry.key) {
                if (currDepth > reqDepth) {
                    return false;
                }
                p_self.entries[i] = n_entry;
                return true;
            }

            if (currDepth < sDepth) {
                idxS = i;
                sDepth = currDepth;
            }
        }

        p_self.entries[idxS] = n_entry;
        return true;
    }
    pub fn addEntry_oldest(p_self: *Hash_bucket, n_entry: Hash_entry) bool {
        var idxS: usize = 0;
        var sAge: usize = 0;
        const reqDepth = n_entry._depth;
        // if a better n_entry exists for this hash key we exit
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const _entry = p_self.entries[i];
            const _age = _entry.age();
            if (!_entry.valid() or (_age + configl.SCHEDULER_MAX_ENDGAME_DEPTH) < n_entry.age()) {
                p_self.entries[i] = n_entry;
                p_self.len = @min(p_self.len + 1, p_self.entries.len);
                return true;
            }
            if (_entry.key == n_entry.key) {
                if (_entry._depth > reqDepth) {
                    return false;
                }
                p_self.entries[i] = n_entry;
                return true;
            }

            if (_age < sAge) {
                idxS = i;
                sAge = _age;
            }
        }
        p_self.entries[idxS] = n_entry;
        return true;
        //p_self.len = @min(p_self.len + 1, p_self.entries.len);
    }
    pub fn addEntry_AR(p_self: *Hash_bucket, entry: Hash_entry) bool {
        p_self.entries[p_self.len] = entry;
        p_self.len = (p_self.len + 1) % configl.ITEM_PER_BUCKET;
        return true;
    }
    pub fn getEntryPerft(p_self: *Hash_bucket, hash: u64, depth: u8) ?Hash_entry {
        const _hash = keyToUpperKey(hash);
        for (0..p_self.len) |i| {
            const entry = p_self.entries[i];
            if (entry.key == _hash and entry._depth == depth) {
                return entry;
            }
        }
        return null;
    }
    pub fn getEntryMatchNext(p_self: *Hash_bucket, hash: u64, depth: u8) getResult {
        const _hash = keyToUpperKey(hash);
        var next: u8 = 0;
        var nextA: u8 = 255;
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const entry = p_self.entries[i];
            // note: now that only one instance of the key gets stored, the highest depth is the first one to get hit
            if ((entry.key == _hash) and (entry._depth >= depth)) {
                hashTable.stat.hit += 1;
                return .{ .entry = entry, .nextIdx = next };
            }
            if (entry._age < nextA) {
                nextA = entry._age;
                next = @intCast(i);
            }
        }
        hashTable.stat.miss += 1;
        return .{ .entry = null, .nextIdx = next };
    }
    pub fn getEntryMatch(p_self: *Hash_bucket, hash: u64, depth: u8) ?Hash_entry {
        const _hash = keyToUpperKey(hash);
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const entry = p_self.entries[i];
            // note: now that only one instance of the key gets stored, the highest depth is the first one to get hit
            if (entry.key == _hash) {
                if (entry._depth >= depth) {
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
    // from 0 - ~8k, the max size of a match, the age of an entry will be gen >> 8
    gen: u16 = 0,

    pub fn init(alloc: std.mem.Allocator, MBsize: u32, verbose: bool) !Hash_table {
        var ret: Hash_table = undefined;
        ret.MBsize = MBsize;

        var total_size: u64 = @intCast(MBsize * 1000000);
        total_size = @divFloor(total_size, @sizeOf(Hash_bucket));

        ret.closestBit = chess.l_getMsbIdx(total_size);
        ret.size = chess.xToBitboard(ret.closestBit);
        ret.mask = ret.size - 1;
        ret.stat.insertion = 0;
        ret.gen = 0;

        ret.entries = (try alloc.alloc(Hash_bucket, ret.size));

        for (0..ret.size) |i| {
            ret.entries[i].len = 0;
            for (0..configl.ITEM_PER_BUCKET) |j| {
                ret.entries[i].entries[j] = .{ .val = .{ .search = .{} } };
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

    pub inline fn nextGeneration(self: *Hash_table) void {
        // to be used at each node root
        self.gen += 1;
    }

    pub inline fn getHashIndex(self: Hash_table, hash: u64) u64 {
        return hash & self.mask;
    }
    pub inline fn getBucketFromFullHashIndex(self: Hash_table, hash: u64) *Hash_bucket {
        const index = self.getHashIndex(hash);
        return &self.entries[index];
    }

    pub fn overwriteEvaluationEntries(p_self: *Hash_table, p_entry: *const Hash_entry, score: scoreType) void {
        const index = p_entry.key;
        var p_bucket = p_self.getBucketFromFullHashIndex(index);
        for (0..p_bucket.len) |i| {
            var ent = &p_bucket.entries[i];
            if (ent.key == p_entry.key) {
                ent.val.search.evaluation = score;
            }
        }
    }
    pub fn storeEntry_cst(p_self: *Hash_table, p_entry: Hash_entry, key: u64, comptime strategy: TT_strat) bool {
        var p_bucket = p_self.getBucketFromFullHashIndex(key);
        const stat = p_bucket.addEntry(p_entry, strategy);
        if (stat) {
            p_self.stat.insertion += 1;
        }
        return true;
    }
    pub inline fn probePerft(p_self: *const Hash_table, key: u64, depth: u8) probeResult {
        const p_bucket = p_self.getBucketFromFullHashIndex(key);
        return .{ .writer = .{ .bucket = p_bucket, .idx = 0 }, .entry = p_bucket.getEntryPerft(key, depth) };
    }
    pub fn probeMatch(p_self: *const Hash_table, key: u64, depth: u8) probeResult {
        const p_bucket = p_self.getBucketFromFullHashIndex(key);
        const res = p_bucket.getEntryMatchNext(key, depth);
        return .{ .writer = .{ .bucket = p_bucket, .idx = res.nextIdx }, .entry = res.entry };
    }
    pub fn storeEntry(p_self: *Hash_table, entry: Hash_entry, key: u64) bool {
        var p_bucket = p_self.getBucketFromFullHashIndex(key);
        const stat = p_bucket.addEntry(entry, configl.DEFAULT_TT_STRAT);
        if (stat) {
            p_self.stat.insertion += 1;
        }
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

pub fn getEntryFromPerft(key: Key, depth: u8) ?Hash_entry {
    const p_bucket: *Hash_bucket = hashTable.getBucketFromFullHashIndex(key.code);
    return p_bucket.getEntryPerft(key.code, depth);
}
pub inline fn getEntryFromMatch(key: Key, depth: u8) ?Hash_entry {
    const p_bucket: *Hash_bucket = hashTable.getBucketFromFullHashIndex(key.code);
    return p_bucket.getEntryMatch(key.code, depth);
}

pub const Zobrist_Keys = struct {
    pieceKeys: [12][64]Key = std.mem.zeroes([12][64]Key),
    turnKey: [chess.NUMBER_PLAYER]Key = std.mem.zeroes([chess.NUMBER_PLAYER]Key),
    playKey: Key = .{},
    castlingKeys: [16]Key = std.mem.zeroes([16]Key),
    enPassantKeys: [64]Key = std.mem.zeroes([64]Key),
    pub fn init(seed: u64) Zobrist_Keys {
        var ret: Zobrist_Keys = .{};
        var rngIntGenerator = std.Random.DefaultPrng.init(seed);
        const rng = rngIntGenerator.random();
        initZobristKeys(rng, &ret);
        return ret;
    }
};

pub const zobristKeys: Zobrist_Keys = Zobrist_Keys.init(configl.SEED);
pub var hashTable: Hash_table = .{ .entries = undefined };

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
    _ = alloc;
    _ = seed;
    //_initZobrist(alloc, seed);
    _ = bitsHashTable;
    return;
}
pub fn _freeHash(alloc: std.mem.Allocator, verbose: bool) void {
    hashTable.free(alloc, verbose);
    //zobristKeys.free(alloc);
}

pub fn initZobristKeys(rng: std.Random, zob: *Zobrist_Keys) void {
    @setEvalBranchQuota(100000);
    for (0..12) |i| {
        for (0..64) |j| {
            zob.pieceKeys[i][j] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };
        }
    }

    zob.turnKey[0] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };
    zob.turnKey[1] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };

    for (0..16) |j| {
        zob.castlingKeys[j] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };
    }

    for (0..64) |j| {
        zob.enPassantKeys[j] = .{ .code = rng.uintAtMost(u64, chess.UNIVERSE) };
    }
    zob.playKey = zob.turnKey[0];
    zob.playKey.code ^= zob.turnKey[1].code;
}
pub fn fullComputeZobristKeys(p_board: *const boardl.boardState) Key {
    // for better perfs look for incremental xor key update using the previous move
    var retKey = zobristKeys.turnKey[@intFromBool(p_board.whiteToMove())];

    for (0..chess.N_SQUARES) |i| {
        const piece = p_board.getPiece(@intCast(i));
        if (piece != .nEmptySquare) {
            retKey.code ^= zobristKeys.pieceKeys[@intFromEnum(piece)][i].code;
        }
    }

    retKey.code ^= zobristKeys.castlingKeys[p_board.frame.stat.castlingKey()].code;
    retKey.code ^= zobristKeys.enPassantKeys[p_board.frame.enPassantIdx].code;

    return retKey;
}

pub inline fn updateKey(keyDst: *Key, keySrc: Key) void {
    keyDst.code ^= keySrc.code;
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
