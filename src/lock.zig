const std = @import("std");
const timel = @import("time.zig");
const mainl = @import("main.zig");

pub const lock = struct {
    //_lock: bool = false,
    //_lock: std.atomic.Mutex = .unlocked,
    _lock: std.Io.Mutex = .{ .state = .init(.unlocked) },
    pub inline fn releaseLock(p_self: *lock) void {
        p_self._lock.unlock(mainl.getGlobalIo());
    }
    pub inline fn acquireLock(p_self: *lock) void {
        p_self._lock.lockUncancelable(mainl.getGlobalIo());
    }
};

pub const semaphore = struct {
    lim: usize = 0,
    cur: usize = 0,
    l: lock = .{},
    pub fn init(limit: usize) semaphore {
        std.debug.assert(limit != 0);
        return .{ .lim = limit };
    }
    pub fn acquireSlot(p_self: *semaphore) void {
        while (p_self.cur >= p_self.lim) {}
        p_self.l.acquireLock();
        p_self.cur += 1;
        p_self.l.releaseLock();
    }
    pub fn releaseSlot(p_self: *semaphore) void {
        p_self.l.acquireLock();
        p_self.cur -= 1;
        p_self.l.releaseLock();
    }
};
