from __future__ import annotations

from dataclasses import dataclass
import time, typing, copy, os
import numpy as np 
import numpy.typing as npt 
import yaml

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
    weights: list[list[float]]

    def __init__(self):
        pass
        
    def saveToFile(self, path: str) -> None:
        # scalar value
        # simpleStackedPawnScore: {d};
        with open(path, "w") as file:
            file.write(f"stackedPawnScore_MG = {self.weights[MG][stackedPawnScore_idx]};\n")
            file.write(f"stackedPawnScore_EG = {self.weights[EG][stackedPawnScore_idx]};\n")

            file.write(f"passedPawnScore_MG = {self.weights[MG][passedPawnScore_idx]};\n")
            file.write(f"passedPawnScore_EG = {self.weights[EG][passedPawnScore_idx]};\n")

            file.write(f"isolatedPawnScore_MG = {self.weights[MG][isolatedPawnScore_idx]};\n")
            file.write(f"isolatedPawnScore_EG = {self.weights[EG][isolatedPawnScore_idx]};\n")

            file.write(f"safetyKnight_MG = {self.weights[MG][safetyKnight_idx]};\n")
            file.write(f"safetyKnight_EG = {self.weights[EG][safetyKnight_idx]};\n")

            file.write(f"safetyBishop_MG = {self.weights[MG][safetyBishop_idx]};\n")
            file.write(f"safetyBishop_EG = {self.weights[EG][safetyBishop_idx]};\n")

            file.write(f"safetyRook_MG = {self.weights[MG][safetyRook_idx]};\n")
            file.write(f"safetyRook_EG = {self.weights[EG][safetyRook_idx]};\n")

            file.write(f"safetyQueen_MG = {self.weights[MG][safetyQueen_idx]};\n")
            file.write(f"safetyQueen_EG = {self.weights[EG][safetyQueen_idx]};\n")

            file.write(f"structureProtection_MG = {self.weights[MG][structureProtection_idx]};\n")
            file.write(f"structureProtection_EG = {self.weights[EG][structureProtection_idx]};\n")

            file.write(f"mobilityScore_MG = {self.weights[MG][mobility_idx]};\n")
            file.write(f"mobilityScore_EG = {self.weights[EG][mobility_idx]};\n")

    def print(self) -> None:

        print(f"stackedPawnScore: {self.weights[MG][stackedPawnScore_idx]} {self.weights[EG][stackedPawnScore_idx]}")

        print(f"passedPawnScore: {self.weights[MG][passedPawnScore_idx]} {self.weights[EG][passedPawnScore_idx]}")

        print(f"isolatedPawnScore: {self.weights[MG][isolatedPawnScore_idx]} {self.weights[EG][isolatedPawnScore_idx]}")

        print(f"safetyKnight: {self.weights[MG][safetyKnight_idx]} {self.weights[EG][safetyKnight_idx]}")

        print(f"safetyBishop: {self.weights[MG][safetyBishop_idx]} {self.weights[EG][safetyBishop_idx]}")

        print(f"safetyRook: {self.weights[MG][safetyRook_idx]} {self.weights[EG][safetyRook_idx]}")

        print(f"safetyQueen: {self.weights[MG][safetyQueen_idx]} {self.weights[EG][safetyQueen_idx]}")

        print(f"structureProtection: {self.weights[MG][structureProtection_idx]} {self.weights[EG][structureProtection_idx]}")

        print(f"mobilityScore: {self.weights[MG][mobility_idx]} {self.weights[EG][mobility_idx]}")

    def get1DArray(self) -> npt.NDArray[np.float64]:
        return np.concatenate(self.weights)

def entryFrom1dArray(arr: npt.NDArray[np.float64]) -> heuristicEntry:
    ret = heuristicEntry()
    ret.weights = arr.reshape(2, -1).tolist()
    return ret


def entryFromListDup(arr: list[float]) -> heuristicEntry:
    ret = heuristicEntry()
    ret.weights = [list(arr), list(arr)]
    return ret

def entryFrom1dList(arr: list[float]) -> heuristicEntry:
    ret = heuristicEntry()
    nsize = int(len(arr) / 2)
    ret.weights = [list(arr[0:nsize]), list(arr[nsize:])]
    return ret

def entryFrom2dList(arr: list[list[float]]) -> heuristicEntry:
    assert len(arr) == 2
    ret = heuristicEntry()
    ret.weights = [list(arr[0]), list(arr[1])]
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
        
 


# weight section
total_idx = 0

mobility_idx = total_idx
total_idx += 1

structureProtection_idx = total_idx
total_idx += 1

isolatedPawnScore_idx = total_idx
total_idx += 1
stackedPawnScore_idx = total_idx
total_idx += 1
passedPawnScore_idx = total_idx
total_idx += 1

#not used
#safetyPawn_idx = total_idx
#total_idx += 1

safetyKnight_idx = total_idx
total_idx += 1
safetyBishop_idx = total_idx
total_idx += 1
safetyRook_idx = total_idx
total_idx += 1
safetyQueen_idx = total_idx
total_idx += 1


# p , n, b, r, q
simplePieceCount: list[float] = [100, 300, 300, 500, 900]

simpleBaselineWeights: list[float] = [-1.0, 2.0, -1.0, 20.0, 20.0, 40.0, 80.0, 1.0, 5.0]

# obtained after 14 iter and 8 popsize
newWeight_0: list[float] = [0.0, -3.0, 100.0, -3.0, 18.0, -0.0, 87.0, 20.0, 11.0]
newWeight_0_bis: list[float] = [1.0, 3.0, 95.0, -3.0, 18.0, -0.0, 87.0, 20.0, 11.0]

newWeight_1: list[list[float]] = [[10.0, 100.0, 9.0, 32.0, 38.0, 100.0, -2.0, 2.0, 42.0], [-2.0, 100.0, 67.0, -2.0, 100.0, 32.0, 20.0, 100.0, -2.0]]

