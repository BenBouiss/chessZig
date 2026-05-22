from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from collections.abc import Generator

import numpy.typing as npt
import constants as cst


@dataclass
class weight:
    idx: int = 0
    val: None | list[float] = None

    def copy(self) -> weight:
        assert self.val is not None
        return weight(idx=self.idx, val=list(self.val))


class texelWeights:
    def __init__(self):
        self.elem: list[weight] = list()

    def copy(self) -> texelWeights:
        ret: texelWeights = texelWeights()
        for e in self.elem:
            ret.elem.append(e.copy())
        return ret

    def len(self) -> int:
        ret: int = 0
        for e in self.elem:
            assert e.val is not None
            ret += len(e.val)
        return ret

    def getIndexes(self) -> list[int]:
        assert len(self.elem) > 0
        ret = []
        for e in self.elem:
            ret.append(e.idx)
        return ret

    def getArray(
        self, fullLength: bool = False, fillValue: float = cst.INVALID_VALUE
    ) -> list[float]:
        assert len(self.elem) > 0
        assert self.elem[-1].val is not None
        if fullLength:
            ret = [fillValue] * (cst.total_idx)
        else:
            ret = [fillValue] * self.len()

        self.sort()
        self.assertBounds()
        offset = 0
        for e in self.elem:
            assert e.val is not None
            if fullLength:
                ret[e.idx : e.idx + len(e.val)] = e.val
            else:
                ret[offset : offset + len(e.val)] = e.val
                offset += len(e.val)
        return ret

    def checkBounds(self) -> bool:
        for i, e in enumerate(self.elem):
            if e.val is None:
                return False
            if i == (len(self.elem) - 1):
                break
            if not ((e.idx + len(e.val)) <= self.elem[i + 1].idx):
                return False
        # non overlaping weights
        return True

    def assertBounds(self) -> None:
        assert self.checkBounds(), "Checkbound failed: overlaping weights were found"

    def sort(self) -> None:
        self.elem.sort(key=lambda x: x.idx)

    def pushArray(self, val: list[float], startingIdx: int) -> None:
        self.elem.append(weight(idx=startingIdx, val=list(val)))
        self.sort()
        self.assertBounds()

    def multiply(self, val: float) -> texelWeights:
        for l in self.elem:
            assert l.val is not None
            for x in range(len(l.val)):
                l.val[x] *= val
        return self

    def divide(self, val: float) -> texelWeights:
        for l in self.elem:
            assert l.val is not None
            for x in range(len(l.val)):
                l.val[x] /= val
        return self

    def __repr__(self) -> str:
        ret = ""
        for e in self.elem:
            assert e.val is not None
            ret += f" {e.val}"
        return ret

    """
    quick exemple
        >>> class t:
        ...     def __init__(self, vals):
        ...         self.vals = vals
        ...     def t(self):
        ...         for e in self.vals:
        ...             yield e
        ...
        >>> A = t([1,2,3])
        >>> B = t([2,4,8])
        >>> for (x1, x2) in zip(A.t(), B.t()):
        ...     print(x1, x2)
        ...
        1 2
        2 4
        3 8
        >>>

    """

    def iterValid(self) -> Generator[tuple[int, float]]:
        # arr = self.getArray(fullLength=True)
        # for i in range(len(arr)):
        #    if (arr[i] != INVALID_VALUE):
        #        yield (i, arr[i])
        # raise StopIteration
        for e in self.elem:
            assert e is not None
            assert e.val is not None
            yield (e.idx, e.val[0])


def texelWeightsFromFlatLists(
    arr: list[float], indexes: list[int] | None = None
) -> texelWeights:
    if indexes is None:
        indexes = list(range(len(arr)))
    w = np.array(arr).reshape(-1, 1).astype(float).tolist()
    return texelWeightsFromLists(w, indexes)


def texelWeightsFromLists(
    weights: list[list[float]], indexes: list[int]
) -> texelWeights:
    ret: texelWeights = texelWeights()
    assert len(weights) == len(indexes), (
        f"Length mismatch error: length of weights ({len(weights)}), length of indexes ({len(indexes)})"
    )
    for val, idx in zip(weights, indexes):
        ret.pushArray(val=val, startingIdx=idx)
    return ret


def texelWeightsFromFlatWeights(elems: list[list[int | list[float]]]) -> texelWeights:
    ret = texelWeights()
    for e in elems:
        assert type(e[0]) is int
        assert type(e[1]) is list
        ret.pushArray(val=e[1], startingIdx=e[0])
    return ret


def texelWeightToFileStr(w: texelWeights, phase: str) -> str:
    ret = ""
    arr = w.getArray(fullLength=True)
    for idx, val in w.iterValid():
        if idx < cst.PSQT_Pawn_idx:
            ret += f"{cst.strWeightNames[idx]}{phase} = {val};\n"
        elif idx == cst.PSQT_Pawn_idx:
            ret += f"pawnPSQT{phase} = {floatArrToString(arr[cst.PSQT_Pawn_idx : cst.PSQT_Bishop_idx])};\n"
        elif idx == cst.PSQT_Bishop_idx:
            ret += f"bishopPSQT{phase} = {floatArrToString(arr[cst.PSQT_Bishop_idx : cst.PSQT_Knight_idx])};\n"
        elif idx == cst.PSQT_Knight_idx:
            ret += f"knightPSQT{phase} = {floatArrToString(arr[cst.PSQT_Knight_idx : cst.PSQT_Rook_idx])};\n"
        elif idx == cst.PSQT_Rook_idx:
            ret += f"rookPSQT{phase} = {floatArrToString(arr[cst.PSQT_Rook_idx : cst.PSQT_Queen_idx])};\n"
        elif idx == cst.PSQT_Queen_idx:
            ret += f"queenPSQT{phase} = {floatArrToString(arr[cst.PSQT_Queen_idx : cst.PSQT_King_idx])};\n"
        elif idx == cst.PSQT_King_idx:
            ret += f"kingPSQT{phase} = {floatArrToString(arr[cst.PSQT_King_idx : cst.PSQT_King_idx + 64])};\n"
        else:
            print(f"[DEBUG] texelWeightToFileStr: unknow value index: {idx}")
            assert False

    return ret


def floatArrToString(arr) -> str:
    tmp = ",".join([f"{x}" for x in arr])
    return f"[{tmp}]"
