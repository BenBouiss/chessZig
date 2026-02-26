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


class heuristicEntry:
    mobilityScore: float
    isolatedPawnScore: float
    stackedPawnScore: float
    passedPawnScore: float

    # safeties? 
    safetyKnight: float
    safetyBishop: float
    safetyRook: float
    safetyQueen: float
    def __init__(self):
        pass
        
    def saveToFile(self, path: str) -> None:
        # scalar value
        # simpleStackedPawnScore: {d};
        with open(path, "w") as file:
            file.write(f"isolatedPawnScore = {self.isolatedPawnScore};\n")
            file.write(f"mobilityScore = {self.mobilityScore};\n")
            file.write(f"stackedPawnScore = {self.stackedPawnScore};\n")

            file.write(f"safetyKnight = {self.safetyKnight};\n")
            file.write(f"safetyBishop = {self.safetyBishop};\n")
            file.write(f"safetyRook = {self.safetyRook};\n")
            file.write(f"safetyQueen = {self.safetyQueen};\n")

    def getPosition(self) -> list[typing.Any]:
        return [self.isolatedPawnScore, self.mobilityScore, self.stackedPawnScore]

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



