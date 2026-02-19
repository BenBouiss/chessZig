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

pub const MAX_HASH_BITS = 18;
pub const MAX_THREAD: u32 = 64;
pub const MAX_HASHSIZE = 1000; // in MB => 1 GB

pub const DEFAULT_THREAD = 1;
pub const DEFAULT_HASHTABLE_SIZE = 1; // in MB
pub const DEFAULT_USEHASHTABLE = true;
pub const DEFAULT_USETEXEL = false;
pub const DEFAULT_USEQUIESC = false;

pub const DEFAULT_DEPTH: u16 = 4;
pub const MIN_DEPTH: u16 = 1;
pub const MAX_DEPTH: u16 = 6;

pub const _DEFAULT_LIMIT_ELO = "false";
pub const DEFAULT_LIMIT_ELO = false;
pub const DEFAULT_ELO: u32 = 2500;

pub const _DEFAULT_FIXED_DEPTH = "true";
pub const DEFAULT_FIXED_DEPTH = true;

pub const MIN_ELO: u32 = 1000;
pub const MAX_ELO: u32 = 3000;

// scheduler options
// maximum allocated time in fraction of the remaining time
pub var SCHEDULER_MAX_TIME_FRCT: f64 = 0.05;
pub var SCHEDULER_CRITICAL_TIME_FRCT: f64 = 0.33;
pub var SCHEDULER_MAX_ENDGAME_DEPTH: u16 = 24;
pub var SCHEDULER_MAX_DEPTH_INCREASE_PER_ITR: u16 = 3;
// estimate of the time increase when increasing the depth by 1
pub var SCHEDULER_GROWTH_TIME_EST: i64 = 10;

// hashTable constants
pub const ITEM_PER_BUCKET = 4;

// inactivity timers:
//
pub const DEBUG_INACTIVITY_SERVING_S = 30; // 30 seconds in ns
pub const DEBUG_INACTIVITY_SERVING_NS = DEBUG_INACTIVITY_SERVING_S * std.math.pow(u64, 10, 9); // 30 seconds in ns
//
pub const DEBUG_INACTIVITY_READING_S = 30; // 30 seconds in ns
pub const DEBUG_INACTIVITY_READING_NS = DEBUG_INACTIVITY_READING_S * std.math.pow(u64, 10, 9); // 30 seconds in ns
//

pub const START_TICKRATE_NS = 2 * std.math.pow(u64, 10, 9); // 2 seconds in ns
pub const LIFE_TICKRATE: u16 = 10;
pub const LIFE_TICKRATE_NS = std.math.pow(u64, 10, 8); // 2 seconds in ns

pub const TICKRATE: u16 = 360; // alla MC 20 ticks/second
pub const UPDATE_TICKRATE: u16 = 360; // 1 ticks/second
pub const INFO_TICKRATE: u16 = 1; // 1 ticks/second

pub const INFO_TICKRATE_NS = (std.math.pow(u64, 10, 9));
pub const WAIT_TICKRATE_NS = 2777777;
pub const UPDATE_TICKRATE_NS = 2777777;
pub const READING_TICKRATE_NS = (2) * (std.math.pow(u64, 10, 6));

pub const ENGINE_PATH: []const u8 = "zig-out/bin/engine";

// Tuner settings
pub const N_POSITIONS: usize = 800000;
//pub const N_POSITIONS: usize = 8;
pub const EPOCH: usize = 2048;
pub const BATCH_SIZE: usize = 16;
pub const USE_ADAGRAD: bool = false;
pub const TUNER_START_FROM_OLD: bool = true;

pub const LEARNING_RATE: f16 = 0.1;
pub const LEARNING_RATE_DROP: f16 = 0.80;
pub const LEARNING_RATE_MIN: f16 = 0.00001;
pub const LEARNING_RATE_FREQ: usize = 64;

pub const WEIGHT_MIN: i64 = -1;
pub const WEIGHT_MAX: i64 = 1;
pub const WEIGHT_MU: f16 = 0;
pub const WEIGHT_SIGMA: f16 = -2;

pub const e_residue_type = enum(u4) { MSE = 0, RMSE };
pub const TUNE_RESIDUE: e_residue_type = .MSE;

pub const TUNE_NORMAL: bool = true; // 392 weights
pub const TUNE_COMPLEXITY: bool = false; // ? weights
pub const TUNE_SAFETY: bool = true; // > 5 weights

pub const N_TERMS: usize = 392 + 5 * @as(usize, @intFromBool(TUNE_SAFETY)); // see below

// TEXEL indexes
pub const TEXEL_PAWN_COUNT_IDX: usize = 0;
pub const TEXEL_BISHOP_COUNT_IDX: usize = 1;
pub const TEXEL_KNIGHT_COUNT_IDX: usize = 2;
pub const TEXEL_ROOK_COUNT_IDX: usize = 3;
pub const TEXEL_QUEEN_COUNT_IDX: usize = 4;

pub const TEXEL_MOVE_COUNT_IDX: usize = 5;
pub const TEXEL_PAWN_ISOL_IDX: usize = 6;
pub const TEXEL_PAWN_STACKED_IDX: usize = 7;

pub const TEXEL_PAWN_PSQT_IDX: usize = 8;
pub const TEXEL_BISHOP_PSQT_IDX: usize = 72;
pub const TEXEL_KNIGHT_PSQT_IDX: usize = 136;
pub const TEXEL_ROOK_PSQT_IDX: usize = 200;
pub const TEXEL_QUEEN_PSQT_IDX: usize = 264;
pub const TEXEL_KING_PSQT_IDX: usize = 328;

pub const TEXEL_SAFETY_PAWN_PROX_IDX: usize = 392;
pub const TEXEL_SAFETY_BISHOP_PROX_IDX: usize = 393;
pub const TEXEL_SAFETY_KNIGHT_PROX_IDX: usize = 394;
pub const TEXEL_SAFETY_ROOK_PROX_IDX: usize = 395;
pub const TEXEL_SAFETY_QUEEN_PROX_IDX: usize = 396;
