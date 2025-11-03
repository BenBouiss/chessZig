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


if __name__ == "__main__":
    b = sys.argv[1]
    print(f"Found argument {b} with type {type(b)}")
    print_bitboard(b)
