// zig file for match orchestration in uci mode or more(?)

const chessl = @import("chess.zig");
const enginel = @import("engine.zig");
const interfacel = @import("interface.zig");

const std = @import("std");

const Board_state = chessl.Board_state;

const guiState = struct {
    chessState: Board_state,
    // will contains each send and receiv
    logs: std.ArrayList([]const u8),
};

const player = struct {
    searchDepth: u8 = 1,
};

pub fn main() void {}
