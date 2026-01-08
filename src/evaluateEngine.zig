// zig file for match orchestration in uci mode or more(?)
const chessl = @import("chess.zig");
const move_genl = @import("move_generation.zig");
const enginel = @import("engine.zig");
const mainl = @import("main.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const gconfigl = @import("gui/config.zig");
const movel = @import("move.zig");
const squarel = @import("square.zig");

const std = @import("std");

const e_color = chessl.e_color;
pub const e_matchFlag = enum(u8) { Error, Continue, CheckMate, StaleMate, StaleMateRepetition, Flagged, Dnf };
const Board_state = chessl.Board_state;
const e_square = squarel.e_square;

const INITIAL_LOGSIZE: u16 = 100;
const DEFAULT_TIME_MS: i64 = 300 * 1000; // 5 min in ms
const DEFAULT_TIME_INC_MS: i64 = 5 * 1000; // 5 sec in ms

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

const matchResultsBench = struct {
    //
    //(W) Win / Lose / Draw
    //(B) Win / Lose / Draw
    win: u8 = 0,
    lose: u8 = 0,
    draw: u8 = 0,
    flagged: u8 = 0,
    avgTimePerTurn: i64 = 0,
    nMatch: u8 = 0,
};
const matchResultContainer = struct {
    items: [MAX_ENGINES]matchResultsBench = std.mem.zeroes([MAX_ENGINES]matchResultsBench),
    pub fn init() matchResultContainer {
        return .{};
    }
    pub fn addOutCome(p_self: *matchResultContainer, match: *matchStatus) void {
        const p = match.chessState.whiteToMove();
        const currEngine = match.playerInv[@intFromBool(p)].engineUsed;
        const otherEngine = match.playerInv[@intFromBool(!p)].engineUsed;
        switch (match.status) {
            .Continue, .Error => {
                @panic("???");
            },
            .CheckMate => {
                p_self.items[currEngine].lose += 1;
                p_self.items[otherEngine].win += 1;
            },

            .Flagged => {
                p_self.items[currEngine].lose += 1;
                p_self.items[currEngine].flagged += 1;
                p_self.items[otherEngine].win += 1;
            },
            .StaleMate, .StaleMateRepetition, .Dnf => {
                p_self.items[currEngine].draw += 1;
                p_self.items[otherEngine].draw += 1;
            },
        }
        for (0..2) |i| {
            const currEng = match.playerInv[i].engineUsed;
            p_self.items[i].nMatch += 1;
            var sum: i64 = 0;
            // can also do original availabe time div by number of move, would need to store the initial time
            for (match.playerInv[i].timeTaken.items) |time| {
                sum += time;
            }
            p_self.items[currEng].avgTimePerTurn = @divFloor(sum, @as(i64, @intCast(match.playerInv[i].timeTaken.items.len + 1)));
        }
    }
    pub fn saveLog(p_self: *matchResultContainer, alloc: std.mem.Allocator, match: *matchStatus) !void {
        const fileName = try std.fmt.allocPrint(alloc, "logs/match_logs_{d}.txt", .{std.time.timestamp()});
        const file = try std.fs.cwd().createFile(fileName, .{ .read = true });
        defer alloc.free(fileName);
        defer file.close();

        for (0..2) |i| {
            const engIdx = match.playerInv[i].engineUsed;
            const res = p_self.items[engIdx];
            const scoreStr = try std.fmt.allocPrint(alloc, "engine: {s}, {d} matches, win: {d}, lose: {d}, draw: {d}, flagged: {d}, speed: {d} ms/move;\n", .{ match.playerInv[i].name, res.nMatch, res.win, res.lose, res.draw, res.flagged, res.avgTimePerTurn });
            defer alloc.free(scoreStr);
            _ = try file.write(scoreStr);
        }
    }
};
const MAX_ENGINES: u8 = 2;
const timeFormat = struct {
    time: i64 = DEFAULT_TIME_MS,
    inc: i64 = DEFAULT_TIME_INC_MS,
};
const standardTimeFormat: timeFormat = .{ .time = 300000, .inc = 5000 };
const bulletTimeFormat: timeFormat = .{ .time = 60000, .inc = 0 };

const signedCmd = struct {
    str: []const u8,
    engine: u8,
    pub fn init(buffer: []u8, engineIndex: u8) signedCmd {
        return .{ .str = buffer, .engine = engineIndex };
    }
};
const matchStatus = struct {
    chessState: Board_state = undefined,
    // [black / white], same as the c_occupiedBB
    playerInv: [chessl.NUMBER_PLAYER]player = undefined,
    availableMoves: movel.moveContainer = .{},
    status: e_matchFlag = .Error,
    nextTurnTrigger: bool = false,
    positionUpdated: bool = false,

    prevTick: i64 = 0,
    prevTurnTick: i64 = 0,

    pub fn reset(p_self: *matchStatus) void {
        //
        p_self.playerInv[0].reset();
        p_self.playerInv[1].reset();
        p_self.status = .Continue;
    }

    pub fn getGoStr(self: *matchStatus, alloc: std.mem.Allocator) ![]const u8 {
        const wP = self.playerInv[@intFromEnum(e_color.WHITE)];
        const bP = self.playerInv[@intFromEnum(e_color.BLACK)];
        const matchStr = try std.fmt.allocPrint(alloc, "wtime {d} btime {d} winc {d} binc {d}", .{ wP.time, bP.time, wP.time_inc, bP.time_inc });
        return matchStr;
    }
    pub fn timeTick(p_self: *matchStatus) bool {
        const curr = std.time.milliTimestamp();
        p_self.playerInv[@intFromBool(p_self.chessState.whiteToMove())].time -= (curr - p_self.prevTick);
        if (p_self.playerInv[@intFromBool(p_self.chessState.whiteToMove())].time < 0) {
            return false;
        }
        p_self.prevTick = curr;
        return true;
    }
    pub fn startTime(p_self: *matchStatus) void {
        p_self.prevTick = std.time.milliTimestamp();
        p_self.prevTurnTick = std.time.milliTimestamp();
    }
    pub fn turnComplete(p_self: *matchStatus, alloc: std.mem.Allocator) !void {
        const curr = std.time.milliTimestamp();
        var p = &p_self.playerInv[@intFromBool(p_self.chessState.whiteToMove())];
        try p.timeTaken.append(alloc, (curr - p_self.prevTurnTick));
        p.time += p.time_inc;

        p_self.prevTurnTick = curr;
    }
};

const engine_info = struct {
    alive: bool = false,
    ready: bool = false,
    options: std.ArrayList([]u8) = undefined,
    f_writer: std.fs.File.Writer,
    f_reader: std.fs.File.Reader,
    _writerBuffer: [configl.MAX_USER_INPUT]u8 = undefined,
    _readerBuffer: [configl.MAX_USER_INPUT]u8 = undefined,

    pub fn init(alloc: std.mem.Allocator) !*engine_info {
        var ret: *engine_info = try alloc.create(engine_info);
        ret.alive = false;
        ret.ready = false;
        ret.options = try std.ArrayList([]u8).initCapacity(alloc, 2);
        ret._writerBuffer = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
        ret._readerBuffer = std.mem.zeroes([configl.MAX_USER_INPUT]u8);

        return ret;
    }
    pub fn free(p_self: *engine_info, alloc: std.mem.Allocator) void {
        for (0..p_self.options.items.len) |i| {
            alloc.free(p_self.options.items[i]);
        }
    }
    pub fn addOption(p_self: *engine_info, alloc: std.mem.Allocator, cmdStr: []const u8) !void {
        const e = try alloc.dupe(u8, cmdStr);
        try p_self.options.append(alloc, e);
    }
    pub fn printInfo(p_self: *engine_info) !void {
        for (0..p_self.options.items.len) |i| {
            std.debug.print("{s}\n", .{p_self.options.items[i]});
        }
    }
};

const engine_Inventory = struct {
    len: u8 = 0,
    items: std.ArrayList(*engine_info) = undefined,
    pub fn init(alloc: std.mem.Allocator) !engine_Inventory {
        var ret: engine_Inventory = undefined;
        ret.len = 0;
        ret.items = try std.ArrayList(*engine_info).initCapacity(alloc, 2);
        return ret;
    }
    pub fn addEngine(p_self: *engine_Inventory, alloc: std.mem.Allocator, engine: *engine_info) bool {
        p_self.len += 1;
        p_self.items.append(alloc, engine) catch {
            return false;
        };
        return true;
    }
};
const player = struct {
    color: e_color = .WHITE,
    _time: i64 = DEFAULT_TIME_MS,
    time: i64 = DEFAULT_TIME_MS,
    time_inc: i64 = DEFAULT_TIME_INC_MS,
    engineUsed: u8 = 0, // index of the engine to be used (0-1)
    timeTaken: std.ArrayList(i64) = undefined,
    name: []const u8,
    pub fn init(alloc: std.mem.Allocator, timeF: timeFormat, color: e_color, engineIndex: u8, name: []const u8) !player {
        var ret: player = .{ ._time = timeF.time, .time = timeF.time, .time_inc = timeF.inc, .color = color, .engineUsed = engineIndex, .name = name };
        ret.timeTaken = try std.ArrayList(i64).initCapacity(alloc, 32);
        return ret;
    }
    pub fn reset(p_self: *player) void {
        p_self.time = p_self._time;
        // removes all elements without freeing the mem
        p_self.timeTaken.clearRetainingCapacity();
    }
};

const guiState = struct {
    workingThreads: std.ArrayList(std.Thread),

    // will contains each send and receiv
    logs: std.ArrayList([]const u8) = undefined,
    status: guiStatus = .{},
    alloc: std.mem.Allocator = undefined,
    input: std.ArrayList(enginel.inputChannel) = undefined,
    match: matchStatus = .{},
    start_time_ms: i64 = undefined,
    engineInventory: engine_Inventory,

    pub fn init() !guiState {
        var ret: guiState = undefined;

        ret.match.status = .Continue;

        ret.alloc = mainl.GLOBAL_ALLOC;
        ret.input = undefined;
        ret.engineInventory = try engine_Inventory.init(ret.alloc);

        ret.input = try std.ArrayList(enginel.inputChannel).initCapacity(ret.alloc, 2);

        ret.workingThreads = try std.ArrayList(std.Thread).initCapacity(ret.alloc, 2);
        ret.logs = try std.ArrayList([]const u8).initCapacity(ret.alloc, INITIAL_LOGSIZE);
        ret.start_time_ms = std.time.milliTimestamp();

        return ret;
    }
    pub fn addEngine(p_self: *guiState, path: []const u8) !bool {
        const argv: [1][]const u8 = .{path};
        var child = std.process.Child.init(&argv, mainl.GLOBAL_ALLOC);

        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Inherit;
        try child.spawn();

        var eng: *engine_info = try engine_info.init(mainl.GLOBAL_ALLOC);

        eng.f_writer = (child.stdin.?.writer(&eng._writerBuffer));
        eng.f_reader = (child.stdout.?.reader(&eng._readerBuffer));
        try p_self.input.append(p_self.alloc, try .init(p_self.alloc));

        return p_self.engineInventory.addEngine(p_self.alloc, eng);
    }
    pub fn setBoard(p_self: *guiState, fen: []const u8) void {
        p_self.match.chessState = chessl.getBoardFromFen(p_self.alloc, fen) catch unreachable;
    }

    pub fn handleCmd(p_self: *guiState, cmd: signedCmd) void {
        const cmdType = getGuiCmdType(cmd.str);
        //const trimmedBuffer = utilsl.trimStr(cmdBuffer);
        const status = p_self.executeCmd(cmdType, cmd);
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

    pub fn respond(p_self: *guiState, msg: []const u8, engineIndex: u8) !void {
        //var writer = &p_self.f_writer.interface;

        const eng: *engine_info = p_self.engineInventory.items.items[engineIndex];
        var writer = &eng.f_writer.interface;

        const respmsg = try std.fmt.allocPrint(p_self.alloc, "OUT: {s} \n", .{msg});
        defer p_self.alloc.free(respmsg);

        try writer.print("{s}\n", .{msg});
        try p_self.appendLog(respmsg);
        try writer.flush();
        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] respond.gui(#{d}): sent msg: {s}\n", .{ engineIndex, respmsg });
        }
    }
    pub fn respondAll(p_self: *guiState, msg: []const u8) !void {
        for (0..p_self.engineInventory.len) |i| {
            try p_self.respond(msg, @intCast(i));
        }
    }

    pub fn readingThread(p_self: *guiState, engineIndex: u8) !void {
        const eng: *engine_info = p_self.engineInventory.items.items[engineIndex];
        var reader = &eng.f_reader.interface;

        var line = std.Io.Writer.Allocating.init(p_self.alloc);
        defer line.deinit();
        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] readingThread.gui: Started reading on the stdout of the {d}nth engine (self status: {})\n", .{ engineIndex, p_self.status.running });
        }
        while (p_self.status.running) {
            const n = reader.streamDelimiter(&line.writer, '\n') catch |err| {
                std.debug.print("[DEBUG] readingThread.gui: caught err {}\n", .{err});
                p_self.crash();
            };
            _ = reader.toss(1);
            const msg = line.written();

            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG]  readingThread.gui (#{d}): found {d} bytes, message: {s}\n", .{ engineIndex, n, msg });
            }

            _ = p_self.input.items[engineIndex].putCmd(p_self.alloc, msg);

            const respmsg = try std.fmt.allocPrint(p_self.alloc, "IN(#{d}): {s}\n", .{ engineIndex, msg });
            defer p_self.alloc.free(respmsg);
            try p_self.appendLog(respmsg);
            line.clearRetainingCapacity();
        }
    }
    pub fn servingGuiThread(p_self: *guiState) !void {
        var cumulTime: u64 = 0;
        while (p_self.status.running) {
            for (0..p_self.input.items.len) |i| {
                var inp = &p_self.input.items[i];
                while (inp.nonEmpty()) {
                    const cmdBuffer = inp.readBuffer();
                    defer p_self.alloc.free(cmdBuffer);
                    p_self.handleCmd(.init(cmdBuffer, @intCast(i)));
                    cumulTime = 0;
                }
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
        p_self.match.status = .Error;
        p_self.respondAll("QUIT") catch {};
        p_self.status.running = false;
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.workingThreads.items[i].join();
        }
        p_self.saveLog() catch |err| {
            std.debug.print("[CLOSE] error while saving: {}\n", .{err});
        };
        p_self.freeLog();
    }
    pub fn crash(p_self: *guiState) noreturn {
        std.debug.print("[CRASH] crashing this gui, with no survivors\n", .{});
        p_self.close();
        std.process.exit(1);
    }

    fn printPlayerStatus(self: guiState) void {
        const player1 = self.match.playerInv[0];
        const eng1 = self.engineInventory.items.items[player1.engineUsed];

        const player2 = self.match.playerInv[1];
        const eng2 = self.engineInventory.items.items[player2.engineUsed];

        std.debug.print("Player 1: {}, ready: {}, alive: {}\n", .{ player1.color, eng1.ready, eng1.alive });
        std.debug.print("Player 2: {}, ready: {}, alive: {}\n", .{ player2.color, eng2.ready, eng2.alive });
    }
    pub fn executeCmd(p_self: *guiState, cmd: e_guiCmd, cmdBuffer: signedCmd) bool {
        switch (cmd) {
            .NOOP => {
                return true;
            },
            .INFO => {
                p_self.engineInventory.items.items[cmdBuffer.engine].alive = true;
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
                p_self.engineInventory.items.items[cmdBuffer.engine].ready = true;
                return true;
            },
            .UCIOK => {
                p_self.engineInventory.items.items[cmdBuffer.engine].alive = true;
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
    pub fn matchOnBestMove(p_self: *guiState, cmdBuffer: signedCmd) !bool {
        const p = p_self.getCurrentPlayer();
        // if this hits, mismatch between the current player and the engine that did the computing
        std.debug.assert(p.engineUsed == cmdBuffer.engine);
        const status = p_self.executeBestMove(cmdBuffer.str) catch |err| {
            std.debug.print("[DEBUG] matchOnBestMove: found err: {}\n", .{err});
            if (err == err_gui_bestmove.unknownMove_error) {
                std.debug.print("[DEBUG] expected one of the following moves: \n", .{});
                p_self.match.availableMoves.print();
                var moveArr = chessl.getMoveListFromStr(&p_self.match.chessState, cmdBuffer.str, p_self.alloc) catch unreachable;
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
    pub fn startMatch(p_self: *guiState, fen: []const u8) !void {
        p_self.match.reset();
        p_self.match.startTime();
        p_self.status.phase = .MATCH;
        const msg = try std.fmt.allocPrint(p_self.alloc, "position fen {s}", .{fen});
        defer p_self.alloc.free(msg);
        p_self.setBoard(fen);
        p_self.match.availableMoves = move_genl.generateLegalMoves(&p_self.match.chessState);

        try p_self.respond(msg, p_self.getCurrentPlayer().engineUsed);

        try p_self.waitEngine();

        try p_self.sendGoSearchCommand();
    }
    fn nextTurn(p_self: *guiState) !bool {
        if (p_self.match.chessState.isStaleMateRepetition()) {
            p_self.match.status = .StaleMateRepetition;
            return false;
        }
        p_self.match.availableMoves = move_genl.generateLegalMoves(&p_self.match.chessState);
        if (p_self.match.availableMoves.len == 0) {
            if (p_self.match.chessState.isLegal(p_self.match.chessState.whiteToMove())) {
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
    fn setDebugMode(p_self: *guiState, flag: bool) !void {
        p_self.status.debugMode = flag;
        if (flag) {
            try p_self.respondAll("DEBUG on");
        } else {
            try p_self.respondAll("DEBUG off");
        }
    }

    fn waitEngine(p_self: *guiState) !void {
        // TODO wait for the current player not just default to WHITE
        // PROBLEM if no sleep before sending the fen gets mangled afterwards in the engine side
        // Fix stop using []const u8 as command container as they do not have ownership of the memory
        const p_player = p_self.getCurrentPlayer();
        const p_engine = p_self.getCurrentEngine();
        var sent: bool = false;
        p_engine.ready = false;
        while (!p_engine.ready) {
            std.Thread.sleep(configl.LIFE_TICKRATE_NS);
            if (!sent) {
                sent = true;
                try p_self.respond("ISREADY", p_player.engineUsed);
            }
        }
        p_engine.ready = true;
    }
    fn waitAllPlayers(p_self: *guiState) !void {
        while (!p_self.allPlayersConnected()) {
            //p_self.respondAll("UCI") catch |err| {
            //    std.debug.print("[DEBUG] waitAllPlayers: First UCI send failed, sleep then retrying (err: {})\n", .{err});
            //};
            std.Thread.sleep(configl.START_TICKRATE_NS);
        }
    }
    fn sendPositionUpdate(p_self: *guiState) !void {
        var lineBuffer = try p_self.match.chessState.move_history.getLineString(p_self.alloc);
        const msg = try std.fmt.allocPrint(p_self.alloc, "position startpos {s}", .{lineBuffer._slice()});

        defer lineBuffer.free(p_self.alloc);
        defer p_self.alloc.free(msg);

        try p_self.respond(msg, p_self.getCurrentPlayer().engineUsed);
    }
    fn sendGoSearchCommand(p_self: *guiState) !void {
        const msgMatch = try p_self.match.getGoStr(p_self.alloc);
        const msg = try std.fmt.allocPrint(p_self.alloc, "go {s} ", .{msgMatch});

        defer p_self.alloc.free(msg);
        defer p_self.alloc.free(msgMatch);

        try p_self.respond(msg, p_self.getCurrentPlayer().engineUsed);
    }
    pub fn sendEngineInterrupt(p_self: *guiState, engineIndex: u8) !void {
        return try p_self.respond("stop", engineIndex);
    }
    pub fn setPlayerEngine(p_self: *guiState, white: bool, engineIndex: u8) void {
        p_self.match.playerInv[@intFromBool(white)].engineUsed = engineIndex;
    }
    pub inline fn getCurrentPlayer(self: *guiState) *player {
        return &self.match.playerInv[@intFromBool(self.match.chessState.whiteToMove())];
    }

    pub fn getCurrentEngine(self: *guiState) *engine_info {
        const p = self.getCurrentPlayer();
        return self.engineInventory.items.items[p.engineUsed];
    }
    pub fn allPlayersConnected(self: *guiState) bool {
        return self.engineInventory.items.items[0].alive and self.engineInventory.items.items[1].alive;
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

        p_self.match.chessState.makeMove(moveArr.items[0]);
        return true;
    }
    pub fn executeOptionCmd(p_self: *guiState, cmdBuffer: signedCmd) bool {
        var tokens = utilsl.split(u8, p_self.alloc, cmdBuffer.str, ' ') catch {
            return false;
        };
        defer tokens.deinit(p_self.alloc);

        if (utilsl.contains(cmdBuffer.str, "SPIN", .ignoreCase)) {
            if (tokens.items.len < 11) {
                return false;
            }
        } else if (utilsl.contains(cmdBuffer.str, "CHECK", .ignoreCase)) {
            if (tokens.items.len < 9) {
                return false;
            }
        } else if (utilsl.contains(cmdBuffer.str, "STRING", .ignoreCase)) {
            if (tokens.items.len < 9) {
                return false;
            }
        } else if (utilsl.contains(cmdBuffer.str, "COMBO", .ignoreCase)) {
            if (tokens.items.len < 9) {
                return false;
            }
        } else {
            return false;
        }
        var eng = p_self.engineInventory.items.items[cmdBuffer.engine];
        eng.addOption(p_self.alloc, cmdBuffer.str) catch {
            return false;
        };
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

fn sendOptions(p_self: *guiState, options: [][]const u8, engineIndex: u8) !void {
    for (options) |opt| {
        try p_self.respond(opt, engineIndex);
    }
}

fn mainGuiThread(p_self: *guiState, nMatch: u8, engines_opts: [][][]const u8) void {
    // check engine

    mainl.initAll();

    p_self.respondAll("UCI") catch {};

    p_self.waitAllPlayers() catch {
        p_self.close();
        return;
    };

    p_self.respondAll("ISREADY") catch unreachable;
    for (0..engines_opts.len) |i| {
        sendOptions(p_self, engines_opts[i], @intCast(i)) catch {
            p_self.close();
            return;
        };
    }

    var record: matchResultContainer = .{};
    var matchCount: u8 = 0;
    while (matchCount < nMatch) {
        matchRoutine(p_self) catch {
            p_self.close();
            return;
        };
        matchCount += 1;
        record.addOutCome(&p_self.match);
    }
    record.saveLog(p_self.alloc, &p_self.match) catch |err| {
        std.debug.print("[CLOSE] error {} while saving the match stats\n", .{err});
    };
    p_self.close();
}
fn matchRoutine(p_self: *guiState) !void {
    try p_self.respondAll("setoption name clearhash");
    p_self.startMatch(chessl.DEFAULT_FEN) catch {
        @panic("Failed to start the match");
    };

    var lastUpated: i64 = 0;
    while (p_self.status.running and p_self.match.status == .Continue) {
        if (p_self.match.nextTurnTrigger) {
            const stat = try onNextTurnTrigger(p_self);
            if (!stat) {
                break;
            }
        }

        std.Thread.sleep(configl.WAIT_TICKRATE_NS);
        const stat = p_self.match.timeTick();
        if (!stat) {
            // flagged
            const p = p_self.getCurrentPlayer();
            try p_self.sendEngineInterrupt(p.engineUsed);
            p_self.match.status = .Flagged;
        }
        if (((std.time.milliTimestamp() - lastUpated) > configl.EVALUTATION_GUI_WAIT_MS) or (p_self.match.positionUpdated)) {
            p_self.match.positionUpdated = false;
            lastUpated = std.time.milliTimestamp();
            try timeTickUserFacingInterface(p_self);
        }
    }
    if (p_self.status.debugMode) {
        std.debug.print("[DEBUG] matchRoutine: Exiting match with status: {}\n", .{p_self.match.status});
        chessl.print_boardstate(&p_self.match.chessState);
    }
}
fn timeTickUserFacingInterface(p_self: *guiState) !void {
    //
    utilsl.clear();
    chessl.print_board(&p_self.match.chessState);
    const times = try p_self.match.getGoStr(p_self.alloc);
    defer (p_self.alloc.free(times));
    std.debug.print("{s}\n", .{times});
}

fn onNextTurnTrigger(p_self: *guiState) !bool {
    try p_self.match.turnComplete(p_self.alloc);
    p_self.match.nextTurnTrigger = false;
    _ = p_self.nextTurn() catch {
        p_self.close();
        return false;
    };
    return true;
}

fn entrypointReaderThreading(p_self: *guiState, engineIndex: u8) void {
    p_self.readingThread(engineIndex) catch unreachable;
}
fn dispatchReadersThreads(p_self: *guiState) !void {
    for (0..p_self.engineInventory.len) |i| {
        const inputThread = try std.Thread.spawn(.{}, entrypointReaderThreading, .{ p_self, @as(u8, @intCast(i)) });
        try p_self.workingThreads.append(p_self.alloc, inputThread);
    }
}
fn entrypointServingThreading(p_self: *guiState) void {
    p_self.servingGuiThread() catch unreachable;
}

var stdin_buffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
var stdout_buffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);

pub fn launch_gui(path1: []const u8, path2: []const u8, nMatch: u8, debugMode: bool, engines_opts: [][][]const u8) !void {
    var ret: guiState = try guiState.init();
    _ = try ret.addEngine(path1);
    _ = try ret.addEngine(path2);

    ret.match.playerInv[0] = try player.init(ret.alloc, bulletTimeFormat, .BLACK, 1, "2");
    ret.match.playerInv[1] = try player.init(ret.alloc, bulletTimeFormat, .WHITE, 0, "1");

    ret.status.running = true;
    ret.status.phase = .MATCH;
    ret.status.debugMode = debugMode;
    try dispatchReadersThreads(&ret);
    const servingThread = try std.Thread.spawn(.{}, entrypointServingThreading, .{&ret});
    try ret.workingThreads.append(ret.alloc, servingThread);

    mainGuiThread(&ret, nMatch, engines_opts);
    return;
}

pub fn main() void {
    //

    const engine1: []const u8 = "engines/engine1";
    const engine2: []const u8 = "engines/engine2";
    var engine2_opt: [1][]const u8 = .{"setoption name UCI_elo 3000"};
    var engine1_opt: [1][]const u8 = .{"setoption name UCI_elo value 1500"};

    var opts = [_][][]const u8{ &engine1_opt, &engine2_opt };
    launch_gui(engine1, engine2, 5, false, &opts) catch {
        return;
    };
}
