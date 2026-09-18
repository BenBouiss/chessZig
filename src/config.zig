pub const NAME = "Ben";
pub const AUTHOR = "Ben";
pub const VERSION = "0.0.1";
pub const SEED = 42;
pub const MAX_MATCH_STR_LENGTH = 24 + 4096 * (5 + 1);
pub const MAX_USER_INPUT = MAX_MATCH_STR_LENGTH;

pub const EVALUTATION_TIMEOUT_ERROR_MS: u64 = 10_000; // 2 sec

pub const MAX_SPRT_MATCH: usize = 10_000;
pub const MAX_THREAD = 16;
pub const MAX_HASHSIZE = 1000; // in MB => 1 GB

pub const DEFAULT_THREAD = 1;
pub const DEFAULT_HASHTABLE_SIZE = 16; // in MB

pub const DEFAULT_TRACKMETRICS = true;
pub const _DEFAULT_TRACKMETRICS = "true";

pub const DEFAULT_REPORTPROGRESS = true;
pub const _DEFAULT_REPORTPROGRESS = "true";

pub const _DEFAULT_FIXED_DEPTH = "false";
pub const DEFAULT_FIXED_DEPTH = false;

pub const _DEFAULT_STATIC_SEARCH = "false";
pub const DEFAULT_STATIC_SEARCH = false;

//https://www.chessprogramming.org/Move_Ordering
pub const ORDERING_LINE_VALUE = 99_999_999;
pub const KILLER_0_HEURISTIC_VALUE = 1_999_999;

pub const ORDERING_PROMOTIONS = KILLER_0_HEURISTIC_VALUE + 1;

pub const MAX_HIST_HEURISTIC_VALUE = 16394;
pub const MAX_CONTINUATION_HEURISTIC_VALUE = 16394;

pub const DEFAULT_ELO = 0;
pub const MIN_ELO = 0;
pub const MAX_ELO = 0;

pub const TT_strat = enum { ALWAYS_REPLACE, KEEP_DEEPER };
pub const DEFAULT_TT_STRAT: TT_strat = .KEEP_DEEPER;
pub const OLD_THRESHOLD = 2;

pub const USE_NNUE = true;
//pub const NET_PATH = "extern/simple-320-colM-128/quantised.bin";
pub const NET_PATH = "extern/simple_1024_load100_cosine-120/quantised.bin";
//pub const NET_PATH = "extern/simple_1024_retrained-120/quantised.bin";

// scheduler options
// maximum allocated time in fraction of the remaining time
pub const SCHEDULER_MAX_TIME_DIV = 20;
pub const SCHEDULER_MAX_TIME_INC_DIV = 2;
pub const SCHEDULER_CRITICAL_TIME_DIV = 3;

// hashTable constants
pub const ITEM_PER_BUCKET = 3;

pub const INFO_TICKRATE = 1; // 1 ticks/second

pub const INFO_TICKRATE_NS = INFO_TICKRATE * 1_000_000_000;
pub const WAIT_TICKRATE_NS = 500_000;

// Tuner settings
pub const N_POSITIONS = 300000;

pub const TUNE_COMPLEXITY: bool = false; // ? weights

// TEXEL indexes
// mobility
pub const TEXEL_MOVE_COUNT_IDX = 0;
pub const TEXEL_OPEN_ROOK_IDX = 1;
// material
pub const TEXEL_DOUBLE_BISHOP_IDX = 2;

//structure protection
pub const TEXEL_PROTECTION_COUNT_IDX = 3;
pub const TEXEL_CENTER_PROTECTION_IDX = 4;
pub const TEXEL_HANGING_PIECE_IDX = 5;
pub const TEXEL_BIG_PIECE_THREAT_IDX = 6;

// pawn structure
pub const TEXEL_PAWN_ISOL_IDX = 7;
pub const TEXEL_PAWN_STACKED_IDX = 8;
pub const TEXEL_PAWN_PASSED_IDX = 9;
pub const TEXEL_PAWN_PHALANX_IDX = 10;
pub const TEXEL_PAWN_CONNECTED_IDX = 11;

// safety
//pub const TEXEL_SAFETY_PAWN_PROX_IDX = 15;
//pub const TEXEL_SAFETY_BISHOP_PROX_IDX = 16;
//pub const TEXEL_SAFETY_KNIGHT_PROX_IDX = 17;
//pub const TEXEL_SAFETY_ROOK_PROX_IDX = 18;
//pub const TEXEL_SAFETY_QUEEN_PROX_IDX = 19;

// king proximity
pub const TEXEL_KING_DISTANCE_IDX = 12;

// counts
pub const TEXEL_PAWN_COUNT_IDX = 13;
pub const TEXEL_BISHOP_COUNT_IDX = 14;
pub const TEXEL_KNIGHT_COUNT_IDX = 15;
pub const TEXEL_ROOK_COUNT_IDX = 16;
pub const TEXEL_QUEEN_COUNT_IDX = 17;

// PSQT
pub const TEXEL_PAWN_PSQT_IDX = 18;
pub const TEXEL_BISHOP_PSQT_IDX = 82;
pub const TEXEL_KNIGHT_PSQT_IDX = 146;
pub const TEXEL_ROOK_PSQT_IDX = 210;
pub const TEXEL_QUEEN_PSQT_IDX = 274;
pub const TEXEL_KING_PSQT_IDX = 338;

pub const N_TERMS = TEXEL_KING_PSQT_IDX + 64; // see below
