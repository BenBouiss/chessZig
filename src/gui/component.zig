const utilsl = @import("../utils.zig");
const chessl = @import("../chess.zig");
const configl = @import("../config.zig");
const gconfigl = @import("../gui/config.zig");

const guil = @import("gui.zig");
const squarel = @import("../square.zig");
const windowl = @import("window.zig");

const std = @import("std");
const r = gconfigl.r;

const screenCoord = windowl.screenCoord;
const Board_state = chessl.Board_state;
const e_square = squarel.e_square;

pub const BOARD_CELLCOLOR1: r.Color = r.WHITE;
pub const BOARD_CELLCOLOR2: r.Color = r.BLACK;
pub const BOARD_FONTSIZE: c_int = 16;

pub const BOARD_COMPONENT_X_OFFSET = (windowl.screenWidth - gconfigl.GUI_X_TILE_SIZE * 8) / 2;
pub const BOARD_COMPONENT_Y_OFFSET = (windowl.screenHeight - gconfigl.GUI_Y_TILE_SIZE * 8) / 2;
pub const INFO_COMPONENT_X_OFFSET = BOARD_COMPONENT_X_OFFSET;
pub const INFO_COMPONENT_Y_OFFSET = BOARD_COMPONENT_Y_OFFSET - 2 * gconfigl.GUI_Y_TILE_SIZE;

pub const e_componenTypes = enum(u8) { WINDOW, BOARD, INFO };
pub const Component = union(enum) {
    e_boardComponent: boardComponent,
    e_infoComponent: infoComponent,
    e_panelComponent: panelComponent,
};

pub const screenSquare = struct {
    //top left most point of a screen tile
    coord: screenCoord = .{},
    sq: e_square = .invalid,
    pub fn init(sq: e_square, p_comp: *boardComponent) screenSquare {
        return .{ .sq = sq, .coord = sqToScreenCoord(sq, p_comp.coordinate.x, p_comp.coordinate.y) };
    }
    pub fn getMiddleCoord(self: screenSquare) screenCoord {
        return .{ .x = (self.coord.x) + gconfigl.GUI_X_TILE_SIZE / 2, .y = (self.coord.y) + gconfigl.GUI_Y_TILE_SIZE / 2 };
    }
};

pub fn sqToScreenCoord(sq: e_square, x_offset: c_int, y_offset: c_int) screenCoord {
    var ret: screenCoord = undefined;
    const rank = chessl.getSqRank(sq);
    const file = chessl.getSqFile(sq);
    ret.x = x_offset + (file * gconfigl.GUI_X_TILE_SIZE);
    ret.y = y_offset + ((7 - rank) * gconfigl.GUI_Y_TILE_SIZE);
    return ret;
}
pub fn drawBackGround(p_comp: *boardComponent) void {
    for (0..chessl.N_SQUARES) |i| {
        const screenSq = screenSquare.init(@enumFromInt(i), p_comp);
        const coord = screenSq.coord;
        if (((i + (i / chessl.ROW_SIZE)) % 2) == 0) {
            r.DrawRectangle(coord.x, coord.y, gconfigl.GUI_X_TILE_SIZE, gconfigl.GUI_Y_TILE_SIZE, BOARD_CELLCOLOR1);
        } else {
            r.DrawRectangle(coord.x, coord.y, gconfigl.GUI_X_TILE_SIZE, gconfigl.GUI_Y_TILE_SIZE, BOARD_CELLCOLOR2);
        }
    }
}
pub fn refreshBoard(p_comp: *boardComponent) bool {
    drawBackGround(p_comp);
    for (0..chessl.N_SQUARES) |i| {
        const sq: e_square = @enumFromInt(i);
        const coord = screenSquare.init(sq, p_comp);
        const middleCoord = coord.getMiddleCoord();
        const piece = p_comp.p_chessState.get_piece(@intCast(i));
        if (piece == .nEmptySquare) {
            continue;
        }
        const pieceStr = chessl.getStrFromPiece(piece);
        if (((i + (i / chessl.ROW_SIZE)) % 2) == 0) {
            r.DrawText(&[_]u8{ pieceStr, 0 }, middleCoord.x, middleCoord.y, BOARD_FONTSIZE, BOARD_CELLCOLOR2);
        } else {
            r.DrawText(&[_]u8{ pieceStr, 0 }, middleCoord.x, middleCoord.y, BOARD_FONTSIZE, BOARD_CELLCOLOR1);
        }
    }
    return true;
}

const arr_color = [_]r.Color{ r.WHITE, r.RED, r.GREEN, r.BLUE };
const boardComponent = struct {
    name: []const u8 = "dummy",
    backGroundColor: r.Color = r.WHITE,
    coordinate: screenCoord = .{},
    size: screenCoord = .{},
    needUpdate: bool = false,
    p_chessState: *chessl.Board_state = undefined,
    chessStateProvided: bool = false,
    color_ptr: usize = 0,

    pub fn contains(self: boardComponent, coord: screenCoord) bool {
        const x: bool = ((self.coordinate.x < coord.x) and ((self.coordinate.x + self.size.x) > coord.x));
        const y: bool = ((self.coordinate.y < coord.y) and ((self.coordinate.y + self.size.y) > coord.y));
        return x and y;
    }

    pub fn setBoard(p_self: *boardComponent, p_state: *chessl.Board_state) bool {
        p_self.p_chessState = p_state;
        p_self.chessStateProvided = true;
        return true;
    }
    pub fn onMouseClick(p_self: *boardComponent, mouse: screenCoord, clickType: windowl.e_mouseClicks) bool {
        _ = p_self;
        _ = mouse;
        _ = clickType;

        return true;
    }
    pub fn onUpdateCallback(p_self: *boardComponent) bool {
        if (!p_self.chessStateProvided) {
            return false;
        }
        //std.debug.print("[DEBUG] onUpdateCallback.boardComponent: printing the board\n", .{});

        r.BeginDrawing();
        defer r.EndDrawing();
        const status = refreshBoard(p_self);
        return status;
        //r.BeginDrawing();
        //r.ClearBackground(arr_color[p_self.color_ptr]);
        //p_self.color_ptr = (p_self.color_ptr + 1) % arr_color.len;
        //defer r.EndDrawing();
        //return true;
    }
    pub fn pingUpdate(p_self: *boardComponent) void {
        p_self.needUpdate = true;
    }
    pub fn initCallback(p_self: *boardComponent) bool {
        r.BeginDrawing();
        defer r.EndDrawing();
        r.DrawRectangle(p_self.coordinate.x, p_self.coordinate.y, p_self.size.x, p_self.size.y, p_self.backGroundColor);
        return true;
    }
    pub fn tickCallback(p_self: *boardComponent) bool {
        //r.BeginDrawing();
        //r.ClearBackground(arr_color[p_self.color_ptr]);
        //p_self.color_ptr = (p_self.color_ptr + 1) % arr_color.len;
        //defer r.EndDrawing();
        _ = p_self;
        return true;
    }
    pub fn freeCallback(p_self: *boardComponent, alloc: std.mem.Allocator) bool {
        _ = p_self;
        _ = alloc;
        return true;
    }
};

const infoComponent = struct {
    name: []const u8 = "dummy_info",
    backGroundColor: r.Color = r.GRAY,
    coordinate: screenCoord = .{},
    size: screenCoord = .{},
    needUpdate: bool = false,
    pub fn contains(self: infoComponent, coord: screenCoord) bool {
        const x: bool = ((self.coordinate.x <= coord.x) and ((self.coordinate.x + self.size.x) >= coord.x));
        const y: bool = ((self.coordinate.y <= coord.y) and ((self.coordinate.y + self.size.y) >= coord.y));
        return x and y;
    }
    pub fn onMouseClick(p_self: *infoComponent, mouse: screenCoord, clickType: windowl.e_mouseClicks) bool {
        _ = p_self;
        _ = mouse;
        _ = clickType;
        return true;
    }
    pub fn onUpdateCallback(p_self: *infoComponent) bool {
        _ = p_self;
        return true;
    }
    pub fn tickCallback(p_self: *infoComponent) bool {
        _ = p_self;
        return true;
    }
    pub fn freeCallback(p_self: *infoComponent, alloc: std.mem.Allocator) bool {
        _ = p_self;
        _ = alloc;

        return true;
    }
    pub fn initCallback(p_self: *infoComponent) bool {
        //if (!p_self.chessStateProvided) {
        //    return false;
        //}

        r.BeginDrawing();
        defer r.EndDrawing();
        r.DrawRectangle(p_self.coordinate.x, p_self.coordinate.y, p_self.size.x, p_self.size.y, p_self.backGroundColor);
        return true;
    }
};
const panelComponent = struct {
    name: []const u8 = "dummy_panel",
    backGroundColor: r.Color = r.LIGHTGRAY,
    coordinate: screenCoord = .{},
    size: screenCoord = .{},
    needUpdate: bool = false,
    color_ptr: usize = 0,
    pub fn contains(self: panelComponent, coord: screenCoord) bool {
        const x: bool = ((self.coordinate.x < coord.x) and ((self.coordinate.x + self.size.x) > coord.x));
        const y: bool = ((self.coordinate.y < coord.y) and ((self.coordinate.y + self.size.y) > coord.y));
        return x and y;
    }
    fn flipColor(p_self: *panelComponent) void {
        if (p_self.color_ptr % 2 == 0) {
            p_self.backGroundColor = r.DARKBLUE;
        } else {
            p_self.backGroundColor = r.LIGHTGRAY;
        }
        p_self.color_ptr += 1;
    }
    pub fn onMouseClick(p_self: *panelComponent, mouse: screenCoord, clickType: windowl.e_mouseClicks) bool {
        _ = mouse;
        if (clickType == .LEFTCLICK) {
            p_self.flipColor();
            _ = p_self.initCallback();
        }
        return true;
    }
    pub fn onUpdateCallback(p_self: *panelComponent) bool {
        _ = p_self;
        return true;
    }
    pub fn tickCallback(p_self: *panelComponent) bool {
        _ = p_self;
        return true;
    }
    pub fn freeCallback(p_self: *panelComponent, alloc: std.mem.Allocator) bool {
        _ = p_self;
        _ = alloc;

        return true;
    }
    pub fn initCallback(p_self: *panelComponent) bool {
        //if (!p_self.chessStateProvided) {
        //    return false;
        //}

        r.BeginDrawing();
        defer r.EndDrawing();
        r.DrawRectangle(p_self.coordinate.x, p_self.coordinate.y, p_self.size.x, p_self.size.y, p_self.backGroundColor);
        return true;
    }
};
