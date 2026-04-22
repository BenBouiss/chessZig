const std = @import("std");
const timel = @import("time.zig");

pub const lock = struct {
    _lock: bool = false,
    //_lock: std.atomic.Mutex = .unlocked,
    pub fn releaseLock(p_self: *lock) void {
        //p_self._lock.unlock();
        p_self._lock = false;
    }
    pub fn acquireLock(p_self: *lock) void {
        //std.debug.assert(p_self._lock.tryLock());
        //std.debug.print("[DEBUG] lock.aquireLock: {}\n", .{ret});
        var sw: timel.stopWatch = .{};
        sw.startTimeTick();
        const timeout = 5;

        while (p_self._lock) {
            if (sw.timeSinceStartSec() > timeout) {
                sw.reset();
                sw.startTimeTick();
                std.debug.print("[INACTIVITY] lock.acquireLock : stuck for the last {d} seconds\n", .{timeout});
            }
        }
        p_self._lock = true;
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
