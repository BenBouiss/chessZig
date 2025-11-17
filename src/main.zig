const rl = @import("raylib");
const chess = @import("chess.zig");
const exploration = @import("exploration.zig");
const std = @import("std");
const benchmark = @import("benchmark.zig");
const interfacel = @import("interface.zig");
const magicl = @import("magic.zig");
const moveTablel = @import("moveTables.zig");

const squarel = @import("square.zig");

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
    const bb1 = magicl.getRookMoves(p_magicTable, .e4, game_state.occupiedBB);
    const bb2 = magicl.getBishopMoves(p_magicTable, .a3, game_state.occupiedBB);
    chess.print_bitboard(game_state.occupiedBB);
    chess.print_bitboard(bb1);
    chess.print_bitboard(bb2);
}

pub fn main() anyerror!void {
    //test
    //magicl.main();
    var magicTable = magicl.initMagic();
    test_magic(&magicTable);
    //const tracy_zone = ztracy.ZoneNC(@src(), "Compute Magic", 0x00_ff_00_00);
    //defer tracy_zone.End();
    //chess.initRayAttacks();
    //try test_main_game();
    //try profiler.main();
    //benchmark.test_benchmark();
    //test_bot_v_bot();
    //interfacel.shell();
    //magicl.magicTables.print();

    //moveTablel.cachedTables.print();
}
