// gui section
pub const r = @cImport(@cInclude("raylib.h"));
pub const std = @import("std");

pub const EVENT_TICKRATE_NS = (std.math.pow(u64, 10, 6));

pub const GUI_FPS_FONTSIZE: c_int = 24;
pub const GUI_FPS_COLOR: r.Color = r.RED;

pub const GUI_X_TILE_SIZE: u16 = 64;
pub const GUI_Y_TILE_SIZE: u16 = 64;
