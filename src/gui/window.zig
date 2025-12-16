const utilsl = @import("../utils.zig");
const chessl = @import("../chess.zig");
const configl = @import("../config.zig");
const gconfigl = @import("../gui/config.zig");
const guil = @import("gui.zig");
const componentl = @import("component.zig");

const std = @import("std");
const r = gconfigl.r;

const Component = componentl.Component;
pub const screenWidth: c_int = 1000;
pub const screenHeight: c_int = 800;

const FPS: c_int = 120;
const sleep_FPS = std.math.pow(u64, 10, 9) / FPS;
pub const screenCoord = struct { x: c_int = 0, y: c_int = 0 };
const windowStatus = struct { debugMode: bool = false, guiOpen: bool = false };

const maxMouseStacksize: u16 = 16;
const mouseStack = struct {
    items: [maxMouseStacksize]mouseInfo = undefined,
    len: u16 = 0,
    lock: bool = false,
    pub fn init() mouseStack {
        return .{};
    }
    fn acquireLock(p_self: *mouseStack) void {
        std.debug.print("[DEBUG] acquireLock.mouseStack: Acquiring lock\n", .{});
        while (p_self.lock) {
            //
        }
        p_self.lock = true;
        return;
    }
    fn releaseLock(p_self: *mouseStack) void {
        std.debug.print("[DEBUG] release.mouseStack: Releasing lock\n", .{});
        p_self.lock = false;
        return;
    }
    pub fn push(p_self: *mouseStack, info: mouseInfo) void {
        p_self.acquireLock();
        if (p_self.len == maxMouseStacksize) {
            p_self.releaseLock();
            return;
        }
        p_self.items[p_self.len] = info;
        p_self.len += 1;
        p_self.releaseLock();
    }
    pub fn pop(p_self: *mouseStack) mouseInfo {
        p_self.acquireLock();
        if (p_self.isEmpty()) {
            p_self.releaseLock();
            return .{};
        }
        const ret = p_self.items[p_self.len - 1];
        p_self.len -= 1;
        p_self.releaseLock();
        return ret;
    }
    pub fn isEmpty(p_self: *mouseStack) bool {
        const ret = p_self.len == 0;
        return ret;
    }
};
const maxComponentAmount: u16 = 10;
const componentContainer = struct {
    items: [maxComponentAmount]*Component = undefined,
    len: u16 = 0,
    pub fn init() componentContainer {
        return .{};
    }
    pub fn append(p_self: *componentContainer, p_comp: *Component) bool {
        if (p_self.len == maxComponentAmount) {
            return false;
        }
        p_self.items[p_self.len] = p_comp;
        p_self.len += 1;
        return true;
    }
    pub fn print(p_self: *componentContainer) void {
        std.debug.print("[DEBUG] Component container(len = {d}) content: ", .{p_self.len});
        for (0..p_self.len) |i| {
            const comp = p_self.items[i];
            switch (comp.*) {
                inline else => |*c| {
                    std.debug.print("{s}, ", .{c.name});
                },
            }
        }
        std.debug.print("\n", .{});
    }

    pub fn getComponentByPosition(p_self: *componentContainer, coord: screenCoord) componentContainer {
        var ret: componentContainer = .{};
        for (0..p_self.len) |i| {
            const comp = p_self.items[i];
            switch (comp.*) {
                inline else => |*c| {
                    if (c.contains(coord)) {
                        _ = ret.append(comp);
                    }
                },
            }
        }
        return ret;
    }
};

const mouseInfo = struct {
    coord: screenCoord = .{},
    isPressed: bool = false,
    refresh: bool = true,
};
pub const e_mouseClicks = enum(u8) { LEFTCLICK };

pub const guiWindow = struct {
    components: componentContainer = .{ .len = 0 },
    screenWidth: c_int = screenWidth,
    screenHeight: c_int = screenHeight,
    fps: c_int = FPS,
    sleepTime: u64 = sleep_FPS,
    status: windowStatus = .{},
    alloc: std.mem.Allocator = undefined,
    workingThreads: std.ArrayList(std.Thread) = undefined,
    mouse: mouseStack = .{},
    n_ticks: i64 = 1,
    pub fn init(alloc: std.mem.Allocator, width: c_int, height: c_int, fps: c_int) !guiWindow {
        var ret: guiWindow = .{ .screenWidth = width, .screenHeight = height };
        ret.alloc = alloc;
        //ret.components = try std.ArrayList(*Component).initCapacity(alloc, 4);
        ret.setFps(fps);

        ret.workingThreads = try std.ArrayList(std.Thread).initCapacity(ret.alloc, 2);
        return ret;
    }
    fn setFps(p_self: *guiWindow, fps: c_int) void {
        p_self.fps = FPS;
        p_self.sleepTime = sleep_FPS;
        _ = fps;
    }
    pub fn appendComponent(p_self: *guiWindow, p_comp: *Component) !bool {
        _ = p_self.components.append(p_comp);
        switch (p_comp.*) {
            inline else => |*c| {
                const absoluteX = c.coordinate.x + c.size.x;
                const absoluteY = c.coordinate.y + c.size.y;
                p_self.screenWidth += @max(0, absoluteX - p_self.screenWidth);
                p_self.screenHeight += @max(0, absoluteY - p_self.screenHeight);
            },
        }
        return true;
    }
    fn setDebugMode(p_self: *guiWindow, debugMode: bool) void {
        p_self.status.debugMode = debugMode;
    }
    pub fn mainThread(p_self: *guiWindow) void {
        p_self.buildComponents();
        defer _ = p_self.close();
        const _start = std.time.microTimestamp();
        while (p_self.status.guiOpen) {
            std.Thread.sleep(p_self.sleepTime);
            p_self.update_perf(_start);
            p_self.globalTick();
        }
    }
    fn update_perf(p_self: *guiWindow, startime: i64) void {
        const coordAnchor: screenCoord = .{ .x = 5, .y = 5 };
        const sizeAnchor: screenCoord = .{ .x = 200, .y = 100 };
        r.BeginDrawing();
        defer r.EndDrawing();
        const base = p_self.components.getComponentByPosition(coordAnchor);
        var backGroundColor: r.Color = r.WHITE;
        if (base.len != 0) {
            switch (base.items[0].*) {
                inline else => |*c| {
                    backGroundColor = @bitCast(c.backGroundColor);
                },
            }
        }
        r.DrawRectangle(coordAnchor.x, coordAnchor.y, sizeAnchor.x, sizeAnchor.y, backGroundColor);

        const stoptime = std.time.microTimestamp();
        const _time_s: i64 = 1 + @divFloor(stoptime - startime, std.time.us_per_s);
        const fps = @divFloor(p_self.n_ticks, _time_s);
        const time = @divFloor(_time_s * 1000, p_self.n_ticks);
        const msg = std.fmt.allocPrint(p_self.alloc, "{d} fps / {d} ms ", .{ fps, time }) catch {
            return;
        };
        defer p_self.alloc.free(msg);

        msg[msg.len - 1] = 0;
        r.DrawText(@ptrCast(msg), coordAnchor.x, coordAnchor.y, gconfigl.GUI_FPS_FONTSIZE, gconfigl.GUI_FPS_COLOR);
        return;
    }
    pub fn _EventThread(p_self: *guiWindow) void {
        // for mouse and keyboard stuff (probably?)
        while (p_self.status.guiOpen) {
            p_self._acquireMouse();
            std.Thread.sleep(gconfigl.EVENT_TICKRATE_NS);
        }
    }

    fn buildComponents(p_self: *guiWindow) void {
        for (0..p_self.components.len) |i| {
            const comp = p_self.components.items[i];
            switch (comp.*) {
                inline else => |*c| {
                    const status = c.initCallback();
                    if (p_self.status.debugMode and !status) {
                        std.debug.print("[DEBUG] free.guiWindow: component {} failed to free\n", .{c});
                    }
                },
            }
        }
    }
    fn free(p_self: *guiWindow, alloc: std.mem.Allocator) void {
        for (0..p_self.components.len) |i| {
            const comp = p_self.components.items[i];
            switch (comp.*) {
                inline else => |*c| {
                    const status = c.freeCallback(alloc);
                    if (p_self.status.debugMode and !status) {
                        std.debug.print("[DEBUG] free.guiWindow: component {} failed to free\n", .{c});
                    }
                },
            }
        }
    }

    fn _acquireMouse(p_self: *guiWindow) void {
        const isPressed = r.IsMouseButtonPressed(r.MOUSE_LEFT_BUTTON);
        if (isPressed) {
            const frame: mouseInfo = .{ .isPressed = true, .coord = .{ .x = r.GetMouseX(), .y = r.GetMouseY() } };
            p_self.mouse.push(frame);

            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG] _acquireMouse.window: Pushing mouse frame: (x: {d}, y: {d})\n", .{ frame.coord.x, frame.coord.y });
            }
            std.Thread.sleep(gconfigl.EVENT_TICKRATE_NS);
        }
        return;
    }
    fn handleMouse(p_self: *guiWindow) void {
        //std.debug.print("[DEBUG] handleMouse.window: Mouse info: (x: {d}, y: {d}, pressed: {})\n", .{ p_self.coord.x, coord.y, p_self.mouse.isPressed });
        while (!p_self.mouse.isEmpty()) {
            const frame = p_self.mouse.pop();
            var clicked = p_self.components.getComponentByPosition(frame.coord);
            p_self.applyLeftClick(frame, &clicked);
            if (p_self.status.debugMode) {
                std.debug.print("[DEBUG] handleMouse.window: Detected click at location: (x: {d}, y: {d})\n", .{ frame.coord.x, frame.coord.y });
            }
        }
    }
    pub fn applyLeftClick(p_self: *guiWindow, mouseEvent: mouseInfo, p_container: *componentContainer) void {
        for (0..p_container.len) |i| {
            const comp = p_container.items[i];
            var status: bool = false;
            switch (comp.*) {
                inline else => |*c| {
                    status = c.onMouseClick(mouseEvent.coord, e_mouseClicks.LEFTCLICK);
                    if (p_self.status.debugMode and !status) {
                        std.debug.print("[DEBUG] globalTick.guiWindow: component {s} failed to handle click\n", .{c.name});
                    }
                },
            }
        }
    }
    pub fn globalTick(p_self: *guiWindow) void {
        if (r.WindowShouldClose()) {
            const status = p_self.close();
            std.debug.print("[DEBUG] globalTick.window: {} status for close\n", .{status});
            return;
        }
        p_self.handleMouse();
        p_self.n_ticks += 1;

        for (0..p_self.components.len) |i| {
            const comp = p_self.components.items[i];
            var status: bool = false;
            switch (comp.*) {
                inline else => |*c| {
                    status = c.tickCallback();
                    if (p_self.status.debugMode and !status) {
                        std.debug.print("[DEBUG] globalTick.guiWindow: component {s} failed to tick \n", .{c.name});
                    }
                },
            }
        }
        for (0..p_self.components.len) |i| {
            const comp = p_self.components.items[i];
            var status: bool = true;
            switch (comp.*) {
                inline else => |*c| {
                    if (c.needUpdate) {
                        c.needUpdate = false;
                        status = c.onUpdateCallback();
                        if (p_self.status.debugMode) {
                            std.debug.print("[DEBUG] globalTick.guiWindow: component {s} updated status {}\n", .{ c.name, status });
                        }
                    }
                },
            }
        }
    }

    pub fn open(p_self: *guiWindow) bool {
        if (p_self.status.guiOpen) {
            return false;
        }
        _ = std.Thread.spawn(.{}, openMainThread, .{p_self}) catch {
            return false;
        };

        return true;
    }
    pub fn close(p_self: *guiWindow) bool {
        std.debug.print("[DEBUG] close.window: closing window \n", .{});
        if (!p_self.status.guiOpen) {
            return false;
        }
        p_self.status.guiOpen = false;
        r.CloseWindow();
        p_self.free(p_self.alloc);
        for (0..p_self.workingThreads.items.len) |i| {
            p_self.workingThreads.items[i].join();
        }
        return true;
    }
};

fn openEventThread(p_self: *guiWindow) void {
    p_self._EventThread();
}
fn openMainThread(p_self: *guiWindow) void {
    p_self.status.guiOpen = true;
    r.InitWindow(p_self.screenWidth, p_self.screenHeight, "Chess GUI");
    r.SetTargetFPS(p_self.fps);
    p_self.setDebugMode(true);
    const eventThread = std.Thread.spawn(.{}, openEventThread, .{p_self}) catch unreachable;

    p_self.workingThreads.append(p_self.alloc, eventThread) catch unreachable;
    p_self.mainThread();
}

pub fn initChessWindow(alloc: std.mem.Allocator, width: c_int, height: c_int) !guiWindow {
    var ret: guiWindow = try guiWindow.init(alloc, width, height, FPS);

    //componentl.GUI_Y_TILE_SIZE = (screenHeight / (2 * 8));

    const boardComp = Component{ .e_boardComponent = .{ .name = "board", .coordinate = .{ .x = componentl.BOARD_COMPONENT_X_OFFSET, .y = screenHeight - 8 * gconfigl.GUI_Y_TILE_SIZE }, .size = .{ .x = 8 * gconfigl.GUI_X_TILE_SIZE, .y = gconfigl.GUI_Y_TILE_SIZE * 8 } } };
    const _b = try alloc.create(Component);
    _b.* = boardComp;

    _ = try ret.appendComponent(_b);

    const infoComp = Component{ .e_infoComponent = .{ .name = "timer", .coordinate = .{ .x = componentl.INFO_COMPONENT_X_OFFSET, .y = componentl.INFO_COMPONENT_Y_OFFSET }, .size = .{ .x = 8 * gconfigl.GUI_X_TILE_SIZE, .y = 2 * gconfigl.GUI_Y_TILE_SIZE } } };
    const _info = try alloc.create(Component);
    _info.* = infoComp;
    _ = try ret.appendComponent(_info);

    var panelComp = Component{ .e_panelComponent = .{ .name = "panel-1", .coordinate = .{ .x = 0, .y = 0 }, .size = .{ .x = screenWidth / 4, .y = screenHeight } } };
    var _panel = try alloc.create(Component);
    _panel.* = panelComp;
    _ = try ret.appendComponent(_panel);

    panelComp = Component{ .e_panelComponent = .{ .name = "panel-2", .coordinate = .{ .x = screenWidth - screenWidth / 4, .y = 0 }, .size = .{ .x = screenWidth / 4, .y = screenHeight } } };
    _panel = try alloc.create(Component);
    _panel.* = panelComp;
    _ = try ret.appendComponent(_panel);

    return ret;
}
