const configl = @import("config.zig");
const enginel = @import("engine.zig");
const movel = @import("move.zig");
const chessl = @import("chess.zig");
const moveGenl = @import("move_generation.zig");
const heuristicl = @import("heuristic.zig");
const weightl = @import("weights.zig");
const hashl = @import("hashTable.zig");
const schedulerl = @import("search/scheduler.zig");
const threadingl = @import("search/threading.zig");

const mailn = @import("main.zig");

const std = @import("std");

const engine = enginel.engine;
const IMove = movel.IMove;
const Board_state = chessl.Board_state;
const threadInfo = threadingl.threadInfo;
const threadInfo_container = threadingl.threadInfo_container;
const threadPackageArray = threadingl.threadPackageArray;
const scoreType = heuristicl.scoreType;
const moveDecisionExt = schedulerl.moveDecisionExt;
const debug_err = chessl.debug_err;
