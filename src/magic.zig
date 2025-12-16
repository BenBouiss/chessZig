const build_options = @import("build_options");

pub const fastBitscan = build_options.fastBitscan;
const ignoreChecks = build_options.fastBitscan;
const useMagic = build_options.useMagic;

const chess = @import("chess.zig");
const squarel = @import("square.zig");
const mainl = @import("main.zig");

const std = @import("std");

const e_piece = chess.e_piece;
const GLOBAL_ALLOC = mainl.GLOBAL_ALLOC;

// TODO Implement fancy bitboard https://www.chessprogramming.org/Magic_Bitboards
// related(?) link: http://pradu.us/old/Nov27_2008/Buzz/

const magic_err = error{noMagicFound};
const MAX_MASK_SIZE: usize = 4096;
const N_SQUARES: usize = 64;

var rngIntGenerator = std.Random.DefaultPrng.init(42);
const randInt = rngIntGenerator.random();

const ROOK_MAGIC_MASK = [64]u64{ 0x101010101017e, 0x202020202027c, 0x404040404047a, 0x8080808080876, 0x1010101010106e, 0x2020202020205e, 0x4040404040403e, 0x8080808080807e, 0x1010101017e00, 0x2020202027c00, 0x4040404047a00, 0x8080808087600, 0x10101010106e00, 0x20202020205e00, 0x40404040403e00, 0x80808080807e00, 0x10101017e0100, 0x20202027c0200, 0x40404047a0400, 0x8080808760800, 0x101010106e1000, 0x202020205e2000, 0x404040403e4000, 0x808080807e8000, 0x101017e010100, 0x202027c020200, 0x404047a040400, 0x8080876080800, 0x1010106e101000, 0x2020205e202000, 0x4040403e404000, 0x8080807e808000, 0x1017e01010100, 0x2027c02020200, 0x4047a04040400, 0x8087608080800, 0x10106e10101000, 0x20205e20202000, 0x40403e40404000, 0x80807e80808000, 0x17e0101010100, 0x27c0202020200, 0x47a0404040400, 0x8760808080800, 0x106e1010101000, 0x205e2020202000, 0x403e4040404000, 0x807e8080808000, 0x7e010101010100, 0x7c020202020200, 0x7a040404040400, 0x76080808080800, 0x6e101010101000, 0x5e202020202000, 0x3e404040404000, 0x7e808080808000, 0x7e01010101010100, 0x7c02020202020200, 0x7a04040404040400, 0x7608080808080800, 0x6e10101010101000, 0x5e20202020202000, 0x3e40404040404000, 0x7e80808080808000 };
const ROOK_MAGIC_KEYS = [64]u64{ 0x80008850224004, 0x4040002000401000, 0x4880200280081000, 0x2080100088004580, 0x200020048104520, 0x1a00120001085410, 0x180020000800900, 0x4080005880002100, 0x2800280400060, 0x4c00401000200040, 0x4081802001100080, 0x23004810002100, 0x2808008000400, 0x2031000209000400, 0x2405000100040200, 0x845000049000086, 0x400808000400020, 0x420004030004000, 0xa0420018220080, 0x1550808008001001, 0x50010080100, 0x820808002000401, 0x8240010429108, 0xa512020004148161, 0xc4400080002c80, 0x240401080200080, 0x800100280200080, 0x2500201200400a00, 0x402000a00209004, 0xa582000404002010, 0x804020c00082910, 0x2c40b200004104, 0x400022800380, 0x100200040401000, 0x802000801002, 0x800800801001, 0xa1000801000410, 0x4002002004040010, 0x1004800100800200, 0x1088004d02001284, 0x2080804000208000, 0x2020052250044000, 0x120200011010042, 0x60800100182800a, 0x2004008040080800, 0x900040002008080, 0x200226110040028, 0x1288088061020004, 0x80002000400040, 0x240008041002100, 0xc0408010220200, 0x4230021084080080, 0x8200040008008080, 0x2a04020004008080, 0x222700042200a100, 0x802004081140200, 0x8040402200110082, 0x810e281400101, 0x200200840820012, 0x104a00208810c006, 0x2000830600406, 0x1000648140009, 0x200021018012094, 0x80200110402c0082 };
const ROOK_MAGIC_INDEX = [64]i8{ 12, 11, 11, 11, 11, 11, 11, 12, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 12, 11, 11, 11, 11, 11, 11, 12 };

const BISHOP_MAGIC_MASK = [64]u64{ 0x40201008040200, 0x402010080400, 0x4020100a00, 0x40221400, 0x2442800, 0x204085000, 0x20408102000, 0x2040810204000, 0x20100804020000, 0x40201008040000, 0x4020100a0000, 0x4022140000, 0x244280000, 0x20408500000, 0x2040810200000, 0x4081020400000, 0x10080402000200, 0x20100804000400, 0x4020100a000a00, 0x402214001400, 0x24428002800, 0x2040850005000, 0x4081020002000, 0x8102040004000, 0x8040200020400, 0x10080400040800, 0x20100a000a1000, 0x40221400142200, 0x2442800284400, 0x4085000500800, 0x8102000201000, 0x10204000402000, 0x4020002040800, 0x8040004081000, 0x100a000a102000, 0x22140014224000, 0x44280028440200, 0x8500050080400, 0x10200020100800, 0x20400040201000, 0x2000204081000, 0x4000408102000, 0xa000a10204000, 0x14001422400000, 0x28002844020000, 0x50005008040200, 0x20002010080400, 0x40004020100800, 0x20408102000, 0x40810204000, 0xa1020400000, 0x142240000000, 0x284402000000, 0x500804020000, 0x201008040200, 0x402010080400, 0x2040810204000, 0x4081020400000, 0xa102040000000, 0x14224000000000, 0x28440200000000, 0x50080402000000, 0x20100804020000, 0x40201008040200 };
const BISHOP_MAGIC_KEYS = [64]u64{ 0x4410021004009012, 0x6001a902008031, 0x8010041080302208, 0x944040084080040, 0xe024042008000000, 0x4042019008004010, 0x82091002516100, 0x103011080844023, 0x800042008120082, 0x810651000920080, 0x202804540c004000, 0x10208a03801010, 0x8000404202a1000, 0x10c20804840201, 0x4008010130022044, 0x460080845002, 0x44102008204800a0, 0x1020020882008220, 0x1060802040010, 0x48240c04011080, 0x14002a10221010, 0x2601008200808400, 0x448944c042c3200, 0x222100821020, 0x5408041343044803, 0x2001080204280800, 0x1010010004600, 0x10104054040002, 0x828840038802000, 0x104a0009010110, 0x11c0820089081290, 0x2010900820080c0, 0x408844000043830, 0x488200008828d, 0x8022a0108380800, 0x20081080082, 0x84008400020102, 0x1031080022020200, 0x1084200009608, 0x820040009408, 0xc500900808082002, 0x1180290000204, 0x1001090048200, 0x900010411002800, 0x20100210110200, 0x86029000804304, 0x2481829000080, 0x10211051000080, 0x1001042104400004, 0x41040201040200, 0x8000410080900400, 0x8040400020a80080, 0x80804005044000, 0x18094208020090, 0x46c0040102120100, 0xa04700485010580, 0x16004202100280, 0xa02208040460, 0x88b1406250441012, 0x190200420204, 0x1000000090202200, 0x30180400c48328a, 0x8042042043118, 0x100220040c014848 };
const BISHOP_MAGIC_INDEX = [64]i8{ 6, 5, 5, 5, 5, 5, 5, 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 7, 7, 7, 7, 5, 5, 5, 5, 7, 9, 9, 7, 5, 5, 5, 5, 7, 9, 9, 7, 5, 5, 5, 5, 7, 7, 7, 7, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 5, 5, 5, 5, 5, 5, 6 };

const magic_entry = struct {
    mask: u64 = 0,
    magic: u64 = 0,
    index_bit: i8 = 0,
};

//uint64 BISHOP_MOVES [64][4096];

pub var magicTable: magicRecord = undefined;
pub const p_magicTable: *magicRecord = &magicTable;

pub const magicRecord = struct {
    isInitialized: bool = false,
    rookMagic: [N_SQUARES]magic_entry = std.mem.zeroes([N_SQUARES]magic_entry),
    bishopMagic: [N_SQUARES]magic_entry = std.mem.zeroes([N_SQUARES]magic_entry),
    rookMoves: [N_SQUARES][MAX_MASK_SIZE]u64,
    bishopMoves: [N_SQUARES][MAX_MASK_SIZE]u64,
    pub fn init() magicRecord {
        const rook = undefined;
        const bishop = undefined;

        return .{ .isInitialized = true, .rookMoves = rook, .bishopMoves = bishop };
    }
};
pub fn _initMagic(p_magic: *magicRecord) void {
    if (comptime useMagic) {
        std.debug.print("Building using magic move gen!\n", .{});
    }
    const _start = std.time.milliTimestamp();
    std.debug.print("[PRE] Starting the search for magic keys \n", .{});
    p_magic.* = magicRecord.init();

    //initRookBishopMagic(&ret);
    initRookBishopMagicCached(p_magic);
    initRookBishopMoves(p_magic);

    std.debug.print("[PRE] Finished (elasped time : {d} ms) \n", .{((std.time.milliTimestamp() - _start))});
    return;
}

pub fn initMagic() magicRecord {
    std.debug.print("Ben\n", .{});
    const _start = std.time.milliTimestamp();
    std.debug.print("[PRE] Starting the search for magic keys \n", .{});

    var ret: magicRecord = magicRecord.init();

    initRookBishopMagicCached(&ret);
    initRookBishopMoves(&ret);

    std.debug.print("[PRE] Finished (elasped time : {d} ms) \n", .{((std.time.milliTimestamp() - _start))});
    return ret;
}
pub fn initRookBishopMagicCached(p_record: *magicRecord) void {
    for (0..64) |sq| {
        const magic: magic_entry = .{ .mask = ROOK_MAGIC_MASK[sq], .magic = ROOK_MAGIC_KEYS[sq], .index_bit = ROOK_MAGIC_INDEX[sq] };
        p_record.rookMagic[sq] = magic;
    }
    for (0..64) |sq| {
        const magic: magic_entry = .{ .mask = BISHOP_MAGIC_MASK[sq], .magic = BISHOP_MAGIC_KEYS[sq], .index_bit = BISHOP_MAGIC_INDEX[sq] };
        p_record.bishopMagic[sq] = magic;
    }
}

pub fn generateMoves(piece: e_piece, sq: squarel.e_square, magic: magic_entry, p_out: *[MAX_MASK_SIZE]u64) void {
    var b: [MAX_MASK_SIZE]u64 = undefined;
    var mask: u64 = 0;
    if (piece == .nWhiteRook or piece == .nBlackRook) {
        mask = rmask(@intFromEnum(sq));
    } else if (piece == .nWhiteBishop or piece == .nBlackBishop) {
        mask = bmask(@intFromEnum(sq));
    }
    const n = chess.l_popcount(mask);
    for (0..4096) |i| {
        b[i] = index_to_uint64(@intCast(i), @intCast(n), mask);
        const j = magicIndex(magic, b[i]);
        if (piece == .nWhiteRook or piece == .nBlackRook) {
            p_out[j] = ratt(@intFromEnum(sq), b[i]);
        } else if (piece == .nWhiteBishop or piece == .nBlackBishop) {
            p_out[j] = batt(@intFromEnum(sq), b[i]);
        }
    }
}

pub fn initRookBishopMoves(p_record: *magicRecord) void {
    for (0..64) |sq| {
        generateMoves(.nWhiteRook, @enumFromInt(sq), p_record.rookMagic[sq], &(p_record.rookMoves[sq]));
        generateMoves(.nWhiteBishop, @enumFromInt(sq), p_record.bishopMagic[sq], &(p_record.bishopMoves[sq]));
    }

    return;
}

pub fn initRookBishopMagic(p_record: *magicRecord) void {
    for (0..64) |sq| {
        const magic = find_magic(@enumFromInt(sq), RBits[sq], .nWhiteRook) catch |err| {
            std.debug.print("Err: {} no magic key found\n", .{err});
            @panic("");
        };
        std.debug.print("[{d}] magic: 0x{x}, mask: 0x{x}, bits: {d}, \n", .{ sq, magic.magic, magic.mask, magic.index_bit });
        p_record.rookMagic[sq] = magic;
    }
    for (0..64) |sq| {
        const magic = find_magic(@enumFromInt(sq), BBits[sq], .nWhiteBishop) catch |err| {
            std.debug.print("Err: {} no magic key found\n", .{err});
            @panic("");
        };
        std.debug.print("[{d}] magic: 0x{x}, mask: 0x{x}, bits: {d}, \n", .{ sq, magic.magic, magic.mask, magic.index_bit });
        p_record.bishopMagic[sq] = magic;
    }
}

pub fn magicIndex(entry: magic_entry, blockers: u64) usize {
    const _blockers = blockers & entry.mask;
    const hash = _blockers *% entry.magic;
    return @intCast(hash >> @intCast(64 - entry.index_bit));
}

pub fn getRookMoves(sq: squarel.e_square, blockers: u64) u64 {
    //if (@intFromEnum(sq) > 63) {
    //    std.debug.print("Found a invalid sq of value: {d}\n", .{@intFromEnum(sq)});
    //}
    const magic = p_magicTable.rookMagic[@intFromEnum(sq)];
    const magic_index = magicIndex(magic, blockers);
    return p_magicTable.rookMoves[@intFromEnum(sq)][magic_index];
}

pub fn getBishopMoves(sq: squarel.e_square, blockers: u64) u64 {
    const magic = p_magicTable.bishopMagic[@intFromEnum(sq)];
    // precomputed then indexing removes the memcpy of indexing then computing then indexing again leading to better perf
    // from: Compiler explorer
    const magic_index = magicIndex(magic, blockers);
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

pub fn find_magic(sq: squarel.e_square, m: i8, piece: e_piece) !magic_entry {
    var mask: u64 = 0;
    var b: [MAX_MASK_SIZE]u64 = undefined;
    var a: [MAX_MASK_SIZE]u64 = undefined;
    var used: [MAX_MASK_SIZE]u64 = undefined;
    var magic: u64 = undefined;
    var j: i32 = 0;

    if (piece == .nWhiteRook or piece == .nBlackRook) {
        mask = rmask(@intFromEnum(sq));
    } else if (piece == .nWhiteBishop or piece == .nBlackBishop) {
        mask = bmask(@intFromEnum(sq));
    }
    const n = chess.l_popcount(mask);
    for (0..(chess.ONE << @intCast(n))) |i| {
        b[i] = index_to_uint64(@intCast(i), @intCast(n), mask);
        if (piece == .nWhiteRook or piece == .nBlackRook) {
            a[i] = ratt(@intFromEnum(sq), b[i]);
        } else if (piece == .nWhiteBishop or piece == .nBlackBishop) {
            a[i] = batt(@intFromEnum(sq), b[i]);
        }
    }
    for (0..100000000) |_| {
        magic = getRandMagicFewBits();
        if (chess.l_popcount((mask *% magic) & 0xFF00000000000000) < 6) {
            continue;
        }
        const _magic: magic_entry = .{ .magic = magic, .index_bit = @intCast(m), .mask = mask };

        for (0..MAX_MASK_SIZE) |i| {
            used[i] = 0;
        }
        var i: usize = 0;
        var fail: usize = 0;
        while ((fail == 0) and i < (chess.ONE << @intCast(n))) : (i += 1) {
            j = @intCast(magicIndex(_magic, b[i]));
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
    return .{ .index_bit = 0, .magic = 0, .mask = 0 };
}

const RBits = [64]i8{ 12, 11, 11, 11, 11, 11, 11, 12, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 11, 12, 11, 11, 11, 11, 11, 11, 12 };

const BBits = [64]i8{ 6, 5, 5, 5, 5, 5, 5, 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 7, 7, 7, 7, 5, 5, 5, 5, 7, 9, 9, 7, 5, 5, 5, 5, 7, 9, 9, 7, 5, 5, 5, 5, 7, 7, 7, 7, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 5, 5, 5, 5, 5, 5, 6 };

pub fn main() void {
    std.debug.print("const uint64 RMagic[64] = \n", .{});
    for (0..64) |sq| {
        const magic = find_magic(@enumFromInt(sq), RBits[sq], .nWhiteRook) catch |err| {
            std.debug.print("Err: {} no magic key found\n", .{err});
            @panic("");
        };
        std.debug.print("  {x},\n", .{magic.magic});
    }
    std.debug.print(";\n\n", .{});

    std.debug.print("const uint64 BMagic[64] = \n", .{});
    for (0..64) |sq| {
        const magic = find_magic(@enumFromInt(sq), BBits[sq], .nWhiteBishop) catch |err| {
            std.debug.print("Err: {} no magic key found\n", .{err});
            @panic("");
        };
        std.debug.print("  {x},\n", .{magic.magic});
    }
    std.debug.print(";\n\n", .{});

    return;
}
