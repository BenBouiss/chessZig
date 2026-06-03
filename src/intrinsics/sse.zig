const c = @cImport({
    @cInclude("emmintrin.h");
});

const std = @import("std");

// for now, going to implement the sse instructions found at https://www.chessprogramming.org/SSE2
// with implem at https://www.intel.com/content/www/us/en/docs/intrinsics-guide/index.html#ig_expand=6889,6889,6976,4635,4635,6179,6170&techs=SSE_ALL

pub const __m128i: type = @Vector(2, u64);

// subsets types
const __m8x16i: type = @Vector(8, i16);

const __m16x8i: type = @Vector(16, i8);
const __m16x8u: type = @Vector(16, u8);

const __m8x8i: type = @Vector(8, i8);
const __m8x8u: type = @Vector(8, u8);

const __m4x16i: type = @Vector(4, i16);
const __m2x32i: type = @Vector(2, i32);
const __m1x128i: type = @Vector(1, i128);

pub const int = i32;

// cast to subset
pub inline fn __m128i_cast_16x8i(b: __m128i) __m16x8i {
    return @bitCast(b);
}
pub inline fn __m128i_cast_16x8u(b: __m128i) __m16x8u {
    return @bitCast(b);
}
pub inline fn __m128i_cast_8x16i(b: __m128i) __m8x16i {
    return @bitCast(b);
}
pub inline fn __m128i_cast_1x128i(b: __m128i) __m1x128i {
    return @bitCast(b);
}

// lossy
pub inline fn __m128i_cast_8x8i(b: __m128i, comptime idx: int) __m8x8i {
    std.debug.assert(idx >= 0);
    std.debug.assert(idx < 2);
    return @bitCast(b[idx]);
}

pub inline fn __m128i_cast_4x16i(b: __m128i, comptime idx: int) __m4x16i {
    std.debug.assert(idx >= 0);
    std.debug.assert(idx < 2);
    return @bitCast(b[idx]);
}
pub inline fn __m128i_cast_2x32i(b: __m128i, comptime idx: int) __m2x32i {
    std.debug.assert(idx >= 0);
    std.debug.assert(idx < 2);
    return @bitCast(b[idx]);
}

// subset back to __m128i
pub inline fn __m8x16i_cast_128i(b: __m8x16i) __m128i {
    return @bitCast(b);
}
pub inline fn __m16x8i_cast_128i(b: __m16x8i) __m128i {
    return @bitCast(b);
}
pub inline fn __m16x8u_cast_128i(b: __m16x8u) __m128i {
    return @bitCast(b);
}
pub inline fn __m1x128i_cast_128i(b: __m1x128i) __m128i {
    return @bitCast(b);
}

// slli
pub inline fn _mm_slli_epi64(a: __m128i, comptime imm8: i8) __m128i {
    if (comptime imm8 > 63) {
        return @splat(0);
    }
    return a << @splat(imm8);
}

// srli
pub inline fn _mm_srli_epi64(a: __m128i, comptime imm8: i8) __m128i {
    if (comptime imm8 > 63) {
        return @splat(0);
    }
    return a >> @splat(imm8);
}

// add
pub inline fn _mm_add_epi8(a: __m128i, b: __m128i) __m128i {
    const ret = __m128i_cast_16x8i(a) + __m128i_cast_16x8i(b);
    return __m16x8i_cast_128i(ret);
}
pub inline fn _mm_adds_epu8(a: __m128i, b: __m128i) __m128i {
    const ret = __m128i_cast_16x8u(a) + __m128i_cast_16x8u(b);
    return __m16x8u_cast_128i(ret);
}
// sads

//pub inline fn _mm_sad_epu8(a: __m128i, b: __m128i) __m128i {
//    //
//}

// sub
pub inline fn _mm_sub_epi8(a: __m128i, b: __m128i) __m128i {
    const ret = __m128i_cast_16x8i(a) - __m128i_cast_16x8i(b);
    return __m16x8i_cast_128i(ret);
}
// and

pub inline fn _mm_and_si128(a: __m128i, b: __m128i) __m128i {
    return a & b;
}

// or
pub inline fn _mm_or_si128(a: __m128i, b: __m128i) __m128i {
    return a | b;
}

// xor
pub inline fn _mm_xor_si128(a: __m128i, b: __m128i) __m128i {
    return a ^ b;
}

// loads
pub inline fn _mm_load_si128(a: *const __m128i) __m128i {
    return a.*;
}

// copy
/// Copy 64-bit integer a to the lower element of dst, and zero the upper element.
pub inline fn _mm_cvtsi64x_si128(a: u64) __m128i {
    return @Vector(2, .{ a, 0 });
}

// unpack

// unpack - low
///Unpack and interleave 8-bit integers from the low half of a and b, and store the results in dst.
pub inline fn _mm_unpacklo_epi8(a: __m128i, b: __m128i) __m128i {
    const _a = __m128i_cast_8x8i(a, 0);
    const _b = __m128i_cast_8x8i(b, 0);
    return @bitCast(std.simd.interlace(_a, _b));
}
pub inline fn _mm_unpacklo_epi16(a: __m128i, b: __m128i) __m128i {
    const _a = __m128i_cast_4x16i(a, 0);
    const _b = __m128i_cast_4x16i(b, 0);
    return @bitCast(std.simd.interlace(_a, _b));
}
pub inline fn _mm_unpacklo_epi32(a: __m128i, b: __m128i) __m128i {
    const _a = __m128i_cast_2x32i(a, 0);
    const _b = __m128i_cast_2x32i(b, 0);
    return @bitCast(std.simd.interlace(_a, _b));
}

// unpack - high
pub inline fn _mm_unpackhi_epi16(a: __m128i, b: __m128i) __m128i {
    const _a = __m128i_cast_4x16i(a, 1);
    const _b = __m128i_cast_4x16i(b, 1);
    return @bitCast(std.simd.interlace(_a, _b));
}
pub inline fn _mm_unpackhi_epi32(a: __m128i, b: __m128i) __m128i {
    const _a = __m128i_cast_2x32i(a, 1);
    const _b = __m128i_cast_2x32i(b, 1);
    return @bitCast(std.simd.interlace(_a, _b));
}

// cmp eq

pub inline fn _mm_cmpeq_epi8(a: __m128i, b: __m128i) __m128i {
    const _a = __m128i_cast_16x8i(a);
    const _b = __m128i_cast_16x8i(b);
    return __m16x8i_cast_128i(@select(__m16x8i, _a == _b, @as(__m16x8i, @splat(0xFF)), @as(__m16x8i, @splat(0))));
}

// cvt
/// Copy the lower 32-bit integer in a to dst.
pub inline fn _mm_cvtsi128_si32(a: __m128i) int {
    return @intCast(a[0] & 0xFFFFFFFF);
}

// extract
pub inline fn _mm_extract_epi16(a: __m128i, comptime b: int) int {
    std.debug.assert(b < 8);
    return __m1x128i_cast_128i((__m128i_cast_1x128i(a) >> @splat(b << 4)) & @as(__m1x128i, @splat(0xFFFF)));
}

// setzero
pub inline fn _mm_setzero_si128() __m128i {
    return @splat(0);
}
