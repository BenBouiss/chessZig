const c = @cImport({
    @cInclude("emmintrin.h");
});

const chessl = @import("../chess.zig");
const squarel = @import("../square.zig");
const moveGenl = @import("../move_generation.zig");

const ssel = @import("sse.zig");

pub inline fn _BitScanForward64(index: *u32, Mask: u64) u8 {
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

pub inline fn _BitScanForwardReverse64(index: *u32, Mask: u64) u8 {
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
// intrinsics for the use of quad bitboard to compute bishop rook queen all dir fill.
//
const __m128i = ssel.__m128i;
pub inline fn nortOne(b: __m128i) __m128i {
    return ssel._mm_slli_epi64(b, 8);
}
pub inline fn soutOne(b: __m128i) __m128i {
    return ssel._mm_srli_epi64(b, 8);
}
pub inline fn eastOne(b: __m128i) __m128i {
    return ssel._mm_add_epi8(b, b);
}
pub fn eastAttacks(occ: __m128i, rooks: __m128i) __m128i {
    const _occ = ssel._mm_or_si128(occ, rooks); //  make rooks member of occupied
    var tmp = ssel._mm_xor_si128(_occ, rooks); // occ - rooks
    tmp = ssel._mm_sub_epi8(tmp, rooks); // occ - 2*rooks
    return ssel._mm_xor_si128(_occ, tmp); // occ ^ (occ - 2*rooks)
}
pub fn dotProduct64(bb: u64, weights: *[]const u8) ssel.int {
    const sbitmask: ssel.__m128i = .{ 0x8040201008040201, 0x8040201008040201 };
    const pW: [*]__m128i = @ptrCast(weights);
    const bm = ssel._mm_load_si128(&sbitmask);
    var x0 = ssel._mm_cvtsi64x_si128(bb); // 0000000000000000:8040201008040201
    // extend bits to bytes
    x0 = ssel._mm_unpacklo_epi8(x0, x0); // 8080404020201010:0808040402020101
    var x2 = ssel._mm_unpackhi_epi16(x0, x0); // 8080808040404040:2020202010101010
    x0 = ssel._mm_unpacklo_epi16(x0, x0); // 0808080804040404:0202020201010101
    var x1 = ssel._mm_unpackhi_epi32(x0, x0); // 0808080808080808:0404040404040404
    x0 = ssel._mm_unpacklo_epi32(x0, x0); // 0202020202020202:0101010101010101
    var x3 = ssel._mm_unpackhi_epi32(x2, x2); // 8080808080808080:4040404040404040
    x2 = ssel._mm_unpacklo_epi32(x2, x2); // 2020202020202020:1010101010101010
    x0 = ssel._mm_and_si128(x0, bm);
    x1 = ssel._mm_and_si128(x1, bm);
    x2 = ssel._mm_and_si128(x2, bm);
    x3 = ssel._mm_and_si128(x3, bm);
    x0 = ssel._mm_cmpeq_epi8(x0, bm);
    x1 = ssel._mm_cmpeq_epi8(x1, bm);
    x2 = ssel._mm_cmpeq_epi8(x2, bm);
    x3 = ssel._mm_cmpeq_epi8(x3, bm);
    // multiply by "and" with -1 or 0
    x0 = ssel._mm_and_si128(x0, pW[0]);
    x1 = ssel._mm_and_si128(x1, pW[1]);
    x2 = ssel._mm_and_si128(x2, pW[2]);
    x3 = ssel._mm_and_si128(x3, pW[3]);
    // add all bytes (with saturation)
    x0 = ssel._mm_adds_epu8(x0, x1);
    x0 = ssel._mm_adds_epu8(x0, x2);
    x0 = ssel._mm_adds_epu8(x0, x3);
    x0 = ssel._mm_sad_epu8(x0, ssel._mm_setzero_si128());
    return ssel._mm_cvtsi128_si32(x0) + ssel._mm_extract_epi16(x0, 4);
}

pub fn main() !void {
    const a: __m128i = .{ chessl.sqToBitboard(.d4), chessl.sqToBitboard(.d4) };
    const occ: __m128i = .{ 0, 0 };
    const b = eastAttacks(occ, a);
    chessl.print_bitboard(@intCast(b[0]));
    chessl.print_bitboard(@intCast(b[1]));

    //chessl.print_bitboard(moveGenl.northOne(chessl.sqToBitboard(.d4)));
}
