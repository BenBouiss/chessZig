import sys


notAFile = 0xFEFEFEFEFEFEFEFE
notABFile = 0xFCFCFCFCFCFCFCFC
notGHFile = 0x3F3F3F3F3F3F3F3F
notHFile = 0x7F7F7F7F7F7F7F7F


def print_bitboard(b: str | int):
    _b = b
    if type(b) is str:
        _b = int(b, 16)
    row = []
    bit_mat = []
    for i in range(64):
        if not i % 8 and i:
            bit_mat.append(row.copy())
            row = []
        if _b & 1:
            row.append(1)
        else:
            row.append(0)
        _b = _b >> 1

    bit_mat.append(row.copy())
    for e in bit_mat[::-1]:
        print(e)


def knight_move(b):
    l1 = (b >> 1) & notHFile
    l2 = (b >> 2) & notGHFile
    r1 = (b << 1) & notAFile
    r2 = (b << 2) & notABFile
    h1 = l1 | r1
    h2 = l2 | r2
    return (h1 << 16) | (h1 >> 16) | (h2 << 8) | (h2 >> 8)


def soutOccl(gen, pro):
    gen |= pro & (gen >> 8)
    pro &= pro >> 8
    gen |= pro & (gen >> 16)
    pro &= pro >> 16
    gen |= pro & (gen >> 32)
    return gen


def southOne(bb):
    return bb | (bb >> 8)


def NorthFill(gen):
    gen |= gen << 8
    gen |= gen << 16
    gen |= gen << 32
    return gen


def convertOldHeuristToNew(
    old: list[int], oldPieceScore: float, newPieceScore: float
) -> None:
    assert oldPieceScore != 0
    assert newPieceScore != 0
    new: list = []
    for x in old:
        new.append(x * (newPieceScore / oldPieceScore))
    print(f"{new}")


if __name__ == "__main__":
    # b = sys.argv[1]
    # print(f"Found argument {b} with type {type(b)}")
    # print_bitboard(b)
    # gen = 0x4400000000
    # pro = 0x444444
    # pro = 0x4400FFFF
    # print(f"Gen bitboard: ")
    # print_bitboard(gen)

    # print(f"Pro bitboard: ")
    # print_bitboard(pro)

    # print(f"North fill bitboard: ")
    # print_bitboard(NorthFill(gen))

    # print(f"South occl bitboard: ")
    # print_bitboard(soutOccl(gen, ~pro))

    # print(f"South att bitboard: ")
    # print_bitboard(southOne(soutOccl(gen, ~pro)))
    pawnArr = [
            0,   0,  0,  0,   0,   0,   0,  0,
    -31, 8,  -7, -37, -36, -14, 3,  -31,
    -22, 9,  5,  -11, -10, -2,  3,  -19,
    -26, 3,  10, 9,   6,   1,   0,  -23,
    -17, 16, -2, 15,  14,  0,   15, -13,
    7,   29, 21, 44,  40,  31,  44, 7,
    78,  83, 86, 73,  102, 82,  85, 90,
    0,   0,  0,  0,   0,   0,   0,  0    ]
    convertOldHeuristToNew(pawnArr, 100, 1)


    bishopArr = [ 
    -7,  2,   -15, -12, -14, -15,  -10, -10,
    19,  20,  11,  6,   7,   6,    20,  16,
    14,  25,  24,  15,  8,   25,   20,  15,
    13,  10,  17,  23,  17,  16,   0,   7,
    25,  17,  20,  34,  26,  25,   15,  10,
    -9,  39,  -32, 41,  52,  -10,  28,  -14,
    -11, 20,  35,  -42, -39, 31,   2,   -22,
    -59, -78, -82, -76, -23, -107, -37, -50
            ]
    convertOldHeuristToNew(bishopArr, 400, 3)


    knightArr = [
    -74, -23, -26, -24, -19, -35, -22, -69,
    -23, -15, 2,   0,   2,   0,   -23, -20,
    -18, 10,  13,  22,  18,  15,  11,  -14,
    -1,  5,   31,  21,  22,  35,  2,   0,
    24,  24,  45,  37,  33,  41,  25,  17,
    10,  67,  1,   74,  73,  27,  62,  -2,
    -3,  -6,  100, -36, 4,   62,  -4,  -14,
    -66, -53, -75, -75, -10, -55, -58, -70
      ]


    convertOldHeuristToNew(knightArr, 400, 3)


    rookArr = [
    -30, -24, -18, 5,   -2,  -18, -31, -32,
    -53, -38, -31, -26, -29, -43, -44, -53,
    -42, -28, -42, -25, -25, -35, -26, -46,
    -28, -35, -16, -21, -13, -29, -46, -30,
    0,   5,   16,  13,  18,  -4,  -9,  -6,
    19,  35,  28,  33,  45,  27,  25,  15,
    55,  29,  56,  67,  55,  62,  34,  60,
    35,  29,  33,  4,   37,  33,  56,  50
    ] 

    convertOldHeuristToNew(rookArr, 600, 5)


    queenArr = [
    -39, -30, -31, -13,  -31, -36, -34, -42,
    -36, -18, 0,   -19,  -15, -15, -21, -38,
    -30, -6,  -13, -11,  -16, -11, -16, -27,
    -14, -15, -2,  -5,   -1,  -10, -20, -22,
    1,   -16, 22,  17,   25,  20,  -13, -6,
    -2,  43,  32,  60,   72,  63,  43,  2,
    14,  32,  60,  -10,  20,  76,  57,  24,
    6,   1,   -8,  -104, 69,  24,  88,  26,
    ] 

    convertOldHeuristToNew(queenArr, 1200, 9)


    kingArr = [
    17,  30,  -3,  -14, 6,   -1,  40,  18,
    -4,  3,   -14, -50, -57, -18, 13,  4,
    -47, -42, -43, -79, -64, -32, -29, -32,
    -55, -43, -52, -28, -51, -47, -8,  -50,
    -55, 50,  11,  -4,  -19, 13,  0,   -49,
    -62, 12,  -57, 44,  -67, 28,  37,  -31,
    -32, 10,  55,  56,  56,  55,  10,  3,
    4,   54,  47,  -99, -99, 60,  83,  -62,
    ] 

    convertOldHeuristToNew(kingArr, 100, 1)

