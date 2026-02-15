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
const bookl = @import("book.zig");
const filel = @import("file.zig");
const heuristicl = @import("heuristic.zig");

const stringl = @import("string.zig");
const std = @import("std");

const e_color = chessl.e_color;
pub const e_matchFlag = enum(u8) { Error, Continue, CheckMate, StaleMate, StaleMateRepetition, StaleMateInsuficientMaterial, Flagged, Dnf };
const Board_state = chessl.Board_state;
const e_square = squarel.e_square;
const string = stringl.string;
const scoreType = heuristicl.scoreType;

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
    finalFen: string = undefined,
    pub fn getScore(self: *matchResultsBench) scoreType {
        var ret: scoreType = @intCast(self.win);
        ret += @as(scoreType, @floatFromInt(self.draw)) / 2;
        return ret;
    }
};
const matchResultContainer = struct {
    items: [MAX_ENGINES]matchResultsBench = std.mem.zeroes([MAX_ENGINES]matchResultsBench),
    fens: std.ArrayList(string) = undefined,
    pub fn init(alloc: std.mem.Allocator) !matchResultContainer {
        return .{ .fens = try std.ArrayList(string).initCapacity(alloc, 4) };
    }
    pub fn addOutCome(p_self: *matchResultContainer, alloc: std.mem.Allocator, match: *matchStatus) !void {
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
            .StaleMateInsuficientMaterial => {
                p_self.items[currEngine].draw += 1;
                p_self.items[otherEngine].draw += 1;
            },
        }
        for (0..2) |i| {
            const currEng = match.playerInv[i].engineUsed;
            p_self.items[currEng].nMatch += 1;
            var timeTaken: i64 = 0;
            for (match.playerInv[i].timeTaken.items) |time| {
                timeTaken += time;
            }

            p_self.items[currEng].avgTimePerTurn = @divFloor(timeTaken, @as(i64, @intCast(match.playerInv[i].timeTaken.items.len + 1)));
        }
        const lineString = try match.chessState.move_history.getLineString(alloc);

        try p_self.fens.append(alloc, lineString);
    }
    pub fn saveLog(p_self: *matchResultContainer, alloc: std.mem.Allocator, match: *matchStatus, settings: *guiSetting) !void {
        if (!settings.match.saveLogs) {
            return;
        }
        var fileName: []u8 = undefined;
        if (settings.match.logPathProvided) {
            fileName = try std.fmt.allocPrint(alloc, "{s}/match_logs_{d}.txt", .{ settings.match.logPath._slice(), std.time.timestamp() });
        } else {
            fileName = try std.fmt.allocPrint(alloc, "logs/match_logs_{d}.txt", .{std.time.timestamp()});
        }
        const file = try std.fs.cwd().createFile(fileName, .{ .read = true });
        defer alloc.free(fileName);
        defer file.close();

        for (0..2) |i| {
            const engIdx = match.playerInv[i].engineUsed;
            const res = p_self.items[engIdx];
            const scoreStr = try std.fmt.allocPrint(alloc, "engine: {s}, {d} matches, win: {d}, lose: {d}, draw: {d}, flagged: {d}, speed: {d} ms/move;\n", .{ settings.engineNames[engIdx]._slice(), res.nMatch, res.win, res.lose, res.draw, res.flagged, res.avgTimePerTurn });
            defer alloc.free(scoreStr);
            _ = try file.write(scoreStr);
        }

        // save the setting part
        try settings.writeSummary(&file);

        _ = try file.write("final positions: \n");
        for (0..p_self.fens.items.len) |i| {
            const fenStr = try std.fmt.allocPrint(alloc, "\t{s};\n", .{p_self.fens.items[i]._slice()});
            defer alloc.free(fenStr);
            _ = try file.write(fenStr);
        }
    }
    pub fn printResults(p_self: *matchResultContainer, alloc: std.mem.Allocator) !void {
        var buffer: [configl.MAX_USER_INPUT]u8 = undefined; // Buffer for stdout
        var writer = std.fs.File.stdout().writer(&buffer);
        const interface = &writer.interface;
        for (0..p_self.items.len) |i| {
            const res = p_self.items[i];
            const respmsg = try std.fmt.allocPrint(alloc, "{d} {d} {d} \n", .{ res.win, res.lose, res.draw });
            defer alloc.free(respmsg);
            try interface.writeAll(respmsg);
            try interface.flush();
        }
    }
    pub fn free(p_self: *matchResultContainer, alloc: std.mem.Allocator) void {
        for (p_self.fens.items) |*fens| {
            fens.free(alloc);
        }
        p_self.fens.deinit(alloc);
    }
};
const MAX_ENGINES: u8 = 2;
const timeFormat = struct {
    time: i64 = DEFAULT_TIME_MS,
    inc: i64 = DEFAULT_TIME_INC_MS,
};
const standardTimeFormat: timeFormat = .{ .time = 300000, .inc = 5000 };
const bulletTimeFormat: timeFormat = .{ .time = 60000, .inc = 0 };
const ultraBulletTimeFormat: timeFormat = .{ .time = 30000, .inc = 0 };

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
        // the other player(!whiteToMove()) is used as the chess state was already updated with the matchOnBestMove
        var p = &p_self.playerInv[@intFromBool(!p_self.chessState.whiteToMove())];
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
    pub fn init(alloc: std.mem.Allocator, timeF: timeFormat, color: e_color, engineIndex: u8) !player {
        var ret: player = .{ ._time = timeF.time, .time = timeF.time, .time_inc = timeF.inc, .color = color, .engineUsed = engineIndex };
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
    config: *guiSetting = undefined,
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
    pub fn setBoardFromLine(p_self: *guiState, line: *string) !void {
        const moves = try chessl.algebraicLineToIMoveMatch(line);
        p_self.match.chessState = try chessl.getBoardFromFen(p_self.alloc, chessl.DEFAULT_FEN);
        for (0..moves.len) |i| {
            const move = moves.moves[i];
            p_self.match.chessState.makeMove(move);
            chessl.sanityCheckBoardState(&p_self.match.chessState);
        }
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
                std.debug.print("[DEBUG] readingThread.gui (#{d}): caught err {}\n", .{ engineIndex, err });
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
        if (!self.config.match.saveLogs) {
            return;
        }
        var fileName: []u8 = undefined;
        if (self.config.match.logPathProvided) {
            fileName = try std.fmt.allocPrint(self.alloc, "{s}/logs_{d}.txt", .{ self.config.match.logPath._slice(), std.time.timestamp() });
        } else {
            fileName = try std.fmt.allocPrint(self.alloc, "logs/logs_{d}.txt", .{std.time.timestamp()});
        }
        defer self.alloc.free(fileName);
        const file = try std.fs.cwd().createFile(fileName, .{ .read = true });
        defer file.close();
        for (0..self.logs.items.len) |i| {
            _ = try file.write(self.logs.items[i]);
        }
    }
    pub fn close(p_self: *guiState) void {
        std.debug.print("[CLOSE] saving logs to log file\n", .{});
        if (p_self.config.match.useOpeningBook) {
            p_self.config.match.openingDb.free(p_self.alloc);
        }
        p_self.match.status = .Error;
        p_self.saveLog() catch |err| {
            std.debug.print("[CLOSE] error while saving: {}\n", .{err});
        };
        defer p_self.freeLog();
        p_self.respondAll("QUIT") catch {};
        p_self.status.running = false;
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
                // not really usefull from the point of view of the gui
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
    pub fn startMatch(p_self: *guiState) !void {
        p_self.match.reset();
        p_self.match.startTime();
        p_self.status.phase = .MATCH;
        try p_self.respondAll("ucinewgame");
        var line = try p_self.match.chessState.move_history.getLineString(p_self.alloc);
        defer line.free(p_self.alloc);
        const msg = try std.fmt.allocPrint(p_self.alloc, "position fen {s} {s}", .{ p_self.match.chessState.get_fen(), line._slice() });
        defer p_self.alloc.free(msg);
        p_self.match.availableMoves = move_genl.generateLegalMoves(&p_self.match.chessState);

        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] guiState.startMatch: First player is engine: {d}\n", .{p_self.getCurrentPlayer().engineUsed});
        }
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
        if (p_self.match.chessState.isInsufficientMaterial()) {
            p_self.match.status = .StaleMateInsuficientMaterial;
            return false;
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
        try p_self.respond("stop", engineIndex);
        // this is needed as we do not want to send critical commands as the engines is cleaning up its internals.
        // bug fixed with this:
        // when an engine is flagged, sendInterrupt is invoked and right after a clearHash is sent for the next match to begin. Thus clearing the hashTable while the engine is still potentially searching.
        try p_self.waitEngine();
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
        if (p_self.status.debugMode) {
            chessl.sanityCheckBoardState(&p_self.match.chessState);
        }
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

fn sendOptions(p_self: *guiState, options: std.ArrayList(string), engineIndex: u8) !void {
    if (p_self.status.debugMode) {
        try p_self.respond("DEBUG on", engineIndex);
    } else {
        try p_self.respond("DEBUG off", engineIndex);
    }
    for (options.items) |opt| {
        try p_self.respond(opt._slice(), engineIndex);
    }
}

fn mainGuiThread(p_self: *guiState, nMatch: u8, engines_opts: [chessl.NUMBER_PLAYER]std.ArrayList(string)) void {
    mainl.initAll(p_self.status.debugMode);
    if (p_self.config.match.useOpeningBook) {
        // init the db or smth
        p_self.config.match.openingDb = bookl.openingDatabase.init(p_self.alloc, &p_self.config.match.openingBookPath, configl.SEED) catch {
            p_self.close();
            return;
        };
    }

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

    var record: matchResultContainer = matchResultContainer.init(p_self.alloc) catch {
        p_self.close();
        return;
    };
    var matchCount: u8 = 0;
    var _nMatch = nMatch;
    if (p_self.config.match.playerSwitch) {
        _nMatch = _nMatch * 2;
    }
    while (matchCount < _nMatch) {
        if (matchCount != 0 and p_self.config.match.playerSwitch) {
            const tmp = p_self.match.playerInv[0].engineUsed;
            p_self.match.playerInv[0].engineUsed = p_self.match.playerInv[1].engineUsed;
            p_self.match.playerInv[1].engineUsed = tmp;
            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG] mainGuiThread: swaping player white engine: {d}, black engine: {d}\n", .{ p_self.match.playerInv[1].engineUsed, p_self.match.playerInv[0].engineUsed });
            }
        }
        matchRoutine(p_self) catch {
            p_self.close();
            return;
        };
        chessl.print_boardstate(&p_self.match.chessState);
        matchCount += 1;
        record.addOutCome(p_self.alloc, &p_self.match) catch {
            p_self.close();
            return;
        };
    }
    record.printResults(p_self.alloc) catch {};
    record.saveLog(p_self.alloc, &p_self.match, p_self.config) catch |err| {
        std.debug.print("[CLOSE] error {} while saving the match stats\n", .{err});
    };
    p_self.close();
    record.free(p_self.alloc);
}
fn matchRoutine(p_self: *guiState) !void {
    try p_self.respondAll("setoption name clearhash");
    if (p_self.config.match.useOpeningBook and p_self.config.match.openingBookPathProvided) {
        var openings = try p_self.config.match.openingDb.sample(p_self.alloc, 1, .draw);
        if (p_self.config.debugMode) {
            std.debug.print("[DEBUG] matchRoutine: opening picked: {s}\n", .{openings.items[0]._slice()});
        }
        defer openings.deinit(p_self.alloc);
        try p_self.setBoardFromLine(&openings.items[0]);
    } else {
        p_self.setBoard(chessl.DEFAULT_FEN);
    }
    p_self.startMatch() catch {
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

    const eval = heuristicl.evaluate_debug(&p_self.match.chessState, &heuristicl.globalHeuristic);
    std.debug.print("Current evaluation: \n", .{});
    eval.print();
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

pub fn launch_gui(infoPath: []const u8) !void {
    var settings = try parseInfoFile(mainl.GLOBAL_ALLOC, infoPath);
    defer settings.free(mainl.GLOBAL_ALLOC);

    var ret: guiState = try guiState.init();
    ret.config = &settings;

    _ = try ret.addEngine(settings.enginePaths[0]._slice());
    _ = try ret.addEngine(settings.enginePaths[1]._slice());

    ret.match.playerInv[0] = try player.init(ret.alloc, standardTimeFormat, .BLACK, 1);
    ret.match.playerInv[1] = try player.init(ret.alloc, standardTimeFormat, .WHITE, 0);

    ret.status.running = true;
    ret.status.phase = .MATCH;
    ret.status.debugMode = settings.debugMode;
    try dispatchReadersThreads(&ret);
    const servingThread = try std.Thread.spawn(.{}, entrypointServingThreading, .{&ret});
    try ret.workingThreads.append(ret.alloc, servingThread);

    mainGuiThread(&ret, settings.match.nMatch, settings.engineOptions);

    return;
}
const configMatch = struct {
    nMatch: u8 = 0,
    playerSwitch: bool = false,
    timeF: timeFormat = standardTimeFormat,
    useOpeningBook: bool = false,
    openingBookPath: string = undefined,
    openingBookPathProvided: bool = false,

    saveLogs: bool = true,
    logPath: string = undefined,
    logPathProvided: bool = false,

    openingDb: bookl.openingDatabase = undefined,
    pub fn setOpeningBookPath(p_self: *configMatch, alloc: std.mem.Allocator, path: []const u8) anyerror!void {
        if (p_self.openingBookPathProvided) {
            p_self.openingBookPath.free(alloc);
        }
        if (!filel.fileExists(path)) {
            return stringl.string_err.itemNotFound_error;
        }
        p_self.openingBookPathProvided = true;
        p_self.openingBookPath = try string.initFromSlice(alloc, path);
    }
    pub fn setLoggingLocationPath(p_self: *configMatch, alloc: std.mem.Allocator, path: []const u8) anyerror!void {
        if (p_self.logPathProvided) {
            p_self.logPath.free(alloc);
        }
        if (!filel.dirExists(path)) {
            try filel.makedirR(path);
        }
        p_self.logPathProvided = true;
        p_self.logPath = try string.initFromSlice(alloc, path);
    }
};

const guiSetting = struct {
    match: configMatch = .{},
    enginePaths: [chessl.NUMBER_PLAYER]string = undefined,
    engineNames: [chessl.NUMBER_PLAYER]string = undefined,
    engineOptions: [chessl.NUMBER_PLAYER]std.ArrayList(string) = undefined,
    nEngines: u8 = 0,
    debugMode: bool = false,
    pub fn init(alloc: std.mem.Allocator) !guiSetting {
        var ret: guiSetting = .{};
        ret.engineOptions[0] = try std.ArrayList(string).initCapacity(alloc, 2);
        ret.engineOptions[1] = try std.ArrayList(string).initCapacity(alloc, 2);
        return ret;
    }
    pub fn setEngineName(p_self: *guiSetting, alloc: std.mem.Allocator, engineIndex: u8, engineName: []const u8) !void {
        p_self.engineNames[engineIndex] = try string.initFromSlice(alloc, engineName);
    }
    pub fn setEnginePath(p_self: *guiSetting, alloc: std.mem.Allocator, engineIndex: u8, enginePath: []const u8) !void {
        p_self.enginePaths[engineIndex] = try string.initFromSlice(alloc, enginePath);
    }

    pub fn addEngineOption(p_self: *guiSetting, alloc: std.mem.Allocator, engineIndex: u8, enginePath: []const u8) !void {
        const strOption = try string.initFromSlice(alloc, enginePath);
        try p_self.engineOptions[engineIndex].append(alloc, strOption);
    }
    pub fn free(p_self: *guiSetting, alloc: std.mem.Allocator) void {
        for (0..chessl.NUMBER_PLAYER) |i| {
            p_self.engineNames[i].free(alloc);
            p_self.enginePaths[i].free(alloc);
            for (p_self.engineOptions[i].items) |*opt| {
                opt.free(alloc);
            }
        }
    }
    pub fn print(p_self: *guiSetting) void {
        for (0..chessl.NUMBER_PLAYER) |i| {
            std.debug.print("Engine #{d}\n", .{i});
            std.debug.print("\t name: {s}\n", .{p_self.engineNames[i]._slice()});
            std.debug.print("\t path: {s}\n", .{p_self.enginePaths[i]._slice()});

            for (p_self.engineOptions[i].items) |*opt| {
                std.debug.print("\t option: {s}\n", .{opt.*._slice()});
            }
        }

        std.debug.print("Match settings: \n", .{});
        std.debug.print("\t nMatch: {d}\n", .{p_self.match.nMatch});
        std.debug.print("\t player switch: {}\n", .{p_self.match.playerSwitch});
        std.debug.print("\t time format: time {d} inc {d}\n", .{ p_self.match.timeF.time, p_self.match.timeF.inc });

        std.debug.print("\t use opening book {}\n", .{p_self.match.useOpeningBook});
        std.debug.print("\t opening book path {s}\n", .{p_self.match.openingBookPath._slice()});

        std.debug.print("\t save logs {}\n", .{p_self.match.saveLogs});
        std.debug.print("\t logs path {s}\n", .{p_self.match.logPath._slice()});
    }
    pub fn writeSummary(p_self: *guiSetting, fd: *const std.fs.File) !void {
        var strBuffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
        for (0..chessl.NUMBER_PLAYER) |i| {
            const engineNbr = try std.fmt.bufPrint(&strBuffer, "Engine #{d}\n", .{i});
            _ = try fd.write(engineNbr);

            const engineName = try std.fmt.bufPrint(&strBuffer, "\t name: {s}\n", .{p_self.engineNames[i]._slice()});
            _ = try fd.write(engineName);

            const enginePath = try std.fmt.bufPrint(&strBuffer, "\t path: {s}\n", .{p_self.enginePaths[i]._slice()});
            _ = try fd.write(enginePath);

            for (p_self.engineOptions[i].items) |*opt| {
                const engineOpt = try std.fmt.bufPrint(&strBuffer, "\t option: {s}\n", .{opt.*._slice()});
                _ = try fd.write(engineOpt);
            }
        }

        _ = try fd.write("Match settings: \n");

        const nMatch = try std.fmt.bufPrint(&strBuffer, "\t nMatch: {d}\n", .{p_self.match.nMatch});
        _ = try fd.write(nMatch);

        const pSwitch = try std.fmt.bufPrint(&strBuffer, "\t player switch: {}\n", .{p_self.match.playerSwitch});
        _ = try fd.write(pSwitch);

        const timeStr = try std.fmt.bufPrint(&strBuffer, "\t time format: time {d} inc {d}\n", .{ p_self.match.timeF.time, p_self.match.timeF.inc });
        _ = try fd.write(timeStr);

        const useOpeningStr = try std.fmt.bufPrint(&strBuffer, "\t use opening book {}\n", .{p_self.match.useOpeningBook});
        _ = try fd.write(useOpeningStr);

        const openingBookPath = try std.fmt.bufPrint(&strBuffer, "\t opening book path {s}\n", .{p_self.match.openingBookPath._slice()});
        _ = try fd.write(openingBookPath);
    }
};
pub fn parseInfoFile(alloc: std.mem.Allocator, path: []const u8) !guiSetting {
    var tokens = try filel.getTokensFromFile(alloc, path, '\n');
    defer stringl.freeArrayList_string(alloc, &tokens);
    var ret: guiSetting = try guiSetting.init(alloc);
    var matchSection: bool = false;

    for (0..tokens.items.len) |i| {
        var s = tokens.items[i];
        if (s.startsWith("//")) {
            continue;
        }
        if (s.containsE("[match]", .ignoreCase)) {
            matchSection = true;
            continue;
        }
        var status: bool = undefined;

        if (matchSection) {
            status = handleMatchInfoStrBuffer(alloc, &ret, &s);
        } else {
            status = handleInfoStrBuffer(alloc, &ret, &s);
        }
        if (!status) {
            std.debug.print("Match handling of {s} failed \n", .{s._slice()});
        }
    }
    ret.print();
    return ret;
}
fn handleMatchInfoStrBuffer(alloc: std.mem.Allocator, settings: *guiSetting, buffer: *string) bool {
    if (buffer.startsWith("nMatch")) {
        const nbrStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        settings.match.nMatch = std.fmt.parseInt(u8, nbrStr, 10) catch {
            return false;
        };

        return true;
    } else if (buffer.startsWith("playerSwitch")) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.equal(u8, boolStr, "true")) {
            settings.match.playerSwitch = true;
        } else if (utilsl.equal(u8, boolStr, "false")) {
            settings.match.playerSwitch = false;
        } else {
            return false;
        }

        return true;
    } else if (buffer.startsWith("debugMode")) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.equal(u8, boolStr, "true")) {
            settings.debugMode = true;
        } else if (utilsl.equal(u8, boolStr, "false")) {
            settings.debugMode = false;
        } else {
            return false;
        }
        return true;
    } else if (buffer.startsWith("useOpeningBook")) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.equal(u8, boolStr, "true")) {
            settings.match.useOpeningBook = true;
        } else if (utilsl.equal(u8, boolStr, "false")) {
            settings.match.useOpeningBook = false;
        } else {
            return false;
        }
        return true;
    } else if (buffer.startsWith("openingBookPath")) {
        const path = buffer.extractFromBounds("\"", "\"") catch {
            return false;
        };
        settings.match.setOpeningBookPath(alloc, path) catch {
            return false;
        };
        return true;
    } else if (buffer.startsWith("saveLogs")) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.equal(u8, boolStr, "true")) {
            settings.match.saveLogs = true;
        } else if (utilsl.equal(u8, boolStr, "false")) {
            settings.match.saveLogs = false;
        } else {
            return false;
        }
        return true;
    } else if (buffer.startsWith("logsLocation")) {
        const path = buffer.extractFromBounds("\"", "\"") catch {
            return false;
        };
        settings.match.setLoggingLocationPath(alloc, path) catch {
            return false;
        };
        return true;
    }

    return false;
}

fn handleInfoStrBuffer(alloc: std.mem.Allocator, settings: *guiSetting, buffer: *string) bool {
    if (buffer.startsWith("[")) {
        if (settings.nEngines == chessl.NUMBER_PLAYER) {
            return false;
        }
        settings.nEngines += 1;

        return true;
    } else if (buffer.startsWith("name")) {
        const name = buffer.extractFromBounds("\"", "\"") catch {
            return false;
        };
        settings.setEngineName(alloc, settings.nEngines - 1, name) catch {
            return false;
        };
        return true;
    } else if (buffer.startsWith("path")) {
        const path = buffer.extractFromBounds("\"", "\"") catch {
            return false;
        };
        settings.setEnginePath(alloc, settings.nEngines - 1, path) catch {
            return false;
        };
        return true;
    } else if (buffer.startsWith("\"")) {
        const opt = buffer.extractFromBounds("\"", "\"") catch {
            return false;
        };
        settings.addEngineOption(alloc, settings.nEngines - 1, opt) catch {
            return false;
        };
        return true;
    }
    return false;
}

pub fn _main() !void {
    const infoFile = "engines/engine.info";
    launch_gui(infoFile) catch {
        return;
    };
}

pub fn main() !void {
    // 1st arg is the zig file, 2nd is the .info file for the evaluation
    std.debug.assert(std.os.argv.len > 1);
    const path_null: [*:0]u8 = std.os.argv[1];
    const path = std.mem.span(path_null);
    try launch_gui(path);
}
