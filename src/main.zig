const std = @import("std");

const chessl = @import("chess.zig");
const nnuel = @import("nnue.zig");
const heuristicl = @import("heuristic.zig");
const intrinsics = @import("intrinsics/intrinsics.zig");
const logl = @import("log.zig");
const bookl = @import("book.zig");
const moveGenl = @import("move_generation.zig");
const hashl = @import("hashTable.zig");
const magicl = @import("magic.zig");
const evaluatel = @import("evaluateEngine.zig");
const filel = @import("file.zig");
const datagenl = @import("datagen.zig");

pub const globalCtx = struct {
    io: std.Io = undefined,
    gpa: std.mem.Allocator = undefined,
    isInit: bool = false,
    pub fn setInit(p_self: *globalCtx, init: std.process.Init) void {
        p_self.io = init.io;
        p_self.gpa = init.gpa;
        p_self.isInit = true;
    }
    pub fn setGPA(p_self: *globalCtx, alloc: std.mem.Allocator) void {
        p_self.gpa = alloc;
    }
    pub fn setIO(p_self: *globalCtx, io: std.Io) void {
        p_self.io = io;
    }
};
pub var GLOBAL_CTX: globalCtx = .{};

pub inline fn getGlobalIo() std.Io {
    return GLOBAL_CTX.io;
}
pub inline fn getGlobalGPA() std.mem.Allocator {
    return GLOBAL_CTX.gpa;
}

fn printArgHelp(invalidTok: bool, tok: ?[]const u8) void {
    if (invalidTok) {
        std.debug.print("Invalid token found \"{s}\" \n", .{tok.?});
    }
    std.debug.print("Usage [command] [options]\n", .{});
    std.debug.print("Commands: \n", .{});

    std.debug.print("\t evaluate [path] \n", .{});

    std.debug.print("\t chess \n", .{});

    std.debug.print("\t main \n", .{});

    std.debug.print("\t convert [inputType] [path] [outputType] [outputPath] \n", .{});
}
fn processMainArgs(init: std.process.Init) anyerror!void {
    GLOBAL_CTX.setInit(init);
    chessl.initAll();
    const GPA = init.gpa;
    const args = init.minimal.args;
    var iter = args.iterate();
    _ = iter.next();
    const _cmd = iter.next();
    if (_cmd == null) {
        printArgHelp(false, null);
        return;
    }
    const cmd = _cmd.?;
    //const n = iter.next();
    //const nn = iter.next();
    //std.debug.print("Found token {s} next next {s} n3 {s}\n", .{ cmd, n.?, nn.? });

    if (std.mem.eql(u8, cmd, "evaluate")) {
        const p = iter.next();
        if (p == null) {
            std.debug.print("Missing path for command evaluate\n", .{});
            printArgHelp(false, null);
            return;
        }
        if (!filel.fileExists(p.?)) {
            std.debug.print("File {s} does not exist\n", .{p.?});
            return filel.file_err.fileNotFound_error;
        }
        try evaluatel.main(GPA, p.?);
    } else if (std.mem.eql(u8, cmd, "chess")) {
        try chessl.main(GPA);
    } else if (std.mem.eql(u8, cmd, "main")) {
        try chessl.main(GPA);
        //try moveGenl.main();
        //try bookl.main(GPA);
        //try logl.main(GPA);
        //try nnuel.main(GPA);
        //try heuristicl.main(GPA);
        //try intrinsics.main();
    } else if (std.mem.eql(u8, cmd, "convert")) {
        datagenl.convert(GPA, &iter) catch |e| {
            std.debug.print("convert caught err {}\n", .{e});
            if (e == chessl.debug_err.argErr) {
                printArgHelp(false, cmd);
            }
        };
    } else {
        printArgHelp(true, cmd);
    }
}

pub fn main(init: std.process.Init) anyerror!void {
    try processMainArgs(init);
}
