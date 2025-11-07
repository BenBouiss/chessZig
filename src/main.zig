const rl = @import("raylib");
const chess = @import("chess.zig");
const exploration = @import("exploration.zig");
const std = @import("std");
const benchmark = @import("benchmark.zig");
const example = @import("raylib_ex.zig");

fn test_main_game() !void {
    chess.initRayAttacks();
    var game_state = chess.getBoardFromFen(chess.DEFAULT_FEN);
    game_state.setSeed(42);
    game_state.setPlayerType(chess.e_color.WHITE, exploration.e_playerType.Human);

    game_state.setPlayerType(chess.e_color.BLACK, exploration.e_playerType.Human);
    game_state.setPlayerSearchDepth(chess.e_color.BLACK, 4);

    chess.match_routine(&game_state);
}

pub fn main() anyerror!void {
    //try test_main_game();
    //try profiler.main();
    benchmark.test_benchmark();
    //try example.main();
}
