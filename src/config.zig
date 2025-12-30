const build_options = @import("build_options");

const std = @import("std");

pub const NAME = "Ben";
pub const AUTHOR = "Ben";
pub const VERSION = "0.0.1";
pub const SEED: u64 = 42;
pub const MAX_MATCH_STR_LENGTH: u64 = 24 + 4096 * (5 + 1);
pub const MAX_USER_INPUT: u64 = MAX_MATCH_STR_LENGTH;
pub const MAX_LINE_LENGTH: usize = 128;

pub const MAX_HASH_BITS = 18;
pub const DEFAULT_THREAD = 1;
pub const DEFAULT_HASHTABLE_SIZE = 1; // in MB
pub const DEFAULT_USEHASHTABLE = true;

pub const DEFAULT_DEPTH: u16 = 4;
pub const MIN_DEPTH: u16 = 1;
pub const MAX_DEPTH: u16 = 6;

pub const _DEFAULT_LIMIT_ELO = "false";
pub const DEFAULT_LIMIT_ELO = false;
pub const DEFAULT_ELO: u32 = 1400;
pub const MIN_ELO: u32 = 1000;
pub const MAX_ELO: u32 = 3000;

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
