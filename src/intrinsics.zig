pub inline fn _BitScanForward64(index: *u32, Mask: u64) i8 {
    var Ret: u64 = undefined;
    asm volatile (
        \\bsfq %[Mask], %[Ret]
        : [Ret] "=r" (Ret),
        : [Mask] "mr" (Mask),
    );
    index.* = @intCast(Ret);
    if (Mask == 0) {
        return 0;
    }
    return 1;
}

pub inline fn _BitScanForwardReverse64(index: *u32, Mask: u64) i8 {
    var Ret: u64 = undefined;
    asm volatile ("bsrq %[Mask], %[Ret]"
        : [Ret] "=r" (Ret),
        : [Mask] "mr" (Mask),
    );
    index.* = @intCast(Ret);
    if (Mask == 0) {
        return 0;
    }
    return 1;
}

//https://www.chessprogramming.org/AVX2#Dumb7Fill
// intrinsics for the use of quad bitboard to computer bishop rook queen all dir fill.
