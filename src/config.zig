const build_options = @import("build_options");

const std = @import("std");

pub const NAME = "Ben";
pub const AUTHOR = "Ben";
pub const VERSION = "0.0.1";
pub const SEED: u64 = 42;
pub const MAX_MATCH_STR_LENGTH: u64 = 24 + 4096 * (5 + 1);
pub const MAX_USER_INPUT: u64 = MAX_MATCH_STR_LENGTH;
pub const MAX_LINE_LENGTH: usize = 32;

pub const EVALUTATION_GUI_WAIT_MS: u64 = 500;

pub const MAX_SPRT_MATCH: usize = 10_000;
pub const MAX_THREAD: u32 = 64;
pub const MAX_HASHSIZE = 1000; // in MB => 1 GB

pub const DEFAULT_THREAD = 1;
pub const DEFAULT_HASHTABLE_SIZE = 25; // in MB

pub const DEFAULT_TRACKMETRICS = true;
pub const _DEFAULT_TRACKMETRICS = "true";

pub const DEFAULT_REPORTPROGRESS = true;
pub const _DEFAULT_REPORTPROGRESS = "true";

pub const DEFAULT_USEHASHTABLE = false;
pub const _DEFAULT_USEHASHTABLE = "false";

pub const DEFAULT_USE_NULLPRUNE = true;
pub const _DEFAULT_USE_NULLPRUNE = "true";

pub const ORDERING_LINE_VALUE = 99999;

//https://www.chessprogramming.org/Move_Ordering
pub const ORDERING_PROMOTIONS = KILLER_0_HEURISTIC_VALUE + 1;
pub const ORDERING_SEE_MULTI = 10;

pub const KILLER_0_HEURISTIC_VALUE = 900;
pub const KILLER_1_HEURISTIC_VALUE = 800;
pub const MAX_HIST_HEURISTIC_VALUE = 700;

pub const DEFAULT_USEQUIESC = true;
pub const _DEFAULT_USEQUIESC = "true";

pub const DEFAULT_DEPTH: u16 = 4;
pub const MIN_DEPTH: u16 = 1;
pub const MAX_DEPTH: u16 = 6;
pub const MAXIMUM_SEARCH_DEPTH: u16 = 64;
pub const MAX_QUIESC_DEPTH: u16 = 8;

pub const _DEFAULT_LIMIT_ELO = "false";
pub const DEFAULT_LIMIT_ELO = false;
pub const DEFAULT_ELO: u32 = 2500;

pub const _DEFAULT_FIXED_DEPTH = "false";
pub const DEFAULT_FIXED_DEPTH = false;

pub const _DEFAULT_STATIC_SEARCH = "false";
pub const DEFAULT_STATIC_SEARCH = false;

pub const DEFAULT_LATE_MOVE_REDUCTION = true;
pub const _DEFAULT_LATE_MOVE_REDUCTION = "true";

pub const DEFAULT_SEARCH_TYPE: searchType = .ZWS;
pub const _DEFAULT_SEARCH_TYPE = "ZWS";

pub const searchType = enum { STD, PVS, ZWS };

pub const TT_strat = enum { ALWAYS_REPLACE, ALWAYS_REPLACE_OLDEST, KEEP_DEEPER };
pub const DEFAULT_TT_STRAT: TT_strat = .ALWAYS_REPLACE_OLDEST;

pub const DEFAULT_USE_FUTILITY = false;
pub const _DEFAULT_USE_FUTILITY = "false";

pub const DEFAULT_USE_RAZORING = false;
pub const _DEFAULT_USE_RAZORING = "false";

pub const MIN_ELO: u32 = 1000;
pub const MAX_ELO: u32 = 3000;

// scheduler options
// maximum allocated time in fraction of the remaining time
pub var SCHEDULER_MAX_TIME_FRCT: f64 = 0.05;
pub var SCHEDULER_CRITICAL_TIME_FRCT: f64 = 0.33;
pub var SCHEDULER_MAX_ENDGAME_DEPTH: u16 = 24;

// estimate of the time increase when increasing the depth by 1
pub var SCHEDULER_GROWTH_TIME_EST: i64 = 10;

// hashTable constants
pub const ITEM_PER_BUCKET = 3;

// inactivity timers:
//
pub const DEBUG_INACTIVITY_SERVING_S = 30; // 30 seconds in ns
pub const DEBUG_INACTIVITY_SERVING_NS = DEBUG_INACTIVITY_SERVING_S * std.math.pow(u64, 10, 9); // 30 seconds in ns
//
pub const DEBUG_INACTIVITY_READING_S = 30; // 30 seconds in ns
pub const DEBUG_INACTIVITY_READING_NS = DEBUG_INACTIVITY_READING_S * std.math.pow(u64, 10, 9); // 30 seconds in ns
pub const DEBUG_INACTIVITY_READING_US = DEBUG_INACTIVITY_READING_S * std.math.pow(u64, 10, 6); // 30 seconds in us
//

pub const START_TICKRATE_NS = 2 * std.math.pow(u64, 10, 9); // 2 seconds in ns

pub const INFO_TICKRATE: u16 = 1; // 1 ticks/second

pub const INFO_TICKRATE_NS = (std.math.pow(u64, 10, 9));
pub const WAIT_TICKRATE_NS = 500_000;
pub const WR_TICKRATE_NS = 500_000;
pub const ENGINE_SERVING_TICKRATE_NS = 100_000;

pub const ENGINE_PATH: []const u8 = "zig-out/bin/engine";

// Tuner settings
//pub const N_POSITIONS: usize = 800000;
pub const N_POSITIONS: usize = 300000;
//pub const N_POSITIONS: usize = 8;

pub const e_residue_type = enum(u4) { MSE = 0, RMSE };
pub const TUNE_RESIDUE: e_residue_type = .MSE;

pub const TUNE_NORMAL: bool = true; // 392 weights
pub const TUNE_SAFETY: bool = true; // > 5 weights
pub const TUNE_COMPLEXITY: bool = false; // ? weights
pub const TUNE_PSQT: bool = true; // > 5 weights

//pub const N_TERMS: usize = 392 + 5 * @as(usize, @intFromBool(TUNE_SAFETY)); // see below
pub const N_TERMS: usize = 397 + 5 * @as(usize, @intFromBool(TUNE_SAFETY)); // see below

// TEXEL indexes
pub const TEXEL_PAWN_COUNT_IDX: usize = 0;
pub const TEXEL_BISHOP_COUNT_IDX: usize = 1;
pub const TEXEL_KNIGHT_COUNT_IDX: usize = 2;
pub const TEXEL_ROOK_COUNT_IDX: usize = 3;
pub const TEXEL_QUEEN_COUNT_IDX: usize = 4;

pub const TEXEL_MOVE_COUNT_IDX: usize = 5;
pub const TEXEL_KINGMOVE_COUNT_IDX: usize = 6;

pub const TEXEL_PROTECTION_COUNT_IDX: usize = 7;

pub const TEXEL_PAWN_ISOL_IDX: usize = 8;
pub const TEXEL_PAWN_STACKED_IDX: usize = 9;
pub const TEXEL_PAWN_PASSED_IDX: usize = 10;

pub const TEXEL_TEMPO_CHECKS_IDX: usize = 11;

pub const TEXEL_SAFETY_PAWN_PROX_IDX: usize = 12;
pub const TEXEL_SAFETY_BISHOP_PROX_IDX: usize = 13;
pub const TEXEL_SAFETY_KNIGHT_PROX_IDX: usize = 14;
pub const TEXEL_SAFETY_ROOK_PROX_IDX: usize = 15;
pub const TEXEL_SAFETY_QUEEN_PROX_IDX: usize = 16;

pub const TEXEL_KING_PROXIMITY_IDX: usize = 17;

pub const TEXEL_PAWN_PSQT_IDX: usize = 18;
pub const TEXEL_BISHOP_PSQT_IDX: usize = 82;
pub const TEXEL_KNIGHT_PSQT_IDX: usize = 146;
pub const TEXEL_ROOK_PSQT_IDX: usize = 210;
pub const TEXEL_QUEEN_PSQT_IDX: usize = 274;
pub const TEXEL_KING_PSQT_IDX: usize = 338;
