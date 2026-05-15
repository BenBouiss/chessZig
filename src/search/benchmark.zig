const std = @import("std");

const enginel = @import("../engine.zig");
const movel = @import("../move.zig");
const chessl = @import("../chess.zig");
const moveGenl = @import("../move_generation.zig");
const alphaBetal = @import("alphaBeta.zig");
const schedulerl = @import("scheduler.zig");
const threadingl = @import("threading.zig");
const utilsl = @import("../utils.zig");
const configl = @import("../config.zig");
const timel = @import("../time.zig");

const engine = enginel.engine;

//https://github.com/maksimKorzh/chess_programming/
pub const benchmarkEntries = [_][]const u8{
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 ",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1 ",
    "rnbqkb1r/pp1p1pPp/8/2p1pP2/1P1P4/3P3P/P1P1P3/RNBQKBNR w KQkq e6 0 1",
    "r2q1rk1/ppp2ppp/2n1bn2/2b1p3/3pP3/3P1NPP/PPP1NPB1/R1BQ1RK1 b - - 0 9 ",
};

pub fn dispatchUciBenchmark(p_engine: *engine) bool {
    // executes the benchmark steps

    const dispatchThread = std.Thread.spawn(.{}, dispatchUciBenchmarkThreads, .{p_engine}) catch {
        return false;
    };
    p_engine.workingThreads.append(p_engine.alloc, dispatchThread) catch {
        return false;
    };
    //p_engine.searcher.searchingThread.appendThread(dispatchThread);

    return true;
}
pub fn dispatchUciBenchmarkThreads(p_engine: *engine) void {
    defer p_engine.status.benchmarking = false;
    //
    var results: std.ArrayList(schedulerl.searchReport) = std.ArrayList(schedulerl.searchReport).initCapacity(p_engine.alloc, 4) catch {
        //
        std.debug.print("[ERROR] dispatchUciBenchmarkThreads: Cant init array of results\n", .{});
        return;
    };
    defer results.deinit(p_engine.alloc);
    const benchmarkDepth: u16 = 8;

    var sched = &p_engine.searcher.schedul;
    sched.setEngine(p_engine);
    if (!sched._threadPool.running) {
        sched._threadPool.addThread(1) catch {
            std.debug.print("[ERROR] dispatchUciBenchmarkThreads: Cant init threadpool and none found\n", .{});
        };
    }
    std.debug.print("============ Benchmark evaluation ============\n", .{});
    for (0..benchmarkEntries.len) |i| {
        p_engine.refreshInternals();
        p_engine.searcher.searching = true;
        sched.timeM.setRemainingTimeMs(std.math.maxInt(i64));
        sched.features.fixedDepth = true;
        sched.features.reportProgress = true;

        const fen = benchmarkEntries[i];
        p_engine.setFen(fen);
        const res = sched.entryPointSearch(benchmarkDepth);
        results.append(p_engine.alloc, res) catch unreachable;
        p_engine.searcher.searching = false;
    }
    p_engine.searcher.searching = false;
    printResults(&benchmarkEntries, &results);
    std.debug.print("============ Benchmark perft ============\nComing soon\n", .{});
}
pub fn printResults(fens: []const []const u8, reports: *const std.ArrayList(schedulerl.searchReport)) void {
    for (0..fens.len) |i| {
        const curr: schedulerl.searchReport = reports.items[i];
        const _time: u64 = @intCast(curr.timeTakenMs);
        const nps = 1000 * @divFloor(curr.searchStat.n_nodeExplored, _time + 1);
        const cuttoffF: f64 = 100 * @as(f64, @floatFromInt(curr.searchStat.n_cutoffs)) / @as(f64, @floatFromInt(curr.searchStat.n_nodeExplored));
        if (curr.searchStat.n_hashRetrieve != 0) {
            std.debug.print("{s} nps: {d} nodes: {d} cutoff {d} cutoff {d:4.1}% move {s} cp {d} retrieved: {d}\n", .{ fens[i], nps, curr.searchStat.n_nodeExplored, curr.searchStat.n_cutoffs, cuttoffF, curr.move.getStr(), curr.score, curr.searchStat.n_hashRetrieve });
        } else {
            std.debug.print("{s} nps: {d} nodes: {d} cutoff {d} cutoff {d:4.1}% move {s} cp {d} \n", .{ fens[i], nps, curr.searchStat.n_nodeExplored, curr.searchStat.n_cutoffs, cuttoffF, curr.move.getStr(), curr.score });
        }
    }
}
