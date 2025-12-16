const guil = @import("gui/gui.zig");
const mainl = @import("main.zig");

pub fn main() void {
    mainl.initAll();
    guil.main();
}
