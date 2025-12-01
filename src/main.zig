const std = @import("std");
const rl = @import("raylib");

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

const chess = @import("chess.zig");
const exploration = @import("exploration.zig");
const benchmark = @import("benchmark.zig");
const interfacel = @import("interface.zig");
const magicl = @import("magic.zig");
const moveTablel = @import("moveTables.zig");
const hashl = @import("hashTable.zig");
const squarel = @import("square.zig");

const build_options = @import("build_options");
const useDebug = build_options.useDebug;

fn test_main_game() !void {
    var game_state = chess.getBoardFromFen(chess.DEFAULT_FEN);
    game_state.setSeed(42);
    game_state.setPlayerType(chess.e_color.WHITE, exploration.e_playerType.Human);

    game_state.setPlayerType(chess.e_color.BLACK, exploration.e_playerType.Human);
    game_state.setPlayerSearchDepth(chess.e_color.BLACK, 4);

    chess.match_routine(&game_state);
}

fn test_bot_v_bot() void {
    var game_state = chess.getBoardFromFen(chess.DEFAULT_FEN);
    game_state.setSeed(42);
    game_state.setPlayerType(chess.e_color.WHITE, exploration.e_playerType.Bot);
    game_state.setPlayerSearcType(.WHITE, .Random);

    game_state.setPlayerType(chess.e_color.BLACK, exploration.e_playerType.Bot);
    game_state.setPlayerSearcType(.BLACK, .DepthBot);
    game_state.setPlayerSearchDepth(.BLACK, 5);
    game_state.setPlayerHeuristicType(.BLACK, .Simple);
    chess.match_routine(&game_state);
}

fn test_magic(p_magicTable: *magicl.magicRecord) void {
    var game_state = chess.getBoardFromFen(chess.DEFAULT_FEN);
    game_state.setSeed(42);
    chess.print_boardstate(&game_state);
    const bb1 = magicl.getRookMoves(.e4, game_state.occupiedBB);
    const bb2 = magicl.getBishopMoves(.a3, game_state.occupiedBB);
    chess.print_bitboard(game_state.occupiedBB);
    chess.print_bitboard(bb1);
    chess.print_bitboard(bb2);
    _ = p_magicTable;
}

fn test_moveTable() void {
    chess.print_bitboard(chess.inBetween(.a1, .a8));
    chess.print_bitboard(chess.inBetween(.f1, .f8));

    chess.print_bitboard(chess.inBetween(.h4, .a4));
    chess.print_bitboard(chess.inBetween(.a8, .h8));

    chess.print_bitboard(chess.inBetween(.a1, .h8));
    chess.print_bitboard(chess.inBetween(.a8, .h1));
}

pub fn initAll() void {
    magicl._initMagic(&magicl.magicTable);
    hashl._initHash(42, 19);
    moveTablel._initTables();
    if (comptime useDebug) {
        std.debug.print("[PRE] Building using the useDebug flag\n", .{});
    }
}

pub fn main() anyerror!void {
    initAll();
    interfacel.shell();
    //benchmark.test_benchmark();
    //magicl.magicTables.print();
    //try chess.main();
    hashl.hashTable.free(GLOBAL_ALLOC);
}
