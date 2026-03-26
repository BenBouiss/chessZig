const std = @import("std");

pub const stopWatch = struct {
    // first implementation will closely resemble the one found in the scheduler file
    startTimeUs: i64 = 0,
    started: bool = false,

    pub inline fn startTimeTick(p_self: *stopWatch) void {
        std.debug.assert(!p_self.started);
        p_self.startTimeUs = std.time.microTimestamp();
        p_self.started = true;
    }
    pub inline fn stop(p_self: *stopWatch) void {
        std.debug.assert(p_self.started);
        p_self.started = false;
    }
    pub inline fn timeSinceStartUs(p_self: *const stopWatch) i64 {
        std.debug.assert(p_self.started);
        return std.time.microTimestamp() - p_self.startTimeUs;
    }
    pub inline fn timeSinceStartMs(p_self: *const stopWatch) i64 {
        std.debug.assert(p_self.started);
        return @divFloor(p_self.timeSinceStartUs(), std.time.us_per_ms);
    }
    pub inline fn timeSinceStartSec(p_self: *const stopWatch) i64 {
        return @divFloor(p_self.timeSinceStartUs(), std.time.us_per_s);
    }
    pub inline fn reset(p_self: *stopWatch) void {
        p_self.started = false;
        p_self.startTimeUs = 0;
    }
};

pub fn main() !void {
    //
}
