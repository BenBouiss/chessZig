const build_options = @import("build_options");

const useMagic = build_options.useMagic;

const chess = @import("chess.zig");
const squarel = @import("square.zig");

const std = @import("std");

// TODO Implement fancy bitboard https://www.chessprogramming.org/Magic_Bitboards
// related(?) link: http://pradu.us/old/Nov27_2008/Buzz/

pub const magic_err = error{noMagicFound};
pub const BISHOP_MOVE_SIZE: usize = 512;
pub const BISHOP_FIXED_BIT: usize = 9;

pub const ROOK_MOVE_SIZE: usize = 4096;
pub const ROOK_FIXED_BIT: usize = 12;

var rngIntGenerator = std.Random.DefaultPrng.init(42);
const randInt = rngIntGenerator.random();

const ROOK_MAGIC_KEYS = [64]u64{ 0x80008850224004, 0xa449004000088240, 0x10003014082080, 0x8010040100020800, 0xa008001801008200, 0x1002104008008020, 0x2180102200088041, 0x21000122c0820500, 0xb860201018480c0, 0x23004000310022, 0x42000440120080, 0x4208020400200, 0x448201108000280, 0x1044200c81004600, 0x4000680110020084, 0x2810200828c00304, 0x242004001002, 0x2100440281029, 0x2805100800288102, 0x8800084040840104, 0x2010120001020820, 0x44900086080c400, 0x1004a1080c030402, 0x200100409020020, 0x404082002485005a, 0x9904005060002009, 0x1408200a080040, 0x441c004210004010, 0x100200800801041, 0x4400502008400100, 0x285000060020080, 0x40a0002080804510, 0x400084800011, 0x8040000c00210900, 0x220041000084148, 0x8420802000804, 0x40060a2944008004, 0x4004208412000200, 0xb040020001048080, 0x400005032000104, 0x4044851204000800, 0x2080444204911200, 0x160002400040100, 0x4000218002004, 0x83001210051002, 0x1000008400010042, 0x2010000800040c0, 0x800111022140, 0x440008208020048, 0x40924082285008, 0x8400910800102248, 0x20046200100200, 0x208a008040043a40, 0x1014103804820010, 0x2000082040100, 0x40020090400120, 0x8000408200210012, 0x481021004001, 0x40804c20a008012, 0x80024a40220046, 0x2140641082082001, 0x4c7900300860002, 0x200109049900184, 0x8104002042 };
const ROOK_MAGIC_MASK = [64]u64{ 0x101010101017e, 0x202020202027c, 0x404040404047a, 0x8080808080876, 0x1010101010106e, 0x2020202020205e, 0x4040404040403e, 0x8080808080807e, 0x1010101017e00, 0x2020202027c00, 0x4040404047a00, 0x8080808087600, 0x10101010106e00, 0x20202020205e00, 0x40404040403e00, 0x80808080807e00, 0x10101017e0100, 0x20202027c0200, 0x40404047a0400, 0x8080808760800, 0x101010106e1000, 0x202020205e2000, 0x404040403e4000, 0x808080807e8000, 0x101017e010100, 0x202027c020200, 0x404047a040400, 0x8080876080800, 0x1010106e101000, 0x2020205e202000, 0x4040403e404000, 0x8080807e808000, 0x1017e01010100, 0x2027c02020200, 0x4047a04040400, 0x8087608080800, 0x10106e10101000, 0x20205e20202000, 0x40403e40404000, 0x80807e80808000, 0x17e0101010100, 0x27c0202020200, 0x47a0404040400, 0x8760808080800, 0x106e1010101000, 0x205e2020202000, 0x403e4040404000, 0x807e8080808000, 0x7e010101010100, 0x7c020202020200, 0x7a040404040400, 0x76080808080800, 0x6e101010101000, 0x5e202020202000, 0x3e404040404000, 0x7e808080808000, 0x7e01010101010100, 0x7c02020202020200, 0x7a04040404040400, 0x7608080808080800, 0x6e10101010101000, 0x5e20202020202000, 0x3e40404040404000, 0x7e80808080808000 };
const ROOK_MAGIC_INDEX = [64]i8{ 12, 11, 11, 11, 11, 11, 11, 12, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 12, 11, 11, 11, 11, 11, 11, 12 };

const BISHOP_MAGIC_KEYS = [64]u64{ 0xe0044310088011, 0x4400208801016210, 0x61d104400440040, 0x41040e041012481, 0x8900c1000000, 0x500121002002, 0x60110a1611100040, 0x2a010101100201, 0x192080080840502, 0xc000508010a50044, 0x4108404c002080, 0x201048c0110180, 0x10100512080180, 0x13080e400100, 0x18072010040408, 0x1000014020840084, 0xc201000c00320404, 0x21008100420d04a0, 0x1020800420680, 0x14403014000212, 0x1800142900400800, 0x4512020800c000, 0xa200614008680101, 0xe382420204820c, 0x4422209040046c42, 0x8400200000828402, 0xa0a4000802c005, 0x234802002020200, 0x801001001004024, 0x2280a04002001000, 0x100102080540201, 0x1441010002004058, 0x908e01000018100, 0x800202081440900, 0xc2a40010802, 0x888042008040100, 0x440004100501100, 0x20e0008001000, 0x602280004074018, 0x2880a2a040024004, 0x21009000401500, 0x80008168004c0200, 0xa028041100442103, 0x508012008001100, 0x500070080200490, 0x40002101020010, 0x4101040100046a, 0x402008212042080, 0x4c01070012024010, 0x400498802810822, 0x2008801148280000, 0x1041090084044400, 0x8906441181a0002, 0x90800614c004000, 0x148a468088004310, 0x2020204010400, 0x40008011302, 0x800088800520200a, 0xc000004023004021, 0xa020004100024413, 0x200c808802020608, 0x1000604000401460, 0x103a35004200, 0x1810028008c082 };

const BISHOP_MAGIC_MASK = [64]u64{ 0x40201008040200, 0x402010080400, 0x4020100a00, 0x40221400, 0x2442800, 0x204085000, 0x20408102000, 0x2040810204000, 0x20100804020000, 0x40201008040000, 0x4020100a0000, 0x4022140000, 0x244280000, 0x20408500000, 0x2040810200000, 0x4081020400000, 0x10080402000200, 0x20100804000400, 0x4020100a000a00, 0x402214001400, 0x24428002800, 0x2040850005000, 0x4081020002000, 0x8102040004000, 0x8040200020400, 0x10080400040800, 0x20100a000a1000, 0x40221400142200, 0x2442800284400, 0x4085000500800, 0x8102000201000, 0x10204000402000, 0x4020002040800, 0x8040004081000, 0x100a000a102000, 0x22140014224000, 0x44280028440200, 0x8500050080400, 0x10200020100800, 0x20400040201000, 0x2000204081000, 0x4000408102000, 0xa000a10204000, 0x14001422400000, 0x28002844020000, 0x50005008040200, 0x20002010080400, 0x40004020100800, 0x20408102000, 0x40810204000, 0xa1020400000, 0x142240000000, 0x284402000000, 0x500804020000, 0x201008040200, 0x402010080400, 0x2040810204000, 0x4081020400000, 0xa102040000000, 0x14224000000000, 0x28440200000000, 0x50080402000000, 0x20100804020000, 0x40201008040200 };
const BISHOP_MAGIC_INDEX = [64]i8{ 6, 5, 5, 5, 5, 5, 5, 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 7, 7, 7, 7, 5, 5, 5, 5, 7, 9, 9, 7, 5, 5, 5, 5, 7, 9, 9, 7, 5, 5, 5, 5, 7, 7, 7, 7, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 5, 5, 5, 5, 5, 5, 6 };

const magic_entry = struct {
    mask: u64 = 0,
    magic: u64 = 0,
};

pub var magicTable: magicRecord = undefined;
pub const p_magicTable: *magicRecord = &magicTable;

pub const magicRecord = struct {
    isInitialized: bool = false,
    rookMagic: [chess.N_SQUARES]magic_entry = std.mem.zeroes([chess.N_SQUARES]magic_entry),
    bishopMagic: [chess.N_SQUARES]magic_entry = std.mem.zeroes([chess.N_SQUARES]magic_entry),
    rookMoves: [chess.N_SQUARES][ROOK_MOVE_SIZE]u64,
    bishopMoves: [chess.N_SQUARES][BISHOP_MOVE_SIZE]u64,
    pub fn init() magicRecord {
        return .{ .isInitialized = true, .rookMoves = undefined, .bishopMoves = undefined };
    }
};
pub fn _initMagic(p_magic: *magicRecord, verbose: bool) void {
    p_magic.* = magicRecord.init();

    initRookBishopMagicCached(p_magic);
    initRookBishopMoves(p_magic);
    if (verbose) {
        std.debug.print("[PRE] Finished magic\n", .{});
    }
    return;
}

pub fn initRookBishopMagicCached(p_record: *magicRecord) void {
    for (0..64) |sq| {
        const magic: magic_entry = .{ .mask = ROOK_MAGIC_MASK[sq], .magic = ROOK_MAGIC_KEYS[sq] };
        p_record.rookMagic[sq] = magic;
    }
    for (0..64) |sq| {
        const magic: magic_entry = .{ .mask = BISHOP_MAGIC_MASK[sq], .magic = BISHOP_MAGIC_KEYS[sq] };
        p_record.bishopMagic[sq] = magic;
    }
}

pub fn bishopGenerateMoves(sq: squarel.e_square, magic: magic_entry, p_out: *[BISHOP_MOVE_SIZE]u64) void {
    var b: [BISHOP_MOVE_SIZE]u64 = undefined;
    const mask = bmask(@intFromEnum(sq));
    const n = chess.popcount(mask);
    for (0..BISHOP_MOVE_SIZE) |i| {
        b[i] = index_to_uint64(@intCast(i), @intCast(n), mask);
        const j = bishopMagicIndex(magic, b[i]);
        p_out[j] = batt(@intFromEnum(sq), b[i]);
    }
}
pub fn rookGenerateMoves(sq: squarel.e_square, magic: magic_entry, p_out: *[ROOK_MOVE_SIZE]u64) void {
    var b: [ROOK_MOVE_SIZE]u64 = undefined;
    const mask = rmask(@intFromEnum(sq));
    const n = chess.popcount(mask);
    for (0..ROOK_MOVE_SIZE) |i| {
        b[i] = index_to_uint64(@intCast(i), @intCast(n), mask);
        const j = rookMagicIndex(magic, b[i]);
        p_out[j] = ratt(@intFromEnum(sq), b[i]);
    }
}

pub fn initRookBishopMoves(p_record: *magicRecord) void {
    for (0..chess.N_SQUARES) |sq| {
        rookGenerateMoves(@enumFromInt(sq), p_record.rookMagic[sq], &(p_record.rookMoves[sq]));
        bishopGenerateMoves(@enumFromInt(sq), p_record.bishopMagic[sq], &(p_record.bishopMoves[sq]));
    }

    return;
}

pub fn rookMagicIndex(entry: magic_entry, blockers: u64) u64 {
    const _blockers = blockers & entry.mask;
    const hash = _blockers *% entry.magic;
    //return (hash >> (64 - ROOK_FIXED_BIT));
    return (hash >> 52);
}
pub fn bishopMagicIndex(entry: magic_entry, blockers: u64) u64 {
    const _blockers = blockers & entry.mask;
    const hash = _blockers *% entry.magic;
    //return (hash >> (64 - BISHOP_FIXED_BIT));
    return (hash >> 55);
}

pub fn getRookMoves(sq: squarel.e_square, blockers: u64) u64 {
    const magic = p_magicTable.rookMagic[@intFromEnum(sq)];
    const _blockers = blockers & magic.mask;
    const hash = _blockers *% magic.magic;
    const magic_index = (hash >> (64 - ROOK_FIXED_BIT));
    return p_magicTable.rookMoves[@intFromEnum(sq)][magic_index];
}

pub fn getBishopMoves(sq: squarel.e_square, blockers: u64) u64 {
    const magic = p_magicTable.bishopMagic[@intFromEnum(sq)];
    // precomputed then indexing removes the memcpy(of the entire table) of indexing then computing then indexing a second time leading to better perf
    // prev: p_magicTable.bishopMoves[@intFromEnum(sq)][(hash >> @intCast(64 - BISHOP_FIXED_BIT))]; or something similar
    // from: Compiler explorer

    const _blockers = blockers & magic.mask;
    const hash = _blockers *% magic.magic;
    const magic_index = (hash >> @intCast(64 - BISHOP_FIXED_BIT));
    return p_magicTable.bishopMoves[@intFromEnum(sq)][magic_index];
}

pub fn randomU64() u64 {
    const rand_u1: u64 = (randInt.int(u32)) & 0xFFFF;
    const rand_u2: u64 = (randInt.int(u32)) & 0xFFFF;
    const rand_u3: u64 = (randInt.int(u32)) & 0xFFFF;
    const rand_u4: u64 = (randInt.int(u32)) & 0xFFFF;
    return rand_u1 | (rand_u2 << 16) | (rand_u3 << 32) | (rand_u4 << 48);
}
pub fn getRandMagicFewBits() u64 {
    return randomU64() & randomU64() & randomU64();
}

const BitTable = [64]i8{ 63, 30, 3, 32, 25, 41, 22, 33, 15, 50, 42, 13, 11, 53, 19, 34, 61, 29, 2, 51, 21, 43, 45, 10, 18, 47, 1, 54, 9, 57, 0, 35, 62, 31, 40, 4, 49, 5, 52, 26, 60, 6, 23, 44, 46, 27, 56, 16, 7, 39, 48, 24, 59, 14, 12, 55, 38, 28, 58, 20, 37, 17, 36, 8 };
pub fn pop_1st_bit(bb: *u64) i8 {
    const _bb: u64 = bb.* ^ (bb.* - 1);
    const fold: u32 = @intCast((_bb & 0xffffffff) ^ (_bb >> 32));
    bb.* &= (bb.* - 1);
    return BitTable[(fold *% 0x783a9b23) >> 26];
}

pub fn index_to_uint64(index: u64, bits: i32, m: u64) u64 {
    var _m = m;
    var result: u64 = 0;
    for (0..@intCast(bits)) |i| {
        const j = pop_1st_bit(&_m);
        if ((index & (chess.ONE << @intCast(i))) != 0) {
            result |= (chess.ONE << @intCast(j));
        }
    }
    return result;
}

pub fn rmask(sq: usize) u64 {
    var result: u64 = 0;
    const rk: i32 = @intCast(sq / 8);
    const fl: i32 = @intCast(sq % 8);
    var r: i32 = undefined;
    var f: i32 = undefined;

    r = rk + 1;
    while (r < 7) : (r += 1) {
        result |= (chess.ONE << @intCast(fl + r * 8));
    }
    r = rk - 1;
    while (r >= 1) : (r -= 1) {
        result |= (chess.ONE << @intCast(fl + r * 8));
    }

    f = fl + 1;
    while (f < 7) : (f += 1) {
        result |= (chess.ONE << @intCast(f + rk * 8));
    }

    f = fl - 1;
    while (f >= 1) : (f -= 1) {
        result |= (chess.ONE << @intCast(f + rk * 8));
    }
    return result;
}

pub fn bmask(sq: usize) u64 {
    var result: u64 = 0;
    const rk: i32 = @intCast(sq / 8);
    const fl: i32 = @intCast(sq % 8);
    var r: i32 = undefined;
    var f: i32 = undefined;

    r = rk + 1;
    f = fl + 1;
    while (r <= 6 and f <= 6) : (r += 1) {
        result |= (chess.ONE << @intCast(f + r * 8));
        f += 1;
    }

    r = rk + 1;
    f = fl - 1;
    while (r <= 6 and f >= 1) : (r += 1) {
        result |= (chess.ONE << @intCast(f + r * 8));
        f -= 1;
    }
    r = rk - 1;
    f = fl + 1;
    while (r >= 1 and f <= 6) : (r -= 1) {
        result |= (chess.ONE << @intCast(f + r * 8));
        f += 1;
    }

    r = rk - 1;
    f = fl - 1;
    while (r >= 1 and f >= 1) : (r -= 1) {
        result |= (chess.ONE << @intCast(f + r * 8));
        f -= 1;
    }
    return result;
}

pub fn ratt(sq: usize, block: u64) u64 {
    var result: u64 = 0;
    const rk: i32 = @intCast(sq / 8);
    const fl: i32 = @intCast(sq % 8);
    var r: i32 = undefined;
    var f: i32 = undefined;

    r = rk + 1;
    while (r < 8) : (r += 1) {
        result |= (chess.ONE << @intCast(fl + r * 8));
        if (block & (chess.ONE << @intCast(fl + r * 8)) != 0) {
            break;
        }
    }
    r = rk - 1;
    while (r >= 0) : (r -= 1) {
        result |= (chess.ONE << @intCast(fl + r * 8));
        if (block & (chess.ONE << @intCast(fl + r * 8)) != 0) {
            break;
        }
    }

    f = fl + 1;
    while (f < 8) : (f += 1) {
        result |= (chess.ONE << @intCast(f + rk * 8));
        if (block & (chess.ONE << @intCast(f + rk * 8)) != 0) {
            break;
        }
    }

    f = fl - 1;
    while (f >= 0) : (f -= 1) {
        result |= (chess.ONE << @intCast(f + rk * 8));
        if (block & (chess.ONE << @intCast(f + rk * 8)) != 0) {
            break;
        }
    }
    return result;
}

pub fn batt(sq: usize, block: u64) u64 {
    var result: u64 = 0;
    const rk: i32 = @intCast(sq / 8);
    const fl: i32 = @intCast(sq % 8);
    var r: i32 = undefined;
    var f: i32 = undefined;

    r = rk + 1;
    f = fl + 1;
    while (r <= 7 and f <= 7) : (r += 1) {
        result |= (chess.ONE << @intCast(f + r * 8));
        if (block & (chess.ONE << @intCast(f + r * 8)) != 0) {
            break;
        }
        f += 1;
    }
    r = rk + 1;
    f = fl - 1;
    while (r <= 7 and f >= 0) : (r += 1) {
        result |= (chess.ONE << @intCast(f + r * 8));
        if (block & (chess.ONE << @intCast(f + r * 8)) != 0) {
            break;
        }
        f -= 1;
    }
    r = rk - 1;
    f = fl + 1;
    while (r >= 0 and f <= 7) : (r -= 1) {
        result |= (chess.ONE << @intCast(f + r * 8));
        if (block & (chess.ONE << @intCast(f + r * 8)) != 0) {
            break;
        }
        f += 1;
    }
    r = rk - 1;
    f = fl - 1;
    while (r >= 0 and f >= 0) : (r -= 1) {
        result |= (chess.ONE << @intCast(f + r * 8));
        if (block & (chess.ONE << @intCast(f + r * 8)) != 0) {
            break;
        }
        f -= 1;
    }
    return result;
}
pub fn bishop_find_magic(sq: squarel.e_square) !magic_entry {
    var mask: u64 = 0;
    var b: [BISHOP_MOVE_SIZE]u64 = undefined;
    var a: [BISHOP_MOVE_SIZE]u64 = undefined;
    var used: [BISHOP_MOVE_SIZE]u64 = undefined;
    var magic: u64 = undefined;
    var j: i32 = 0;

    mask = bmask(@intFromEnum(sq));
    const n = chess.popcount(mask);
    for (0..(chess.ONE << @intCast(n))) |i| {
        b[i] = index_to_uint64(@intCast(i), @intCast(n), mask);
        a[i] = batt(@intFromEnum(sq), b[i]);
    }
    for (0..100000000) |_| {
        magic = getRandMagicFewBits();
        if (chess.popcount((mask *% magic) & 0xFF00000000000000) < 6) {
            continue;
        }
        const _magic: magic_entry = .{ .magic = magic, .mask = mask };

        for (0..BISHOP_MOVE_SIZE) |i| {
            used[i] = 0;
        }
        var i: usize = 0;
        var fail: usize = 0;
        while ((fail == 0) and i < (chess.ONE << @intCast(n))) : (i += 1) {
            j = @intCast(bishopMagicIndex(_magic, b[i]));
            if (used[@intCast(j)] == chess.EMPTY) {
                used[@intCast(j)] = a[i];
            } else if (used[@intCast(j)] != a[i]) {
                fail = 1;
            }
        }
        if (fail == 0) {
            return _magic;
        }
    }
    std.debug.print("FAILED\n", .{});
    return magic_err.noMagicFound;
}
pub fn rook_find_magic(sq: squarel.e_square) !magic_entry {
    var mask: u64 = 0;
    var b: [ROOK_MOVE_SIZE]u64 = undefined;
    var a: [ROOK_MOVE_SIZE]u64 = undefined;
    var used: [ROOK_MOVE_SIZE]u64 = undefined;
    var magic: u64 = undefined;
    var j: i32 = 0;

    mask = rmask(@intFromEnum(sq));
    const n = chess.popcount(mask);
    for (0..(chess.ONE << @intCast(n))) |i| {
        b[i] = index_to_uint64(@intCast(i), @intCast(n), mask);
        a[i] = ratt(@intFromEnum(sq), b[i]);
    }
    for (0..100000000) |_| {
        magic = getRandMagicFewBits();
        if (chess.popcount((mask *% magic) & 0xFF00000000000000) < 6) {
            continue;
        }
        const _magic: magic_entry = .{ .magic = magic, .mask = mask };

        for (0..ROOK_MOVE_SIZE) |i| {
            used[i] = 0;
        }
        var i: usize = 0;
        var fail: usize = 0;
        while ((fail == 0) and i < (chess.ONE << @intCast(n))) : (i += 1) {
            j = @intCast(rookMagicIndex(_magic, b[i]));
            if (used[@intCast(j)] == chess.EMPTY) {
                used[@intCast(j)] = a[i];
            } else if (used[@intCast(j)] != a[i]) {
                fail = 1;
            }
        }
        if (fail == 0) {
            return _magic;
        }
    }
    std.debug.print("FAILED\n", .{});
    return magic_err.noMagicFound;
}

pub fn main() void {
    std.debug.print("const uint64 RMagic[64] = \n", .{});
    for (0..64) |sq| {
        const magic = rook_find_magic(@enumFromInt(sq)) catch |err| {
            std.debug.print("Err: {} no magic key found\n", .{err});
            @panic("");
        };
        std.debug.print("\t 0x{x},\n", .{magic.mask});
    }
    std.debug.print(";\n\n", .{});

    std.debug.print("const uint64 BMagic[64] = \n", .{});
    for (0..64) |sq| {
        const magic = bishop_find_magic(@enumFromInt(sq)) catch |err| {
            std.debug.print("Err: {} no magic key found\n", .{err});
            @panic("");
        };
        std.debug.print("\t 0x{x},\n", .{magic.mask});
    }
    std.debug.print(";\n\n", .{});

    return;
}
