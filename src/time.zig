const std = @import("std");
const mainl = @import("main.zig");

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
        p_self.startTimeUs = std.Io.Timestamp.now(mainl.getGlobalIo(), .real).toMicroseconds();
        p_self.started = true;
    }
    pub inline fn stop(p_self: *stopWatch) void {
        p_self.savedTimeUs = p_self.timeSinceStartUs();
        p_self.started = false;
    }
    pub inline fn timeSinceStartUs(p_self: *const stopWatch) i64 {
        std.debug.assert(p_self.startTimeUs != 0);
        if (p_self.started) {
            return std.Io.Timestamp.now(mainl.getGlobalIo(), .real).toMicroseconds() - p_self.startTimeUs;
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
// implement to implement a sort of ping every x seconds, ms...
// call .tick returns bool
pub const timer = struct {
    sw: stopWatch = .{},
    frequencyUs: i64 = std.time.us_per_s,
    pub fn init(frequencyUs: i64) timer {
        var ret: timer = .{ .frequencyUs = frequencyUs };
        ret.sw.startTimeTick();
        return ret;
    }
    pub fn tick(self: *timer) bool {
        if (self.sw.timeSinceStartUs() > self.frequencyUs) {
            self.sw.reset();
            self.sw.startTimeTick();
            return true;
        }
        return false;
    }
};

pub fn main() !void {
    //
}
