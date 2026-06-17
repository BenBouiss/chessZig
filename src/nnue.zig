const std = @import("std");

const typel = @import("type.zig");
const boardl = @import("board.zig");
const chessl = @import("chess.zig");
const heuristicl = @import("heuristic.zig");
const stringl = @import("string.zig");
const filel = @import("file.zig");
const configl = @import("config.zig");
const utilsl = @import("utils.zig");
const mainl = @import("main.zig");

const scoreType = typel.scoreType;

pub const networkScale = 400;
pub const qA = 255;
pub const qB = 64;
pub const HL_SIZE = 1024; // 1024 or 3072 per the site(?)
pub const INPUT_SIZE = 768; // 6 pieces x 2 colors x 64 sqs

//https://www.chessprogramming.org/NNUE
pub const network = struct {
    accWeights: [INPUT_SIZE][HL_SIZE]i16 = std.mem.zeroes([INPUT_SIZE][HL_SIZE]i16),
    accBiases: [HL_SIZE]i16 = std.mem.zeroes([HL_SIZE]i16),

    outputWeights: [2 * HL_SIZE]i16 = std.mem.zeroes([2 * HL_SIZE]i16),
    outputBiase: i16 = 0,
};
pub const accumulator = struct {
    values: [HL_SIZE]i16 = std.mem.zeroes([HL_SIZE]i16),
    pub fn addNetwork(self: *accumulator, n: *network, index: usize) void {
        for (0..HL_SIZE) |i| {
            self.values[i] += n.accWeights[index][i];
        }
    }
    pub fn subNetwork(self: *accumulator, n: *network, index: usize) void {
        for (0..HL_SIZE) |i| {
            self.values[i] -= n.accWeights[index][i];
        }
    }
};
pub const accumulatorPair = struct {
    w: accumulator = .{},
    b: accumulator = .{},
};

pub inline fn networkIndex(piece: typel.e_pieceType, color: typel.e_color, sq: typel.e_square) usize {
    return @as(usize, @intFromEnum(color)) * 64 * 6 + @as(usize, @intFromEnum(piece)) * 64 + @as(usize, @intFromEnum(sq));
}
pub fn networkIndexPerspective(piece: typel.e_pieceType, color: typel.e_color, sq: typel.e_square, perspective: typel.e_color) usize {
    var side: usize = @intFromEnum(color);
    var _sq: usize = @intFromEnum(sq);
    if (perspective == .BLACK) {
        side = 1 - side;
        _sq = chessl.flipSq(_sq);
    }
    return side * 64 * 6 + @intFromEnum(piece) * 64 + _sq;
}

// easier to vectorize compared to below
//pub inline fn activationFunc(val: i16) i16 {
//    return std.math.clamp(val, 0, qA);
//}
pub inline fn activationFunc(val: i16) i32 {
    return std.math.pow(i32, std.math.clamp(val, 0, qA), 2);
}
pub fn forward(n: *const network, stm_acc: *const accumulator, nstm_acc: *const accumulator) i32 {
    var ret: i32 = 0;
    for (0..HL_SIZE) |i| {
        ret += activationFunc(stm_acc.values[i]) * @as(i32, @intCast(n.outputWeights[i]));
        ret += activationFunc(nstm_acc.values[i]) * @as(i32, @intCast(n.outputWeights[i + HL_SIZE]));
    }
    // only used with the activ that uses the pow(2) SCReLU
    ret /= qA;
    ret *= networkScale;
    ret /= (qA * qB);
    return ret;
}
pub const nnueEntry = struct {
    //
    //seval: i32 = 0,
    // phase value describing how far the game progressed
    // turn of the extracted fen
    turn: bool = true,

    eval: scoreType = 0,
    // 0.0 black win, 0.5 draw, 1.0 white win
    result: f32 = -1,
    phase: scoreType = 0,

    // either 0 or 1
    input: [INPUT_SIZE]u8 = @splat(0),
    valid: bool = true,
    pub fn set_fen(p_self: *nnueEntry, alloc: std.mem.Allocator, fen: []const u8, result: f32) !void {
        p_self.result = result;
        var board = chessl.getBoardFromFen(fen) catch {
            std.debug.print("[ERROR] set_fen: error while using the fen: '{s}'\n", .{fen});
            @panic("");
        };
        defer board.free(alloc);
        const phase: scoreType = @intCast(board.getPhase());

        p_self.phase = @divFloor((256 * (24 - phase)), 24);

        p_self.turn = board.whiteToMove();
        p_self.valid = heuristicl.isBoardTexelValid(&board);
        if (!p_self.valid) {
            return heuristicl.texel_err.board_err;
        }
        p_self.input = nnueInputFromState(&board);
    }
    pub fn print(p_self: *nnueEntry) void {
        //
        std.debug.print("Printing texelEntry: \n", .{});
        std.debug.print("Res: {d}\n", .{p_self.result});
        //std.debug.print("Res: {d}, seval: {d}\n", .{ p_self.result, p_self.seval });
        std.debug.print("Coefficients array: ", .{});
        p_self.tuples.print();
    }
};
pub fn nnueInputFromState(p_state: *const boardl.boardState) [INPUT_SIZE]u8 {
    var ret: [INPUT_SIZE]u8 = @splat(0);
    for (0..chessl.N_SQUARES) |i| {
        const p = p_state.getPiece(@intCast(i));
        if (p == .nEmptySquare) {
            continue;
        }
        const _p = chessl.e_pieceTo_e_pieceType(p);
        const white: bool = chessl.getColorFromPiece(p);
        const w: typel.e_color = if (white) .WHITE else .BLACK;
        const index = networkIndex(_p, w, @enumFromInt(i));
        ret[index] = 1;
    }
    return ret;
}
pub fn getEntriesFromFile(alloc: std.mem.Allocator, path: stringl.string, nSkips: usize) ![]nnueEntry {
    var tokens = try filel.getTokensFromFileAlloc(alloc, path._slice(), '\n', configl.N_POSITIONS, nSkips);
    var entries: []nnueEntry = try alloc.alloc(nnueEntry, configl.N_POSITIONS);

    for (0..tokens.items.len) |i| {
        var s = tokens.items[i];
        var tok = try s.split(alloc, ' ');
        defer tok.deinit(alloc);
        const outcome = try s.extractFromBounds("[", "]");
        var foutcome: f32 = 0;
        if (utilsl.contains(outcome, "0.5", .ignoreCase)) {
            foutcome = 0.5;
        } else if (utilsl.contains(outcome, "1.0", .ignoreCase)) {
            foutcome = 1;
        }
        entries[i].set_fen(alloc, s._slice(), foutcome) catch {
            continue;
        };
    }
    defer stringl.freeArrayList_string(alloc, &tokens);
    return entries;
}
const csvHeader = struct {
    n_weights: usize,
    pub fn format(self: csvHeader, writer: *std.Io.Writer) !void {
        for (0..self.n_weights) |i| {
            try writer.print("Weight_{d},", .{i});
        }
        try writer.print("Phase, Outcome", .{});
    }
};
const csvBody = struct {
    entry: *nnueEntry = undefined,
    pub fn format(self: csvBody, writer: *std.Io.Writer) !void {
        for (0..self.entry.input.len) |i| {
            try writer.print("{d},", .{self.entry.input[i]});
        }

        try writer.print("{d},{d}", .{ self.entry.phase, self.entry.result });
    }
};
pub fn createEmptyFile(alloc: std.mem.Allocator, path: stringl.string) !void {
    // format
    // Coeff_1_w, Coeff_1_b, ...., Coeff_n_w, Coeff_n_b, phase, outcome)
    // <--comma separated values--->
    //const file = try std.fs.cwd().createFile(path._slice(), .{ .read = true });
    const file = try std.Io.Dir.createFile(.cwd(), mainl.getGlobalIo(), path._slice(), .{ .read = true });
    defer file.close(mainl.getGlobalIo());

    // save header
    const headerTemplate: csvHeader = .{ .n_weights = INPUT_SIZE };

    const header_str = try std.fmt.allocPrint(alloc, "{f}\n", .{headerTemplate});
    defer alloc.free(header_str);
    _ = file.writeStreamingAll(mainl.getGlobalIo(), header_str) catch unreachable;
}
fn saveCoefficientToFile(alloc: std.mem.Allocator, entries: []nnueEntry, path: stringl.string) !void {
    // <--comma separated values--->
    //const file = try std.fs.cwd().openFile(path._slice(), .{ .mode = .write_only });
    const file = try std.Io.Dir.openFile(.cwd(), mainl.getGlobalIo(), path._slice(), .{ .mode = .write_only });
    defer file.close(mainl.getGlobalIo());

    const print_freq: usize = 10000;
    for (0..entries.len) |i| {
        if (i % print_freq == 0) {
            std.debug.print("{d} / {d} \r", .{ i, entries.len });
        }
        if (!entries[i].valid) {
            continue;
        }
        const body: csvBody = .{ .entry = &entries[i] };
        const body_str = try std.fmt.allocPrint(alloc, "{f}\n", .{body});
        defer alloc.free(body_str);
        _ = file.writePositionalAll(mainl.getGlobalIo(), body_str[0..body_str.len], file.length(mainl.getGlobalIo()) catch unreachable) catch unreachable;
    }
}
pub fn test_save(alloc: std.mem.Allocator, dataPath: stringl.string, savePath: stringl.string) !void {
    //
    const allEntries = try filel.getFileLineSize(alloc, dataPath._slice());
    var remainingEntries = allEntries;
    std.debug.print("[DEBUG] test_save: number of lines found: {d}\n", .{allEntries});

    try createEmptyFile(alloc, savePath);
    var skips: usize = 0;
    while (remainingEntries != 0) {
        std.debug.print("Remaining entries: {d} \n", .{remainingEntries});
        remainingEntries = remainingEntries -| configl.N_POSITIONS;
        const entries = try getEntriesFromFile(alloc, dataPath, skips);

        printEntriesInfo(entries);
        defer alloc.free(entries);
        try saveCoefficientToFile(alloc, entries, savePath);
        skips += configl.N_POSITIONS;
    }
}
fn printEntriesInfo(entries: []const nnueEntry) void {
    var buffer: [3]usize = .{ 0, 0, 0 };
    var validBuffer: [2]usize = .{ 0, 0 };
    for (0..entries.len) |i| {
        buffer[@intFromFloat(entries[i].result * 2)] += 1;
        validBuffer[@intFromBool(entries[i].valid)] += 1;
    }
    std.debug.print("[DEBUG] printEntriesInfo: Breakdown of entries found 0: {d}, 0.5: {d}, 1: {d}\n valid: {d} non valid: {d}\n\n", .{ buffer[0], buffer[1], buffer[2], validBuffer[1], validBuffer[0] });
}
pub fn main(alloc: std.mem.Allocator) !void {
    //mainl.initAll(alloc, false);
    var path: stringl.string = try stringl.string.initFromSlice(alloc, "opening/E12.33-1M-D12-Resolved.book");
    var savePath: stringl.string = try stringl.string.initFromSlice(alloc, "out/logs/nnue_test.csv");
    defer path.free(alloc);
    defer savePath.free(alloc);
    try test_save(alloc, path, savePath);
}
