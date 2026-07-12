const std = @import("std");
const enginel = @import("engine.zig");
const configl = @import("config.zig");
const mainl = @import("main.zig");
const utilsl = @import("utils.zig");
const chessl = @import("chess.zig");
const weightl = @import("weights.zig");

const e_uciCMD = enum(u8) { NOOP = 0, QUIT, STOP, ISREADY, GO, POSITION, UCINEWGAME, REGISTER, SETOPTION, DEBUG, UCI, PONDERHIT, PRINT, BENCHMARK, PRINTPARAMS };

pub const uciState = struct {
    eng: enginel.engine = undefined,
    running: bool = false,
    uciMode: bool = false,
    pub fn init(alloc: std.mem.Allocator) !uciState {
        var ret: uciState = .{};
        ret.eng = try .init(alloc);
        return ret;
    }
    pub fn free(self: *uciState) void {
        self.eng.free();
    }
    pub fn executeBuffer(state: *uciState, cmdBuffer: []const u8) bool {
        const cmdType = enginel.getEngineCmdType(cmdBuffer);
        if (state.uciMode) {
            switch (cmdType) {
                .NOOP => {
                    return true;
                },
                .QUIT => {
                    state.eng.interruptSearch();
                    state.running = false;
                    return state.eng.executeQuitProcedure();
                },
                .STOP => {
                    state.eng.interruptSearch();
                    return true;
                },
                .ISREADY => {
                    return state.eng.executeIsReady() catch {
                        return false;
                    };
                },
                .GO => {
                    if (state.eng.scheduler.searching) {
                        @panic("go but still searching");
                    }
                    return state.eng.executeGoCmd(cmdBuffer);
                },
                .POSITION => {
                    return state.eng.executePositionCmd(cmdBuffer);
                },
                .UCINEWGAME => {
                    return state.eng.executeUciNewGameCmd();
                },
                .REGISTER => {
                    return state.eng.executeRegisterCmd(cmdBuffer);
                },
                .SETOPTION => {
                    return state.eng.executeSetOptionCmd(cmdBuffer);
                },
                .DEBUG => {
                    const ret = state.eng.executeDebugCmd(cmdBuffer);
                    if (ret) {
                        state.eng.scheduler._threadPool.debugMode = state.eng.status.debugMode;
                    }
                    return ret;
                },
                .UCI => {
                    respond("ICU");
                    return true;
                },
                .PONDERHIT => {
                    respond("pondering ...");
                    return true;
                },
                .BENCHMARK => {
                    // by default single threaded will probably just use the engine options maybe
                    return state.eng.executeBenchmarkCmd(cmdBuffer);
                },
                .PRINTPARAMS => {
                    const stepDiv: f32 = 20;
                    std.debug.print("{{\n", .{});
                    for (0..weightl.tunerOpts.items.len) |i| {
                        const opt = weightl.tunerOpts.items[i];
                        const step = @max(@ceil(@as(f32, @floatFromInt(@max(@abs(opt.opt.info.spin.max), @abs(opt.opt.info.spin.min)))) / stepDiv), 1);
                        if (i == weightl.tunerOpts.items.len - 1) {
                            std.debug.print(" \"{s}\": {{ \"value\": {d}, \"min_value\": {d}, \"max_value\": {d}, \"step\": {d} }}\n", .{ opt.opt.name, opt.addr.*, opt.opt.info.spin.min, opt.opt.info.spin.max, step });
                        } else {
                            std.debug.print(" \"{s}\": {{ \"value\": {d}, \"min_value\": {d}, \"max_value\": {d}, \"step\": {d} }},\n", .{ opt.opt.name, opt.addr.*, opt.opt.info.spin.min, opt.opt.info.spin.max, step });
                        }
                    }
                    std.debug.print("}}\n", .{});
                },
                .PRINT => {
                    chessl.print_boardstate(&state.eng.state);
                    return true;
                },
            }
        } else if (cmdType == .UCI) {
            state.uciMode = true;
            state.eng.printEngineInfo();
            return true;
        }
        return true;
    }
};

pub fn loop(alloc: std.mem.Allocator) !void {
    var state: uciState = try .init(alloc);
    state.running = true;

    var buffer: [configl.MAX_USER_INPUT]u8 = undefined;
    var f_reader = std.Io.File.stdin().reader(mainl.getGlobalIo(), &buffer);
    const reader = &f_reader.interface;
    while (state.running) {
        const inputBuffer = try enginel.getMsgStdin(reader);
        const msg = utilsl.trimStr(&inputBuffer);
        const status = state.executeBuffer(msg);
        if (state.eng.status.debugMode) {
            std.debug.print("status {} for cmd {s}\n", .{ status, msg });
        }
    }
}

pub fn respond(msg: []const u8) void {
    var buffer: [configl.MAX_USER_INPUT]u8 = undefined; // Buffer for stdout
    var writer = std.Io.File.stdout().writer(mainl.getGlobalIo(), &buffer);
    const interface = &writer.interface;
    interface.writeAll(msg) catch |err| {
        std.debug.print("[DEBUG] respond.engine: caught err: {}\n", .{err});
        return;
    };
    interface.writeAll("\n") catch |err| {
        std.debug.print("[DEBUG] respond.engine: caught err: {}\n", .{err});
        return;
    };
    interface.flush() catch |err| {
        std.debug.print("[DEBUG] respond.engine: caught err: {}\n", .{err});
        return;
    };
}
pub inline fn launchUci(alloc: std.mem.Allocator) !void {
    try loop(alloc);
}

pub fn main(alloc: std.mem.Allocator) !void {
    try launchUci(alloc);
}
