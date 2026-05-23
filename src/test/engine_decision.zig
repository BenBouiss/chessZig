const chessl = @import("../chess.zig");
const moveGenl = @import("../move_generation.zig");
const movel = @import("../move.zig");
const squarel = @import("../square.zig");
const hashl = @import("../hashTable.zig");
const mainl = @import("../main.zig");
const perftl = @import("../search/perft.zig");
const enginel = @import("../engine.zig");

const std = @import("std");

const Board_state = chessl.Board_state;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
pub const GLOBAL_ALLOC = GPA.allocator();

//test "Mate in one" {
//    var engine: enginel.engine = try enginel.engine.init(GLOBAL_ALLOC);
//    engine.status.debugMode = true;
//    engine.executeBuffer("uci");
//    engine.executeBuffer("isready");
//    engine.executeBuffer("quit");
//    std.debug.print("[TEST]: Mate in one test passed\n", .{});
//    //defer @panic("broken test");
//}

const fenListMateOne = [_][]const u8{
    "position fen Q7/8/8/8/5K1k/8/8/8 w - - 0 0",
    "position fen q7/8/8/8/5k1K/8/8/8 b - - 0 0",
};

pub fn main() void {
    std.debug.print("[TEST]: Running the move generation checks\n", .{});
}
