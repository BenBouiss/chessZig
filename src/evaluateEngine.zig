// zig file for match orchestration in uci mode or more(?)
const chessl = @import("chess.zig");
const move_genl = @import("move_generation.zig");
const enginel = @import("engine.zig");
const mainl = @import("main.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const movel = @import("move.zig");
const bookl = @import("book.zig");
const filel = @import("file.zig");
const heuristicl = @import("heuristic.zig");
const mathl = @import("math.zig");
const timel = @import("time.zig");
const lockl = @import("lock.zig");
const typel = @import("type.zig");
const hashTablel = @import("hashTable.zig");
const boardl = @import("board.zig");

const stringl = @import("string.zig");
const std = @import("std");

const e_color = typel.e_color;
pub const e_matchFlag = enum(u8) { Error, Continue, CheckMate, StaleMate, StaleMateRepetition, StaleMateInsuficientMaterial, Flagged, Dnf };

pub const SPRT_RES = enum(u8) { NULL, H0, H1 };

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
    closing: bool = false,
    debugMode: bool = false,
};

pub const err_eval = error{
    mem_error,
    nei_error,
    unknownMove_error,
    timeout_error,
    match_error,
};

const matchResult = struct {
    win: usize = 0,
    lose: usize = 0,
    draw: usize = 0,
    flagged: usize = 0,
};

const matchResultsBench = struct {
    //
    //0: (B) Win / Lose / Draw
    //1: (W) Win / Lose / Draw
    res: [2]matchResult = .{ .{}, .{} },
    avgTimePerTurn: i64 = 0,
    stdTimePerTurn: i64 = 0,
    nMatch: usize = 0,
    finalFen: string = undefined,
    pub fn getScore(self: matchResultsBench) scoreType {
        var ret: scoreType = @intCast(self.res.win[0] + self.res.win[1]);
        ret += @as(scoreType, @floatFromInt(self.res.draw[0] + self.res.draw[1])) / 2;
        return ret;
    }
    pub fn combine(self: matchResultsBench) matchResult {
        return .{ .win = self.res[0].win + self.res[1].win, .draw = self.res[0].draw + self.res[1].draw, .lose = self.res[0].lose + self.res[1].lose, .flagged = self.res[0].flagged + self.res[1].flagged };
    }
};
const matchResultContainer = struct {
    items: [MAX_ENGINES]matchResultsBench = std.mem.zeroes([MAX_ENGINES]matchResultsBench),
    fens: std.ArrayList(string) = undefined,
    pub fn init(alloc: std.mem.Allocator) !matchResultContainer {
        return .{ .fens = try std.ArrayList(string).initCapacity(alloc, 4) };
    }
    pub fn sprtTag(self: *matchResultContainer, engineIdx: usize, settings: configSPRT) SPRT_RES {
        const res = self.items[engineIdx];
        const s = res.combine();
        return computeSPRT(settings.elo_0, settings.elo_1, settings.alpha, settings.beta, s.win, s.draw, s.lose);
    }
    pub fn addOutCome(p_self: *matchResultContainer, alloc: std.mem.Allocator, match: *matchStatus) !void {
        const p = match.chessState.whiteToMove();
        const currEngine = match.playerInv[@intFromBool(p)].engineUsed;
        const otherEngine = match.playerInv[@intFromBool(!p)].engineUsed;
        const oneEngine: bool = (currEngine == otherEngine);

        switch (match.status) {
            .Continue, .Error => {
                std.debug.print("[PANIC] bad status found: {}\n", .{match.status});
            },
            .CheckMate => {
                p_self.items[otherEngine].res[@intFromBool(!p)].win += 1;
                p_self.items[currEngine].res[@intFromBool(p)].lose += 1;
            },

            .Flagged => {
                p_self.items[currEngine].res[@intFromBool(p)].flagged += 1;
                if (match.chessState.isInsufficientMaterialSide(!p)) {
                    p_self.items[currEngine].res[@intFromBool(p)].draw += 1;
                    p_self.items[otherEngine].res[@intFromBool(!p)].draw += 1;
                } else {
                    p_self.items[otherEngine].res[@intFromBool(!p)].win += 1;
                    p_self.items[currEngine].res[@intFromBool(p)].lose += 1;
                }
            },
            .StaleMate, .StaleMateRepetition, .Dnf => {
                p_self.items[currEngine].res[@intFromBool(p)].draw += 1;
                p_self.items[otherEngine].res[@intFromBool(!p)].draw += 1;
            },
            .StaleMateInsuficientMaterial => {
                p_self.items[currEngine].res[@intFromBool(p)].draw += 1;
                p_self.items[otherEngine].res[@intFromBool(!p)].draw += 1;
            },
        }

        for (0..2 - @as(usize, @intCast(@intFromBool(oneEngine)))) |i| {
            const currEng = match.playerInv[i].engineUsed;
            p_self.items[currEng].nMatch += 1;
            p_self.items[currEng].stdTimePerTurn = 0;
            p_self.items[currEng].avgTimePerTurn = @divFloor(match.playerInv[i].timeTakenCum, match.playerInv[i].movesMade + 1);
        }
        const lineString = try match.chessState.moveHistory.getLineString(alloc);

        try p_self.fens.append(alloc, lineString);
    }
    pub fn saveLog(p_self: *matchResultContainer, alloc: std.mem.Allocator, match: *matchStatus, settings: *guiSetting) !void {
        var fileName: []u8 = undefined;
        if (settings.match.logPathProvided) {
            fileName = try std.fmt.allocPrint(alloc, "{s}/match_logs_{d}.txt", .{ settings.match.logPath._slice(), std.Io.Timestamp.now(mainl.getGlobalIo(), .real) });
        } else {
            fileName = try std.fmt.allocPrint(alloc, "out/logs/match_logs_{d}.txt", .{std.Io.Timestamp.now(mainl.getGlobalIo(), .real)});
        }
        const file = try std.Io.Dir.createFile(.cwd(), mainl.getGlobalIo(), fileName, .{ .read = true });
        defer alloc.free(fileName);
        defer file.close(mainl.getGlobalIo());

        for (0..settings.nEngines) |i| {
            const engIdx = match.playerInv[i].engineUsed;
            const res = p_self.items[engIdx];
            const s = res.combine();
            const nwins = s.win;
            const nloses = s.lose;
            const ndraws = s.draw;
            const nflags = s.flagged;

            const scoreStr = try std.fmt.allocPrint(alloc, "engine: {s}, {d} matches, win: {d}, lose: {d}, draw: {d}, flagged: {d}, speed: {d}(+-{d}) ms/move;\n", .{ settings.engineNames[engIdx]._slice(), res.nMatch, nwins, nloses, ndraws, nflags, res.avgTimePerTurn, res.stdTimePerTurn });
            defer alloc.free(scoreStr);
            try file.writeStreamingAll(mainl.getGlobalIo(), scoreStr[0..scoreStr.len]);

            if (settings.match.sprt.enabled) {
                const breakStr = try std.fmt.allocPrint(alloc, "engine: {s}, breakdown (w/l/d) w: {d}/{d}/{d}, b: {d}/{d}/{d} sprt {};\n", .{ settings.engineNames[engIdx]._slice(), res.res[1].win, res.res[1].lose, res.res[1].draw, res.res[0].win, res.res[0].lose, res.res[0].draw, p_self.sprtTag(@intCast(engIdx), settings.match.sprt) });
                defer alloc.free(breakStr);
                try file.writeStreamingAll(mainl.getGlobalIo(), breakStr[0..breakStr.len]);
            } else {
                const breakStr = try std.fmt.allocPrint(alloc, "engine: {s}, breakdown (w/l/d) w: {d}/{d}/{d}, b: {d}/{d}/{d};\n", .{ settings.engineNames[engIdx]._slice(), res.res[1].win, res.res[1].lose, res.res[1].draw, res.res[0].win, res.res[0].lose, res.res[0].draw });
                defer alloc.free(breakStr);
                try file.writeStreamingAll(mainl.getGlobalIo(), breakStr[0..breakStr.len]);
            }
        }

        // save the setting part
        try settings.writeSummary(&file);

        //_ = try file.write("final positions: \n");
        try file.writeStreamingAll(mainl.getGlobalIo(), "final positions: \n");
        for (0..p_self.fens.items.len) |i| {
            const fenStr = try std.fmt.allocPrint(alloc, "\t{s};\n", .{p_self.fens.items[i]._slice()});
            defer alloc.free(fenStr);
            //_ = try file.write(fenStr);
            try file.writeStreamingAll(mainl.getGlobalIo(), fenStr[0..fenStr.len]);
        }
    }
    pub fn printResults(p_self: *matchResultContainer, alloc: std.mem.Allocator) !void {
        var buffer: [configl.MAX_USER_INPUT]u8 = undefined; // Buffer for stdout
        //var writer = std.fs.File.stdout().writer(&buffer);
        var writer = std.Io.File.stdout().writer(mainl.getGlobalIo(), &buffer);
        const interface = &writer.interface;
        for (0..p_self.items.len) |i| {
            const res = p_self.items[i];

            // add the results from white and black for each engines
            const nwins = res.res[0].win + res.res[1].win;
            const nloses = res.res[0].lose + res.res[1].lose;
            const ndraws = res.res[0].draw + res.res[1].draw;

            const respmsg = try std.fmt.allocPrint(alloc, "{d} {d} {d} \n", .{ nwins, nloses, ndraws });
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
    pub fn init(buffer: []const u8, engineIndex: u8) signedCmd {
        return .{ .str = buffer, .engine = engineIndex };
    }
};
const matchStatus = struct {
    chessState: boardl.boardState = undefined,
    // [black / white], same as the c_occupiedBB
    playerInv: [chessl.NUMBER_PLAYER]player = undefined,
    availableMoves: movel.moveContainer = .{},
    status: e_matchFlag = .Error,
    nextTurnTrigger: bool = false,
    nextTurn_move: movel.IMove = .{},
    positionUpdated: bool = false,
    turnSW: timel.stopWatch = .{},

    pub fn reset(p_self: *matchStatus) void {
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
    pub fn getGuiStr(self: *matchStatus, alloc: std.mem.Allocator) ![]const u8 {
        var wP = self.playerInv[@intFromEnum(e_color.WHITE)].time;
        var bP = self.playerInv[@intFromEnum(e_color.BLACK)].time;
        if (self.chessState.whiteToMove()) {
            wP -= self.turnSW.timeSinceStartMs();
        } else {
            bP -= self.turnSW.timeSinceStartMs();
        }
        const guiStr = try std.fmt.allocPrint(alloc, "wtime {d} btime {d} ", .{ wP, bP });
        return guiStr;
    }
    pub fn timeTick(p_self: *matchStatus) bool {
        if (p_self.playerInv[@intFromBool(p_self.chessState.whiteToMove())].time < p_self.turnSW.timeSinceStartMs()) {
            return false;
        }
        return true;
    }
    pub fn turnComplete(p_self: *matchStatus) !void {
        // turnComplete now before makemove thus whitetomove()
        var p = &p_self.playerInv[@intFromBool(p_self.chessState.whiteToMove())];
        p.timeTakenCum += p_self.turnSW.timeSinceStartMs();
        p.movesMade += 1;
        p.time -= p_self.turnSW.timeSinceStartMs();
        p.time += p.time_inc;
    }
};

const engine_info = struct {
    alive: bool = false,
    ready: bool = false,
    options: std.ArrayList([]u8) = undefined,
    proc: std.process.Child = undefined,
    f_writer: std.Io.File.Writer,
    f_reader: std.Io.File.Reader,
    _writerBuffer: [configl.MAX_USER_INPUT]u8 = undefined,
    _readerBuffer: [configl.MAX_USER_INPUT]u8 = undefined,
    l: lockl.lock = .{},

    pub fn init(alloc: std.mem.Allocator) !*engine_info {
        var ret: *engine_info = try alloc.create(engine_info);
        ret.alive = false;
        ret.ready = false;
        ret.options = try std.ArrayList([]u8).initCapacity(alloc, 2);
        ret._writerBuffer = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
        ret._readerBuffer = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
        ret.l = .{};

        return ret;
    }
    pub fn free(p_self: *engine_info, alloc: std.mem.Allocator) void {
        for (0..p_self.options.items.len) |i| {
            alloc.free(p_self.options.items[i]);
        }
        p_self.options.deinit(alloc);
        alloc.destroy(p_self);
    }
    pub fn addOption(p_self: *engine_info, alloc: std.mem.Allocator, cmdStr: []const u8) !void {
        const e = try alloc.dupe(u8, cmdStr);
        try p_self.options.append(alloc, e);
    }
    pub fn setReady(p_self: *engine_info, stat: bool) void {
        p_self.l.acquireLock();
        p_self.ready = stat;
        p_self.l.releaseLock();
    }
    pub fn isReady(p_self: *engine_info) bool {
        p_self.l.acquireLock();
        const ret = p_self.ready;
        p_self.l.releaseLock();
        return ret;
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
    pub fn free(p_self: *engine_Inventory, alloc: std.mem.Allocator) void {
        for (0..p_self.len) |i| {
            p_self.items.items[i].free(alloc);
        }
        p_self.items.deinit(alloc);
    }
    pub fn sendKill(p_self: *engine_Inventory) void {
        for (0..p_self.len) |i| {
            p_self.items.items[i].proc.kill(mainl.getGlobalIo());
        }
    }
};
const player = struct {
    color: e_color = .WHITE,
    _time: i64 = DEFAULT_TIME_MS,
    time: i64 = DEFAULT_TIME_MS,
    time_inc: i64 = DEFAULT_TIME_INC_MS,
    engineUsed: u8 = 0, // index of the engine to be used (0-1)
    timeTakenCum: i64 = undefined,
    movesMade: i64 = 0,

    pub fn init(alloc: std.mem.Allocator, timeF: timeFormat, color: e_color, engineIndex: u8) !player {
        var ret: player = .{ ._time = timeF.time, .time = timeF.time, .time_inc = timeF.inc, .color = color, .engineUsed = engineIndex };
        ret.timeTakenCum = 0;
        ret.movesMade = 0;
        _ = alloc;
        return ret;
    }
    pub fn reset(p_self: *player) void {
        p_self.time = p_self._time;
        // removes all elements without freeing the mem
        p_self.timeTakenCum = 0;
        p_self.movesMade = 0;
    }
};

const guiState = struct {
    workingThreads: std.ArrayList(std.Thread),

    // will contains each send and receiv
    config: *guiSetting = undefined,
    logs: enginel.logging = .{},
    status: guiStatus = .{},
    alloc: std.mem.Allocator = undefined,
    input: std.ArrayList(enginel.inputChannel) = undefined,
    match: matchStatus = .{},
    startSw: timel.stopWatch = .{},
    engineInventory: engine_Inventory,

    pub fn init(alloc: std.mem.Allocator) !guiState {
        var ret: guiState = undefined;

        ret.status = .{};
        ret.match.status = .Continue;

        ret.alloc = alloc;
        ret.input = undefined;
        ret.engineInventory = try engine_Inventory.init(ret.alloc);

        ret.input = try std.ArrayList(enginel.inputChannel).initCapacity(ret.alloc, 2);

        ret.workingThreads = try std.ArrayList(std.Thread).initCapacity(ret.alloc, 2);
        ret.logs = try enginel.logging.init(alloc, INITIAL_LOGSIZE);
        ret.startSw = .{};
        ret.startSw.startTimeTick();

        return ret;
    }
    pub fn addEngine(p_self: *guiState, path: []const u8) !bool {
        const argv: [1][]const u8 = .{path};
        const opt: std.process.SpawnOptions = .{
            .argv = &argv,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .inherit,
        };

        var eng: *engine_info = try engine_info.init(p_self.alloc);
        eng.proc = try std.process.spawn(mainl.getGlobalIo(), opt);

        eng.f_writer = (eng.proc.stdin.?.writer(mainl.getGlobalIo(), &eng._writerBuffer));
        eng.f_reader = (eng.proc.stdout.?.reader(mainl.getGlobalIo(), &eng._readerBuffer));
        try p_self.input.append(p_self.alloc, try .init(p_self.alloc));

        return p_self.engineInventory.addEngine(p_self.alloc, eng);
    }
    pub inline fn setBoard(p_self: *guiState, fen: []const u8) void {
        p_self.match.chessState = chessl.getBoardFromFen(p_self.alloc, fen) catch unreachable;
    }
    pub inline fn setBoardFromLine(p_self: *guiState, line: *string) !void {
        p_self.match.chessState = try chessl.algebraicLineToBoardstate(p_self.alloc, line);
    }

    pub fn handleCmd(p_self: *guiState, cmd: signedCmd) void {
        const cmdType = getGuiCmdType(cmd.str);
        //const trimmedBuffer = utilsl.trimStr(cmdBuffer);
        const status = p_self.executeCmd(cmdType, cmd);
        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] handleCmd.guiState: executed command {}, status: {}\n", .{ cmdType, status });
        }
    }
    pub fn appendLog(p_self: *guiState, log: []const u8) !void {
        if (!p_self.config.match.saveLogs) {
            return;
        }
        const logmsg = try std.fmt.allocPrint(p_self.alloc, "[LOG]{d} ms => {s}", .{ p_self.startSw.timeSinceStartMs(), log });
        try p_self.logs.append(p_self.alloc, logmsg);
    }
    pub fn logErr(p_self: *guiState, err: anyerror) !void {
        if (!p_self.config.match.saveLogs) {
            return;
        }
        const logmsg = try std.fmt.allocPrint(p_self.alloc, "[PANIC]{d} ms => {}\n", .{ p_self.startSw.timeSinceStartMs(), err });
        try p_self.logs.append(p_self.alloc, logmsg);

        //const buffer1 = try std.fmt.allocPrint(p_self.alloc, "[PANIC]{d} ms => buffer 1 {s} {any}\n", .{ p_self.startSw.timeSinceStartMs(), p_self.engineInventory.items.items[0]._writerBuffer, p_self.engineInventory.items.items[0]._writerBuffer });
        //try p_self.logs.append(p_self.alloc, buffer1);

        //const buffer2 = try std.fmt.allocPrint(p_self.alloc, "[PANIC]{d} ms => buffer 2 {s} {any}\n", .{ p_self.startSw.timeSinceStartMs(), p_self.engineInventory.items.items[1]._writerBuffer, p_self.engineInventory.items.items[1]._writerBuffer });
        //try p_self.logs.append(p_self.alloc, buffer2);
    }

    pub fn respond(p_self: *guiState, msg: []const u8, engineIndex: u8) !void {
        const eng: *engine_info = p_self.engineInventory.items.items[engineIndex];
        var writer = &eng.f_writer.interface;

        try writer.print("{s}\n", .{msg});
        try writer.flush();

        if (p_self.config.match.saveLogs) {
            const respmsg = try std.fmt.allocPrint(p_self.alloc, "OUT(#{d}): {s} \n", .{ engineIndex, msg });
            defer p_self.alloc.free(respmsg);
            try p_self.appendLog(respmsg);
        }
        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] respond.gui(#{d}): sent msg: {s}\n", .{ engineIndex, msg });
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

        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG] readingThread.gui: Started reading on the stdout of the {d}nth engine (self status: {})\n", .{ engineIndex, p_self.status.running });
        }
        var buffer = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
        while (p_self.status.running) {
            var w: std.Io.Writer = .fixed(&buffer);
            const n = reader.streamDelimiter(&w, '\n') catch |err| {
                std.debug.print("[DEBUG] readingThread.gui (#{d}): caught err {}\n", .{ engineIndex, err });
                break;
                //p_self.crash();
            };
            //if (n <= 1) {
            //    continue;
            //}
            _ = reader.toss(1);
            const msg = buffer[0..n];

            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG]  readingThread.gui (#{d}): found {d} bytes, message: '{s}'\n", .{ engineIndex, n, msg });
            }

            _ = p_self.input.items[engineIndex].putCmd(msg);

            if (p_self.config.match.saveLogs) {
                const respmsg = try std.fmt.allocPrint(p_self.alloc, "IN(#{d}): {s}\n", .{ engineIndex, msg });
                defer p_self.alloc.free(respmsg);
                try p_self.appendLog(respmsg);
            }
        }
        if (p_self.status.debugMode) {
            std.debug.print("[DEBUG]  readingThread.gui (#{d}): exiting\n", .{engineIndex});
        }
    }
    pub fn servingGuiThread(p_self: *guiState) !void {
        var cumulTime: u64 = 0;
        while (p_self.status.running) {
            for (0..p_self.input.items.len) |i| {
                var inp = &p_self.input.items[i];
                while (inp.nonEmpty()) {
                    const cmd = inp.readBuffer();
                    p_self.handleCmd(.init(cmd.cmd[0..cmd.len], @intCast(i)));
                    cumulTime = 0;
                }
            }

            if (cumulTime > configl.DEBUG_INACTIVITY_SERVING_NS) {
                std.debug.print("[INACTIVITY] servingGuiThread.gui: no activity found in the last {d}s \n", .{configl.DEBUG_INACTIVITY_SERVING_S});
                cumulTime = 0;
            }
            try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.WAIT_TICKRATE_NS) }, .real);
            cumulTime += configl.WAIT_TICKRATE_NS;
        }
    }
    pub fn saveLog(self: *guiState) !void {
        if (!self.config.match.saveLogs) {
            std.debug.assert(self.logs._logs.items.len == 0);
            return;
        }
        var fileName: []u8 = undefined;
        if (self.config.match.logPathProvided) {
            fileName = try std.fmt.allocPrint(self.alloc, "{s}/logs_{d}.txt", .{ self.config.match.logPath._slice(), std.Io.Timestamp.now(mainl.getGlobalIo(), .real) });
        } else {
            fileName = try std.fmt.allocPrint(self.alloc, "logs/logs_{d}.txt", .{std.Io.Timestamp.now(mainl.getGlobalIo(), .real)});
        }
        defer self.alloc.free(fileName);
        const file = try std.Io.Dir.createFile(.cwd(), mainl.getGlobalIo(), fileName, .{ .read = true });
        defer file.close(mainl.getGlobalIo());

        for (0..self.logs._logs.items.len) |i| {
            _ = try file.writeStreamingAll(mainl.getGlobalIo(), self.logs._logs.items[i]);
        }
    }
    pub fn free(p_self: *guiState) void {
        p_self.engineInventory.free(p_self.alloc);
        p_self.logs.free(p_self.alloc);
        p_self.config.free(p_self.alloc);
        for (0..p_self.input.items.len) |i| {
            p_self.input.items[i].free(p_self.alloc);
        }
        p_self.input.deinit(p_self.alloc);
        p_self.workingThreads.deinit(p_self.alloc);

        hashTablel.hashTable.free(p_self.alloc, p_self.status.debugMode);
        //hashTablel.zobristKeys.free(p_self.alloc);
        if (p_self.config.match.useOpeningBook) {
            p_self.config.match.openingDb.free(p_self.alloc);
        }
    }
    pub fn close(p_self: *guiState) void {
        if (p_self.status.closing) {
            return;
        }
        p_self.status.closing = true;
        std.debug.print("[CLOSE] saving logs to log file\n", .{});

        p_self.saveLog() catch |err| {
            std.debug.print("[CLOSE] error while saving: {}\n", .{err});
        };
        p_self.respondAll("quit") catch {};
        p_self.status.running = false;
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.workingThreads.items[i].join();
        }
        std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(std.time.ns_per_s) }, .real) catch {};
        p_self.engineInventory.sendKill();

        p_self.free();
    }
    pub fn crash(p_self: *guiState) noreturn {
        std.log.err("[CRASH] crashing this gui, with no survivors\n", .{});
        p_self.close();
        std.process.exit(1);
    }

    pub fn executeCmd(p_self: *guiState, cmd: e_guiCmd, cmdBuffer: signedCmd) bool {
        switch (cmd) {
            .NOOP => {
                return true;
            },
            .INFO => {
                p_self.executeInfoCmd(cmdBuffer);
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
                const p_engine = p_self.engineInventory.items.items[cmdBuffer.engine];
                p_engine.setReady(true);
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
        std.debug.assert(!p_self.match.nextTurnTrigger);
        const status = p_self.executeBestMove(cmdBuffer.str) catch |err| {
            std.debug.print("[DEBUG] matchOnBestMove: found err: {} with command: '{s}' len {d}\n", .{ err, cmdBuffer.str, cmdBuffer.str.len });
            if (err == err_eval.unknownMove_error) {
                std.debug.print("[DEBUG] expected one of the following moves: \n", .{});
                p_self.match.availableMoves.print();
                const moveArr = chessl.getEmptyMoveListFromStr(cmdBuffer.str);
                const move = moveArr.moves[0];
                std.debug.print("[DEBUG] matchOnBestMove: move found: {s}-{} \n", .{ move.getStr(), move.getFlag() });
                chessl.print_boardstate(&p_self.match.chessState);
            }
            return false;
        };
        p_self.match.nextTurnTrigger = true;
        p_self.match.turnSW.stop();
        return status;
    }
    pub fn startMatch(p_self: *guiState) !void {
        p_self.match.reset();
        p_self.status.phase = .MATCH;
        try p_self.respondAll("ucinewgame");

        var line = try p_self.match.chessState.moveHistory.getLineString(p_self.alloc);
        defer line.free(p_self.alloc);

        try p_self.waitEngine();
        const msg = try std.fmt.allocPrint(p_self.alloc, "position startpos moves {s}", .{line._slice()});
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
        if (p_self.match.chessState.isInsufficientMaterial()) {
            p_self.match.status = .StaleMateInsuficientMaterial;
            return false;
        }

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
    }

    fn waitEngine(p_self: *guiState) !void {
        try p_self.appendLog("Entering waitEngine\n");
        const p_player = p_self.getCurrentPlayer();
        const p_engine = p_self.getCurrentEngine();
        p_engine.ready = false;
        var sw: timel.stopWatch = .{};
        sw.startTimeTick();
        const heartBeatUs = 10_000; // every 10 ms retry
        var timer: timel.timer = .init(heartBeatUs);
        while (!p_engine.isReady()) {
            try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.WAIT_TICKRATE_NS) }, .real);
            if (timer.tick()) {
                try p_self.respond("isready", p_player.engineUsed);
            }
            if (sw.timeSinceStartMs() > configl.EVALUTATION_TIMEOUT_ERROR_MS) {
                std.log.err("[ERROR] timeout error after {d} s\n", .{configl.EVALUTATION_TIMEOUT_ERROR_MS});
                return err_eval.timeout_error;
            }
        }
    }
    fn waitAllPlayers(p_self: *guiState) !void {
        while (!p_self.allPlayersConnected()) {
            try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.START_TICKRATE_NS) }, .real);
        }
    }
    fn sendPositionUpdate(p_self: *guiState) !void {
        var buffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
        const lineString = p_self.match.chessState.moveHistory.getLineStatic();
        const msg = try std.fmt.bufPrint(&buffer, "position startpos moves {s}", .{utilsl.trimStr(&lineString)});
        try p_self.respond(msg, p_self.getCurrentPlayer().engineUsed);
    }
    fn sendGoSearchCommand(p_self: *guiState) !void {
        if (p_self.match.availableMoves.len == 0) {
            p_self.close();
            std.debug.assert(p_self.match.availableMoves.len != 0);
        }

        p_self.match.turnSW.reset();
        p_self.match.turnSW.startTimeTick();
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
        try p_self.waitEngine();
    }
    pub inline fn setPlayerEngine(p_self: *guiState, white: bool, engineIndex: u8) void {
        p_self.match.playerInv[@intFromBool(white)].engineUsed = engineIndex;
    }
    pub inline fn getCurrentPlayer(self: *guiState) *player {
        return &self.match.playerInv[@intFromBool(self.match.chessState.whiteToMove())];
    }

    pub inline fn getCurrentEngine(self: *guiState) *engine_info {
        const p = self.getCurrentPlayer();
        return self.engineInventory.items.items[p.engineUsed];
    }
    pub inline fn allPlayersConnected(self: *guiState) bool {
        return self.engineInventory.items.items[self.match.playerInv[0].engineUsed].alive and self.engineInventory.items.items[self.match.playerInv[1].engineUsed].alive;
    }
    pub fn executeBestMove(p_self: *guiState, cmdBuffer: []const u8) err_eval!bool {
        var gen = utilsl.splitGenerator(u8).init(cmdBuffer, ' ');
        if (gen.len() < 2) {
            return err_eval.nei_error;
        }
        const move = chessl.getFirstMoveFromStr(&p_self.match.chessState, cmdBuffer);
        if (!move.isValid()) {
            return err_eval.unknownMove_error;
        }
        if (!move.isIn(p_self.match.availableMoves)) {
            return err_eval.unknownMove_error;
        }
        p_self.match.nextTurn_move = move;
        return true;
    }
    pub fn executeInfoCmd(p_self: *guiState, cmdBuffer: signedCmd) void {
        if (p_self.config.printToScreen) {
            std.debug.print("{d}: {s}\n", .{ cmdBuffer.engine, cmdBuffer.str });
        }
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
    } else if (utilsl.contains(cmd, "engineop", .ignoreCase)) {
        return .NOOP;
    }
    return .NOOP;
}

fn sendOptions(p_self: *guiState, options: std.ArrayList(string), engineIndex: u8) !void {
    //if (p_self.status.debugMode) {
    //    try p_self.respond("debug on", engineIndex);
    //} else {
    //    try p_self.respond("debug off", engineIndex);
    //}
    for (options.items) |opt| {
        try p_self.respond(opt._slice(), engineIndex);
    }
}

fn mainGuiThread(p_self: *guiState) !void {
    mainl.initAll(p_self.alloc, p_self.status.debugMode);
    if (p_self.config.match.useOpeningBook) {
        // init the db or smth
        p_self.config.match.openingDb = try bookl.openingDatabase.init(p_self.alloc, &p_self.config.match.openingBookPath, configl.SEED);
    }

    try p_self.respondAll("uci");
    try p_self.waitAllPlayers();
    try p_self.respondAll("isready");

    for (0..p_self.config.nEngines) |i| {
        try sendOptions(p_self, p_self.config.engineOptions[i], @intCast(i));
    }
    var record: matchResultContainer = try matchResultContainer.init(p_self.alloc);

    var matchCount: usize = 0;
    var _nMatch = p_self.config.match.nMatch;
    if (p_self.config.match.playerSwitch) {
        _nMatch = _nMatch * 2;
    }
    var currState: boardl.boardState = undefined;
    while (matchCount < _nMatch or (p_self.config.match.sprt.enabled and record.sprtTag(0, p_self.config.match.sprt) == .NULL and matchCount < p_self.config.match.sprt.maxMatch)) {
        if (matchCount != 0 and p_self.config.match.playerSwitch) {
            const tmp = p_self.match.playerInv[0].engineUsed;
            p_self.match.playerInv[0].engineUsed = p_self.match.playerInv[1].engineUsed;
            p_self.match.playerInv[1].engineUsed = tmp;
            if (matchCount % 2 == 0) {
                currState = try pickBoardState(p_self);
            }
            p_self.match.chessState = currState.copy();
        } else {
            currState = try pickBoardState(p_self);

            p_self.match.chessState = currState.copy();
        }
        matchRoutine(p_self) catch {
            break;
        };
        chessl.print_boardstate(&p_self.match.chessState);
        matchCount += 1;
        try record.addOutCome(p_self.alloc, &p_self.match);
    }

    record.printResults(p_self.alloc) catch {};
    record.saveLog(p_self.alloc, &p_self.match, p_self.config) catch |err| {
        std.debug.print("[CLOSE] error {} while saving the match stats\n", .{err});
    };
    record.free(p_self.alloc);
    if (p_self.status.running) {
        p_self.close();
    }
}
fn pickBoardState(p_self: *guiState) !boardl.boardState {
    if (p_self.config.match.useOpeningBook and p_self.config.match.openingBookPathProvided) {
        var openings = try p_self.config.match.openingDb.sample(p_self.alloc, 1, .draw);
        defer openings.deinit(p_self.alloc);
        return try chessl.algebraicLineToBoardstate(p_self.alloc, &openings.items[0]);
    } else {
        return try chessl.getBoardFromFen(chessl.DEFAULT_FEN);
    }
}
fn matchRoutine(p_self: *guiState) !void {
    p_self.match.nextTurnTrigger = false;
    p_self.startMatch() catch {
        @panic("Failed to start the match");
    };

    var timer: timel.timer = .init(configl.EVALUTATION_GUI_WAIT_MS * 1000);
    while (p_self.status.running and p_self.match.status == .Continue) {
        if (p_self.match.nextTurnTrigger) {
            p_self.match.nextTurnTrigger = false;
            const stat = try onNextTurnTrigger(p_self);
            if (!stat) {
                std.debug.print("[ERROR] matchRoutine: err match status {}\n", .{p_self.match.status});
                chessl.print_boardstate(&p_self.match.chessState);
                return err_eval.match_error;
            }
            p_self.match.positionUpdated = true;
        }

        try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.WAIT_TICKRATE_NS) }, .real);

        const stat = p_self.match.timeTick();
        if (!stat) {
            // flagged
            const p = p_self.getCurrentPlayer();
            try p_self.sendEngineInterrupt(p.engineUsed);
            p_self.match.status = .Flagged;
            break;
        }
        if (timer.tick() or p_self.match.positionUpdated) {
            p_self.match.positionUpdated = false;
            if (p_self.config.printToScreen) {
                try timeTickUserFacingInterface(p_self);
            }
        }
    }
    if (p_self.status.debugMode) {
        std.debug.print("[DEBUG] matchRoutine: Exiting match with status: {}\n", .{p_self.match.status});
        chessl.print_boardstate(&p_self.match.chessState);
    }
}
fn timeTickUserFacingInterface(p_self: *guiState) !void {
    utilsl.clear();
    chessl.print_board(&p_self.match.chessState);
    const times = try p_self.match.getGuiStr(p_self.alloc);
    defer (p_self.alloc.free(times));
    std.debug.print("{s} mem of buffer {d} {d}\n", .{ times, p_self.engineInventory.items.items[0].f_reader.interface.buffer.len, p_self.engineInventory.items.items[1].f_reader.interface.buffer.len });

    const eval = heuristicl.evaluate_debug(&p_self.match.chessState, &heuristicl.globalHeuristic);
    std.debug.print("Current evaluation: \n", .{});
    eval.print();
}

fn onNextTurnTrigger(p_self: *guiState) !bool {
    if (p_self.status.debugMode) {
        std.debug.print("onNextTurnTrigger: next turn trigger received \n", .{});
    }
    try p_self.match.turnComplete();

    p_self.match.chessState.makeMove(p_self.match.nextTurn_move);
    p_self.match.availableMoves = move_genl.generateLegalMoves(&p_self.match.chessState);
    if (p_self.status.debugMode) {
        chessl.sanityCheckBoardState(&p_self.match.chessState);
    }

    _ = p_self.nextTurn() catch |err| {
        try p_self.logErr(err);
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

pub fn launch_gui(infoPath: []const u8, alloc: std.mem.Allocator) !void {
    var settings = try parseInfoFile(alloc, infoPath);

    var ret: guiState = try guiState.init(alloc);
    ret.config = &settings;

    if (settings.enginePaths[0].valid) {
        _ = try ret.addEngine(settings.enginePaths[0].path._slice());
    }

    if (settings.enginePaths[1].valid) {
        if (!settings.enginePaths[0].valid) {
            @panic("First engine missing a path\n");
        }
        _ = try ret.addEngine(settings.enginePaths[1].path._slice());
    }
    if (ret.engineInventory.len == 0) {
        @panic("No valid path found\n");
    }

    ret.match.playerInv[0] = try player.init(ret.alloc, settings.match.timeF, .BLACK, ret.engineInventory.len - 1);
    ret.match.playerInv[1] = try player.init(ret.alloc, settings.match.timeF, .WHITE, 0);

    ret.status.running = true;
    ret.status.phase = .MATCH;
    ret.status.debugMode = settings.debugMode;
    try dispatchReadersThreads(&ret);
    const servingThread = try std.Thread.spawn(.{}, entrypointServingThreading, .{&ret});
    try ret.workingThreads.append(ret.alloc, servingThread);

    mainGuiThread(&ret) catch {
        ret.close();
    };

    return;
}
const configSPRT = struct {
    enabled: bool = false,
    alpha: f32 = 0.05,
    beta: f32 = 0.05,
    elo_0: f32 = 0.0,
    elo_1: f32 = 10.0,
    maxMatch: usize = configl.MAX_SPRT_MATCH,
    // bounds exemples https:www.chessprogramming.org/Sequential_Probability_Ratio_Test
    // gainer [0, 10], non regression [-10, 0]
};
const configMatch = struct {
    nMatch: usize = 0,
    sprt: configSPRT = .{},
    playerSwitch: bool = false,
    timeF: timeFormat = standardTimeFormat,
    useOpeningBook: bool = false,
    openingBookPath: string = undefined,
    openingBookPathProvided: bool = false,

    saveLogs: bool = true,
    logPath: string = undefined,
    logPathProvided: bool = false,
    infinite: bool = false,
    openingDb: bookl.openingDatabase = undefined,
    pub fn setOpeningBookPath(p_self: *configMatch, alloc: std.mem.Allocator, path: []const u8) anyerror!void {
        if (p_self.openingBookPathProvided) {
            p_self.openingBookPath.free(alloc);
        }
        if (!filel.fileExists(path)) {
            return filel.file_err.fileNotFound_error;
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
    pub fn free(p_self: *configMatch, alloc: std.mem.Allocator) void {
        if (p_self.openingBookPathProvided) {
            p_self.openingBookPath.free(alloc);
        }
        if (p_self.logPathProvided) {
            p_self.logPath.free(alloc);
        }
    }
};
const engineSettingS = struct {
    path: string = undefined,
    valid: bool = false,
};

const guiSetting = struct {
    match: configMatch = .{},
    enginePaths: [chessl.NUMBER_PLAYER]engineSettingS = std.mem.zeroes([chessl.NUMBER_PLAYER]engineSettingS),
    engineNames: [chessl.NUMBER_PLAYER]string = undefined,
    engineOptions: [chessl.NUMBER_PLAYER]std.ArrayList(string) = undefined,
    nEngines: u8 = 0,
    debugMode: bool = false,
    printToScreen: bool = true,
    seed: u64 = configl.SEED,
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
        const exists = filel.fileExists(enginePath);
        p_self.enginePaths[engineIndex].valid = exists;
        if (exists) {
            p_self.enginePaths[engineIndex].path = try string.initFromSlice(alloc, enginePath);
        }
    }

    pub fn addEngineOption(p_self: *guiSetting, alloc: std.mem.Allocator, engineIndex: u8, enginePath: []const u8) !void {
        const strOption = try string.initFromSlice(alloc, enginePath);
        try p_self.engineOptions[engineIndex].append(alloc, strOption);
    }
    pub fn free(p_self: *guiSetting, alloc: std.mem.Allocator) void {
        for (0..p_self.nEngines) |i| {
            p_self.engineNames[i].free(alloc);
            p_self.enginePaths[i].path.free(alloc);
            for (p_self.engineOptions[i].items) |*opt| {
                opt.free(alloc);
            }
            p_self.engineOptions[i].deinit(alloc);
        }
        p_self.match.free(alloc);
    }
    pub fn print(p_self: *guiSetting) void {
        for (0..p_self.nEngines) |i| {
            std.debug.print("Engine #{d}\n", .{i});
            std.debug.print("\t name: {s}\n", .{p_self.engineNames[i]._slice()});
            std.debug.print("\t path: {s}\n", .{p_self.enginePaths[i].path._slice()});

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
        std.debug.print("\t seed: {d}\n", .{p_self.seed});

        std.debug.print("\t save logs {}\n", .{p_self.match.saveLogs});
        std.debug.print("\t logs path {s}\n", .{p_self.match.logPath._slice()});
        std.debug.print("\t print to screen {}\n", .{p_self.printToScreen});
        std.debug.print("\t sprt mode {}\n", .{p_self.match.sprt.enabled});
        if (p_self.match.sprt.enabled) {
            std.debug.print("\t max sprt matches {d}\n", .{p_self.match.sprt.maxMatch});
            std.debug.print("\t alpha {d} beta {d} elo_0 {d} elo_1 {d}\n", .{ p_self.match.sprt.alpha, p_self.match.sprt.beta, p_self.match.sprt.elo_0, p_self.match.sprt.elo_1 });
        }
    }
    pub fn writeSummary(p_self: *guiSetting, fd: *const std.Io.File) !void {
        var strBuffer: [configl.MAX_USER_INPUT]u8 = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
        for (0..p_self.nEngines) |i| {
            const engineNbr = try std.fmt.bufPrint(&strBuffer, "Engine #{d}\n", .{i});
            //_ = try fd.write(engineNbr);
            try fd.writeStreamingAll(mainl.getGlobalIo(), engineNbr[0..engineNbr.len]);

            const engineName = try std.fmt.bufPrint(&strBuffer, "\t name: {s};\n", .{p_self.engineNames[i]._slice()});
            //_ = try fd.write(engineName);
            try fd.writeStreamingAll(mainl.getGlobalIo(), engineName[0..engineName.len]);

            const enginePath = try std.fmt.bufPrint(&strBuffer, "\t path: {s};\n", .{p_self.enginePaths[i].path._slice()});
            //_ = try fd.write(enginePath);
            try fd.writeStreamingAll(mainl.getGlobalIo(), enginePath[0..enginePath.len]);

            for (p_self.engineOptions[i].items) |*opt| {
                const engineOpt = try std.fmt.bufPrint(&strBuffer, "\t option: {s};\n", .{opt.*._slice()});
                //_ = try fd.write(engineOpt);
                try fd.writeStreamingAll(mainl.getGlobalIo(), engineOpt[0..engineOpt.len]);
            }
        }

        //_ = try fd.write("Match settings: \n");
        try fd.writeStreamingAll(mainl.getGlobalIo(), "Match settings: \n");

        const nMatch = try std.fmt.bufPrint(&strBuffer, "\t nMatch: {d};\n", .{p_self.match.nMatch});
        //_ = try fd.write(nMatch);
        try fd.writeStreamingAll(mainl.getGlobalIo(), nMatch[0..nMatch.len]);

        const pSwitch = try std.fmt.bufPrint(&strBuffer, "\t player switch: {};\n", .{p_self.match.playerSwitch});
        //_ = try fd.write(pSwitch);
        try fd.writeStreamingAll(mainl.getGlobalIo(), pSwitch[0..pSwitch.len]);

        const timeStr = try std.fmt.bufPrint(&strBuffer, "\t time format: time {d} inc {d};\n", .{ p_self.match.timeF.time, p_self.match.timeF.inc });
        //_ = try fd.write(timeStr);
        try fd.writeStreamingAll(mainl.getGlobalIo(), timeStr[0..timeStr.len]);

        const seedStr = try std.fmt.bufPrint(&strBuffer, "\t seed {d};\n", .{p_self.seed});
        //_ = try fd.write(seedStr);
        try fd.writeStreamingAll(mainl.getGlobalIo(), seedStr[0..seedStr.len]);

        const useOpeningStr = try std.fmt.bufPrint(&strBuffer, "\t use opening book {};\n", .{p_self.match.useOpeningBook});
        //_ = try fd.write(useOpeningStr);
        try fd.writeStreamingAll(mainl.getGlobalIo(), useOpeningStr[0..useOpeningStr.len]);

        const openingBookPath = try std.fmt.bufPrint(&strBuffer, "\t opening book path {s};\n", .{p_self.match.openingBookPath._slice()});
        //_ = try fd.write(openingBookPath);
        try fd.writeStreamingAll(mainl.getGlobalIo(), openingBookPath[0..openingBookPath.len]);
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
        settings.match.nMatch = std.fmt.parseInt(usize, nbrStr, 10) catch {
            return false;
        };
        return true;
    } else if (buffer.containsE("seed", .ignoreCase)) {
        const seed = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        settings.seed = std.fmt.parseInt(u64, seed, 10) catch {
            return false;
        };
        return true;
    } else if (buffer.startsWith("playerSwitch")) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.contains(boolStr, "true", .ignoreCase)) {
            settings.match.playerSwitch = true;
        } else if (utilsl.contains(boolStr, "false", .ignoreCase)) {
            settings.match.playerSwitch = false;
        } else {
            return false;
        }

        return true;
    } else if (buffer.startsWith("debugMode")) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.contains(boolStr, "true", .ignoreCase)) {
            settings.debugMode = true;
        } else if (utilsl.contains(boolStr, "false", .ignoreCase)) {
            settings.debugMode = false;
        } else {
            return false;
        }
        return true;
    } else if (buffer.startsWith("useOpeningBook")) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.contains(boolStr, "true", .ignoreCase)) {
            settings.match.useOpeningBook = true;
        } else if (utilsl.contains(boolStr, "false", .ignoreCase)) {
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
    } else if (buffer.containsE("savelogs", .ignoreCase)) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.contains(boolStr, "true", .ignoreCase)) {
            settings.match.saveLogs = true;
        } else if (utilsl.contains(boolStr, "false", .ignoreCase)) {
            settings.match.saveLogs = false;
        } else {
            return false;
        }
        return true;
    } else if (buffer.containsE("printToScreen", .ignoreCase)) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.contains(boolStr, "true", .ignoreCase)) {
            settings.printToScreen = true;
        } else if (utilsl.contains(boolStr, "false", .ignoreCase)) {
            settings.printToScreen = false;
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
    } else if (buffer.startsWith("timeFormat")) {
        const start = buffer.extractFromBounds("(", ",") catch {
            return false;
        };
        const inc = buffer.extractFromBounds(",", ")") catch {
            return false;
        };

        const _start = std.fmt.parseInt(i64, utilsl.stripStr(start), 10) catch {
            return false;
        };
        const _inc = std.fmt.parseInt(i64, utilsl.stripStr(inc), 10) catch {
            return false;
        };

        settings.match.timeF = .{ .time = _start, .inc = _inc };
        return true;
    } else if (buffer.startsWith("infinite")) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        if (utilsl.contains(boolStr, "true", .ignoreCase)) {
            settings.match.infinite = true;
        } else if (utilsl.contains(boolStr, "false", .ignoreCase)) {
            settings.match.infinite = false;
        } else {
            return false;
        }
        return true;
    } else if (buffer.containsE("sprtmode", .ignoreCase)) {
        const boolStr = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        settings.match.sprt.enabled = utilsl.contains(boolStr, "true", .ignoreCase);
        return true;
    } else if (buffer.containsE("alpha", .ignoreCase)) {
        const val = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        settings.match.sprt.alpha = std.fmt.parseFloat(f32, val) catch {
            return false;
        };
        return true;
    } else if (buffer.containsE("beta", .ignoreCase)) {
        const val = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        settings.match.sprt.beta = std.fmt.parseFloat(f32, val) catch {
            return false;
        };
        return true;
    } else if (buffer.containsE("elo_0", .ignoreCase)) {
        const val = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        settings.match.sprt.elo_0 = std.fmt.parseFloat(f32, val) catch {
            return false;
        };
        return true;
    } else if (buffer.containsE("elo_1", .ignoreCase)) {
        const val = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        settings.match.sprt.elo_1 = std.fmt.parseFloat(f32, val) catch {
            return false;
        };
        return true;
    } else if (buffer.containsE("maxsprtmatch", .ignoreCase)) {
        const val = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        settings.match.sprt.maxMatch = std.fmt.parseInt(usize, val, 10) catch {
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

pub fn LL(x: f32) f32 {
    return 1.0 / (1.0 + std.math.pow(f32, 10, -x / 400.0));
}
pub fn LLR(elo_0: f32, elo_1: f32, wins: usize, draws: usize, losses: usize) f32 {
    const N: f32 = @floatFromInt(wins + draws + losses);
    if (N == 0) {
        return 0.0;
    }
    const n_wins: f32 = @as(f32, @floatFromInt(wins)) / N;
    const n_draws = @as(f32, @floatFromInt(draws)) / N;
    const score = n_wins + 0.5 * n_draws;
    const varScore = ((n_wins + n_draws * 0.25) - (std.math.pow(f32, score, 2))) / N;
    const s0 = LL(elo_0);
    const s1 = LL(elo_1);
    return 0.5 * ((s1 - s0) * (2 * score - s0 - s1)) / (varScore);
}
pub fn computeSPRT(elo_0: f32, elo_1: f32, alpha: f32, beta: f32, wins: usize, draws: usize, losses: usize) SPRT_RES {
    const llr = LLR(elo_0, elo_1, wins, draws, losses);
    const LA = std.math.log(f32, beta / (1.0 - alpha), 10);
    const LB = std.math.log(f32, (1.0 - beta) / alpha, 10);
    if (llr > LB) {
        return .H1;
    }
    if (llr < LA) {
        return .H0;
    }
    return .NULL;
}

pub fn _main() !void {
    const infoFile = "engines/engine.info";
    launch_gui(infoFile, mainl.GLOBAL_ALLOC) catch {
        return;
    };
}

pub fn main(init: std.process.Init) !void {

    // 1st arg is the zig file, 2nd is the .info file for the evaluation
    mainl.GLOBAL_CTX.setInit(init);
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);
    std.debug.assert(args.len > 1);

    const path = args[1];
    //std.debug.print("path found: {s}\n", .{path});
    //if (true)
    //    @panic("");
    try launch_gui(path, init.gpa);
}
