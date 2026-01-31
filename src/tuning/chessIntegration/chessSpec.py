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

def weightFileToHeuristicEntry(path: str) -> heuristicEntry:
    ret: heuristicEntry = heuristicEntry()
    with open(path, "r") as file:
        for line in file.readlines():
            if not line:
                continue
            leftBorder = line.find("[")
            rightBorder = line.find("]")
            if (leftBorder == -1 or rightBorder == -1):
                continue
            tokenList = line[leftBorder+1:rightBorder].split(",")
            floatList = [float(x) for x in tokenList]
            if line.startswith("pawn"):
                ret.pawnScoreArr = np.array(floatList, dtype = float)
            elif line.startswith("bishop"):
                ret.bishopScoreArr = np.array(floatList, dtype = float)
            elif line.startswith("knight"):
                ret.knightScoreArr = np.array(floatList, dtype = float)
            elif line.startswith("rook"):
                ret.rookScoreArr = np.array(floatList, dtype = float)
            elif line.startswith("queen"):
                ret.queenScoreArr = np.array(floatList, dtype = float)
            elif line.startswith("king"):
                ret.kingScoreArr = np.array(floatList, dtype = float)
        return ret


class heuristicEntry:
    simpleMobilityScore: float
    simpleIsolatedPawnScore: float
    simpleStackedPawnScore: float

    pawnScoreArr: npt.NDArray[np.float64]
    bishopScoreArr: npt.NDArray[np.float64]
    knightScoreArr: npt.NDArray[np.float64]
    rookScoreArr: npt.NDArray[np.float64]
    queenScoreArr: npt.NDArray[np.float64]
    kingScoreArr: npt.NDArray[np.float64]

    def __init__(self):
        pass
        
    def printAll(self): 
        print(f"All the scores: {self.simpleMobilityScore} {self.simpleIsolatedPawnScore} {self.simpleStackedPawnScore}")
        print(self.pawnScoreArr)

    def saveToFile(self, path: str) -> None:
        with open(path, "w") as file:
            file.write(f"pawnScoreArr: {self.pawnScoreArr.tolist()};\n")
            file.write(f"bishopScoreArr: {self.bishopScoreArr.tolist()};\n")
            file.write(f"knightScoreArr: {self.knightScoreArr.tolist()};\n")
            file.write(f"rookScoreArr: {self.rookScoreArr.tolist()};\n")
            file.write(f"queenScoreArr: {self.queenScoreArr.tolist()};\n")
            file.write(f"kingScoreArr: {self.kingScoreArr.tolist()};\n")

    def getPosition(self) -> list[npt.ArrayLike]:
        return [self.pawnScoreArr, self.bishopScoreArr, self.knightScoreArr, self.rookScoreArr, self.queenScoreArr, self.kingScoreArr]

    def get1DArray(self) -> npt.NDArray[np.float64]:
        return np.concatenate(self.getPosition())
        

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



