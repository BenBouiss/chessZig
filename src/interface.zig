const std = @import("std");
const utilsl = @import("utils.zig");
const benchmarkl = @import("benchmark.zig");
const chessl = @import("chess.zig");
const explorationl = @import("exploration.zig");
const heuristicl = @import("heuristic.zig");

const e_color = chessl.e_color;
const e_playerType = explorationl.e_playerType;
const e_searchType = explorationl.e_searchType;
const e_heuristicType = heuristicl.e_heuristicType;

const shell_err = error{ERR_ARG};

const e_userCmd = enum(u8) {
    QUIT = 0,
    NOOP,
    SET_BOARD,
    PERFT,
    SET,
    START,
    PRINT,
    CLEAR,
    PRESET,
};

const e_shellSetTable = enum(u8) {
    SEED = 0,
};

const e_playerSetTable = enum(u8) {
    DEPTH = 0,
    SEARCH,
    HEURISTIC,
    TYPE,
};

const MAX_USER_INPUT: u64 = 1024;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
const GLOBAL_ALLOC = GPA.allocator();

const ShellState = struct {
    isOpen: bool = true,
    fenProvided: bool = false,
    chessBoardState: chessl.Board_state = undefined,
};

fn printTerminalGui() void {
    return;
}

pub fn argsToE_Color(arg: []const u8) shell_err!e_color {
    if (utilsl.equal(u8, arg, "white")) {
        return .WHITE;
    } else if (utilsl.equal(u8, arg, "black")) {
        return .BLACK;
    } else {
        return shell_err.ERR_ARG;
    }
}

pub fn argsToE_PlayerType(arg: []const u8) shell_err!e_playerType {
    if (utilsl.equal(u8, arg, "human")) {
        return .Human;
    } else if (utilsl.equal(u8, arg, "bot")) {
        return .Bot;
    } else {
        return shell_err.ERR_ARG;
    }
}

pub fn argsToE_SearchType(arg: []const u8) shell_err!e_searchType {
    if (utilsl.equal(u8, arg, "random")) {
        return e_searchType.Random;
    } else if (utilsl.equal(u8, arg, "simple")) {
        return e_searchType.Simple;
    } else if (utilsl.equal(u8, arg, "depth")) {
        return e_searchType.DepthBot;
    } else {
        return shell_err.ERR_ARG;
    }
}

pub fn argsToE_PlayerSetTable(arg: []const u8) shell_err!e_playerSetTable {
    if (utilsl.equal(u8, arg, "depth")) {
        return .DEPTH;
    } else if (utilsl.equal(u8, arg, "search")) {
        return .SEARCH;
    } else if (utilsl.equal(u8, arg, "heuristic")) {
        return .HEURISTIC;
    } else if (utilsl.equal(u8, arg, "type")) {
        return .TYPE;
    } else {
        return shell_err.ERR_ARG;
    }
}

pub fn argsToE_ShellSetTable(arg: []const u8) shell_err!e_shellSetTable {
    if (utilsl.equal(u8, arg, "seed")) {
        return .SEED;
    } else {
        return shell_err.ERR_ARG;
    }
}

pub fn argsToE_HeuristicType(arg: []const u8) shell_err!e_heuristicType {
    if (utilsl.equal(u8, arg, "simple")) {
        return .Simple;
    } else {
        return shell_err.ERR_ARG;
    }
}
pub fn getUserStdinput() [MAX_USER_INPUT]u8 {
    std.debug.print("> ", .{});
    var stdin_buffer = std.mem.zeroes([MAX_USER_INPUT]u8);
    var line_buffer = std.mem.zeroes([MAX_USER_INPUT]u8);
    var stdin = std.fs.File.stdin().reader(&stdin_buffer);
    var w: std.io.Writer = .fixed(&line_buffer);
    _ = stdin.interface.streamDelimiter(&w, '\n') catch unreachable;
    return line_buffer;
}

pub fn getCmdFromUserInput(buffer: []const u8) e_userCmd {
    var indiv_args = utilsl.split(u8, GLOBAL_ALLOC, utilsl.removePaddingValue(buffer), ' ') catch unreachable;
    if (indiv_args.items.len == 0) {
        return .NOOP;
    }
    const l_cmd = utilsl.lower(GLOBAL_ALLOC, indiv_args.items[0]) catch unreachable;
    defer indiv_args.deinit(GLOBAL_ALLOC);
    defer GLOBAL_ALLOC.free(l_cmd);

    if (utilsl.equal(u8, l_cmd, "quit")) {
        return e_userCmd.QUIT;
    } else if (utilsl.equal(u8, l_cmd, "perft")) {
        return e_userCmd.PERFT;
    } else if (utilsl.equal(u8, l_cmd, "setboard")) {
        return e_userCmd.SET_BOARD;
    } else if (utilsl.equal(u8, l_cmd, "set")) {
        return e_userCmd.SET;
    } else if (utilsl.equal(u8, l_cmd, "start")) {
        return e_userCmd.START;
    } else if (utilsl.equal(u8, l_cmd, "clear")) {
        return e_userCmd.CLEAR;
    } else if (utilsl.equal(u8, l_cmd, "print")) {
        return e_userCmd.PRINT;
    } else if (utilsl.equal(u8, l_cmd, "preset")) {
        return e_userCmd.PRESET;
    } else {
        std.debug.print("Command {s} was not found\n", .{l_cmd});
        return e_userCmd.NOOP;
    }
    return e_userCmd.NOOP;
}

pub fn verifySetBoardArgs(args: std.ArrayList([]const u8)) bool {
    if (args.items.len < 2) {
        //std.debug.print("Command SET_BOARD failed: expected >2 args, the value DEFAULT can also be passed, format: SETBOARD <FEN_CODE>\n", .{});
        return false;
    }
    //std.debug.print("[DEBUG] verifySetBoardArgs: args: {any}\n", .{args});
    return true;
}
pub fn execSetBoard(p_shellState: *ShellState, userBuffer: []const u8) bool {
    var indiv_args = utilsl.split(u8, GLOBAL_ALLOC, utilsl.removePaddingValue(userBuffer), ' ') catch unreachable;
    //std.debug.print("[DEBUG] execSetBoard: buffer : {s}, args: {any}\n", .{ userBuffer, utilsl.removePaddingValue(userBuffer) });
    defer indiv_args.deinit(GLOBAL_ALLOC);

    if (!verifySetBoardArgs(indiv_args)) {
        return false;
    }
    p_shellState.fenProvided = true;
    const def_flag = utilsl.lower(GLOBAL_ALLOC, indiv_args.items[1]) catch {
        return false;
    };
    defer GLOBAL_ALLOC.free(def_flag);
    if (utilsl.equal(u8, def_flag, "default")) {
        p_shellState.chessBoardState = chessl.getBoardFromFen(chessl.DEFAULT_FEN);
    } else {
        const concat = utilsl.concatSlice(u8, GLOBAL_ALLOC, indiv_args.items[1..], ' ') catch {
            return false;
        };
        defer GLOBAL_ALLOC.free(concat);
        if (concat.len == 1) {
            return false;
        }
        p_shellState.chessBoardState = chessl.getBoardFromFen(concat);
    }

    return true;
}

pub fn verifySetArgs(args: std.ArrayList([]const u8)) bool {
    // exemple cmd:
    // SET <PLAYER> <FIELD> <VAL>
    // ex: SET BLACK DEPTH 4
    // or SET TIMECON FALSE
    // if Player args > 4
    // else > 3
    if (args.items.len < 2) {
        return false;
    }
    const scdArg = utilsl.lower(GLOBAL_ALLOC, args.items[1]) catch {
        return false;
    };
    defer GLOBAL_ALLOC.free(scdArg);
    if (utilsl.equal(u8, scdArg, "white") or utilsl.equal(u8, scdArg, "black")) {
        if (args.items.len != 4) {
            return false;
        }
    }
    return true;
}
pub fn execSet(p_shellState: *ShellState, userBuffer: []const u8) bool {
    var indiv_args = utilsl.split(u8, GLOBAL_ALLOC, utilsl.removePaddingValue(userBuffer), ' ') catch unreachable;
    defer indiv_args.deinit(GLOBAL_ALLOC);
    if (!verifySetArgs(indiv_args)) {
        std.debug.print("Command SET failed: expected <3> args for shell variable set or <4> for player specific variables, format:\nSET <FIELD> <VAL>\nSET <PLAYER> <FIELD> <VAL>`\n", .{});
        return false;
    }
    if (indiv_args.items.len == 3) {
        return _execSetShell(p_shellState, indiv_args);
    } else {
        return _execSetPlayer(p_shellState, indiv_args);
    }
    return true;
}
pub fn _execSetShell(p_shellState: *ShellState, args: std.ArrayList([]const u8)) bool {
    const scdArg = utilsl.lower(GLOBAL_ALLOC, args.items[1]) catch {
        return false;
    };
    const thrdArg = utilsl.lower(GLOBAL_ALLOC, args.items[2]) catch {
        return false;
    };
    defer GLOBAL_ALLOC.free(scdArg);
    defer GLOBAL_ALLOC.free(thrdArg);
    const shellAttr = argsToE_ShellSetTable(scdArg) catch {
        return false;
    };
    switch (shellAttr) {
        .SEED => {
            const seed = std.fmt.parseInt(u64, thrdArg, 10) catch {
                return false;
            };
            p_shellState.chessBoardState.setSeed(seed);
        },
    }
    return true;
}

pub fn _execSetPlayer(p_shellState: *ShellState, args: std.ArrayList([]const u8)) bool {
    const scdArg = utilsl.lower(GLOBAL_ALLOC, args.items[1]) catch {
        return false;
    };
    const thrdArg = utilsl.lower(GLOBAL_ALLOC, args.items[2]) catch {
        return false;
    };
    const frthArg = utilsl.lower(GLOBAL_ALLOC, args.items[3]) catch {
        return false;
    };
    defer GLOBAL_ALLOC.free(scdArg);
    defer GLOBAL_ALLOC.free(thrdArg);
    defer GLOBAL_ALLOC.free(frthArg);

    const color: e_color = argsToE_Color(scdArg) catch {
        return false;
    };

    const playerAttr = argsToE_PlayerSetTable(thrdArg) catch {
        return false;
    };
    switch (playerAttr) {
        .DEPTH => {
            const depth = std.fmt.parseInt(u8, args.items[3], 10) catch {
                return false;
            };
            p_shellState.chessBoardState.setPlayerSearchDepth(color, depth);
        },
        .HEURISTIC => {
            const heuristic = argsToE_HeuristicType(frthArg) catch {
                return false;
            };

            p_shellState.chessBoardState.setPlayerHeuristicType(color, heuristic);
        },
        .SEARCH => {
            const heuristic = argsToE_SearchType(frthArg) catch {
                return false;
            };

            p_shellState.chessBoardState.setPlayerSearcType(color, heuristic);
        },
        .TYPE => {
            const player_type = argsToE_PlayerType(frthArg) catch {
                return false;
            };

            p_shellState.chessBoardState.setPlayerType(color, player_type);
        },
    }
    return true;
}

pub fn verifyPerftArgs(args: std.ArrayList([]const u8)) bool {
    // exemple cmd:
    // Perft <MAXDEPTH> <THREAD>(TBD)
    // ex: Perft 8 0
    // values: 0 use max possible else use 1 for single threaded
    //
    if (args.items.len < 3) {
        return false;
    }
    return true;
}
pub fn execPerft(p_shellState: *ShellState, userBuffer: []const u8) bool {
    var indiv_args = utilsl.split(u8, GLOBAL_ALLOC, utilsl.removePaddingValue(userBuffer), ' ') catch unreachable;
    defer indiv_args.deinit(GLOBAL_ALLOC);
    if (!verifyPerftArgs(indiv_args)) {
        std.debug.print("Command PERFT failed: expected 3 args, format: PERFT <MAXDEPTH> <THREAD>\n", .{});
        return false;
    }
    const depth = std.fmt.parseInt(u8, indiv_args.items[1], 10) catch {
        return false;
    };
    const nThread = std.fmt.parseInt(u8, indiv_args.items[2], 10) catch {
        return false;
    };
    benchmarkl.nodeExplorationBenchmark(&p_shellState.chessBoardState, depth, nThread);
    return true;
}

pub fn execStringCmd(p_shellState: *ShellState, cmdStr: []const u8) bool {
    const cmd_type = getCmdFromUserInput(cmdStr);
    const cmdStatus = execCmd(p_shellState, cmd_type, cmdStr);
    if (!cmdStatus) {
        std.debug.print("Command: {} failed\n", .{cmd_type});
    }
    return cmdStatus;
}

pub fn execCmd(p_shellState: *ShellState, cmd: e_userCmd, userBuffer: []const u8) bool {
    switch (cmd) {
        .NOOP => {
            return true;
        },
        .QUIT => {
            p_shellState.isOpen = false;
            return true;
        },
        .SET => {
            return execSet(p_shellState, userBuffer);
        },
        .SET_BOARD => {
            return execSetBoard(p_shellState, userBuffer);
        },
        .PERFT => {
            return execPerft(p_shellState, userBuffer);
        },
        .START => {
            return execStart(p_shellState);
        },
        .CLEAR => {
            utilsl.clear();
            return true;
        },
        .PRINT => {
            if (p_shellState.fenProvided) {
                chessl.print_boardstate(&p_shellState.chessBoardState);
            } else {
                std.debug.print("Please provide a chess state using the SETBOARD command before using PRINT \n", .{});
            }
            return true;
        },
        .PRESET => {
            return useMainTemplate(p_shellState);
        },
    }
    return true;
}

pub fn execStart(p_shellState: *ShellState) bool {
    chessl.match_routine(&p_shellState.chessBoardState);
    return true;
}

pub fn useMainTemplate(p_shellState: *ShellState) bool {
    _ = execStringCmd(p_shellState, "SETBOARD DEFAULT");

    _ = execStringCmd(p_shellState, "SET SEED 42");

    _ = execStringCmd(p_shellState, "SET WHITE TYPE BOT");
    _ = execStringCmd(p_shellState, "SET WHITE SEARCH RANDOM");

    _ = execStringCmd(p_shellState, "SET BLACK TYPE BOT");
    _ = execStringCmd(p_shellState, "SET BLACK SEARCH DEPTH");
    _ = execStringCmd(p_shellState, "SET BLACK DEPTH 5");
    _ = execStringCmd(p_shellState, "SET BLACK HEURISTIC SIMPLE");
    //p_shellState.chessBoardState.players[0].print();
    //p_shellState.chessBoardState.players[1].print();
    return true;
}

pub fn shell() void {
    var state: ShellState = .{};
    while (state.isOpen) {
        printTerminalGui();
        const userBuffer = getUserStdinput();
        //std.debug.print(" [DEBUG] shell: command found {s}\n", .{userBuffer});
        _ = execStringCmd(&state, &userBuffer);
    }
}
