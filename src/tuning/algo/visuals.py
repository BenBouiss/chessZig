import matplotlib.pyplot as plt
import matplotlib

# matplotlib.use("TkAgg")
from dataclasses import dataclass
import numpy as np
import random

MAX_PLY = 255


def depthToMilliDepth(md: int) -> int:
    return md << 10


def milliDepthToDepth(md: int) -> int:
    return md >> 10


def lmrFDepth(md: int) -> int:
    return int(md / 2)


@dataclass
class heuristics:
    lmr_expectedCutOff: int = 400
    lmr_notImproving: int = 300
    lmr_hashMoveCapture: int = 100
    lmr_baseDeficit: int = 1024
    lmr_badCapture: int = 80
    lmr_oldMulti: int = 50
    lmr_givesCheck: int = -600
    lmr_killerMove: int = -50
    lmr_inPvNode: int = -200
    lmr_isPromotion: int = -50
    lmr_threatening: int = -100


@dataclass
class modifiers:
    expectCutOff: bool = False
    improving: bool = False
    hashMoveCapture: bool = False
    badCapture: bool = False
    # isChecked: bool = False
    givesCheck: bool = False
    killerMove: bool = False
    pvNode: bool = False
    promotion: bool = False
    threatening: bool = False


def randomModifier() -> modifiers:
    attr = {}
    for x in modifiers.__dataclass_fields__:
        attr[x] = random.randint(0, 1) == 0
    return modifiers(**attr)


def sampleModifier(n: int, seed: int) -> list[modifiers]:
    random.seed(seed)
    ret = []
    for _ in range(n):
        ret.append(randomModifier())
    return ret


def computeDepth(values: heuristics, move: modifiers, depth: int) -> int:
    s: int = values.lmr_baseDeficit
    if move.pvNode:
        s += values.lmr_inPvNode
    if not move.improving:
        s += values.lmr_notImproving
    if move.hashMoveCapture:
        s += values.lmr_hashMoveCapture
    if move.expectCutOff:
        s += values.lmr_expectedCutOff
    if move.givesCheck:
        s += values.lmr_givesCheck
    if move.promotion:
        s += values.lmr_isPromotion
    if move.killerMove:
        s += values.lmr_killerMove
    if move.badCapture:
        s += values.lmr_badCapture
    if move.threatening:
        s += values.lmr_threatening
    fDepth = lmrFDepth(depthToMilliDepth(depth))
    ret = depth - 1 - min((max(s, 0) * fDepth) >> 20, depth - 1)
    return ret


def extrapolate(values: heuristics, move: modifiers) -> list[int]:
    ret = [0] * MAX_PLY
    for d in range(MAX_PLY):
        ret[d] = computeDepth(values, move, d)
    return ret


if __name__ == "__main__":
    val = heuristics()
    stdDepths = extrapolate(
        val,
        modifiers(
            expectCutOff=False,
            improving=True,
            hashMoveCapture=False,
            badCapture=False,
            givesCheck=False,
            killerMove=False,
            pvNode=True,
            promotion=False,
            threatening=False,
        ),
    )
    prioDepths = extrapolate(
        val,
        modifiers(
            expectCutOff=False,
            improving=True,
            hashMoveCapture=False,
            badCapture=False,
            givesCheck=True,
            killerMove=True,
            pvNode=True,
            promotion=False,
            threatening=True,
        ),
    )
    depthExtent = 16
    fig, ax = plt.subplots()
    ax.plot(list(range(depthExtent)), label="y=x")
    ax.plot(stdDepths[:depthExtent], label="std")
    ax.plot(prioDepths[:depthExtent], label="prio")
    modifs = sampleModifier(8, 42)
    for x in modifs:
        ax.plot(
            extrapolate(val, x)[:depthExtent],
            label="random",
        )

    fig.legend()

    fig.show()
    plt.show()

    # while input("Press q to quit: ") != "q":
    #    pass
