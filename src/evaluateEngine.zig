// zig file for match orchestration in uci mode or more(?)
const chessl = @import("chess.zig");
const moveGenl = @import("move_generation.zig");
const mainl = @import("main.zig");
const utilsl = @import("utils.zig");
const configl = @import("config.zig");
const bookl = @import("book.zig");
const filel = @import("file.zig");
const timel = @import("time.zig");
const lockl = @import("lock.zig");
const typel = @import("type.zig");
const boardl = @import("board.zig");
const weightl = @import("weights.zig");
const mathl = @import("math.zig");

const build_options = @import("build_options");
const stringl = @import("string.zig");
const std = @import("std");

pub const e_matchFlag = enum(u8) { Error, Continue, CheckMate, StaleMate, StaleMateRepetition, StaleMateInsuficientMaterial, Flagged, Dnf };
pub const e_matchResultFlag = enum(u8) { ERROR, WIN, DRAW, LOSE, FLAGGED_D, FLAGGED_L };

pub const SPRT_RES = enum(u8) { NULL, H0, H1 };

const e_color = typel.e_color;
const string = stringl.string;

const INPUTCHANNEL_LEN: usize = 64;
pub const cmdResult = struct {
    cmd: [configl.MAX_USER_INPUT]u8 = undefined,
    len: usize = 0,
};

pub const inputChannel = struct {
    cmdBuffer: [][configl.MAX_USER_INPUT]u8 = undefined,
    cmdSize: []usize = undefined,
    currentIdx: usize = 0,
    nextIdx: usize = 0,
    len: usize = INPUTCHANNEL_LEN,
    l: lockl.lock = .{},

    pub fn init(alloc: std.mem.Allocator) !inputChannel {
        var ret: inputChannel = undefined;
        ret.cmdBuffer = (try alloc.alloc([configl.MAX_USER_INPUT]u8, INPUTCHANNEL_LEN));
        ret.cmdSize = (try alloc.alloc(usize, INPUTCHANNEL_LEN));
        ret.nextIdx = 0;
        ret.currentIdx = 0;
        ret.l = .{};
        return ret;
    }
    pub fn initP(alloc: std.mem.Allocator) !*inputChannel {
        const ret = try alloc.create(inputChannel);
        ret.cmdBuffer = (try alloc.alloc([configl.MAX_USER_INPUT]u8, INPUTCHANNEL_LEN));
        ret.cmdSize = (try alloc.alloc(usize, INPUTCHANNEL_LEN));
        ret.nextIdx = 0;
        ret.currentIdx = 0;
        ret.l = .{};
        return ret;
    }

    pub fn nonEmpty(p_self: *inputChannel) bool {
        p_self.l.acquireLock();
        defer p_self.l.releaseLock();
        return p_self.currentIdx != p_self.nextIdx;
    }
    pub fn readBuffer(p_self: *inputChannel) cmdResult {
        p_self.l.acquireLock();
        defer p_self.l.releaseLock();
        p_self.currentIdx = (p_self.currentIdx + 1) % INPUTCHANNEL_LEN;
        std.debug.assert(p_self.currentIdx != p_self.nextIdx + 1);
        const ret_len = p_self.cmdSize[p_self.currentIdx];
        var ret: cmdResult = .{ .len = ret_len };
        @memcpy((ret.cmd[0..ret_len]), p_self.cmdBuffer[p_self.currentIdx][0..ret_len]);
        return ret;
    }
    pub fn putCmd(p_self: *inputChannel, cmd: []const u8) void {
        p_self.l.acquireLock();
        defer p_self.l.releaseLock();
        p_self.nextIdx = (p_self.nextIdx + 1) % INPUTCHANNEL_LEN;
        @memcpy((p_self.cmdBuffer[p_self.nextIdx][0..cmd.len]), cmd[0..cmd.len]);
        p_self.cmdSize[p_self.nextIdx] = cmd.len;
    }
    pub fn free(p_self: *inputChannel, alloc: std.mem.Allocator) void {
        alloc.free(p_self.cmdBuffer);
        alloc.free(p_self.cmdSize);
    }
};

const INITIAL_LOGSIZE: u16 = 100;
const DEFAULT_TIME_MS: i64 = 60 * 1_000; // 1 min in ms
const DEFAULT_TIME_INC_MS: i64 = 1_000; // 1 sec in ms

const e_guiCmd = enum(u8) { NOOP = 0, INFO, BESTMOVE, READYOK, UCIOK, ID, OPTION };
const e_guiPhase = enum(u8) { INVALID, WAITING, MATCH };

pub const err_eval = error{
    mem_error,
    nei_error,
    unknownMove_error,
    timeout_error,
    match_error,
};

const player = struct {
    color: e_color = .WHITE,
    timeMs: i64 = DEFAULT_TIME_MS,
    engineUsed: u8 = 0, // index of the engine to be used (0-1)
    timeTakenMs: i64 = undefined,
    movesMade: i64 = 0,

    pub fn init(timeF: timeFormat, color: e_color, engineIndex: u8) player {
        return .{ .timeMs = timeF.time, .color = color, .engineUsed = engineIndex, .timeTakenMs = 0, .movesMade = 0 };
    }
    pub fn reset(p_self: *player, timeF: timeFormat) void {
        p_self.timeMs = timeF.time;
        // removes all elements without freeing the mem
        p_self.timeTakenMs = 0;
        p_self.movesMade = 0;
    }
    pub inline fn addDeltaTime(p_self: *player, deltaMs: i64) void {
        p_self.timeMs += deltaMs;
    }
};
const tournamentResult = struct {
    win: usize = 0,
    lose: usize = 0,
    draw: usize = 0,
    flagged: usize = 0,
    pub inline fn getScore(self: tournamentResult) f32 {
        var ret: f32 = @floatFromInt(self.win);
        ret += @as(f32, @floatFromInt(self.draw)) / 2.0;
        return ret;
    }
    pub inline fn nMatch(self: tournamentResult) usize {
        return self.win + self.draw + self.lose;
    }
    pub inline fn getExpectedWinrate(self: tournamentResult) f32 {
        // 0 - 1
        const s = self.getScore();
        const a: f32 = @floatFromInt(self.nMatch());
        return s / a;
    }
};
const matchResult = struct {
    res: e_matchResultFlag = .ERROR,
    p: player = .{},
};

const timeFormat = struct {
    time: i64 = DEFAULT_TIME_MS,
    inc: i64 = DEFAULT_TIME_INC_MS,
};

const enginePathS = struct {
    path: string = undefined,
    valid: bool = false,
};
const signedCmd = struct {
    str: []const u8,
    engine: u8,
    pub fn init(buffer: []const u8, engineIndex: u8) signedCmd {
        return .{ .str = buffer, .engine = engineIndex };
    }
};

const matchResultsBench = struct {
    // contains from one engine the score when playing W and when playing B
    //0: (B) Win / Lose / Draw
    //1: (W) Win / Lose / Draw
    res: [2]tournamentResult = .{ .{}, .{} },
    movesMade: i64 = 0,
    totalTimeUsedMs: i64 = 0,

    stdTimePerTurn: i64 = 0,
    nMatch: usize = 0,
    pub inline fn getScore(self: matchResultsBench) f32 {
        return self.combine().getScore();
    }
    pub fn combine(self: matchResultsBench) tournamentResult {
        return .{ .win = self.res[0].win + self.res[1].win, .draw = self.res[0].draw + self.res[1].draw, .lose = self.res[0].lose + self.res[1].lose, .flagged = self.res[0].flagged + self.res[1].flagged };
    }
};
const matchResultContainer = struct {
    items: [MAX_ENGINES]matchResultsBench = std.mem.zeroes([MAX_ENGINES]matchResultsBench),
    fens: std.ArrayList(string) = .empty,
    l: lockl.lock = .{},
    pub fn init(alloc: std.mem.Allocator) !matchResultContainer {
        return .{ .fens = try std.ArrayList(string).initCapacity(alloc, 4) };
    }
    pub fn sprtTag(self: *matchResultContainer, engineIdx: usize, settings: configSPRT) SPRT_RES {
        const res = self.items[engineIdx];
        const s = res.combine();
        const ret = computeSPRT(settings.elo_0, settings.elo_1, settings.alpha, settings.beta, s.win, s.draw, s.lose);
        //std.debug.print("[DEBUG] sprtTag: {}, eng {d}, (w/d/l) ({d}/{d}/{d}) {d} {d} {d} {d}\n", .{ ret, engineIdx, s.win, s.draw, s.lose, settings.alpha, settings.beta, settings.elo_0, settings.elo_1 });
        return ret;
    }
    pub fn addResult(p_self: *matchResultContainer, match: matchResult) void {
        p_self.l.acquireLock();
        defer p_self.l.releaseLock();
        var engRes = &p_self.items[match.p.engineUsed];
        switch (match.res) {
            .WIN => {
                engRes.res[@intFromEnum(match.p.color)].win += 1;
            },
            .LOSE => {
                engRes.res[@intFromEnum(match.p.color)].lose += 1;
            },
            .DRAW => {
                engRes.res[@intFromEnum(match.p.color)].draw += 1;
            },
            .FLAGGED_D => {
                engRes.res[@intFromEnum(match.p.color)].draw += 1;
                engRes.res[@intFromEnum(match.p.color)].flagged += 1;
            },
            .FLAGGED_L => {
                engRes.res[@intFromEnum(match.p.color)].lose += 1;
                engRes.res[@intFromEnum(match.p.color)].flagged += 1;
            },
            .ERROR => {
                @panic("");
            },
        }
        engRes.nMatch += 1;
        engRes.movesMade += match.p.movesMade;
        engRes.totalTimeUsedMs += match.p.timeTakenMs;
        //engRes.avgTimePerTurn = @divFloor(match.p.timeTakenCum, match.p.movesMade + 1);
    }

    pub fn saveLog(p_self: *matchResultContainer, alloc: std.mem.Allocator, settings: *guiSetting) !void {
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
            const res = p_self.items[i];
            const s = res.combine();
            const nwins = s.win;
            const nloses = s.lose;
            const ndraws = s.draw;
            const nflags = s.flagged;

            const scoreStr = try std.fmt.allocPrint(alloc, "engine: {s}, {d} matches, win: {d}, lose: {d}, draw: {d}, flagged: {d}, speed: {d}(+-{d}) ms/move;\n", .{ settings.engineNames[i]._slice(), res.nMatch, nwins, nloses, ndraws, nflags, @divFloor(res.totalTimeUsedMs, res.movesMade + 1), res.stdTimePerTurn });
            defer alloc.free(scoreStr);
            try file.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(scoreStr));

            if (settings.match.sprt.enabled) {
                const breakStr = try std.fmt.allocPrint(alloc, "engine: {s}, breakdown (w/l/d) w: {d}/{d}/{d}, b: {d}/{d}/{d} sprt {};\n", .{ settings.engineNames[i]._slice(), res.res[1].win, res.res[1].lose, res.res[1].draw, res.res[0].win, res.res[0].lose, res.res[0].draw, p_self.sprtTag(i, settings.match.sprt) });
                defer alloc.free(breakStr);
                try file.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(breakStr));
            } else {
                const breakStr = try std.fmt.allocPrint(alloc, "engine: {s}, breakdown (w/l/d) w: {d}/{d}/{d}, b: {d}/{d}/{d};\n", .{ settings.engineNames[i]._slice(), res.res[1].win, res.res[1].lose, res.res[1].draw, res.res[0].win, res.res[0].lose, res.res[0].draw });
                defer alloc.free(breakStr);
                try file.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(breakStr));
            }
        }

        // save the setting part
        try settings.writeSummary(&file);
        try file.writeStreamingAll(mainl.getGlobalIo(), "final positions: \n");
        for (0..p_self.fens.items.len) |i| {
            const fenStr = try std.fmt.allocPrint(alloc, "\t{s};\n", .{p_self.fens.items[i]._slice()});
            defer alloc.free(fenStr);
            //_ = try file.write(fenStr);
            //try file.writeStreamingAll(mainl.getGlobalIo(), fenStr[0..fenStr.len]);
            try file.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(fenStr));
        }
    }
    pub fn printResults(p_self: *matchResultContainer, alloc: std.mem.Allocator) !void {
        var buffer: [configl.MAX_USER_INPUT]u8 = undefined; // Buffer for stdout
        var writer = std.Io.File.stdout().writer(mainl.getGlobalIo(), &buffer);
        const interface = &writer.interface;
        for (0..p_self.items.len) |i| {
            // add the results from white and black for each engines
            const res = p_self.items[i].combine();
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

const standardTimeFormat: timeFormat = .{ .time = 300000, .inc = 5000 };
const bulletTimeFormat: timeFormat = .{ .time = 60000, .inc = 0 };
const ultraBulletTimeFormat: timeFormat = .{ .time = 30000, .inc = 0 };

const engine_info = struct {
    alive: bool = false,
    // contains the options sent by the engine at launch time
    options: std.ArrayList([]u8) = undefined,
    proc: std.process.Child = undefined,
    f_writer: std.Io.File.Writer,
    f_reader: std.Io.File.Reader,
    _writerBuffer: [configl.MAX_USER_INPUT]u8 = undefined,
    _readerBuffer: [configl.MAX_USER_INPUT]u8 = undefined,
    l: lockl.lock = .{},
    path: string = undefined,

    pub fn init(alloc: std.mem.Allocator, path: []const u8) !*engine_info {
        var ret: *engine_info = try alloc.create(engine_info);
        ret.options = try std.ArrayList([]u8).initCapacity(alloc, 2);
        ret._writerBuffer = @splat(0);
        ret._readerBuffer = @splat(0);
        ret.l = .{};
        const argv: [1][]const u8 = .{path};
        const opt: std.process.SpawnOptions = .{
            .argv = &argv,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .inherit,
        };
        ret.proc = try std.process.spawn(mainl.getGlobalIo(), opt);
        ret.f_writer = (ret.proc.stdin.?.writer(mainl.getGlobalIo(), &ret._writerBuffer));
        ret.f_reader = (ret.proc.stdout.?.reader(mainl.getGlobalIo(), &ret._readerBuffer));
        ret.path = try .initFromSlice(alloc, path);
        ret.alive = true;

        return ret;
    }
    pub fn free(p_self: *engine_info, alloc: std.mem.Allocator) void {
        for (0..p_self.options.items.len) |i| {
            alloc.free(p_self.options.items[i]);
        }
        p_self.options.deinit(alloc);
        p_self.path.free(alloc);
        alloc.destroy(p_self);
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
    pub fn sendMsg(p_self: *engine_info, msg: []const u8) !void {
        var writer = &p_self.f_writer.interface;
        try writer.print("{s}\n", .{msg});
        try writer.flush();
        //std.debug.print("sending msg '{s}' ({d} bytes) \n", .{ msg, msg.len });
    }
    pub fn reset(p_self: *engine_info) void {
        if (!p_self.alive) return;
        p_self.proc.kill(mainl.getGlobalIo());
        //
        const argv: [1][]const u8 = .{p_self.path._slice()};
        const opt: std.process.SpawnOptions = .{
            .argv = &argv,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .inherit,
        };
        p_self.proc = try std.process.spawn(mainl.getGlobalIo(), opt);
        p_self.f_writer = (p_self.proc.stdin.?.writer(mainl.getGlobalIo(), &p_self._writerBuffer));
        p_self.f_reader = (p_self.proc.stdout.?.reader(mainl.getGlobalIo(), &p_self._readerBuffer));
    }
    pub fn waitEngine(p_self: *engine_info, input: *inputChannel) !void {
        var sw: timel.stopWatch = .init(true);
        const heartBeatUs = 10_000; // every 10 ms retry
        var timer: timel.timer = .init(heartBeatUs);
        try p_self.sendMsg("isready");
        //std.debug.print("in wait sent isready \n", .{});
        while (true) {
            if (timer.tick()) {
                try p_self.sendMsg("isready");
            }
            if (sw.timeSinceStartMs() > configl.EVALUTATION_TIMEOUT_ERROR_MS) {
                std.log.err("[ERROR] timeout error after {d} s\n", .{configl.EVALUTATION_TIMEOUT_ERROR_MS});
                return err_eval.timeout_error;
            }
            while (input.nonEmpty()) {
                const cmd = input.readBuffer();
                if (getGuiCmdType(&cmd.cmd) == .READYOK) {
                    return;
                }
            }
            try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @intCast(configl.WAIT_TICKRATE_NS) }, .awake);
        }
    }
    pub inline fn sendInterrupt(p_self: *engine_info) !void {
        try p_self.sendMsg("stop");
    }
    pub inline fn sendInterruptWait(p_self: *engine_info, input: *inputChannel) !void {
        try p_self.sendMsg("stop");
        try p_self.waitEngine(input);
    }
    pub inline fn quit(p_self: *engine_info, alloc: std.mem.Allocator) !void {
        try p_self.sendMsg("quit");
        p_self.alive = false;
        p_self.proc.kill(mainl.getGlobalIo());
        try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = std.time.ns_per_ms }, .awake);
        p_self.free(alloc);
    }
};

const engine_Inventory = struct {
    len: u8 = 0,
    items: std.ArrayList(*engine_info) = .empty,
    pub fn init(alloc: std.mem.Allocator) !engine_Inventory {
        var ret: engine_Inventory = undefined;
        ret.len = 0;
        ret.items = try std.ArrayList(*engine_info).initCapacity(alloc, 2);
        return ret;
    }
    pub fn addEngine(p_self: *engine_Inventory, alloc: std.mem.Allocator, engine: *engine_info) !void {
        p_self.len += 1;
        try p_self.items.append(alloc, engine);
    }
    pub fn free(p_self: *engine_Inventory, alloc: std.mem.Allocator) void {
        for (0..p_self.len) |i| {
            p_self.items.items[i].quit(alloc) catch continue;
        }
        p_self.items.deinit(alloc);
    }
    pub fn sendKill(p_self: *engine_Inventory) void {
        for (0..p_self.len) |i| {
            p_self.items.items[i].proc.kill(mainl.getGlobalIo());
        }
    }
    pub fn sendMsg(p_self: *const engine_Inventory, msg: []const u8, engineIndex: usize) !void {
        std.debug.assert(p_self.items.items.len > 0);
        std.debug.assert(p_self.items.items.len > engineIndex);
        try p_self.items.items[engineIndex].sendMsg(msg);
    }
    pub fn sendMsgAll(p_self: *const engine_Inventory, msg: []const u8) !void {
        std.debug.assert(p_self.items.items.len > 0);
        for (p_self.items.items) |eng| {
            try eng.sendMsg(msg);
        }
    }
    pub fn waitAll(self: *const engine_Inventory, inputs: []*inputChannel) !void {
        for (self.items.items, inputs) |eng, inp| {
            try eng.waitEngine(inp);
        }
    }
};
const matchPlayers = struct {
    inv: [chessl.NUMBER_PLAYER]player = @splat(.{}),
    pub inline fn getPlayerC(self: *matchPlayers, c: e_color) *player {
        return &self.inv[@intFromEnum(c)];
    }
    pub inline fn getPlayerWhite(self: *matchPlayers, w: bool) *player {
        return &self.inv[chessl.whiteBoolToInt(w)];
    }
    pub inline fn makeScoreArr(self: *const matchPlayers) [2]matchResult {
        return [2]matchResult{
            .{ .p = self.inv[@intFromEnum(e_color.WHITE)] },
            .{ .p = self.inv[@intFromEnum(e_color.BLACK)] },
        };
    }
};

fn getGuiCmdType(cmd: []const u8) e_guiCmd {
    if (utilsl.startsWith(cmd, "info", .ignoreCase)) {
        return .INFO;
    } else if (utilsl.startsWith(cmd, "bestmove", .ignoreCase)) {
        return .BESTMOVE;
    } else if (utilsl.startsWith(cmd, "readyok", .ignoreCase)) {
        return .READYOK;
    } else if (utilsl.startsWith(cmd, "uciok", .ignoreCase)) {
        return .UCIOK;
    } else if (utilsl.startsWith(cmd, "id", .ignoreCase)) {
        return .ID;
    } else if (utilsl.startsWith(cmd, "option", .ignoreCase)) {
        return .OPTION;
    } else if (utilsl.startsWith(cmd, "engineop", .ignoreCase)) {
        return .NOOP;
    }
    return .NOOP;
}

pub fn endMatchTickUserFacingInterface(p_self: *const threadCtx, match: *matchStruct) void {
    const settings = p_self.pool.setting;
    for (0..settings.nEngines) |i| {
        var side: u8 = 'w';
        for (match.players.inv) |p| {
            if (p.engineUsed == i) {
                side = if (p.color == .BLACK) 'b' else 'w';
            }
        }
        const name = settings.engineNames[i];
        const outcome = p_self.pool.results.items[i];
        const _outcome = outcome.combine();
        std.debug.print("({c}) {d} (w/l/d) {d}/{d}/{d} black({d}/{d}/{d}) white({d}/{d}/{d}) {s}\n", .{ side, outcome.getScore(), _outcome.win, _outcome.lose, _outcome.draw, outcome.res[0].win, outcome.res[0].lose, outcome.res[0].draw, outcome.res[1].win, outcome.res[1].lose, outcome.res[1].draw, name._slice() });
    }
}
pub fn endMatchEloPrint(pool: *const poolCtx) !void {
    var buffer: [configl.MAX_USER_INPUT]u8 = undefined; // Buffer for stdout
    var writer = std.Io.File.stdout().writer(mainl.getGlobalIo(), &buffer);
    const interface = &writer.interface;

    const settings = pool.setting;
    const e1 = settings.engineNames[0];
    const e2 = settings.engineNames[1];
    const res1 = pool.results.items[0].combine();

    const expectedWR: f32 = res1.getExpectedWinrate();
    try interface.print("({s} vs {s}) - Elo difference {d} (+- {d}) - LOS {d} % \n", .{ e1._slice(), e2._slice(), deltaElo(expectedWR), deltaEloError(expectedWR, res1.nMatch()), los(res1.win, res1.lose) * 100 });
    try interface.flush();
}
pub fn endMatchPrint(pool: *poolCtx, match: *matchStruct, matchId: usize) !void {
    var buffer: [configl.MAX_USER_INPUT]u8 = undefined; // Buffer for stdout
    var writer = std.Io.File.stdout().writer(mainl.getGlobalIo(), &buffer);
    const interface = &writer.interface;

    const settings = pool.setting;
    const eW = settings.engineNames[match.players.getPlayerC(.WHITE).engineUsed];
    const eB = settings.engineNames[match.players.getPlayerC(.BLACK).engineUsed];
    switch (match.status) {
        .Continue, .Error, .Dnf => {
            try interface.print("({s} vs {s}) - Match #{d}/{d} error \n", .{ eW._slice(), eB._slice(), matchId, settings.match.nMatch });
        },
        .CheckMate => {
            if (match.chessState.whiteToMove()) {
                try interface.print("({s} vs {s}) - Match #{d}/{d} white checkmated \n", .{ eW._slice(), eB._slice(), matchId, settings.match.nMatch });
            } else {
                try interface.print("({s} vs {s}) - Match #{d}/{d} black checkmated \n", .{ eW._slice(), eB._slice(), matchId, settings.match.nMatch });
            }
        },
        .Flagged => {
            if (match.chessState.whiteToMove()) {
                try interface.print("({s} vs {s}) - Match #{d}/{d} white flagged\n", .{ eW._slice(), eB._slice(), matchId, settings.match.nMatch });
            } else {
                try interface.print("({s} vs {s}) - Match #{d}/{d} black flagged\n", .{ eW._slice(), eB._slice(), matchId, settings.match.nMatch });
            }
        },
        .StaleMate, .StaleMateRepetition => {
            try interface.print("({s} vs {s}) - Match #{d}/{d} stalemate by repetition \n", .{ eW._slice(), eB._slice(), matchId, settings.match.nMatch });
        },
        .StaleMateInsuficientMaterial => {
            try interface.print("({s} vs {s}) - Match #{d}/{d} stalemate by insuficient material \n", .{ eW._slice(), eB._slice(), matchId, settings.match.nMatch });
        },
    }

    const e1 = settings.engineNames[0];
    const e2 = settings.engineNames[1];
    const res1 = pool.results.items[0];
    const res2 = pool.results.items[1];

    try interface.print("({s} vs {s}) - Score {d}-{d} \n", .{ e1._slice(), e2._slice(), res1.getScore(), res2.getScore() });
    try interface.flush();
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

const guiSetting = struct {
    match: configMatch = .{},
    enginePaths: [chessl.NUMBER_PLAYER]enginePathS = @splat(.{}),
    engineNames: [chessl.NUMBER_PLAYER]string = undefined,
    engineOptions: [chessl.NUMBER_PLAYER]std.ArrayList(string) = @splat(.empty),
    nEngines: u8 = 0,
    nThreads: u8 = 1,
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
            try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(engineNbr));

            const engineName = try std.fmt.bufPrint(&strBuffer, "\t name: {s};\n", .{p_self.engineNames[i]._slice()});
            try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(engineName));

            const enginePath = try std.fmt.bufPrint(&strBuffer, "\t path: {s};\n", .{p_self.enginePaths[i].path._slice()});
            try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(enginePath));

            for (p_self.engineOptions[i].items) |*opt| {
                const engineOpt = try std.fmt.bufPrint(&strBuffer, "\t option: {s};\n", .{opt.*._slice()});
                try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(engineOpt));
            }
        }

        try fd.writeStreamingAll(mainl.getGlobalIo(), "Match settings: \n");

        const nMatch = try std.fmt.bufPrint(&strBuffer, "\t nMatch: {d};\n", .{p_self.match.nMatch});
        try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(nMatch));

        const pSwitch = try std.fmt.bufPrint(&strBuffer, "\t player switch: {};\n", .{p_self.match.playerSwitch});
        try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(pSwitch));

        const timeStr = try std.fmt.bufPrint(&strBuffer, "\t time format: time {d} inc {d};\n", .{ p_self.match.timeF.time, p_self.match.timeF.inc });
        try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(timeStr));

        const seedStr = try std.fmt.bufPrint(&strBuffer, "\t seed {d};\n", .{p_self.seed});
        try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(seedStr));

        const useOpeningStr = try std.fmt.bufPrint(&strBuffer, "\t use opening book {};\n", .{p_self.match.useOpeningBook});
        try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(useOpeningStr));

        const openingBookPath = try std.fmt.bufPrint(&strBuffer, "\t opening book path {s};\n", .{p_self.match.openingBookPath._slice()});
        try fd.writeStreamingAll(mainl.getGlobalIo(), @ptrCast(openingBookPath));
    }
};
pub fn parseInfoFile(alloc: std.mem.Allocator, path: []const u8) !guiSetting {
    var tokens = try filel.getTokensFromFile(alloc, path, '\n');
    defer stringl.freeArrayList_string(alloc, &tokens);
    var ret: guiSetting = try guiSetting.init(alloc);
    var matchSection: bool = false;

    for (0..tokens.items.len) |i| {
        var s = tokens.items[i];
        if (s.startsWith("//", .standardToken)) {
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
    if (buffer.startsWith("nMatch", .ignoreCase)) {
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
    } else if (buffer.startsWith("playerSwitch", .ignoreCase)) {
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
    } else if (buffer.startsWith("debugMode", .ignoreCase)) {
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
    } else if (buffer.startsWith("useOpeningBook", .ignoreCase)) {
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
    } else if (buffer.startsWith("openingBookPath", .ignoreCase)) {
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
    } else if (buffer.startsWith("logsLocation", .ignoreCase)) {
        const path = buffer.extractFromBounds("\"", "\"") catch {
            return false;
        };
        settings.match.setLoggingLocationPath(alloc, path) catch {
            return false;
        };
        return true;
    } else if (buffer.startsWith("timeFormat", .ignoreCase)) {
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
    } else if (buffer.startsWith("infinite", .ignoreCase)) {
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
    } else if (buffer.containsE("nthreads", .ignoreCase)) {
        const val = buffer.extractFromBounds("=", ";") catch {
            return false;
        };
        const t = std.fmt.parseInt(u8, val, 10) catch {
            return false;
        };
        if (t == 0) {
            return false;
        }
        settings.nThreads = t;
        return true;
    }

    return false;
}

fn handleInfoStrBuffer(alloc: std.mem.Allocator, settings: *guiSetting, buffer: *string) bool {
    if (buffer.startsWith("[", .standardToken)) {
        if (settings.nEngines == chessl.NUMBER_PLAYER) {
            return false;
        }
        settings.nEngines += 1;
        return true;
    } else if (buffer.startsWith("name", .ignoreCase)) {
        const name = buffer.extractFromBounds("\"", "\"") catch {
            return false;
        };
        settings.setEngineName(alloc, settings.nEngines - 1, name) catch {
            return false;
        };
        return true;
    } else if (buffer.startsWith("path", .ignoreCase)) {
        const path = buffer.extractFromBounds("\"", "\"") catch {
            return false;
        };
        settings.setEnginePath(alloc, settings.nEngines - 1, path) catch {
            return false;
        };
        return true;
    } else if (buffer.startsWith("\"", .standardToken)) {
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
    if (N == 0 or wins == 0 or draws == 0) {
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
pub fn deltaElo(expectedWR: f32) f32 {
    return 400 * std.math.log(f32, 10, expectedWR / (1 - expectedWR));
}
// https://www.talkchess.com/forum/viewtopic.php?t=57969
pub fn deltaEloError(expectedWR: f32, nGames: usize) f32 {
    const _nGames: f32 = @floatFromInt(@max(1, nGames));
    return 700 * std.math.sqrt((4 * expectedWR * (1 - expectedWR)) - expectedWR) / std.math.sqrt(_nGames);
}
pub fn los(wins: usize, losses: usize) f32 {
    // 0 - 1
    if (wins + losses == 0) {
        return 0.0;
    }
    const w: f32 = @floatFromInt(wins);
    const l: f32 = @floatFromInt(losses);
    return 0.5 + 0.5 * mathl.erf(f32, (w - l) / std.math.sqrt(2 * (w + l)));
}

pub fn engineInfoListener(engine: *engine_info, engineIndex: usize, output: *inputChannel) !void {
    var reader = &engine.f_reader.interface;

    var buffer = std.mem.zeroes([configl.MAX_USER_INPUT]u8);
    //var listenClock: timel.stopWatch = .init(true);
    //std.debug.print("[DEBUG] readingThread.gui (#{d}): starting to listen \n", .{engineIndex});
    while (engine.alive) {
        var w: std.Io.Writer = .fixed(&buffer);
        const n = reader.streamDelimiter(&w, '\n') catch |err| {
            if (engine.alive) {
                std.debug.print("[DEBUG] readingThread.gui (#{d}): caught err {}\n", .{ engineIndex, err });
            }
            break;
        };
        //std.debug.print("[DEBUG] readingThread.gui (#{d}): found {d} raw bytes\n", .{ engineIndex, n });

        if (n == 0) {
            continue;
        }
        _ = reader.toss(1);
        const msg = buffer[0..n];

        //std.debug.print("[DEBUG] readingThread.gui (#{d}): found {d} bytes, message: '{s}'\n", .{ engineIndex, n, msg });
        output.putCmd(msg);
    }

    //std.debug.print("[DEBUG] readingThread.gui (#{d}): exiting \n", .{engineIndex});
}
const threadCtx = struct {
    pool: *poolCtx,
    alive: bool = false,
    seed: u64 = configl.SEED,
    engineInventory: engine_Inventory = .{},
    alloc: std.mem.Allocator,
    listeningThreads: std.ArrayList(std.Thread) = .empty,
    tId: usize = 0,
};

const poolCtx = struct {
    threads: std.ArrayList(*threadCtx) = .empty,
    _threads: std.ArrayList(std.Thread) = .empty,

    running: bool = false,
    blockNewSubmit: bool = false,
    setting: guiSetting = .{},

    results: matchResultContainer = .{},
    submitLock: lockl.lock = .{},

    nCommitedMatches: usize = 0,
    nThreads: usize = 0,
    nRunningThreads: usize = 0,

    pub fn kill(self: *poolCtx) void {
        for (self.threads.items) |thread| {
            thread.alive = false;
        }
    }
    pub inline fn runningThreads(self: *const poolCtx) usize {
        var ret: usize = 0;
        for (self.threads.items) |t| {
            ret += @intFromBool(t.alive);
        }
        return ret;
    }
    pub fn free(self: *poolCtx, alloc: std.mem.Allocator) void {
        std.debug.assert(self.runningThreads() == 0);
        self.setting.free(alloc);
        self.results.free(alloc);
        self._threads.deinit(alloc);
        self.threads.deinit(alloc);
    }

    pub fn startMatch(self: *poolCtx) usize {
        self.submitLock.acquireLock();
        defer self.submitLock.releaseLock();
        self.nCommitedMatches += 1;
        std.debug.print("Starting match {d} / {d}\n", .{ self.nCommitedMatches, self.setting.match.nMatch });
        return self.nCommitedMatches;
    }
    pub fn submitMatch(self: *poolCtx, alloc: std.mem.Allocator, m: *matchStruct, matchId: usize) !void {
        self.submitLock.acquireLock();
        defer self.submitLock.releaseLock();
        if (self.blockNewSubmit) return;

        var engResults: [2]matchResult = m.players.makeScoreArr();
        const w = m.chessState.whiteToMove();
        const stm: usize = @intFromEnum(chessl.boolTo_e_color(w));
        const stnm: usize = @intFromEnum(chessl.boolTo_e_color(!w));
        switch (m.status) {
            .Continue, .Error, .Dnf => {
                return;
            },
            .CheckMate => {
                engResults[stm].res = .LOSE;
                engResults[stnm].res = .WIN;
            },
            .StaleMate, .StaleMateRepetition, .StaleMateInsuficientMaterial => {
                engResults[stm].res = .DRAW;
                engResults[stnm].res = .DRAW;
            },
            .Flagged => {
                if (m.chessState.isInsufficientMaterialSide(!w)) {
                    engResults[stm].res = .FLAGGED_D;
                    engResults[stnm].res = .DRAW;
                } else {
                    engResults[stm].res = .FLAGGED_L;
                    engResults[stnm].res = .WIN;
                }
            },
        }
        //std.debug.print("[DEBUG] submit match adding {} to engine {d} color {} totalTime {d} movesMade {d}\n", .{ engResults[0].res, engResults[0].p.engineUsed, engResults[0].p.color, engResults[0].p.timeTakenMs, engResults[0].p.movesMade });
        //std.debug.print("[DEBUG] submit match adding {} to engine {d} color {} totalTime {d} movesMade {d}\n", .{ engResults[1].res, engResults[1].p.engineUsed, engResults[1].p.color, engResults[1].p.timeTakenMs, engResults[1].p.movesMade });

        self.results.addResult(engResults[0]);
        self.results.addResult(engResults[1]);
        const lineString = try m.chessState.moveHistory.getLineString(alloc);
        try self.results.fens.append(alloc, lineString);
        try endMatchPrint(self, m, matchId);
        if ((self.nCommitedMatches + self.nThreads) % 32 == 0) {
            try endMatchEloPrint(self);
        }
        if (self.setting.match.sprt.enabled) {
            if (self.results.sprtTag(0, self.setting.match.sprt) != .NULL and self.results.sprtTag(1, self.setting.match.sprt) != .NULL) {
                //if (self.results.sprtTag(0, self.setting.match.sprt) != .NULL) {
                self.blockNewSubmit = true;
            }
        }
    }
    pub fn canRelaunch(self: *poolCtx) bool {
        self.submitLock.acquireLock();
        defer self.submitLock.releaseLock();
        if (self.blockNewSubmit) {
            return false;
        }
        if ((self.setting.match.sprt.enabled and self.nCommitedMatches < self.setting.match.sprt.maxMatch) or (self.nCommitedMatches < self.setting.match.nMatch)) {
            return true;
        }
        return false;
    }
    pub fn exit(self: *poolCtx, current: *threadCtx) void {
        current.alive = false;
        _ = self;
    }
    pub fn save(self: *poolCtx, alloc: std.mem.Allocator) void {
        self.results.saveLog(alloc, &self.setting) catch |err| {
            std.debug.print("[CLOSE] error {} while saving the match stats\n", .{err});
        };
    }
    pub fn waitOnFinish(self: *poolCtx) !void {
        while (self.runningThreads() != 0) {
            try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = 500 * std.time.ns_per_ms }, .awake);
        }
    }
};
pub fn addEnginesToCtx(ctx: *threadCtx, alloc: std.mem.Allocator, settings: guiSetting) !void {
    for (settings.enginePaths) |path| {
        const eng = try engine_info.init(alloc, path.path._slice());
        try ctx.engineInventory.addEngine(alloc, eng);
        //std.debug.print("[DEBUG] addEnginesToCtx: adding engine path {s} \n", .{path.path._slice()});
    }
}
pub fn spawnListeningThreads(ctx: *threadCtx, alloc: std.mem.Allocator) !std.ArrayList(*inputChannel) {
    if (ctx.engineInventory.len == 0) {
        @panic("no engines found in current ctx");
    }
    var ret: std.ArrayList(*inputChannel) = .empty;
    for (0..ctx.engineInventory.len) |i| {
        //std.debug.print("Spawning listening to engine {d}\n", .{i});
        const inp: *inputChannel = try .initP(alloc);
        try ret.append(alloc, inp);
        const inputThread = try std.Thread.spawn(.{}, engineInfoListener, .{ ctx.engineInventory.items.items[i], i, inp });
        try ctx.listeningThreads.append(alloc, inputThread);
    }
    return ret;
}
const matchStruct = struct {
    chessState: boardl.boardState = undefined,
    // [black / white], same as the c_occupiedBB
    players: matchPlayers = .{},
    timeF: timeFormat = .{},
    status: e_matchFlag = .Error,
    positionUpdated: bool = false,
    pub fn init(timeF: timeFormat) matchStruct {
        var ret: matchStruct = .{ .timeF = timeF };
        ret.players.getPlayerC(.WHITE).color = .WHITE;
        ret.players.getPlayerC(.WHITE).engineUsed = 0;

        ret.players.getPlayerC(.BLACK).color = .BLACK;
        ret.players.getPlayerC(.BLACK).engineUsed = 1;

        ret.resetTimes();
        return ret;
    }

    pub fn resetTimes(self: *matchStruct) void {
        self.players.getPlayerC(.WHITE).timeMs = self.timeF.time;
        self.players.getPlayerC(.WHITE).timeTakenMs = 0;
        self.players.getPlayerC(.WHITE).movesMade = 0;

        self.players.getPlayerC(.BLACK).timeMs = self.timeF.time;
        self.players.getPlayerC(.BLACK).timeTakenMs = 0;
        self.players.getPlayerC(.BLACK).movesMade = 0;
    }
    pub inline fn sideToMove(self: *const matchStruct) e_color {
        return chessl.boolTo_e_color(self.chessState.whiteToMove());
    }
    pub inline fn sideToMoveW(self: *const matchStruct) bool {
        return self.chessState.whiteToMove();
    }
    pub inline fn engineToMove(self: *const matchStruct, engines: *engine_Inventory) *engine_info {
        const p = self.players.inv[@intFromEnum(self.sideToMove())];
        return engines.items.items[p.engineUsed];
    }
    pub inline fn playerToMove(self: *matchStruct) *player {
        return self.players.getPlayerWhite(self.sideToMoveW());
    }
    pub fn swapPlayers(self: *matchStruct) void {
        std.mem.swap(player, &self.players.inv[0], &self.players.inv[1]);

        self.players.inv[0].color = chessl.invert_e_color(self.players.inv[0].color);
        self.players.inv[1].color = chessl.invert_e_color(self.players.inv[1].color);
    }
    pub fn sendPositionUpdate(p_self: *matchStruct, engines: *engine_Inventory) !void {
        var buffer: [configl.MAX_USER_INPUT]u8 = @splat(0);
        const lineString = p_self.chessState.moveHistory.getLineStatic();
        const msg = try std.fmt.bufPrint(&buffer, "position startpos moves {s}", .{utilsl.trimStr(&lineString)});
        try p_self.engineToMove(engines).sendMsg(msg);
    }
    pub fn printTimes(p_self: *matchStruct, turnTimer: timel.stopWatch) void {
        const wP = p_self.players.getPlayerC(.WHITE);
        const bP = p_self.players.getPlayerC(.BLACK);
        std.debug.print("wtime {d}{} btime {d}{} winc {d} binc {d} timeTurn {d}\n", .{ wP.timeMs, wP.color, bP.timeMs, bP.color, p_self.timeF.inc, p_self.timeF.inc, turnTimer.timeSinceStartMs() });
    }

    pub fn sendGoCmd(p_self: *matchStruct, engines: *engine_Inventory) !void {
        var buffer: [configl.MAX_USER_INPUT]u8 = @splat(0);
        const wP = p_self.players.getPlayerC(.WHITE);
        const bP = p_self.players.getPlayerC(.BLACK);
        const msg = try std.fmt.bufPrint(&buffer, "go wtime {d} btime {d} winc {d} binc {d}", .{ wP.timeMs, bP.timeMs, p_self.timeF.inc, p_self.timeF.inc });
        try p_self.engineToMove(engines).sendMsg(msg);
    }

    pub fn drawNewState(self: *matchStruct, book: *bookl.openingDatabase) !void {
        const line = book.pickOne(.draw);
        self.chessState = try chessl.algebraicLineToBoardstate(&line);
    }

    pub fn executeCmd(p_self: *matchStruct, cmdBuffer: signedCmd, turnTimer: timel.stopWatch) bool {
        const cmd = getGuiCmdType(cmdBuffer.str);
        switch (cmd) {
            .ID, .OPTION => {
                std.log.warn("Unsupported cmd {} for match handling\n", .{cmd});
                @panic("unknown cmd");
            },
            .INFO => {
                //std.debug.print("{s}\n", .{cmdBuffer.str});
            },
            .NOOP, .READYOK => {
                return true;
            },
            .UCIOK => {
                return true;
            },
            .BESTMOVE => {
                return p_self.matchOnBestMove(cmdBuffer, turnTimer) catch {
                    return false;
                };
            },
        }
        return true;
    }
    pub fn matchOnBestMove(p_self: *matchStruct, cmdBuffer: signedCmd, turnTimer: timel.stopWatch) !bool {
        const p = p_self.playerToMove();
        const timeTaken = turnTimer.timeSinceStartMs();

        // if this hits, mismatch between the current player and the engine that did the computing
        std.debug.assert(p.engineUsed == cmdBuffer.engine);
        const move = chessl.getFirstMoveFromStr(&p_self.chessState, cmdBuffer.str);
        const fmoves = moveGenl.generateLegalMoves(&p_self.chessState);
        if (!move.isValid() or !move.isIn(fmoves)) {
            std.debug.print("[DEBUG] matchOnBestMove: found err: with command: '{s}' len {d}\n", .{ cmdBuffer.str, cmdBuffer.str.len });
            std.debug.print("[DEBUG] matchOnBestMove: move found: {s}-{} \n", .{ move.getStr(), move.getFlag() });
            chessl.print_boardstate(&p_self.chessState);
            p_self.status = .Error;
            return false;
        }
        p.addDeltaTime(p_self.timeF.inc - timeTaken);
        //std.debug.assert(p.timeMs > 0);
        p.timeTakenMs += timeTaken;
        p.movesMade += 1;
        p_self.chessState.makeMove(move);
        p_self.positionUpdated = true;
        return true;
    }

    pub fn isCurrentlyFlagged(self: *matchStruct, turnTimer: timel.stopWatch) bool {
        return turnTimer.timeSinceStartMs() > self.playerToMove().timeMs;
    }
};
pub fn startPool(infoPath: []const u8, alloc: std.mem.Allocator) !void {
    const settings = try parseInfoFile(alloc, infoPath);
    var pool: poolCtx = .{ .nThreads = settings.nThreads, .setting = settings };

    var rngIntGenerator = std.Random.DefaultPrng.init(settings.seed);
    const rng = rngIntGenerator.random();
    const ctxs = try alloc.alloc(threadCtx, pool.nThreads);
    defer {
        pool.waitOnFinish() catch {};
        pool.results.printResults(alloc) catch {};
        pool.save(alloc);

        pool.free(alloc);
        alloc.free(ctxs);
    }
    for (1..pool.nThreads) |tId| {
        const ctx = &ctxs[tId];
        ctx.* = .{ .alloc = alloc, .pool = &pool, .alive = true, .seed = rng.uintAtMost(u64, chessl.UNIVERSE), .tId = tId };
        const inputThread = try std.Thread.spawn(.{}, threadMainLoop, .{ctx});
        try pool._threads.append(alloc, inputThread);
        try pool.threads.append(alloc, ctx);
    }
    const ctx = &ctxs[0];
    ctx.* = .{ .alloc = alloc, .pool = &pool, .alive = true, .seed = rng.uintAtMost(u64, chessl.UNIVERSE), .tId = 0 };
    try threadMainLoop(ctx);
}

pub fn threadMainLoop(self: *threadCtx) !void {
    try addEnginesToCtx(self, self.alloc, self.pool.setting);
    var inputs = try spawnListeningThreads(self, self.alloc);

    const setting = self.pool.setting.match;
    var openingDb = try bookl.openingDatabase.init(self.alloc, &setting.openingBookPath, self.seed, false);

    defer {
        self.engineInventory.free(self.alloc);
        self.listeningThreads.deinit(self.alloc);

        self.pool.exit(self);
        // free engine inputs
        for (inputs.items) |inp| {
            inp.free(self.alloc);
            self.alloc.destroy(inp);
        }
        inputs.deinit(self.alloc);
        openingDb.free(self.alloc);
    }

    try self.engineInventory.sendMsgAll("uci");

    // TODO: put this with verification on options elsewhere
    for (self.engineInventory.items.items, 0..) |eng, i| {
        for (self.pool.setting.engineOptions[i].items) |opt| {
            try eng.sendMsg(opt._slice());
        }
    }

    try self.engineInventory.sendMsgAll("isready");
    var match: matchStruct = .init(setting.timeF);
    try self.engineInventory.waitAll(inputs.items);

    while (self.alive) {
        if (setting.useOpeningBook) {
            try match.drawNewState(&openingDb);
        } else {
            match.chessState = try chessl.getBoardFromFen(chessl.DEFAULT_FEN);
        }

        matchLoop(self, inputs.items, &match) catch {
            continue;
        };
        if (setting.playerSwitch) {
            match.swapPlayers();
        }
        if (!self.pool.canRelaunch()) {
            break;
        }
    }
}

pub fn matchLoop(ctx: *threadCtx, inputs: []*inputChannel, match: *matchStruct) !void {
    const originalState = match.chessState.copy();
    const setting = ctx.pool.setting.match;
    var positionOver: bool = false;

    var roundOver: bool = false;
    var switchPlayers = setting.playerSwitch;
    try ctx.engineInventory.sendMsgAll("ucinewgame");
    var matchId: usize = ctx.pool.startMatch();

    match.positionUpdated = true;
    match.resetTimes();

    //var roundTimer: timel.stopWatch = .init(true);
    var turnTimer: timel.stopWatch = .init(true);
    //const heartBeatNS: i64 = 10_000;
    var inactivityMs: i64 = 2_000;
    var itr: usize = 0;
    while (ctx.alive and !roundOver and !ctx.pool.blockNewSubmit) {
        std.atomic.spinLoopHint();
        const engIdx = match.playerToMove().engineUsed;
        const inp = inputs[engIdx];
        itr += 1;

        while (inp.nonEmpty()) {
            const cmd = inp.readBuffer();
            const status = match.executeCmd(.init(cmd.cmd[0..cmd.len], @intCast(engIdx)), turnTimer);
            _ = status;
        }
        if (itr == 256) {
            itr = 0;
            if (turnTimer.timeSinceStartMs() > inactivityMs) {
                std.debug.print("[WARNING] inactivity? {d} ms thresh {d} ms \n", .{ turnTimer.timeSinceStartMs(), inactivityMs });
                match.printTimes(turnTimer);
                inactivityMs += (inactivityMs + 1000);
            }

            if (match.isCurrentlyFlagged(turnTimer)) {
                const eng = match.engineToMove(&ctx.engineInventory);
                try eng.sendInterruptWait(inp);
                match.status = .Flagged;
                positionOver = true;
                match.positionUpdated = true;
            }
        }

        if (match.positionUpdated) {
            match.positionUpdated = false;
            const fmoves = moveGenl.generateLegalMoves(&match.chessState);
            if (fmoves.len == 0) {
                if (match.chessState.isChecked()) {
                    match.status = .CheckMate;
                } else {
                    match.status = .StaleMate;
                }
                positionOver = true;
            } else if (match.chessState.isStaleMateRepetition()) {
                match.status = .StaleMateRepetition;
                positionOver = true;
            } else if (match.chessState.isInsufficientMaterial()) {
                match.status = .StaleMateInsuficientMaterial;
                positionOver = true;
            } else {
                match.status = .Continue;
            }

            // send pos to current engine
            if (positionOver) {
                try ctx.pool.submitMatch(ctx.alloc, match, matchId);
                positionOver = false;
                if (switchPlayers and !ctx.pool.blockNewSubmit) {
                    try ctx.engineInventory.sendMsgAll("ucinewgame");
                    matchId = ctx.pool.startMatch();
                    switchPlayers = false;
                    match.swapPlayers();
                    match.chessState = originalState.copy();
                    match.resetTimes();
                    match.positionUpdated = true;
                } else {
                    roundOver = true;
                }
            } else {
                try match.sendPositionUpdate(&ctx.engineInventory);
                try match.sendGoCmd(&ctx.engineInventory);

                turnTimer.reset();
                turnTimer.startTimeTick();
                //match.turnSW.restart();
            }
        }

        //try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = heartBeatNS }, .real);
        try std.Io.sleep(mainl.getGlobalIo(), .{ .nanoseconds = @divFloor(std.time.ns_per_ms, 16) }, .awake);
    }
}
pub fn main(init: std.process.Init) !void {

    // 1st arg is the zig file, 2nd is the .info file for the evaluation
    mainl.GLOBAL_CTX.setInit(init);
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);
    std.debug.assert(args.len > 1);

    const path = args[1];

    if (build_options.useTune) {
        weightl.modif_val();
    }
    chessl.initAll(false);
    try startPool(path, init.gpa);
}
