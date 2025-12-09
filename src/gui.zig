// zig file for match orchestration in uci mode or more(?)

const chessl = @import("chess.zig");
const move_genl = @import("move_generation.zig");
const enginel = @import("engine.zig");
const interfacel = @import("interface.zig");
const mainl = @import("main.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const explorationl = @import("exploration.zig");
const movel = @import("move.zig");

const std = @import("std");

const e_color = chessl.e_color;
const e_matchFlag = explorationl.e_matchFlag;
const Board_state = chessl.Board_state;

const INITIAL_LOGSIZE: u16 = 100;
const DEFAULT_TIME: i64 = 300 * 1000; // 5 min in ms
const DEFAULT_TIME_INC: i64 = 5 * 1000; // 5 sec in ms
const LIFE_TICKRATE: u16 = 10;
const LIFE_TICKRATE_NS = std.math.pow(u64, 10, 8); // 2 seconds in ns

const START_TICKRATE_NS = 2 * std.math.pow(u64, 10, 9); // 2 seconds in ns

const DEBUG_INACTIVITY_SERVING_S = 30; // 30 seconds in ns
const DEBUG_INACTIVITY_SERVING_NS = DEBUG_INACTIVITY_SERVING_S * std.math.pow(u64, 10, 9); // 30 seconds in ns
const e_guiCmd = enum(u8) { NOOP = 0, INFO, BESTMOVE, READYOK, UCIOK, ID, OPTION };
const e_guiPhase = enum(u8) { INVALID, WAITING, MATCH };

const guiStatus = struct {
    running: bool = false,
    phase: e_guiPhase = .INVALID,
    debugMode: bool = false,
};

pub const err_gui_bestmove = error{
    mem_error,
    nei_error,
    unknownMove_error,
};

const matchStatus = struct {
    chessState: Board_state = undefined, //chessl.getEmptyBoardState(),
    playerInv: [chessl.NUMBER_PLAYER]player = undefined,
    availableMoves: movel.moveContainer = .{},
    status: e_matchFlag = .Error,
    nextTurnTrigger: bool = false,

    pub fn getGoStr(self: *matchStatus, alloc: std.mem.Allocator) ![]const u8 {
        const wP = self.playerInv[@intFromEnum(e_color.WHITE)];
        const bP = self.playerInv[@intFromEnum(e_color.BLACK)];
        const matchStr = try std.fmt.allocPrint(alloc, "wtime {d} btime {d} winc {d} binc {d}", .{ wP.time, bP.time, wP.time_inc, bP.time_inc });
        return matchStr;
    }
};
const engineStatus = struct {
    alive: bool = false,
    ready: bool = false,
};
const player = struct {
    color: e_color = .WHITE,
    searchDepth: u8 = 1,
    time: i64 = DEFAULT_TIME,
    time_inc: i64 = DEFAULT_TIME_INC,
    status: engineStatus = .{},
};

const guiState = struct {
    workingThreads: std.ArrayList(std.Thread),

    // will contains each send and receiv
    logs: std.ArrayList([]const u8) = undefined,
    status: guiStatus = .{},
    alloc: std.mem.Allocator = undefined,
    input: enginel.inputChannel = undefined,
    match: matchStatus = .{},
    f_writer: *std.fs.File.Writer,
    f_reader: *std.fs.File.Reader,
    start_time_ms: i64 = undefined,

    pub fn init() !guiState {
        var ret: guiState = undefined;
        const player_white: player = .{ .color = .WHITE, .searchDepth = 5 };
        const player_black: player = .{ .color = .BLACK, .searchDepth = 1 };

        ret.match.playerInv[0] = player_white;
        ret.match.playerInv[1] = player_black;
        ret.match.status = .Continue;

        ret.alloc = mainl.GLOBAL_ALLOC;
        ret.input = undefined;
        ret.input.lock = false;

        ret.input.cmdBuffer = try std.ArrayList([]u8).initCapacity(ret.alloc, 10);
        ret.workingThreads = try std.ArrayList(std.Thread).initCapacity(ret.alloc, 2);
        ret.logs = try std.ArrayList([]const u8).initCapacity(ret.alloc, INITIAL_LOGSIZE);
        ret.start_time_ms = std.time.milliTimestamp();

        return ret;
    }
    pub fn setBoard(p_self: *guiState, fen: []const u8) void {
        p_self.match.chessState = chessl.getBoardFromFen(p_self.alloc, fen) catch unreachable;
    }

    pub fn handleCmd(p_self: *guiState, cmdBuffer: []const u8) void {
        const cmdType = getGuiCmdType(cmdBuffer);
        //const trimmedBuffer = utilsl.trimStr(cmdBuffer);
        const status = p_self.executeCmd(cmdType, cmdBuffer);
        if (!status) {
            std.debug.print("[DEBUG] handleCmd: failed to execute command {}\n", .{cmdType});
        }
    }
    pub fn appendLog(p_self: *guiState, log: []const u8) !void {
        const logmsg = try std.fmt.allocPrint(p_self.alloc, "[LOG]{d} ms => {s}\n", .{ std.time.milliTimestamp() - p_self.start_time_ms, log });
        try p_self.logs.append(p_self.alloc, logmsg);
    }
    pub fn freeLog(p_self: *guiState) void {
        for (0..p_self.logs.items.len) |i| {
            p_self.alloc.free(p_self.logs.items[i]);
        }
        p_self.logs.deinit(p_self.alloc);
    }
    pub fn respond(p_self: *guiState, msg: []const u8) !void {
        var writer = &p_self.f_writer.interface;
        const respmsg = try std.fmt.allocPrint(p_self.alloc, "out: {s} \n", .{msg});
        defer p_self.alloc.free(respmsg);

        try writer.print("{s}\n", .{msg});
        try p_self.appendLog(respmsg);
        try writer.flush();
        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] respond.gui: sent msg: '{s}'\n", .{msg});
        }
    }

    pub fn readingThread(p_self: *guiState) !void {
        var reader = &p_self.f_reader.interface;
        var line = std.Io.Writer.Allocating.init(p_self.alloc);
        defer line.deinit();
        while (p_self.status.running) {
            const n = reader.streamDelimiter(&line.writer, '\n') catch |err| {
                std.debug.print("[DEBUG] readingThread.gui: caught err {}\n", .{err});
                p_self.crash();
            };
            _ = reader.toss(1);
            const msg = line.written();

            std.debug.print("[DEBUG] readingThread.gui: found {d} bytes, message: {s}\n", .{ n, msg });

            _ = p_self.input.putCmd(p_self.alloc, msg);
            try p_self.appendLog(utilsl.trimStr(msg));
            line.clearRetainingCapacity();
        }
    }
    pub fn servingGuiThread(p_self: *guiState) !void {
        var cumulTime: u64 = 0;
        while (p_self.status.running) {
            while (p_self.input.cmdBuffer.items.len != 0) {
                const cmdBuffer = p_self.input.readBuffer();
                defer p_self.alloc.free(cmdBuffer);
                p_self.handleCmd(cmdBuffer);
                cumulTime = 0;
            }
            if (cumulTime > DEBUG_INACTIVITY_SERVING_NS) {
                std.debug.print("[INACTIVITY] servingGuiThread.gui: no activity found in the last {d}s \n", .{DEBUG_INACTIVITY_SERVING_S});
                cumulTime = 0;
            }
            std.Thread.sleep(enginel.WAIT_TICKRATE_NS);
            cumulTime += enginel.WAIT_TICKRATE_NS;
        }
    }
    pub fn saveLog(self: *guiState) !void {
        const fileName = try std.fmt.allocPrint(self.alloc, "logs/logs_{d}.txt", .{std.time.timestamp()});
        defer self.alloc.free(fileName);
        const file = try std.fs.cwd().createFile(fileName, .{ .read = true });
        defer file.close();
        for (0..self.logs.items.len) |i| {
            _ = try file.write(self.logs.items[i]);
        }
    }
    pub fn close(p_self: *guiState) void {
        std.debug.print("[CLOSE] saving logs to log file\n", .{});
        p_self.respond("QUIT") catch {};
        p_self.status.running = false;
        p_self.saveLog() catch |err| {
            std.debug.print("[CLOSE] error while saving: {}\n", .{err});
        };
        p_self.freeLog();
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.workingThreads.items[i].join();
        }
    }
    pub fn crash(p_self: *guiState) noreturn {
        std.debug.print("[CRASH] crashing this gui, with no survivors\n", .{});
        p_self.close();
        std.process.exit(1);
    }
    pub fn executeCmd(p_self: *guiState, cmd: e_guiCmd, cmdBuffer: []const u8) bool {
        switch (cmd) {
            .NOOP => {
                return true;
            },
            .INFO => {
                p_self.match.playerInv[0].status.alive = true;
                p_self.match.playerInv[1].status.alive = true;
                return true;
            },
            .BESTMOVE => {
                if (p_self.status.phase == .MATCH) {
                    return p_self.matchOnBestMove(cmdBuffer) catch {
                        return false;
                    };
                }
                return false;
            },
            .READYOK => {
                p_self.match.playerInv[0].status.ready = true;
                p_self.match.playerInv[1].status.ready = true;
                return true;
            },
            .UCIOK => {
                p_self.match.playerInv[0].status.alive = true;
                p_self.match.playerInv[1].status.alive = true;
                return true;
            },
            .ID => {
                return true;
            },
            .OPTION => {
                return true;
            },
        }
        return true;
    }
    pub fn matchOnBestMove(p_self: *guiState, cmdBuffer: []const u8) !bool {
        const status = p_self.executeBestMove(cmdBuffer) catch |err| {
            std.debug.print("[DEBUG] matchOnBestMove: found err: {}\n", .{err});
            if (err == err_gui_bestmove.unknownMove_error) {
                std.debug.print("[DEBUG] expected one of the following moves: \n", .{});
                p_self.match.availableMoves.print();
                var moveArr = chessl.getMoveListFromStr(&p_self.match.chessState, cmdBuffer, p_self.alloc) catch unreachable;
                defer moveArr.deinit(p_self.alloc);
                const move = moveArr.items[0];
                std.debug.print("[DEBUG] matchOnBestMove: move found: {s}-{}-{}-{} \n", .{ move.getStr(), move.getFlag(), move.getFromPiece(), move.getCapturePiece() });
                chessl.print_boardstate(&p_self.match.chessState);
            }
            return false;
        };
        if (status) {
            p_self.match.nextTurnTrigger = true;
        }
        return status;
    }
    pub fn startMatch(p_self: *guiState, fen: []const u8) !bool {
        p_self.match.status = .Continue;
        p_self.status.phase = .MATCH;
        const msg = try std.fmt.allocPrint(p_self.alloc, "position fen {s}", .{fen});
        p_self.setBoard(fen);
        p_self.match.availableMoves = move_genl.generateLegalMoves(&p_self.match.chessState);

        defer p_self.alloc.free(msg);
        try p_self.respond(msg);

        try p_self.waitEngine();

        try p_self.sendGoSearchCommand();
        return true;
    }
    fn nextTurn(p_self: *guiState) !bool {
        if (p_self.match.chessState.isStaleMateRepetition()) {
            p_self.match.status = .StaleMateRepetition;
            return false;
        }
        p_self.match.availableMoves = move_genl.generateLegalMoves(&p_self.match.chessState);
        if (p_self.match.availableMoves.len == 0) {
            if (p_self.match.chessState.isLegal(p_self.match.chessState.turn)) {
                p_self.match.status = .StaleMate;
                return false;
            } else {
                p_self.match.status = .CheckMate;
                return false;
            }
        }

        try p_self.waitEngine();
        try p_self.sendPositionUpdate();

        try p_self.waitEngine();
        try p_self.sendGoSearchCommand();
        return true;
    }
    fn setDebugMode(p_self: *guiState, flag: bool) void {
        p_self.status.debugMode = flag;
        if (flag) {
            p_self.respond("DEBUG on") catch {};
        }
    }
    fn waitEngine(p_self: *guiState) !void {
        // TODO wait for the current player not just default to WHITE
        // PROBLEM if no sleep before sending the fen gets mangled afterwards in the engine side
        // Fix stop using []const u8 as command container as they do not have ownership of the memory
        var p_currentP = p_self.getCurrentPlayer();
        var sent: bool = false;
        p_currentP.status.ready = false;
        while (!p_currentP.status.ready) {
            std.Thread.sleep(LIFE_TICKRATE_NS);
            if (!sent) {
                sent = true;
                try p_self.respond("ISREADY");
            }
        }
        p_currentP.status.ready = true;
    }
    fn sendPositionUpdate(self: *guiState) !void {
        const msg = try std.fmt.allocPrint(self.alloc, "position startpos {s}", .{self.match.chessState.getLastMove().getStr()});
        defer self.alloc.free(msg);
        try self.respond(msg);
    }
    fn sendGoSearchCommand(self: *guiState) !void {
        const p_currentPlayer = self.getCurrentPlayer();
        const msgMatch = try self.match.getGoStr(self.alloc);
        const msg = try std.fmt.allocPrint(self.alloc, "go {s} depth {d}", .{ msgMatch, p_currentPlayer.searchDepth });

        defer self.alloc.free(msg);
        defer self.alloc.free(msgMatch);

        try self.respond(msg);
    }
    pub fn getCurrentPlayer(self: *guiState) *player {
        return &self.match.playerInv[@intFromEnum(self.match.chessState.turn)];
    }
    pub fn allPlayersConnected(self: *guiState) bool {
        return self.match.playerInv[0].status.alive and self.match.playerInv[1].status.alive;
    }
    pub fn executeBestMove(p_self: *guiState, cmdBuffer: []const u8) err_gui_bestmove!bool {
        var tokens = utilsl.split(u8, p_self.alloc, cmdBuffer, ' ') catch {
            return err_gui_bestmove.mem_error;
        };
        defer tokens.deinit(p_self.alloc);
        if (tokens.items.len < 2) {
            return err_gui_bestmove.nei_error;
        }
        var moveArr = chessl.getMoveListFromStr(&p_self.match.chessState, cmdBuffer, p_self.alloc) catch {
            return err_gui_bestmove.mem_error;
        };
        defer moveArr.deinit(p_self.alloc);
        if (moveArr.items.len != 1) {
            return err_gui_bestmove.nei_error;
        }
        if (!moveArr.items[0].isIn(p_self.match.availableMoves)) {
            return err_gui_bestmove.unknownMove_error;
        }

        p_self.match.chessState.makeMoveUpdate(moveArr.items[0]);
        return true;
    }
};
fn getGuiCmdType(cmd: []const u8) e_guiCmd {
    if (utilsl.contains(cmd, "info", .ignoreCase)) {
        return .INFO;
    } else if (utilsl.contains(cmd, "bestmove", .ignoreCase)) {
        return .BESTMOVE;
    } else if (utilsl.contains(cmd, "readyok", .ignoreCase)) {
        return .READYOK;
    } else if (utilsl.contains(cmd, "uciok", .ignoreCase)) {
        return .UCIOK;
    } else if (utilsl.contains(cmd, "id", .ignoreCase)) {
        return .ID;
    } else if (utilsl.contains(cmd, "option", .ignoreCase)) {
        return .OPTION;
    }
    return .NOOP;
}

fn mainGuiThread(p_self: *guiState) void {
    // check engine

    p_self.setBoard(chessl.DEFAULT_FEN);

    while (!p_self.allPlayersConnected()) {
        p_self.respond("UCI") catch |err| {
            std.debug.print("[DEBUG] mainGuiThread: First UCI send failed, sleep then retrying (err: {})\n", .{err});
        };
        std.Thread.sleep(START_TICKRATE_NS);
    }
    p_self.setDebugMode(false);
    const status: bool = p_self.startMatch(chessl.DEFAULT_FEN) catch {
        @panic("Failed to start");
    };
    if (!status) {
        @panic("Failed to start");
    }

    var cumulTime: u64 = 0;
    while (p_self.status.running) {
        std.Thread.sleep(enginel.WAIT_TICKRATE_NS);
        cumulTime += enginel.WAIT_TICKRATE_NS;
        if (cumulTime > DEBUG_INACTIVITY_SERVING_NS) {
            std.debug.print("[INACTIVITY] mainGuiThread.gui: no activity found in the last {d}s \n", .{DEBUG_INACTIVITY_SERVING_S});
            cumulTime = 0;
        }
        if (p_self.match.nextTurnTrigger) {
            p_self.match.nextTurnTrigger = false;
            cumulTime = 0;

            chessl.print_boardstate(&p_self.match.chessState);
            const turn_status = p_self.nextTurn() catch {
                p_self.close();
                break;
            };
            if (!turn_status) {
                p_self.close();
                break;
            }
        }
    }
    chessl.print_boardstate(&p_self.match.chessState);
}

fn entrypointReaderThreading(p_self: *guiState) void {
    p_self.readingThread() catch unreachable;
}
fn entrypointServingThreading(p_self: *guiState) void {
    p_self.servingGuiThread() catch unreachable;
}

var stdin_buffer: [interfacel.MAX_USER_INPUT]u8 = std.mem.zeroes([interfacel.MAX_USER_INPUT]u8);
var stdout_buffer: [interfacel.MAX_USER_INPUT]u8 = std.mem.zeroes([interfacel.MAX_USER_INPUT]u8);

pub fn launch_gui() !void {
    const argvInit = try std.fmt.allocPrint(mainl.GLOBAL_ALLOC, "{s}", .{std.os.argv[0]});
    defer mainl.GLOBAL_ALLOC.free(argvInit);
    const argv: [2][]const u8 = .{ argvInit, "engine" };
    var child = std.process.Child.init(&argv, mainl.GLOBAL_ALLOC);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    //var writer = child.stdin.?.writer();
    var writer = child.stdin.?.writer(&stdin_buffer);
    var reader = child.stdout.?.reader(&stdout_buffer);
    var ret: guiState = try guiState.init();
    ret.f_writer = &writer;
    ret.f_reader = &reader;

    ret.status.running = true;
    ret.status.phase = .MATCH;

    const inputThread = try std.Thread.spawn(.{}, entrypointReaderThreading, .{&ret});
    try ret.workingThreads.append(ret.alloc, inputThread);

    const servingThread = try std.Thread.spawn(.{}, entrypointServingThreading, .{&ret});
    try ret.workingThreads.append(ret.alloc, servingThread);

    mainGuiThread(&ret);
    return;
}

pub fn main() void {
    //
    launch_gui() catch {
        return;
    };
}
