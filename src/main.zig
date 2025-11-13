const rl = @import("raylib");
const chess = @import("chess.zig");
const exploration = @import("exploration.zig");
const std = @import("std");
const benchmark = @import("benchmark.zig");
const interfacel = @import("interface.zig");

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

pub fn main() anyerror!void {

    //const tracy_zone = ztracy.ZoneNC(@src(), "Compute Magic", 0x00_ff_00_00);
    //defer tracy_zone.End();
    //chess.initRayAttacks();
    //try test_main_game();
    //try profiler.main();
    //benchmark.test_benchmark();
    //test_bot_v_bot();
    interfacel.shell();
}
