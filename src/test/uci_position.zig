const chessl = @import("../chess.zig");
const utilsl = @import("../utils.zig");
const mainl = @import("../main.zig");

const std = @import("std");

test "apply moves" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    mainl.initAll(arena, false);
    var tmp = try chessl.getBoardFromFen(chessl.DEFAULT_FEN);
    try chessl.applyUciMoves(&tmp, "position startpos moves a2a4 a7a5 b2b4 a5b4 c2c4 b4c3 d2c3 a8a4 a1a4 b7b5", false);
    chessl.sanityCheckBoardState(&tmp);

    tmp = try chessl.getBoardFromFen(chessl.DEFAULT_FEN);
    try chessl.applyUciMoves(&tmp, "position startpos moves d2d3 a7a5 b2b3 a5a4 b3a4 a8a4 b1c3 a4a2 a1a2 b7b5 a2a8 b5b4 c3a4 b4b3 a8b8 b3c2 d1c2 c7c5 c2c5 d7d5 c5c6 c8d7 b8d8 e8d8 c6b6 d8c8 c1a3 d7a4 b6a6 c8c7 a6a4 d5d4 a3c5 e7e5 a4a7 c7c6 a7b6 c6d5 e2e4", false);
    chessl.sanityCheckBoardState(&tmp);
}

test "fen" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    mainl.initAll(arena, false);
    var tmp = try chessl.getBoardFromFen(chessl.DEFAULT_FEN);
    try std.testing.expect(true);
    var str = tmp.get_fen();
    var comp = utilsl.trimStr(&str);
    try std.testing.expect(utilsl.equal(u8, comp, chessl.DEFAULT_FEN));

    const def_noCastle = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 0";
    tmp = try chessl.getBoardFromFen(def_noCastle);
    str = tmp.get_fen();
    comp = utilsl.trimStr(&str);

    try std.testing.expect(utilsl.equal(u8, comp, def_noCastle));
}

pub fn main() void {}
