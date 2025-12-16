// zig file for match orchestration in uci mode or more(?)
const chessl = @import("../chess.zig");
const move_genl = @import("../move_generation.zig");
const enginel = @import("../engine.zig");
const interfacel = @import("../interface.zig");
const mainl = @import("../main.zig");
const utilsl = @import("../utils.zig");
const configl = @import("../config.zig");
const gconfigl = @import("../gui/config.zig");
const explorationl = @import("../exploration.zig");
const movel = @import("../move.zig");
const squarel = @import("../square.zig");
const windowl = @import("window.zig");

const std = @import("std");
const r = gconfigl.r;

const e_color = chessl.e_color;
const e_matchFlag = explorationl.e_matchFlag;
const Board_state = chessl.Board_state;
const e_square = squarel.e_square;
const screenCoord = windowl.screenCoord;

const INITIAL_LOGSIZE: u16 = 100;
const DEFAULT_TIME: i64 = 300 * 1000; // 5 min in ms
const DEFAULT_TIME_INC: i64 = 5 * 1000; // 5 sec in ms

const e_guiCmd = enum(u8) { NOOP = 0, INFO, BESTMOVE, READYOK, UCIOK, ID, OPTION };
const e_guiPhase = enum(u8) { INVALID, WAITING, MATCH };

const guiStatus = struct {
    running: bool = false,
    phase: e_guiPhase = .INVALID,
    debugMode: bool = false,
    positionUpdated: bool = false,
};

pub const err_gui_bestmove = error{
    mem_error,
    nei_error,
    unknownMove_error,
};

const matchStatus = struct {
    chessState: Board_state = undefined,
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
const engine_info = struct {
    alive: bool = false,
    ready: bool = false,
    options: std.ArrayList(enginel.setOptionEntry) = undefined,
    pub fn init(alloc: std.mem.Allocator) !engine_info {
        var ret: engine_info = undefined;
        ret.alive = false;
        ret.ready = false;
        ret.options = try std.ArrayList(enginel.setOptionEntry).initCapacity(alloc, 2);
        return ret;
    }
};
const engine_Inventory = struct {
    len: u8 = 0,
    items: std.ArrayList(engine_info) = undefined,
    pub fn init(alloc: std.mem.Allocator) !engine_Inventory {
        var ret: engine_Inventory = undefined;
        ret.len = 0;
        ret.items = try std.ArrayList(engine_info).initCapacity(alloc, 2);
        return ret;
    }
    pub fn addEngine(p_self: *engine_Inventory, alloc: std.mem.Allocator, engine: engine_info) bool {
        p_self.len += 1;
        p_self.items.append(alloc, engine) catch {
            return false;
        };
        return true;
    }
};
const player = struct {
    color: e_color = .WHITE,
    searchDepth: u8 = 1,
    time: i64 = DEFAULT_TIME,
    time_inc: i64 = DEFAULT_TIME_INC,
    engineUsed: engine_info = .{}, // index of the engine to be used
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
    engineInventory: engine_Inventory,
    p_window: *windowl.guiWindow = undefined,

    pub fn init() !guiState {
        var ret: guiState = undefined;

        ret.match.status = .Continue;

        ret.alloc = mainl.GLOBAL_ALLOC;
        ret.input = undefined;
        ret.input.lock = false;

        const player_white: player = .{ .color = .WHITE, .searchDepth = 2, .engineUsed = try engine_info.init(ret.alloc) };
        const player_black: player = .{ .color = .BLACK, .searchDepth = 1, .engineUsed = try engine_info.init(ret.alloc) };
        ret.match.playerInv[0] = player_white;
        ret.match.playerInv[1] = player_black;

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
        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] handleCmd: executed command {}, status: {}\n", .{ cmdType, status });
        }
    }
    pub fn appendLog(p_self: *guiState, log: []const u8) !void {
        const logmsg = try std.fmt.allocPrint(p_self.alloc, "[LOG]{d} ms => {s}", .{ std.time.milliTimestamp() - p_self.start_time_ms, log });
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
        const respmsg = try std.fmt.allocPrint(p_self.alloc, "OUT: {s} \n", .{msg});
        defer p_self.alloc.free(respmsg);

        try writer.print("{s}\n", .{msg});
        try p_self.appendLog(respmsg);
        try writer.flush();
        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] respond.gui: sent msg: '{s}'", .{respmsg});
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

            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG] readingThread.gui: found {d} bytes, message: {s}\n", .{ n, msg });
            }

            _ = p_self.input.putCmd(p_self.alloc, msg);

            const respmsg = try std.fmt.allocPrint(p_self.alloc, "IN: {s}\n", .{msg});
            defer p_self.alloc.free(respmsg);
            try p_self.appendLog(respmsg);
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
            if (cumulTime > configl.DEBUG_INACTIVITY_SERVING_NS) {
                std.debug.print("[INACTIVITY] servingGuiThread.gui: no activity found in the last {d}s \n", .{configl.DEBUG_INACTIVITY_SERVING_S});
                cumulTime = 0;
            }
            std.Thread.sleep(configl.WAIT_TICKRATE_NS);
            cumulTime += configl.WAIT_TICKRATE_NS;
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

    fn printPlayerStatus(self: guiState) void {
        const player1 = self.match.playerInv[0];
        const player2 = self.match.playerInv[1];
        std.debug.print("Player 1: {}, ready: {}, alive: {}\n", .{ player1.color, player1.engineUsed.ready, player1.engineUsed.alive });
        std.debug.print("Player 2: {}, ready: {}, alive: {}\n", .{ player2.color, player2.engineUsed.ready, player2.engineUsed.alive });
    }
    pub fn executeCmd(p_self: *guiState, cmd: e_guiCmd, cmdBuffer: []const u8) bool {
        switch (cmd) {
            .NOOP => {
                return true;
            },
            .INFO => {
                p_self.match.playerInv[0].engineUsed.alive = true;
                p_self.match.playerInv[0].engineUsed.ready = true;

                p_self.match.playerInv[1].engineUsed.alive = true;
                p_self.match.playerInv[1].engineUsed.ready = true;
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
                p_self.match.playerInv[0].engineUsed.ready = true;
                p_self.match.playerInv[1].engineUsed.ready = true;
                return true;
            },
            .UCIOK => {
                p_self.match.playerInv[0].engineUsed.alive = true;
                p_self.match.playerInv[1].engineUsed.alive = true;
                return true;
            },
            .ID => {
                return true;
            },
            .OPTION => {
                return p_self.executeOptionCmd(cmdBuffer);
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
        const p_currentP = p_self.getCurrentPlayer();
        var sent: bool = false;
        p_currentP.engineUsed.ready = false;
        while (!p_currentP.engineUsed.ready) {
            std.Thread.sleep(configl.LIFE_TICKRATE_NS);
            if (!sent) {
                sent = true;
                try p_self.respond("ISREADY");
            }
        }
        p_currentP.engineUsed.ready = true;
    }
    fn waitAllPlayers(p_self: *guiState) !void {
        while (!p_self.allPlayersConnected()) {
            p_self.respond("UCI") catch |err| {
                std.debug.print("[DEBUG] waitAllPlayers: First UCI send failed, sleep then retrying (err: {})\n", .{err});
            };
            std.Thread.sleep(configl.START_TICKRATE_NS);
        }
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
        return self.match.playerInv[0].engineUsed.alive and self.match.playerInv[1].engineUsed.alive;
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
    pub fn executeOptionCmd(p_self: *guiState, cmdBuffer: []const u8) bool {
        var option_ret: enginel.setOptionEntry = undefined;
        var tokens = utilsl.split(u8, p_self.alloc, cmdBuffer, ' ') catch {
            return false;
        };
        defer tokens.deinit(p_self.alloc);
        var index: usize = 0;
        while (index < (tokens.items.len - 1)) {
            const str = tokens.items[index];
            if (utilsl.contains(str, "option", .ignoreCase)) {
                index += 1;
                continue;
            } else if (utilsl.contains(str, "name", .ignoreCase)) {
                const name = std.fmt.allocPrint(p_self.alloc, "{s}", .{tokens.items[index + 1]}) catch {
                    return false;
                };
                option_ret.name = name;
            } else if (utilsl.contains(str, "type", .ignoreCase)) {
                const _type = tokens.items[index + 1];
                if (utilsl.contains(_type, "SPIN", .ignoreCase)) {
                    option_ret.argType = .SPIN;
                } else if (utilsl.contains(_type, "CHECK", .ignoreCase)) {
                    option_ret.argType = .CHECK;
                } else if (utilsl.contains(_type, "STRING", .ignoreCase)) {
                    option_ret.argType = .STRING;
                } else if (utilsl.contains(_type, "COMBO", .ignoreCase)) {
                    option_ret.argType = .COMBO;
                } else {
                    return false;
                }
            }

            index += 2;
        }
        return true;
    }
    pub fn passThreadsToWindow(p_self: *guiState) void {
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.p_window.workingThreads.append(p_self.alloc, p_self.workingThreads.items[i]) catch {
                return;
            };
        }
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
    var window = windowl.initChessWindow(p_self.alloc, windowl.screenWidth, windowl.screenHeight) catch {
        p_self.close();
        return;
    };
    _ = window.open();

    p_self.waitAllPlayers() catch {
        p_self.close();
        return;
    };

    p_self.setDebugMode(false);
    const status: bool = p_self.startMatch(chessl.DEFAULT_FEN) catch {
        @panic("Failed to start");
    };
    if (!status) {
        @panic("Failed to start");
    }
    var boardComp = &window.components.items[0].e_boardComponent;
    _ = boardComp.setBoard(&p_self.match.chessState);
    boardComp.pingUpdate();

    var cumulTime: u64 = 0;
    p_self.status.positionUpdated = true;
    while (p_self.status.running) {
        if (!window.status.guiOpen) {
            p_self.close();
        }

        if (cumulTime > configl.DEBUG_INACTIVITY_SERVING_NS) {
            std.debug.print("[INACTIVITY] mainGuiThread.gui: no activity found in the last {d}s \n", .{configl.DEBUG_INACTIVITY_SERVING_S});
            cumulTime = 0;
        }
        if (p_self.match.nextTurnTrigger) {
            boardComp.pingUpdate();
            p_self.status.positionUpdated = true;
            p_self.match.nextTurnTrigger = false;
            //chessl.print_boardstate(&p_self.match.chessState);

            cumulTime = 0;

            const turn_status = p_self.nextTurn() catch {
                p_self.close();
                break;
            };
            if (!turn_status) {
                p_self.close();
                break;
            }
        }

        std.Thread.sleep(configl.WAIT_TICKRATE_NS);
        cumulTime += configl.WAIT_TICKRATE_NS;
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
    const argv: [1][]const u8 = .{configl.ENGINE_PATH};
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

    r.SetTraceLogLevel(r.LOG_NONE);
    launch_gui() catch {
        return;
    };
}
