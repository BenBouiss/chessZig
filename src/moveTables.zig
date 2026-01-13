const chess = @import("chess.zig");
const magicl = @import("magic.zig");
const moveGenl = @import("move_generation.zig");
const squarel = @import("square.zig");

const std = @import("std");

const N_SQUARES = chess.N_SQUARES;
const NUMBER_PLAYER = chess.NUMBER_PLAYER;
const ONE = chess.ONE;
const e_color = chess.e_color;
const e_direction = chess.e_direction;
const squareInfo = squarel.squareInfo;

pub const cachedTables: AttackTable = AttackTable.init();
pub const cachedKingTable: kingTable = kingTable.init();

// https://www.chessprogramming.org/Square_Attacked_By#Obstructed
pub var arrRectangular: [64][64]u64 = undefined;

pub fn _initTables(verbose: bool) void {
    if (verbose) {
        std.debug.print("[PRE] Starting the table move build\n", .{});
    }
    initInbetween(&arrRectangular);

    if (verbose) {
        std.debug.print("[PRE] Finished\n", .{});
    }
}

pub const AttackTable = struct {
    rayAttacks: [64][8]u64 = undefined,

    pub fn init() AttackTable {
        var ret: AttackTable = .{};
        initRayAttackDiag(&ret);
        initRayAttacks(&ret);
        return ret;
    }
};
pub const kingTable = struct {
    KingAttack: [N_SQUARES]u64 = undefined,

    pub fn init() kingTable {
        var ret: kingTable = .{};
        initKingAttacks(&ret);
        return ret;
    }
};

pub fn initKingAttacks(table: *kingTable) void {
    for (0..N_SQUARES) |sq| {
        table.KingAttack[sq] = kingAttacks(@intCast(sq));
    }
}
pub fn kingAttacks(sq: i8) u64 {
    var ret: u64 = chess.EMPTY;
    const pos: u64 = (ONE << @intCast(sq));

    ret |= (pos >> 8);
    ret |= (pos << 8);

    if (pos & chess.notAFile != 0) {
        ret |= (pos >> 1);
        ret |= (pos << 7);
        ret |= (pos >> 9);
    }

    if (pos & chess.notHFile != 0) {
        ret |= (pos << 1);
        ret |= (pos << 9);
        ret |= (pos >> 7);
    }

    return ret;
}

pub fn initRayAttacks(table: *AttackTable) void {
    // https://www.chessprogramming.org/On_an_empty_Board formulas used
    var nort: u64 = (0x0101010101010100);
    var sout: u64 = (0x0080808080808080);
    var _sq: u6 = 0;
    for (0..N_SQUARES) |sq| {
        _sq = @intCast(sq);
        table.rayAttacks[sq][@intFromEnum(e_direction.NORTH)] = nort;
        table.rayAttacks[63 - sq][@intFromEnum(e_direction.SOUTH)] = sout;
        // optionnal can be computed on the fly
        table.rayAttacks[sq][@intFromEnum(e_direction.WEST)] = (ONE << _sq) - (ONE << (_sq & 56));
        table.rayAttacks[sq][@intFromEnum(e_direction.EAST)] = 2 * ((ONE << (_sq | 7)) - (ONE << _sq));
        nort <<= 1;
        sout >>= 1;
    }
}

pub fn initRayAttackDiag(table: *AttackTable) void {
    var delMask: u64 = undefined;
    const one: u64 = 1;

    var _sq: u6 = 0;
    var diag: u64 = undefined;
    var antidiag: u64 = undefined;

    for (0..N_SQUARES) |sq| {
        _sq = @intCast(sq);
        delMask = one << _sq;
        delMask = delMask ^ (delMask - 1);
        diag = chess.diagonalMask(@intCast(sq));
        antidiag = chess.antiDiagMask(@intCast(sq));

        table.rayAttacks[sq][@intFromEnum(e_direction.NORTHEAST)] = diag & ~delMask;
        table.rayAttacks[sq][@intFromEnum(e_direction.NORTHWEST)] = antidiag & ~delMask;
        table.rayAttacks[sq][@intFromEnum(e_direction.SOUTHEAST)] = antidiag & (delMask >> 1);
        table.rayAttacks[sq][@intFromEnum(e_direction.SOUTHWEST)] = diag & (delMask >> 1);
    }
}

pub fn initInbetween(table: *[64][64]u64) void {
    for (0..64) |x| {
        const fromBB = chess.ONE << @intCast(x);
        const fromSq: squareInfo = squareInfo.init(@enumFromInt(x));
        for (0..64) |y| {
            if (x == y) {
                table[x][y] = 0;
                continue;
            }
            const toBB = chess.ONE << @intCast(y);
            const toSq: squareInfo = squareInfo.init(@enumFromInt(y));
            if (fromSq.file == toSq.file) {
                if (x < y) {
                    table[x][y] = moveGenl.northOccl(fromBB, ~toBB) ^ fromBB;
                } else {
                    table[x][y] = moveGenl.southOccl(fromBB, ~toBB) ^ fromBB;
                }
            } else if (fromSq.rank == toSq.rank) {
                if (x < y) {
                    table[x][y] = moveGenl.eastOccl(fromBB, ~toBB) ^ fromBB;
                } else {
                    table[x][y] = moveGenl.westOccl(fromBB, ~toBB) ^ fromBB;
                }
            } else if (fromSq.diagonal == toSq.diagonal) {
                if (x < y) {
                    table[x][y] = moveGenl.northEastOccl(fromBB, ~toBB) ^ fromBB;
                } else {
                    table[x][y] = moveGenl.southWestOccl(fromBB, ~toBB) ^ fromBB;
                }
            } else if (fromSq.antidiagonal == toSq.antidiagonal) {
                if (x < y) {
                    table[x][y] = moveGenl.northWestOccl(fromBB, ~toBB) ^ fromBB;
                } else {
                    table[x][y] = moveGenl.southEastOccl(fromBB, ~toBB) ^ fromBB;
                }
            } else {
                table[x][y] = 0;
                continue;
            }
        }
    }
}
