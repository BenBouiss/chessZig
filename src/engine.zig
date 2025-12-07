const std = @import("std");

const utilsl = @import("utils.zig");
const chess = @import("chess.zig");
const mainl = @import("main.zig");
const configl = @import("config.zig");
const movel = @import("move.zig");
const explorationl = @import("exploration.zig");
const benchmarkl = @import("benchmark.zig");

const Board_state = chess.Board_state;
const e_moveFlags = movel.e_moveFlags;
const IMove = movel.IMove;
const debug_err = chess.debug_err;

const GLOBAL_ALLOC = mainl.GLOBAL_ALLOC;

const e_engineCmd = enum(u8) { NOOP = 0, QUIT, STOP, ISREADY, GO, POSITION, UCINEWGAME, REGISTER, SETOPTION, DEBUG, UCI, PONDERHIT, PRINT };
const e_goTypes = enum(u8) { SEARCHMOVES, PONDER, EVAL };
const e_engineOptions = enum(u8) { THREADS = 0, USEHASHTABLE, HASHTABLESIZE, INVALID };
const e_engineOptionsArgType = enum(u8) { SPIN = 0, CHECK, STRING, COMBO, INVALID };

pub const TICKRATE: u8 = 20; // alla MC 20 ticks/second
pub const UPDATE_TICKRATE: u8 = 1; // 1 ticks/second
pub const WAIT_TICKRATE_NS = (1 / TICKRATE) * (std.math.pow(u64, 10, 9));
pub const UPDATE_TICKRATE_NS = (1 / UPDATE_TICKRATE) * (std.math.pow(u64, 10, 9));

pub const goArgStruct = struct {
    searchMoves: bool = false,
    ponder: bool = false,
    infinite: bool = false,
    eval: bool = false,
    wtime: u32 = 0,
    btime: u32 = 0,
    winc: u32 = 0,
    binc: u32 = 0,
    movestogo: u32 = 0,
    movetime: u32 = 0,
    nodes: u64 = 0,
    depth: u16 = 1,
    mate: u16 = 0,
};

pub const inputChannel = struct {
    cmdBuffer: std.ArrayList([]const u8),
    lock: bool = false,

    fn acquireLock(p_self: *inputChannel) void {
        while (p_self.lock) {
            //std.Thread.sleep((1 / TICKRATE) * (std.math.pow(u64, 10, 9)));
        }
        p_self.lock = true;
    }
    fn releaseLock(p_self: *inputChannel) void {
        p_self.lock = false;
    }
    pub fn readBuffer(p_self: *inputChannel) []const u8 {
        p_self.acquireLock();
        const ret = p_self.cmdBuffer.orderedRemove(0);
        p_self.releaseLock();
        return ret;
    }
    pub fn putCmd(p_self: *inputChannel, alloc: std.mem.Allocator, cmd: []const u8) bool {
        p_self.acquireLock();
        p_self.cmdBuffer.append(alloc, cmd) catch {
            p_self.releaseLock();
            return false;
        };
        p_self.releaseLock();
        return true;
    }
};

const MAX_THREAD: u32 = 64;
const MAX_HASHSIZE = 1000; // in MB => 1 GB

const optionInfo_spin = struct { min: u32, max: u32, default: u32 };

const optionInfo_str = struct { default: []const u8, _var: []const u8 };

const optionInfo = union { spin: optionInfo_spin, str: optionInfo_str };

pub const setOptionEntry = struct {
    name: []const u8,
    optionType: e_engineOptions = .INVALID,
    argType: e_engineOptionsArgType = .INVALID,
    info: optionInfo,
    pub fn optionNameMsg(self: *setOptionEntry, alloc: std.mem.Allocator) ![]const u8 {
        var msg: []const u8 = undefined;
        if (self.argType == .SPIN) {
            msg = try std.fmt.allocPrint(alloc, "option name {s} type {} default {d} min {d} max {d}", .{ self.name, self.argType, self.info.spin.default, self.info.spin.min, self.info.spin.max });
        } else if (self.argType == .COMBO) {
            msg = try std.fmt.allocPrint(alloc, "option name {s} type {} default {s} var {s}", .{ self.name, self.argType, self.info.str.default, self.info.str._var });
        } else if (self.argType == .CHECK) {
            msg = try std.fmt.allocPrint(alloc, "option name {s} type {} default {s} var {s}", .{ self.name, self.argType, self.info.str.default, self.info.str._var });
        }
        return msg;
    }
};

pub const engineStatus = struct {
    running: bool = false,
    searching: bool = false,
    debugMode: bool = false,
    positionProvided: bool = false,
};
pub const engineIdentification = struct {
    name: []const u8 = configl.NAME,
    author: []const u8 = configl.AUTHOR,
    code: []const u8 = configl.VERSION,
    setLater: bool = false,
};

pub const engineOptions = struct {
    nThreads: u16 = 1,
    useHashTable: bool = false,
    hashTableSize: u64 = 0,
    setOptions: std.ArrayList(setOptionEntry) = undefined,
    nOptions: u16 = 0,
};

pub const engine = struct {
    state: Board_state,
    workingThreads: std.ArrayList(std.Thread),
    status: engineStatus = .{},
    input: inputChannel,
    searcher: explorationl.uciSearcher,
    alloc: std.mem.Allocator,
    uciMode: bool = false,
    id: engineIdentification = .{},
    options: engineOptions = .{},

    pub fn init(alloc: std.mem.Allocator) !engine {
        var ret: engine = undefined;
        ret.input = undefined;
        ret.input.lock = false;
        ret.input.cmdBuffer = try std.ArrayList([]const u8).initCapacity(alloc, 10);
        ret.status = .{};
        ret.id = .{};
        ret.searcher = .{};
        ret.workingThreads = try std.ArrayList(std.Thread).initCapacity(alloc, 2);
        ret.options = .{};
        ret.options.setOptions = try std.ArrayList(setOptionEntry).initCapacity(alloc, 4);
        ret.alloc = GLOBAL_ALLOC;
        ret.uciMode = true;
        try ret.initOptions();
        ret.printEngineInfo();

        return ret;
    }

    pub fn printEngineInfo(p_self: *engine) void {
        var buffer: [1024]u8 = std.mem.zeroes([1024]u8);
        var msgId = std.fmt.bufPrint(&buffer, "id name {s}", .{p_self.id.name}) catch unreachable;
        p_self.respond(msgId);
        msgId = std.fmt.bufPrint(&buffer, "id version {s}", .{p_self.id.code}) catch unreachable;
        p_self.respond(msgId);
        msgId = std.fmt.bufPrint(&buffer, "id author {s}", .{p_self.id.author}) catch unreachable;
        p_self.respond(msgId);

        for (0..p_self.options.nOptions) |i| {
            const msg = p_self.options.setOptions.items[i].optionNameMsg(p_self.alloc) catch unreachable;
            defer p_self.alloc.free(msg);
            p_self.respond(msg);
        }
        p_self.respond("uciok");
    }
    pub fn initOptions(p_self: *engine) !void {
        //p_self.addOption(.THREADS, .SPIN,
        try p_self.addOption(.{ .name = "threads", .optionType = .THREADS, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = 1, .max = MAX_THREAD, .default = 1 } } });
        try p_self.addOption(.{ .name = "Hash", .optionType = .HASHTABLESIZE, .argType = .SPIN, .info = optionInfo{ .spin = optionInfo_spin{ .min = 1, .max = MAX_HASHSIZE, .default = 1 } } });
        //p_self.addOption(.{ .name = "useHash", .optionType = .USEHASHTABLE, .argType = .CHECK, ._type = bool, .default = true, ._var = .{ false, true } });
    }
    pub fn addOption(p_self: *engine, opt: setOptionEntry) !void {
        try p_self.options.setOptions.append(p_self.alloc, opt);
        p_self.options.nOptions += 1;
    }
    fn executeBuffer(p_self: *engine, cmdBuffer: []const u8) void {
        if (p_self.uciMode) {
            const cmdtype = getCmdType(cmdBuffer) catch unreachable;
            const trimmedBuffer = utilsl.trimStr(cmdBuffer);
            //std.debug.print("[DEBUG] executeBuffer: before: ({d}: {s}), after: ({d}: {s})\n", .{ cmdBuffer.len, cmdBuffer, trimmedBuffer.len, trimmedBuffer });
            const status = p_self.uci_executeCmd(cmdtype, trimmedBuffer);
            if (p_self.status.debugMode) {
                if (cmdtype != .NOOP) {
                    std.debug.print("[DEBUG] executeBuffer: found command type {} status: {}\n", .{ cmdtype, status });
                }
            }
        }
    }
    pub fn uci_executeCmd(p_self: *engine, cmd: e_engineCmd, cmdBuffer: []const u8) bool {
        switch (cmd) {
            .NOOP => {
                return true;
            },
            .QUIT => {
                p_self.status.running = false;
                p_self.searcher.interrupt = true;
                p_self.respond("its ovah");
                return true;
            },
            .STOP => {
                p_self.searcher.interrupt = true;
                return true;
            },
            .ISREADY => {
                return p_self.executeIsReady();
            },
            .GO => {
                if (!p_self.status.positionProvided) {
                    return false;
                }
                return p_self.executeGoCmd(cmdBuffer);
            },
            .POSITION => {
                return p_self.executePositionCmd(cmdBuffer, p_self.alloc);
            },
            .UCINEWGAME => {
                return p_self.executeUciNewGameCmd();
            },
            .REGISTER => {
                return p_self.executeRegisterCmd(cmdBuffer);
            },
            .SETOPTION => {
                p_self.respond("setoption needs to be setup");
                return p_self.executeSetOptionCmd(cmdBuffer);
            },
            .DEBUG => {
                return p_self.executeDebugCmd(cmdBuffer);
            },
            .UCI => {
                p_self.respond("ICU");
                return true;
            },
            .PONDERHIT => {
                p_self.respond("pondering ...");
                return true;
            },
            .PRINT => {
                if (p_self.status.positionProvided) {
                    chess.print_boardstate(&p_self.state);
                    return true;
                }
                return false;
            },
        }
        return true;
    }
    pub fn respond(self: engine, msg: []const u8) void {
        _ = self;
        std.debug.print("\t [RESP]: {s}\n", .{msg});
    }
    pub fn addCommand(p_self: *engine, alloc: std.mem.Allocator, cmd: []const u8) bool {
        _ = p_self.input.putCmd(alloc, cmd);
        return true;
    }
    pub fn sendKill(p_self: *engine) void {
        p_self.status.running = false;
        p_self.searcher.interrupt = true;
        p_self.respond("its ovah");
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.workingThreads.items[i].join();
        }
    }
    pub fn free(p_self: *engine) void {
        p_self.input.cmdBuffer.deinit(p_self.alloc);
        p_self.workingThreads.deinit(p_self.alloc);
        p_self.options.setOptions.deinit(p_self.alloc);
    }

    pub fn executeUciNewGameCmd(p_self: *engine) bool {
        p_self.status.positionProvided = false;
        return true;
    }
    pub fn executeDebugCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        if (utilsl.contains(cmdBuffer, "on", .ignoreCase)) {
            p_self.status.debugMode = true;
            return true;
        } else if (utilsl.contains(cmdBuffer, "off", .ignoreCase)) {
            p_self.status.debugMode = false;
            return true;
        }
        return false;
    }
    pub fn executeRegisterCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        //
        var tokens = utilsl.split(u8, p_self.alloc, cmdBuffer, ' ') catch {
            return false;
        };
        defer tokens.deinit(p_self.alloc);
        var tokenIndex: u32 = 1;
        while (tokenIndex != tokens.items.len) {
            if (utilsl.contains(tokens.items[tokenIndex], "later", .ignoreCase)) {
                p_self.id.setLater = true;
                return true;
            }
            if (utilsl.contains(tokens.items[tokenIndex], "name", .ignoreCase)) {
                if ((tokenIndex != tokens.items.len) and !utilsl.contains(tokens.items[tokenIndex + 1], "code", .ignoreCase)) {
                    p_self.setName(tokens.items[tokenIndex + 1]);
                }
            } else if (utilsl.contains(tokens.items[tokenIndex], "code", .ignoreCase)) {
                if ((tokenIndex != tokens.items.len) and !utilsl.contains(tokens.items[tokenIndex + 1], "name", .ignoreCase)) {
                    p_self.setCode(tokens.items[tokenIndex + 1]);
                }
            }
            tokenIndex += 2;
        }
        return true;
    }
    pub fn executeSetOptionCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        var tokens = utilsl.split(u8, p_self.alloc, cmdBuffer, ' ') catch {
            return false;
        };
        defer tokens.deinit(p_self.alloc);
        if (tokens.items.len < 3) {
            return false;
        }
        //if (tokens.items.len == 3)
        //const optionType: e_engineOptions = parseSetOptionTypeCmd(tokens.items[2]);
        //switch (optionType) {
        //    .INVALID => {
        //        return false;
        //    },
        //    .THREADS => {},
        //}
        return true;
    }

    fn setName(p_self: *engine, name: []const u8) void {
        p_self.id.name = name;
    }
    fn setCode(p_self: *engine, code: []const u8) void {
        p_self.id.code = code;
    }
    fn executePositionCmd(p_self: *engine, cmdBuffer: []const u8, alloc: std.mem.Allocator) bool {
        const cmdOffset = 8;
        //* position [fen <fenstring> | startpos ]  moves <move1> .... <movei>
        // ex: position rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w AHah -
        if (utilsl.contains(cmdBuffer, "startpos", .ignoreCase)) {
            chess.applyUciMoves(&p_self.state, cmdBuffer[cmdOffset..], alloc) catch {
                return false;
            };
        } else if (utilsl.contains(cmdBuffer, "fen", .ignoreCase)) {
            const fenCmdOffset = 4;
            p_self.state = chess.getBoardFromUciFen(cmdBuffer[(cmdOffset + fenCmdOffset)..], alloc) catch {
                return false;
            };
        } else {
            return false;
        }
        p_self.status.positionProvided = true;
        return true;
    }

    pub fn executeIsReady(p_self: *engine) bool {
        while (p_self.status.searching) {
            std.Thread.sleep(WAIT_TICKRATE_NS);
        }
        p_self.respond("readyok");
        return true;
    }
    pub fn executeGoCmd(p_self: *engine, cmdBuffer: []const u8) bool {
        var tokens = utilsl.split(u8, p_self.alloc, cmdBuffer, ' ') catch {
            return false;
        };
        defer tokens.deinit(p_self.alloc);
        const goArg = parseGoCmd(&tokens);

        p_self.searcher.reset();
        p_self.searcher.config = goArg;
        p_self.status.positionProvided = false;
        return explorationl.dispatchUciGoCmd(p_self, cmdBuffer);
    }
};
pub fn getLastMoveFromUci(p_board: *Board_state, cmdBuffer: []const u8, alloc: std.mem.Allocator) !IMove {
    var moveArray = try chess.getMoveListFromStr(p_board, cmdBuffer, alloc);
    defer moveArray.deinit(alloc);
    const n = moveArray.items.len;
    if (n == 0) {
        return debug_err.fenErr;
    }
    var retMove = moveArray.items[n - 1];
    chess.updateMoveWithBoard(p_board, &retMove);
    if (retMove.isEnpassant()) {
        if (p_board.turn == .WHITE) {
            retMove.setCapture(.nBlackPawn);
        } else {
            retMove.setCapture(.nWhitePawn);
        }
    }
    return retMove;
}

fn parseGoCmd(tokens: *std.ArrayList([]const u8)) goArgStruct {
    var goArgs: goArgStruct = .{};
    var tokenIndex: u32 = 1;
    while (tokenIndex < tokens.items.len) {
        const arg = tokens.items[tokenIndex];
        if (utilsl.contains(arg, "searchmoves", .ignoreCase)) {
            goArgs.searchMoves = true;
            tokenIndex -= 1;
        } else if (utilsl.contains(arg, "eval", .ignoreCase)) {
            goArgs.eval = true;
            break;
        } else if (utilsl.contains(arg, "ponder", .ignoreCase)) {
            goArgs.ponder = true;
            tokenIndex -= 1;
        } else if (utilsl.contains(arg, "wtime", .ignoreCase)) {
            goArgs.wtime = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch unreachable;
        } else if (utilsl.contains(arg, "btime", .ignoreCase)) {
            goArgs.btime = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch unreachable;
        } else if (utilsl.contains(arg, "winc", .ignoreCase)) {
            goArgs.winc = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch unreachable;
        } else if (utilsl.contains(arg, "binc", .ignoreCase)) {
            goArgs.binc = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch unreachable;
        } else if (utilsl.contains(arg, "movestogo", .ignoreCase)) {
            goArgs.movestogo = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch unreachable;
        } else if (utilsl.contains(arg, "depth", .ignoreCase)) {
            goArgs.depth = std.fmt.parseInt(u16, tokens.items[tokenIndex + 1], 10) catch unreachable;
        } else if (utilsl.contains(arg, "nodes", .ignoreCase)) {
            goArgs.nodes = std.fmt.parseInt(u64, tokens.items[tokenIndex + 1], 10) catch unreachable;
        } else if (utilsl.contains(arg, "mate", .ignoreCase)) {
            goArgs.mate = std.fmt.parseInt(u16, tokens.items[tokenIndex + 1], 10) catch unreachable;
        } else if (utilsl.contains(arg, "movetime", .ignoreCase)) {
            goArgs.movetime = std.fmt.parseInt(u32, tokens.items[tokenIndex + 1], 10) catch unreachable;
        } else if (utilsl.contains(arg, "infinite", .ignoreCase)) {
            goArgs.infinite = true;
        } else {
            tokenIndex -= 1;
        }

        tokenIndex += 2;
    }

    return goArgs;
}

pub fn parseSetOptionTypeCmd(cmdBuffer: []const u8) e_engineOptions {
    if (utilsl.contains(cmdBuffer, "threads", .ignoreCase)) {
        return .THREADS;
    } else if (utilsl.contains(cmdBuffer, "hash", .ignoreCast)) {
        return .HASHTABLESIZE;
    } else if (utilsl.contains(cmdBuffer, "usehash", .ignoreCast)) {
        return .USEHASHTABLE;
    }
    return .INVALID;
}
pub fn inputThreading(p_self: *engine) void {
    while (p_self.status.running) {
        if (p_self.input.cmdBuffer.items.len != 0) {
            const cmdBuffer = p_self.input.readBuffer();
            p_self.executeBuffer(cmdBuffer);
        }
        std.Thread.sleep(WAIT_TICKRATE_NS);
    }
}

pub fn getCmdType(cmd: []const u8) !e_engineCmd {
    if (utilsl.contains(cmd, "isready", .ignoreCase)) {
        return .ISREADY;
    } else if (utilsl.contains(cmd, "go", .ignoreCase)) {
        return .GO;
    } else if (utilsl.contains(cmd, "position", .ignoreCase)) {
        return .POSITION;
    } else if (utilsl.contains(cmd, "ucinewgame", .ignoreCase)) {
        return .UCINEWGAME;
    } else if (utilsl.contains(cmd, "register", .ignoreCase)) {
        return .REGISTER;
    } else if (utilsl.contains(cmd, "setoption", .ignoreCase)) {
        return .SETOPTION;
    } else if (utilsl.contains(cmd, "debug", .ignoreCase)) {
        return .DEBUG;
    } else if (utilsl.contains(cmd, "uci", .ignoreCase)) {
        return .UCI;
    } else if (utilsl.contains(cmd, "stop", .ignoreCase)) {
        return .STOP;
    } else if (utilsl.contains(cmd, "quit", .ignoreCase)) {
        return .QUIT;
    } else if (utilsl.contains(cmd, "ponderhit", .ignoreCase)) {
        return .PONDERHIT;
    } else if (utilsl.contains(cmd, "print", .ignoreCase)) {
        return .PRINT;
    }
    return .NOOP;
}

pub fn launch_engine(p_engine: *engine) !std.Thread {
    p_engine.status.running = true;
    const inputThread = try std.Thread.spawn(.{}, inputThreading, .{p_engine});
    try p_engine.workingThreads.append(p_engine.alloc, inputThread);
    return inputThread;
}
