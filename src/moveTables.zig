const chess = @import("chess.zig");
const magicl = @import("magic.zig");
const std = @import("std");

const N_SQUARES = chess.N_SQUARES;
const NUMBER_PLAYER = chess.NUMBER_PLAYER;
const ONE = chess.ONE;
const e_color = chess.e_color;
const e_direction = chess.e_direction;

pub const cachedTables: AttackTable = AttackTable.init();

pub const AttackTable = struct {
    RookAttack: [N_SQUARES]u64 = undefined,
    BishopAttack: [N_SQUARES]u64 = undefined,
    QueenAttack: [N_SQUARES]u64 = undefined,
    //PawnAttack: [N_SQUARES]u64 = undefined,
    //KnightAttack: [N_SQUARES]u64 = undefined,
    KingAttack: [N_SQUARES]u64 = undefined,
    SimplePawnAttack: [NUMBER_PLAYER][N_SQUARES]u64 = undefined,
    rayAttacks: [64][8]u64 = undefined,

    pub fn init() AttackTable {
        var ret: AttackTable = .{};
        initRayAttackDiag(&ret);
        initRayAttacks(&ret);
        initMaskAttacks(&ret);
        return ret;
    }
    pub fn print(self: AttackTable) void {
        std.debug.print("Ben \n", .{});
        chess.print_bitboard(self.RookAttack[10]);
    }
};

pub fn initMaskAttacks(table: *AttackTable) void {
    var diagsMask: [N_SQUARES][2]u64 = undefined;
    for (0..N_SQUARES) |sq| {
        diagsMask[sq][0] = chess.diagonalMask(@intCast(sq));
        diagsMask[sq][1] = chess.antiDiagMask(@intCast(sq));
        table.BishopAttack[sq] = (diagsMask[sq][0] | diagsMask[sq][1]);
        table.QueenAttack[sq] = (diagsMask[sq][0] | diagsMask[sq][1]);

        table.RookAttack[sq] = table.rayAttacks[sq][0] | table.rayAttacks[sq][1] | table.rayAttacks[sq][2] | table.rayAttacks[sq][3];

        table.QueenAttack[sq] |= table.RookAttack[sq];
        table.SimplePawnAttack[@intFromEnum(e_color.WHITE)][sq] = chess.simplePawnMask(@enumFromInt(sq), e_color.WHITE);
        table.SimplePawnAttack[@intFromEnum(e_color.BLACK)][sq] = chess.simplePawnMask(@enumFromInt(sq), e_color.BLACK);
        table.KingAttack[sq] = chess.kingAttacks(@intCast(sq));
    }
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
