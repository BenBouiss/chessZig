const chessl = @import("../chess.zig");
const moveGenl = @import("../move_generation.zig");
const movel = @import("../move.zig");
const squarel = @import("../square.zig");
const benchmarkl = @import("../benchmark.zig");
const mainl = @import("../main.zig");

const std = @import("std");

const Board_state = chessl.Board_state;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

test "apply moves" {
    mainl.initAll();
    var tmp: Board_state = try chessl.getBoardFromFen(GLOBAL_ALLOC, chessl.DEFAULT_FEN);
    try chessl.applyUciMoves(&tmp, "position startpos moves a2a4 a7a5 b2b4 a5b4 c2c4 b4c3 d2c3 a8a4 a1a4 b7b5", GLOBAL_ALLOC, true);
    chessl.sanityCheckBoardState(&tmp);

    tmp = try chessl.getBoardFromFen(GLOBAL_ALLOC, chessl.DEFAULT_FEN);
    try chessl.applyUciMoves(&tmp, "position startpos moves d2d3 a7a5 b2b3 a5a4 b3a4 a8a4 b1c3 a4a2 a1a2 b7b5 a2a8 b5b4 c3a4 b4b3 a8b8 b3c2 d1c2 c7c5 c2c5 d7d5 c5c6 c8d7 b8d8 e8d8 c6b6 d8c8 c1a3 d7a4 b6a6 c8c7 a6a4 d5d4 a3c5 e7e5 a4a7 c7c6 a7b6 c6d5 e2e4", GLOBAL_ALLOC, true);
    chessl.sanityCheckBoardState(&tmp);
}

pub fn main() void {
    //std.debug.print("[TEST]: Running the move generation checks\n", .{});
}
