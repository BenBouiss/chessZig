from __future__ import annotations

from dataclasses import dataclass
import time, typing, copy, os, sys
import numpy as np
import numpy.typing as npt
import yaml

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

import texel
from algo import template

SLEEP_LOCK_S = 0.01


@dataclass
class score:
    win: int = 0
    lose: int = 0
    draw: int = 0
    lock: bool = False

    def realeaseLock(self) -> None:
        self.lock = False

    def acquireLock(self) -> None:
        while self.lock:
            time.sleep(SLEEP_LOCK_S)
        self.lock = True

    def getScore(self) -> float:
        self.acquireLock()
        ret: float = 0.0
        ret += self.draw / 2
        ret += self.win
        self.realeaseLock()
        return ret

    def addEq(self, other: score) -> None:
        self.acquireLock()
        self.win += other.win
        self.draw += other.draw
        self.lose += other.lose
        self.realeaseLock()

    def __repr__(self) -> str:
        return f"win: {self.win} lose: {self.lose} draw: {self.draw} score: {self.getScore()}"


MG = 0
EG = 1


class heuristicEntry:
    weights: list[texel.texelWeights]

    def __init__(self, weights: list[texel.texelWeights]):
        assert len(weights) == 2
        self.weights = [weights[0].copy(), weights[1].copy()]

    def maskOut(
        self, indexes: list[int], defaultValue: float = texel.INVALID_VALUE
    ) -> heuristicEntry:
        # return the weights masked with the new indexes where non present indexes are marked with texel.INVALID_VALUE or current value
        ret = []
        for i in range(len(self.weights)):
            arr = np.array(self.weights[i].getArray(fullLength=True))
            mask = arr == texel.INVALID_VALUE
            arr[mask] = defaultValue

            ret.append(
                texel.texelWeightsFromFlatLists(
                    arr[np.array(indexes)].tolist(), indexes=indexes
                )
            )
        return heuristicEntry(weights=ret)

    def saveToFile(self, path: str) -> None:
        # scalar value
        # simpleStackedPawnScore: {d};
        phases = ["_MG", "_EG"]
        with open(path, "w") as file:
            for i in range(len(phases)):
                file.write(texel.texelWeightToFileStr(self.weights[i], phases[i]))

    def print(self) -> None:
        phases = ["_MG", "_EG"]
        weights = [[], []]
        for i in range(len(phases)):
            weights[i] = self.weights[i].getArray(fullLength=True)
        for w in range(len(weights[0])):
            if weights[MG][w] != texel.INVALID_VALUE:
                print(f"{strWeightNames[w]}: {weights[MG][w]} {weights[EG][w]}")

    def get1DArray(self) -> npt.NDArray[np.float64]:
        return np.concatenate(
            [self.weights[MG].getArray(), self.weights[EG].getArray()]
        )


def entryFrom1dArray(
    arr: npt.NDArray[np.float64], indexes: list[int] | None = None
) -> heuristicEntry:
    w = arr.reshape(2, -1, 1).astype(float).tolist()
    if indexes is None:
        indexes = list(range(len(w[0])))
    ret = heuristicEntry(
        weights=[
            texel.texelWeightsFromLists(w[0], indexes),
            texel.texelWeightsFromLists(w[1], indexes),
        ]
    )
    return ret


def entryFromListDup(
    arr: list[float], indexes: list[int] | None = None
) -> heuristicEntry:
    return entryFrom2dList([arr, arr], indexes)


def entryFrom1dList(
    arr: list[float], indexes: list[int] | None = None
) -> heuristicEntry:
    nsize = int(len(arr) / 2)
    return entryFrom2dList([list(arr[0:nsize]), list(arr[nsize:])], indexes)


def entryFrom2dList(
    arr: list[list[float]], indexes: list[int] | None = None
) -> heuristicEntry:
    assert len(arr) == 2
    ret = heuristicEntry(
        weights=[
            texel.texelWeightsFromFlatLists(arr[0], indexes),
            texel.texelWeightsFromFlatLists(arr[1], indexes),
        ]
    )
    return ret


def entryFromTexelWeights(w: texel.texelWeights) -> heuristicEntry:
    ret: heuristicEntry = heuristicEntry(weights=[w.copy(), w.copy()])
    return ret


@dataclass
class chessIndividual(object):
    position: heuristicEntry
    uid: int
    scoring: score


weight_ext = ".winfo"


class callbackSave(template.callback):
    """ """

    def __init__(self, logDir: str, prefix: str = "result"):
        super().__init__()
        self.logDir: str = logDir
        self.totalPopulation: list[list[template.individual]] = []
        self.prefix = prefix
        self.uid = int(time.time())

    def on_iter_end(self):
        assert self.mh is not None
        self.totalPopulation.append(copy.deepcopy(self.mh.population))

    def on_optim_end(self):
        assert self.mh is not None
        path = os.path.join(self.logDir, f"{self.prefix}_{self.uid}.yaml")
        self.saveToFile(path)

    def printHistory(self) -> None:
        for itrr in range(len(self.totalPopulation)):
            buffer = self.totalPopulation[itrr]
            print(f"Population of iterration: {itrr}")
            for i in range(len(buffer)):
                print(f"{buffer[i]}")

    def saveToFile(self, path: str) -> None:
        # can be overloaded by other algo to save more things
        assert self.mh is not None
        savingDict: dict = {}
        savingDict["populationHistory"] = []
        savingDict["iter"] = self.mh.iter
        savingDict["maxiter"] = self.mh.maxiter
        savingDict["popsize"] = self.mh.popsize
        if self.mh.objective is not None:
            # check fmt if not good need to convert to list of list
            savingDict["bounds"] = self.mh.objective.bounds.tolist()
            savingDict["steps"] = self.mh.objective.steps.tolist()

        savingDict["fmtCode"] = list(self.mh.population[0].position.shape)
        for itr, iterList in enumerate(self.totalPopulation):
            iterBuffer = [[], [], []]
            for indiv in iterList:
                frame = indiv.saveFrame()
                iterBuffer[0].append(frame[0])
                iterBuffer[1].append(frame[1])
                iterBuffer[2].append(frame[2])
            if len(iterList) != 0:
                savingDict["populationHistory"].append(iterBuffer)

        print(f"Saving dict {savingDict} to file: {path}")

        with open(path, "w") as file:
            yaml.dump(savingDict, file)


class callbackBaseline(template.callback):
    """ """

    def __init__(self):
        super().__init__()

    def on_iter_end(self):
        assert self.mh is not None
        assert self.mh.objective is not None
        best = self.mh.getBestIndiv()
        nBaseline = len(self.mh.objective.baseline)
        if best.score == nBaseline * 2:
            print("[DEBUG] callbackBaseline: adding the current best to the baseline")
            self.mh.objective.appendBaseline(entryFrom1dArray(best.position))


# p , n, b, r, q
simplePieceCount: list[float] = [100, 300, 300, 500, 900]

# simpleBaselineWeights: list[float] = [-1.0, 2.0, -1.0, 20.0, 20.0, 40.0, 80.0, 1.0, 5.0]

prevIndexes = [
    texel.mobility_idx,
    texel.structureProtection_idx,
    texel.isolatedPawnScore_idx,
    texel.stackedPawnScore_idx,
    texel.passedPawnScore_idx,
    texel.safetyKnight_idx,
    texel.safetyBishop_idx,
    texel.safetyRook_idx,
    texel.safetyQueen_idx,
]
currentIndexes = list(range(texel.mobility_idx, texel.safetyQueen_idx + 1))
currentIndexes.remove(texel.safetyPawn_idx)
defaultWeights: heuristicEntry = entryFromListDup(
    arr=[5, 10, 1, 1, 1, 2, 25, 20, 20, 40, 80], indexes=currentIndexes
)
# texel.INVALID_VALUE, #pawn safety is not used

simpleBaselineWeights: heuristicEntry = entryFromListDup(
    arr=[-1.0, 2.0, -1.0, 20.0, 20.0, 40.0, 80.0, 1.0, 5.0],
    indexes=prevIndexes,
)


# obtained after 14 iter and 8 popsize
newWeight_0: heuristicEntry = entryFromListDup(
    arr=[0.0, -3.0, 100.0, -3.0, 18.0, -0.0, 87.0, 20.0, 11.0], indexes=prevIndexes
)
newWeight_0_bis: list[float] = [1.0, 3.0, 95.0, -3.0, 18.0, -0.0, 87.0, 20.0, 11.0]

newWeight_1: heuristicEntry = entryFrom2dList(
    arr=[
        [10.0, 100.0, 9.0, 32.0, 38.0, 100.0, -2.0, 2.0, 42.0],
        [-2.0, 100.0, 67.0, -2.0, 100.0, 32.0, 20.0, 100.0, -2.0],
    ],
    indexes=prevIndexes,
)
strWeightNames = [
    "pawnCountScore",
    "bishopCountScore",
    "knightCountScore",
    "rookCountScore",
    "queenCountScore",
    "mobilityScore",
    "mobilityKingScore",
    "structureProtectionScore",
    "isolatedPawnScore",
    "stackedPawnScore",
    "passedPawnScore",
    "tempoChecksScore",
    "safetyPawn",
    "safetyKnight",
    "safetyBishop",
    "safetyRook",
    "safetyQueen",
]
