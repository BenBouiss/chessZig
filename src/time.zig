const std = @import("std");

pub const stopWatch = struct {
    // first implementation will closely resemble the one found in the scheduler file
    startTimeUs: i64 = 0,
    started: bool = false,
    savedTimeUs: i64 = 0,

    pub fn print(self: *const stopWatch) void {
        std.debug.print("Started: {}, startime: {d}, saved time: {d}, started {d} us ago\n", .{ self.started, self.startTimeUs, self.savedTimeUs, self.timeSinceStartUs() });
    }
    pub inline fn startTimeTick(p_self: *stopWatch) void {
        std.debug.assert(!p_self.started);
        p_self.startTimeUs = std.time.microTimestamp();
        p_self.started = true;
    }
    pub inline fn stop(p_self: *stopWatch) void {
        p_self.savedTimeUs = p_self.timeSinceStartUs();
        p_self.started = false;
    }
    pub inline fn timeSinceStartUs(p_self: *const stopWatch) i64 {
        std.debug.assert(p_self.startTimeUs != 0);
        if (p_self.started) {
            return std.time.microTimestamp() - p_self.startTimeUs;
        } else {
            std.debug.assert(p_self.savedTimeUs != 0);
            return p_self.savedTimeUs;
        }
    }
    pub inline fn timeSinceStartMs(p_self: *const stopWatch) i64 {
        return @divFloor(p_self.timeSinceStartUs(), std.time.us_per_ms);
    }
    pub inline fn timeSinceStartSec(p_self: *const stopWatch) i64 {
        return @divFloor(p_self.timeSinceStartUs(), std.time.us_per_s);
    }
    pub inline fn reset(p_self: *stopWatch) void {
        p_self.started = false;
        p_self.startTimeUs = 0;
        p_self.savedTimeUs = 0;
    }
};

pub fn main() !void {
    //
}
