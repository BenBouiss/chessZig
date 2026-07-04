import sys, os, struct
import json


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


layerNames = [b"l0w\n", b"l0b\n", b"l1w\n", b"l1b\n"]


def readNNUEbin(path: str):
    assert os.path.exists(path)
    n = 0
    buffers = []
    with open(path, "rb") as f:
        neg = False
        while b := f.read(2):
            # if b in layerNames:
            #    continue
            n += 1
            # nbr = struct.unpack("i", b)[0]
            nbr = int.from_bytes(b, byteorder="little")
            if nbr < 0:
                neg = True
            print(f"{nbr}, ", end="")
        print(f"\n numbers found {n} {neg}")

    # print(buffers)


# open json format result file extract the 6 piece 2 phase values into [("name", "val")]
order = [
    "pawnPSQT_MG",
    "pawnPSQT_EG",
    "knightPSQT_MG",
    "knightPSQT_EG",
    "bishopPSQT_MG",
    "bishopPSQT_EG",
    "rookPSQT_MG",
    "rookPSQT_EG",
    "queenPSQT_MG",
    "queenPSQT_EG",
    "kingPSQT_MG",
    "kingPSQT_EG",
]


def print_board(name: str, l: list[int]):
    print(f"const {name} = [_]scoreType {{", end=" ")
    for sq in range(8):
        row = l[sq * 8 : (sq + 1) * 8]
        [print(f"{x}, ", end="") for x in row]
        print("")
    print("};")


def openWeatherFactory(path: str):
    assert os.path.exists(path), f"path {path} does not exist"
    with open(path, "rb") as f:
        d = json.load(f)

    tot = len(d["uci_params"])
    offsetName = 0
    # for x, name in enumerate(order):
    squares = [0] * 64
    for x in range(tot):
        var: str = d["uci_params"][x]["name"]
        nbr = int(d["uci_params"][x]["value"])
        if "_" in var and var.split("_")[-1].isnumeric():
            # print(var)
            n = int(var.split("_")[-1])
            squares[n] = nbr
            if n == 63:
                print_board(order[offsetName], squares)
                offsetName += 1
                squares = [0] * 64
        else:
            print(f"pub var {var}: scoreType = {nbr};")


if __name__ == "__main__":
    b = sys.argv[1]
    print(f"Found argument {b} with type {type(b)}")
    # print_bitboard(b)
    # readNNUEbin(b)
    openWeatherFactory(b)
