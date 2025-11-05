const rl = @import("raylib");
const chess = @import("chess.zig");
const exploration = @import("exploration.zig");
const std = @import("std");
const benchmark = @import("benchmark.zig");
fn test_main_game() !void {
    chess.initRayAttacks();
    //var game_state = chess.getBoardFromFen(chess.DEFAULT_FEN);
    var game_state = chess.getBoardFromFen("r1bk1bnr/p2pppp1/2P4p/q7/7P/1P3N2/P1nPPPP1/RNBQKB1R w");
    game_state.setSeed(42);
    game_state.setPlayerType(chess.e_color.WHITE, exploration.e_playerType.SimpleBot);

    game_state.setPlayerType(chess.e_color.BLACK, exploration.e_playerType.DepthBot);
    game_state.setPlayerSearchDepth(chess.e_color.BLACK, 4);

    chess.match_routine(&game_state);
}

pub fn main() anyerror!void {
    try test_main_game();

    //benchmark.test_benchmark();
}
