// idea of generic shell_like interface
// problem: Current implementation in interface.zig requires lots of problem specific code
// idea: Follow the spirit of the exemple below
// for print (ie: printboard)
// shell.add_argument("PRINT", fmt = "print", n_args = 0, func = execPrintCmd);
//
// for setboard (ie: printboard)
// shell.add_argument("setboard", fmt = "setboard <str>", n_args = 1, arg_name = ["fen"], func = execSetboardCmd);

const std = @import("std");

const arg = struct {
    fmt: []const u8,
    nArgs: usize = 0,
    func: *const fn (arg) bool,
    pub fn init(alloc: std.mem.Allocator, fmt: []const u8, nArgs: usize, func: *const fn (arg) bool) arg {
        const ret = alloc.create(arg);
        ret.* = .{.fmt = fmt, .nArgs = nArgs, .func = func};
        //var ret: arg = .{.nArgs = nArgs, .func = func};
        //ret.fmt = GLOBAL_ALLOC.alloc(u8, fmt.len);
        //@memcpy(&ret.fmt, &fmt);
    }
};

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
const GLOBAL_ALLOC = GPA.allocator();

const shell = struct {
    args: std.AutoArrayHashMap([]const u8, arg),
    //args: std.StringArrayHashMap([]const u8, arg),
    pub fn init() shell {
        var ret: shell = undefined;
        ret.args = std.AutoArrayHashMap([]const u8, arg).init(GLOBAL_ALLOC);
    }
    pub fn 
    pub fn printArgs(self: shell) void {
        var itr = self.args.iterator();
        const kv = self.args.fetchSwapRemove();
        while (itr.next()) |entry| {
            entry.value_ptr.
        }
        return;
    }
};
