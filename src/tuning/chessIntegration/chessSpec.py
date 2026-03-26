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
        while (self.lock):
            time.sleep(SLEEP_LOCK_S)
        self.lock = True

    def getScore(self) -> float:
        self.acquireLock()
        ret: float = 0.0
        ret += (self.draw / 2)
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

    def __init__(self):
        pass

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
            weights[i] = self.weights[i].getArray()

        if (weights[MG][texel.mobility_idx] != texel.INVALID_VALUE):
            print(f"mobilityScore: {weights[MG][texel.mobility_idx]} {weights[EG][texel.mobility_idx]}")

        if (weights[MG][texel.structureProtection_idx] != texel.INVALID_VALUE):
            print(f"structureProtection: {weights[MG][texel.structureProtection_idx]} {weights[EG][texel.structureProtection_idx]}")

        if (weights[MG][texel.isolatedPawnScore_idx] != texel.INVALID_VALUE):
            print(f"isolatedPawnScore: {weights[MG][texel.isolatedPawnScore_idx]} {weights[EG][texel.isolatedPawnScore_idx]}")

        if (weights[MG][texel.stackedPawnScore_idx] != texel.INVALID_VALUE):
            print(f"stackedPawnScore: {weights[MG][texel.stackedPawnScore_idx]} {weights[EG][texel.stackedPawnScore_idx]}")

        if (weights[MG][texel.passedPawnScore_idx] != texel.INVALID_VALUE):
            print(f"passedPawnScore: {weights[MG][texel.passedPawnScore_idx]} {weights[EG][texel.passedPawnScore_idx]}")

        if (weights[MG][texel.safetyKnight_idx] != texel.INVALID_VALUE):
            print(f"safetyKnight: {weights[MG][texel.safetyKnight_idx]} {weights[EG][texel.safetyKnight_idx]}")

        if (weights[MG][texel.safetyBishop_idx] != texel.INVALID_VALUE):
            print(f"safetyBishop: {weights[MG][texel.safetyBishop_idx]} {weights[EG][texel.safetyBishop_idx]}")

        if (weights[MG][texel.safetyRook_idx] != texel.INVALID_VALUE):
            print(f"safetyRook: {weights[MG][texel.safetyRook_idx]} {weights[EG][texel.safetyRook_idx]}")

        if (weights[MG][texel.safetyQueen_idx] != texel.INVALID_VALUE):
            print(f"safetyQueen: {weights[MG][texel.safetyQueen_idx]} {weights[EG][texel.safetyQueen_idx]}")



    def get1DArray(self) -> npt.NDArray[np.float64]:
        return np.concatenate([self.weights[MG].getArray(), self.weights[EG].getArray()])

def entryFrom1dArray(arr: npt.NDArray[np.float64], indexes: list[int]|None = None) -> heuristicEntry:
    ret = heuristicEntry()
    w = arr.reshape(2, -1, 1).astype(float).tolist()
    if indexes is None:
        indexes = list(range(len(w[0])))
    ret.weights = [texel.texelWeightsFromLists(w[0], indexes), texel.texelWeightsFromLists(w[1], indexes)]
    return ret

def entryFromListDup(arr: list[float], indexes: list[int] | None = None) -> heuristicEntry:
    return entryFrom2dList([arr, arr], indexes)

def entryFrom1dList(arr: list[float], indexes: list[int] | None = None) -> heuristicEntry:
    nsize = int(len(arr) / 2)
    return entryFrom2dList([list(arr[0:nsize]), list(arr[nsize:])], indexes)

def entryFrom2dList(arr: list[list[float]], indexes: list[int] | None = None) -> heuristicEntry:
    assert len(arr) == 2
    ret = heuristicEntry()
    ret.weights = [texel.texelWeightsFromFlatLists(arr[0], indexes), texel.texelWeightsFromFlatLists(arr[1], indexes)]
    return ret

def entryFromTexelWeights(w: texel.texelWeights) -> heuristicEntry:
    ret: heuristicEntry = heuristicEntry()
    ret.weights = [w.copy(), w.copy()]
    return ret


@dataclass
class chessIndividual(object):
    position: heuristicEntry  
    uid: int
    scoring: score 

weight_ext = ".winfo"

class callbackSave(template.callback):
    """
    """
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
        if (self.mh.objective is not None):
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
            if (len(iterList) != 0):
                savingDict["populationHistory"].append(iterBuffer)

        print(f"Saving dict {savingDict} to file: {path}")

        with open(path, "w") as file:
            yaml.dump(savingDict, file)

class callbackBaseline(template.callback):
    """
    """
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

#simpleBaselineWeights: list[float] = [-1.0, 2.0, -1.0, 20.0, 20.0, 40.0, 80.0, 1.0, 5.0]
#simpleBaselineWeights: texel.texelWeights = texel.texelWeightsFromLists(weights = [[-1.0], [2.0], [-1.0], [20.0], [20.0], [40.0], [80.0], [1.0], [5.0]], indexes = [texel.mobility_idx, texel.structureProtection_idx, texel.isolatedPawnScore_idx, texel.stackedPawnScore_idx, texel.passedPawnScore_idx, texel.safetyKnight_idx, texel.safetyBishop_idx, texel.safetyRook_idx, texel.safetyQueen_idx]) 
simpleBaselineWeights: heuristicEntry = entryFromListDup(arr = [-1.0, 2.0, -1.0, 20.0, 20.0, 40.0, 80.0, 1.0, 5.0], indexes = [texel.mobility_idx, texel.structureProtection_idx, texel.isolatedPawnScore_idx, texel.stackedPawnScore_idx, texel.passedPawnScore_idx, texel.safetyKnight_idx, texel.safetyBishop_idx, texel.safetyRook_idx, texel.safetyQueen_idx])


# obtained after 14 iter and 8 popsize
newWeight_0: list[float] = [0.0, -3.0, 100.0, -3.0, 18.0, -0.0, 87.0, 20.0, 11.0]
newWeight_0_bis: list[float] = [1.0, 3.0, 95.0, -3.0, 18.0, -0.0, 87.0, 20.0, 11.0]

newWeight_1: list[list[float]] = [[10.0, 100.0, 9.0, 32.0, 38.0, 100.0, -2.0, 2.0, 42.0], [-2.0, 100.0, 67.0, -2.0, 100.0, 32.0, 20.0, 100.0, -2.0]]

