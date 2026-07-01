const c = @cImport({
    @cInclude("emmintrin.h");
});

const std = @import("std");

// for now, going to implement the sse instructions found at https://www.chessprogramming.org/SSE2
// with implem at https://www.intel.com/content/www/us/en/docs/intrinsics-guide/index.html#ig_expand=6889,6889,6976,4635,4635,6179,6170&techs=SSE_ALL

pub const __m128i: type = @Vector(2, u64);
pub const __m256i: type = @Vector(4, u64);
pub const __m512i: type = @Vector(8, u64);

// subsets types
// 512
const __m32x16i: type = @Vector(32, i16);
const __m32x32i: type = @Vector(32, i32);

// 256
const __m16x16i: type = @Vector(16, i16);
const __m8x32i: type = @Vector(8, i32);
const __m16x32i: type = @Vector(16, i32);
const __m32x8i: type = @Vector(32, i8);
const __m32x8u: type = @Vector(32, u8);
const __m2x128i: type = @Vector(2, i128);

// 128
const __m4x32i: type = @Vector(4, i32);
const __m8x16i: type = @Vector(8, i16);
const __m16x8i: type = @Vector(16, i8);
const __m16x8u: type = @Vector(16, u8);
const __m1x128i: type = @Vector(1, i128);

// 64
const __m8x8i: type = @Vector(8, i8);
const __m8x8u: type = @Vector(8, u8);
const __m4x16i: type = @Vector(4, i16);
const __m2x32i: type = @Vector(2, i32);

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

pub inline fn __m256i_cast_32x8i(b: __m256i) __m32x8i {
    return @bitCast(b);
}
pub inline fn __m256i_cast_32x8u(b: __m256i) __m32x8u {
    return @bitCast(b);
}
pub inline fn __m256i_cast_16x16i(b: __m256i) __m16x16i {
    return @bitCast(b);
}
pub inline fn __m256i_cast_8x32i(b: __m256i) __m8x32i {
    return @bitCast(b);
}

pub inline fn __m512i_cast_32x16i(b: __m512i) __m32x16i {
    return @bitCast(b);
}
pub inline fn __m512i_cast_16x32i(b: __m512i) __m16x32i {
    return @bitCast(b);
}

// any

inline fn intCast_8xi32(a: anytype) __m8x32i {
    return @intCast(a);
}

inline fn intCast_16xi32(a: anytype) __m16x32i {
    return @intCast(a);
}
inline fn intCast_32xi32(a: anytype) __m32x32i {
    return @intCast(a);
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

// subset back to __mX
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

pub inline fn __m16x16i_cast_256i(b: __m16x16i) __m256i {
    return @bitCast(b);
}
pub inline fn __m32x16i_cast_512i(b: __m32x16i) __m512i {
    return @bitCast(b);
}

pub inline fn __m8x32i_cast_256i(b: __m8x32i) __m256i {
    return @bitCast(b);
}
pub inline fn __m32x8i_cast_256i(b: __m16x8i) __m256i {
    return @bitCast(b);
}
pub inline fn __m32x8u_cast_256i(b: __m16x8u) __m256i {
    return @bitCast(b);
}
pub inline fn __m2x128i_cast_256i(b: __m2x128i) __m256i {
    return @bitCast(b);
}

pub inline fn __m16x32i_cast_512i(b: __m16x32i) __m512i {
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

pub inline fn _mm256_adds_epi32(a: __m256i, b: __m256i) __m256i {
    const ret = __m256i_cast_8x32i(a) + __m256i_cast_8x32i(b);
    return __m8x32i_cast_256i(ret);
}
// add
pub inline fn _mm256_add_epi32(a: __m256i, b: __m256i) __m256i {
    return __m8x32i_cast_256i(__m256i_cast_8x32i(a) + __m256i_cast_8x32i(b));
}
pub inline fn _mm512_add_epi32(a: __m512i, b: __m512i) __m512i {
    return __m16x32i_cast_512i(__m512i_cast_16x32i(a) + __m512i_cast_16x32i(b));
}
// hadd
//    pub fn vec_int32_hadd(v: __m256i) i32 {
//  auto sum_into_4 = _mm256_hadd_epi32(vec, vec);
//  auto sum_into_2 = _mm256_hadd_epi32(sum_into_4, sum_into_4);
//
//  auto lane_1 = _mm256_castsi256_si128(sum_into_2);
//  auto lane_2 = _mm256_extractf128_si256(sum_into_2, 1);
//  auto result = _mm_add_epi32(lane_1, lane_2);
//  auto rel = _mm_extract_epi32(result, 0);
//}
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

pub inline fn _mm256_load_si256(addr: *align(32) const __m256i) __m256i {
    return addr.*;
}
pub inline fn _mm512_load_si512(addr: *align(32) const __m512i) __m512i {
    return addr.*;
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
pub inline fn _mm_setzero_si256() __m256i {
    return @splat(0);
}
pub inline fn _mm_setzero_si512() __m512i {
    return @splat(0);
}

// set1
pub inline fn _mm256_set1_epi16(a: i16) __m256i {
    const ret: __m16x16i = @splat(a);
    return __m16x16i_cast_256i(ret);
}
pub inline fn _mm512_set1_epi16(a: i16) __m512i {
    const ret: __m32x16i = @splat(a);
    return __m32x16i_cast_512i(ret);
}

// min
pub inline fn _mm256_min_epi16(a: __m256i, b: __m256i) __m256i {
    return __m16x16i_cast_256i(@min(__m256i_cast_16x16i(a), __m256i_cast_16x16i(b)));
}

pub inline fn _mm512_min_epi16(a: __m512i, b: __m512i) __m512i {
    return __m32x16i_cast_512i(@min(__m512i_cast_32x16i(a), __m512i_cast_32x16i(b)));
}

// max
pub inline fn _mm256_max_epi16(a: __m256i, b: __m256i) __m256i {
    return __m16x16i_cast_256i(@max(__m256i_cast_16x16i(a), __m256i_cast_16x16i(b)));
}

pub inline fn _mm512_max_epi16(a: __m512i, b: __m512i) __m512i {
    return __m32x16i_cast_512i(@max(__m512i_cast_32x16i(a), __m512i_cast_32x16i(b)));
}

// mullo

pub inline fn _mm256_mullo_epi16(a: __m256i, b: __m256i) __m256i {
    return __m16x16i_cast_256i(__m256i_cast_16x16i(a) *% __m256i_cast_16x16i(b));
}

pub inline fn _mm512_mullo_epi16(a: __m512i, b: __m512i) __m512i {
    return __m32x16i_cast_512i(__m512i_cast_32x16i(a) *% __m512i_cast_32x16i(b));
}

// madd
pub inline fn _mm256_madd_epi16(a: __m256i, b: __m256i) __m256i {
    const r = intCast_16xi32(__m256i_cast_16x16i(a)) *% intCast_16xi32(__m256i_cast_16x16i(b));

    const even = @shuffle(i32, r, undefined, [_]i32{ 0, 2, 4, 6, 8, 10, 12, 14 });
    const second = @shuffle(i32, r, undefined, [_]i32{ 1, 3, 5, 7, 9, 11, 13, 15 });
    return @bitCast(even +% second);
}

pub inline fn _mm512_madd_epi16(a: __m512i, b: __m512i) __m512i {
    const r = intCast_32xi32(__m512i_cast_32x16i(a)) *% intCast_32xi32(__m512i_cast_32x16i(b));

    const even = @shuffle(i32, r, undefined, [_]i32{ 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30 });
    const second = @shuffle(i32, r, undefined, [_]i32{ 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31 });
    return @bitCast(even +% second);
}
