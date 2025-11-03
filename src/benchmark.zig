const chess = @import("chess.zig");
const exploration = @import("exploration.zig");
const std = @import("std");
pub fn test_benchmark() void {
    chess.initRayAttacks();
    var game_state = chess.getBoardFromFen(chess.DEFAULT_FEN);
    game_state.setSeed(42);
    exploration.nodeExplorationBenchmark(&game_state, 8);
}

pub fn main() !void {
    test_benchmark();
}
