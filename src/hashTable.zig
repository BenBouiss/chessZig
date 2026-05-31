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
const entryComponents = union { search: searchEntry, perft: perftEntry };
pub const TT_t = enum { perft, search };

pub const subKeyType = u16;
pub const KEY_SHIFT = 64 - @bitSizeOf(subKeyType);
pub inline fn keyToUpperKey(key: u64) subKeyType {
    return @intCast(key >> KEY_SHIFT);
}

pub const perftEntry = struct {
    // 16 bytes
    // 4 + 2 + 1 + 1
    moveAmount: u32 align(1) = 0,
    key: subKeyType align(1) = 0,
    _depth: u8 = 0,
    _age: u8 = 0,
    val: u8 = 0,
    pub fn init(key: subKeyType, moveA: u32, depth: u8, age: u8) perftEntry {
        return .{ .key = key, .moveAmount = moveA, ._depth = depth, ._age = age, .val = 1 };
    }
    pub inline fn valid(self: perftEntry) bool {
        return (self.val & 1) != 0;
    }
};

// Types of nodes:
//  ALL: Upper bound: less than alpha
//  UPPER: or Exact Complete evaluation of a position done a depth 0 to be compared with alpha
//  LOWER: Lower bound: greater or equal than beta. Induced a beta cutoff to be compared with beta
//
pub const nodeType = enum(u2) { UPPER, ALL, LOWER };

const DEPTH_MASK = 0x3FC;
const DEPTH_SHIFT = 2;

const NODETYPE_mask = 0x3;
const VALID_MASK = 0x400;
const VALID_SHIFT = 10;

const AGE_SHIFT = 11;
const AGE_MASK = 0xF800;

pub const searchEntry = struct {
    // 16 + 16 +
    key: subKeyType align(1) = 0,
    evaluation: i16 align(1) = 0,
    bestMove: movel.IMove align(1) = .{},
    _depth: u8 = 0,
    _age: u8 = 0,
    val: u8 = 0,
    pub fn init(key: subKeyType, eval: i16, bestMove: movel.IMove, depth: u8, age: u8, node: nodeType) searchEntry {
        const val: u8 = @as(u8, @intFromEnum(node)) | 0x8;
        return .{ .key = key, .evaluation = eval, .bestMove = bestMove, ._depth = depth, ._age = age, .val = val };
    }
    pub inline fn nodeT(self: searchEntry) nodeType {
        return @enumFromInt(self.val & 0x3);
    }
    pub inline fn valid(self: searchEntry) bool {
        return (self.val & 0x8) != 0;
    }
};

pub const Hash_entry = struct {
    val: entryComponents = undefined,
    pub inline fn moveA(self: *const Hash_entry) u64 {
        return @intCast(self.val.perft.moveAmount);
    }
    pub inline fn eval(self: *const Hash_entry) scoreType {
        return self.val.search.evaluation;
    }
    pub inline fn age(self: *const Hash_entry, comptime t: TT_t) u8 {
        if (comptime t == .perft) {
            return self.val.perft._age;
        } else {
            return self.val.search._age;
        }
    }
    pub inline fn depth(self: *const Hash_entry, comptime t: TT_t) u8 {
        if (comptime t == .perft) {
            return self.val.perft._depth;
        } else {
            return self.val.search._depth;
        }
    }
    pub inline fn key(self: *const Hash_entry, comptime t: TT_t) subKeyType {
        if (comptime t == .perft) {
            return self.val.perft.key;
        } else {
            return self.val.search.key;
        }
    }
    pub inline fn nodeT(self: *const Hash_entry) nodeType {
        return self.val.search.nodeT();
    }
    pub inline fn valid(self: *const Hash_entry, comptime t: TT_t) bool {
        if (comptime t == .perft) {
            return self.val.perft.valid();
        } else {
            return self.val.search.valid();
        }
    }

    pub inline fn copy(self: *const Hash_entry) Hash_entry {
        return .{ .val = self.val, .key = self.key };
    }
};

pub inline fn buildEntryFromPerftResult(key: Key, depth: u8, moveAmount: u64) Hash_entry {
    return .{ .val = .{ .perft = .init(keyToUpperKey(key.code), @truncate(moveAmount), depth, @intCast(hashTable.gen >> 4)) } };
}
pub inline fn buildEntryFromMatchResult(key: Key, depth: u8, eval: scoreType) Hash_entry {
    return .{ .val = .{ .search = .init(keyToUpperKey(key.code), @truncate(eval), .{}, depth, @intCast(hashTable.gen >> 4), .ALL) } };
    //return .{ .val = .{ .search = .{ .evaluation = @truncate(eval), .val = @as(u8, @intFromEnum(nodeType.ALL)), ._depth = depth, .key = keyToUpperKey(key.code), ._age = @truncate(hashTable.gen >> 4) } } };
}

pub inline fn buildEntryMatchExt(key: Key, depth: u8, eval: scoreType, nodeT: nodeType, bestMove: movel.IMove) Hash_entry {
    return .{ .val = .{ .search = .init(keyToUpperKey(key.code), @truncate(eval), bestMove, depth, @intCast(hashTable.gen >> 4), nodeT) } };
    //return .{ .val = .{ .search = .{ .evaluation = @truncate(eval), .val = @as(u8, @intFromEnum(nodeT)), .bestMove = bestMove, ._depth = depth, .key = keyToUpperKey(key.code), ._age = @truncate(hashTable.gen >> 4) } } };
}

pub const getResult = struct {
    nextIdx: u8 = 0,
    entry: ?Hash_entry = null,
};
pub const probeResult = struct {
    writer: hashWriter = .{},
    entry: ?Hash_entry = null,
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

    pub inline fn write(self: *hashWriter, entry: Hash_entry, comptime t: TT_t) void {
        const stat = self.bucket.addEntry(entry, configl.DEFAULT_TT_STRAT, t);
        if (stat) {
            hashTable.stat.insertion += 1;
        }
    }
};

pub const Hash_bucket = struct {
    entries: [configl.ITEM_PER_BUCKET]Hash_entry align(32) = undefined,

    pub fn printSize(p_self: *const Hash_bucket) void {
        std.debug.print("[DEBUG] printSize: hash bucket = {d} bytes\n", .{@sizeOf(Hash_bucket)});
        std.debug.print("[DEBUG] printSize: entries size is {d} bytes\n", .{@sizeOf(Hash_entry)});
        std.debug.print("[DEBUG] printSize: entries val size is {d} bytes\n", .{@sizeOf(entryComponents)});
        std.debug.print("[DEBUG] printSize: is of perft entry is {d} bytes\n", .{@sizeOf(perftEntry)});
        std.debug.print("[DEBUG] printSize: is of search entry is {d} bytes\n", .{@sizeOf(searchEntry)});

        //std.debug.print("[DEBUG] printSize: hash bucket extern  {d} bytes\n", .{@sizeOf(ext_Hash_bucket)});
        _ = p_self;
    }
    pub fn t_len(self: Hash_bucket, comptime t: TT_t) u8 {
        var ret: u8 = 0;
        for (0..configl.ITEM_PER_BUCKET) |i| {
            if (comptime t == .perft) {
                ret += @intFromBool(self.entries[i].valid(.perft));
            } else {
                ret += @intFromBool(self.entries[i].valid(.search));
            }
        }
        return ret;
    }
    pub fn len(self: Hash_bucket) u8 {
        var ret: u8 = 0;
        for (0..configl.ITEM_PER_BUCKET) |i| {
            ret += @intFromBool(self.entries[i].valid(.perft));
        }
        return ret;
    }
    pub fn addEntry(p_self: *Hash_bucket, entry: Hash_entry, strategy: TT_strat, comptime t: TT_t) bool {
        switch (strategy) {
            .ALWAYS_REPLACE => {
                return p_self.addEntry_AR(entry, t);
            },
            .ALWAYS_REPLACE_OLDEST => {
                return p_self.addEntry_oldest(entry, t);
            },
            .KEEP_DEEPER => {
                return p_self.addEntry_deep(entry, t);
            },
        }
    }

    pub fn addEntry_deep(p_self: *Hash_bucket, n_entry: Hash_entry, comptime t: TT_t) bool {
        var idxS: usize = 0;
        var sDepth: u8 = 255;
        const reqDepth = n_entry.depth(t);
        // if a better entry exists for this hash key we exit
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const entry = p_self.entries[i];
            const currDepth = entry.depth(t);
            if (!entry.valid(t) or (entry.age(t) + configl.OLD_THRESHOLD) < n_entry.age(t)) {
                p_self.entries[i] = n_entry;
                //p_self.len = @min(p_self.len + 1, p_self.entries.len);
                return true;
            }
            if (entry.key(t) == n_entry.key(t)) {
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
    pub fn addEntry_oldest(p_self: *Hash_bucket, n_entry: Hash_entry, comptime t: TT_t) bool {
        var idxS: usize = 0;
        var sAge: usize = 0;
        const reqDepth = n_entry.depth(t);
        // if a better n_entry exists for this hash key we exit
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const _entry = p_self.entries[i];
            const _age = _entry.age(t);
            if (!_entry.valid(t) or (_age + configl.SCHEDULER_MAX_ENDGAME_DEPTH) < n_entry.age(t)) {
                p_self.entries[i] = n_entry;
                //p_self.len = @min(p_self.len + 1, p_self.entries.len);
                return true;
            }
            if (_entry.key(t) == n_entry.key(t)) {
                if (_entry.depth(t) > reqDepth) {
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
    pub fn addEntry_AR(p_self: *Hash_bucket, entry: Hash_entry, comptime t: TT_t) bool {
        _ = p_self;
        _ = entry;
        _ = t;
        //p_self.entries[p_self.len] = entry;
        //p_self.len = (p_self.len + 1) % configl.ITEM_PER_BUCKET;
        return true;
    }
    pub fn getEntryPerft(p_self: *Hash_bucket, hash: u64, depth: u8) ?Hash_entry {
        const _hash = keyToUpperKey(hash);
        for (0..configl.ITEM_PER_BUCKET) |i| {
            var entry = p_self.entries[i];
            if (entry.key(.perft) == _hash and entry.depth(.perft) == depth) {
                return entry;
            }
        }
        return null;
    }
    pub fn getEntryMatchNext(p_self: *Hash_bucket, hash: u64, depth: u8, p_state: *const boardl.boardState) getResult {
        const _hash = keyToUpperKey(hash);
        var next: u8 = 0;
        var nextA: u8 = 255;
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const entry = p_self.entries[i];
            // note: now that only one instance of the key gets stored, the highest depth is the first one to get hit
            if ((entry.key(.search) == _hash) and (entry.depth(.search) >= depth)) {
                if (p_state.isMovePseudoLegal(entry.val.search.bestMove)) {
                    hashTable.stat.hit += 1;
                    return .{ .entry = entry, .nextIdx = next };
                }
            }
            if (entry.age(.search) < nextA) {
                nextA = entry.age(.search);
                next = @intCast(i);
            }
        }
        hashTable.stat.miss += 1;
        return .{ .entry = null, .nextIdx = next };
    }
    pub fn getEntryMatch(p_self: *Hash_bucket, hash: u64, depth: u8) ?Hash_entry {
        const _hash = keyToUpperKey(hash);
        for (0..configl.ITEM_PER_BUCKET) |i| {
            var entry = p_self.entries[i];
            if (entry.key(.search) == _hash and entry.depth(.search) >= depth) {
                hashTable.stat.hit += 1;
                return entry;
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

        //var total_size: u64 = @intCast(MBsize * 1000000);
        var total_size: u64 = @intCast(MBsize * 1024 * 1024);
        total_size = @divFloor(total_size, @sizeOf(Hash_entry) * configl.ITEM_PER_BUCKET);

        ret.closestBit = chess.l_getMsbIdx(total_size) - 1;
        ret.size = chess.xToBitboard(ret.closestBit);
        ret.mask = ret.size - 1;
        ret.stat.insertion = 0;
        ret.gen = 0;

        ret.entries = (try alloc.alloc(Hash_bucket, ret.size));

        for (0..ret.size) |i| {
            var b = ret.getBucket(@intCast(i));
            for (0..configl.ITEM_PER_BUCKET) |j| {
                b.entries[j] = .{ .val = .{ .search = .{} } };
            }
        }
        ret.initialized = true;

        if (verbose) {
            std.debug.print("[PRE] Initializing hash table with a size of {d} buckets closest bit {d} for input of {d}MB = {d} msb total size {d}! Total allocated size {d} bytes for {d} entries\n", .{ ret.size, ret.closestBit, MBsize, chess.l_getMsbIdx(total_size), total_size, ret.size * configl.ITEM_PER_BUCKET * @sizeOf(Hash_entry), ret.size * configl.ITEM_PER_BUCKET });
            ret.getBucket(0).printSize();
        }
        return ret;
    }
    pub inline fn getBucket(p_self: *Hash_table, bucketIdx: u64) *Hash_bucket {
        return &p_self.entries[bucketIdx];
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
    pub inline fn getBucketFromFullHashIndex(self: *Hash_table, hash: u64) *Hash_bucket {
        const index = self.getHashIndex(hash);
        return self.getBucket(index);
    }

    pub fn overwriteEvaluationEntries(p_self: *Hash_table, p_entry: *Hash_entry, score: scoreType) void {
        const index = p_entry.key;
        var p_bucket = p_self.getBucketFromFullHashIndex(index);
        for (0..configl.ITEM_PER_BUCKET) |i| {
            var ent = &p_bucket.entries[i];
            if (ent.key == p_entry.key) {
                ent.val.search.evaluation = score;
            }
        }
    }
    pub fn storeEntry_cst(p_self: *Hash_table, p_entry: Hash_entry, key: u64, comptime strategy: TT_strat, comptime t: TT_t) bool {
        var p_bucket = p_self.getBucketFromFullHashIndex(key);
        const stat = p_bucket.addEntry(p_entry, strategy, t);
        if (stat) {
            p_self.stat.insertion += 1;
        }
        return true;
    }
    pub inline fn probePerft(p_self: *Hash_table, key: u64, depth: u8) probeResult {
        const p_bucket = p_self.getBucketFromFullHashIndex(key);
        return .{ .writer = .{ .bucket = p_bucket, .idx = 0 }, .entry = p_bucket.getEntryPerft(key, depth) };
    }
    pub fn probeMatch(p_self: *Hash_table, key: u64, depth: u8, p_state: *const boardl.boardState) probeResult {
        const p_bucket = p_self.getBucketFromFullHashIndex(key);
        const res = p_bucket.getEntryMatchNext(key, depth, p_state);
        return .{ .writer = .{ .bucket = p_bucket, .idx = res.nextIdx }, .entry = res.entry };
    }
    pub fn storeEntry(p_self: *Hash_table, entry: Hash_entry, key: u64, comptime t: TT_t) bool {
        var p_bucket = p_self.getBucketFromFullHashIndex(key);
        const stat = p_bucket.addEntry(entry, configl.DEFAULT_TT_STRAT, t);
        if (stat) {
            p_self.stat.insertion += 1;
        }
        return true;
    }
    pub fn countNonEmpty(p_self: *Hash_table) u64 {
        var ret: u64 = 0;
        for (0..p_self.size) |i| {
            ret += @intFromBool(p_self.getBucket(i).len() != 0);
        }
        return ret;
    }
    pub fn countValids(p_self: *Hash_table) u64 {
        var ret: u64 = 0;
        for (p_self.entries) |e| {
            ret += @intCast(e.len());
        }
        return ret;
    }

    pub fn getMostUtilized(p_self: *Hash_table) u8 {
        var ret: u8 = 0;
        for (0..p_self.size) |i| {
            const e = p_self.getBucket(@intCast(i));
            ret = @max(ret, e.len());
            if (ret == configl.ITEM_PER_BUCKET) {
                break;
            }
        }
        return ret;
    }
};

pub fn getEntryFromPerft(key: Key, depth: u8) ?Hash_entry {
    const p_bucket: Hash_bucket = hashTable.getBucketFromFullHashIndex(key.code);
    return p_bucket.getEntryPerft(key.code, depth);
}
pub inline fn getEntryFromMatch(key: Key, depth: u8) ?Hash_entry {
    var p_bucket: *Hash_bucket = hashTable.getBucketFromFullHashIndex(key.code);
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
    const frac: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(hashTable.size)) * 100;
    std.log.info("TT: {d:.2}% of buckets used, non empty {d} total {} buckets", .{ frac, n, hashTable.size });

    const nvalid = hashTable.countValids();
    const frac2: f64 = @as(f64, @floatFromInt(nvalid)) / @as(f64, @floatFromInt(hashTable.entries.len * configl.ITEM_PER_BUCKET)) * 100;
    std.log.info("TT: total utilization {d:.2}%", .{frac2});

    const util = hashTable.getMostUtilized();
    std.log.info("TT: most entries in a bucket {d}", .{util});

    std.log.info("TT: insertions {d} hit {d} miss {d}", .{ hashTable.stat.insertion, hashTable.stat.hit, hashTable.stat.miss });
}
