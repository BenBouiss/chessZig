from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

import threading 
import subprocess
import os, time, sys

import numpy as np
import numpy.typing as npt 

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from algo import objective as obj
from algo import gw

from algo.template import individual, saveOptions

sys.path.append(os.path.dirname(__file__))
from chessSpec import heuristicEntry, score, chessIndividual
import chessSpec

baseWeightPath = "engines/heuristics/baseOldWeights.info"

SLEEP_LOCK_S = 0.01
SLEEP_STDOUT_S = 1

@dataclass
class scoreBoard:
    lock: bool = False
    def updateScoreBoard(self, tourney: tournament) -> None:
        self.acquireLock()
        clear()
        for i in range(len(tourney.population)):
            print(f"{i}: {tourney.population[i].scoring}, id: {tourney.population[i].uid}")
        for j in range(len(tourney.matchInv.status)):
            p = tourney.matchInv.order[j]
            match tourney.matchInv.status[j]:
                case matchStatus.PENDING:
                    text = "PENDING"
                case matchStatus.IN_PROGRESS:
                    text = "IN_PROGRESS"
                case matchStatus.FINISHED:
                    text = "FINISHED"
                case _:
                    text = "UNKNOWN"

            print(f"{p[0]} vs {p[1]} status: {text}")

        self.releaseLock()

    def releaseLock(self) -> None:
        self.lock = False

    def acquireLock(self) -> None:
        while (self.lock):
            time.sleep(SLEEP_LOCK_S)
        self.lock = True

global_scoreBoard = scoreBoard()

@dataclass
class timeFormat:
    # times in ms
    time: int
    inc: int

@dataclass
class infoFile:
    engineSettings: list[list[str]]
    engineNames: list[str]
    matchSettings: list[str]
    def print(self) -> None:
        print("engine settings: ")
        for i in range(len(self.engineSettings)):
            print(self.engineNames[i])
            print(self.engineSettings[i])

        print("match settings: ")
        print(self.matchSettings)

def readInfoFile(path: str) -> infoFile:
    ret = infoFile([[]], [], [])
    matchSection: bool = False
    engineIndex = 0
    with open(path, "r") as file:
        for line in file.readlines():
            _line = line.rstrip()
            if (not len(_line) or _line.startswith("//")):
                continue
            if _line.startswith("[match]"):
                matchSection = True
                continue
            if (_line.startswith("[") ):
                ret.engineNames.append(_line)
                if (len(ret.engineSettings[engineIndex])):
                    engineIndex += 1
                    ret.engineSettings.append([])
                continue
            if (matchSection):
                ret.matchSettings.append(_line.rstrip())
            else:
                ret.engineSettings[engineIndex].append(_line.rstrip())
    return ret

def saveHeuristicsWeights(entries: list[heuristicEntry], directory: str, uid: int, extra: str) -> list[str]:
    ret: list[str] = []
    for i in range(len(entries)):
        path = os.path.join(directory, f"{uid}_{i}_{extra}.winfo")
        entries[i].saveToFile(path)
        ret.append(path)
    return ret

standardTimeFormat = timeFormat(time=300_000, inc=5000)
blitzTimeFormat = timeFormat(time=300_000, inc=0)
class match(object): 
    def __init__(self, conf1: heuristicEntry, conf2: heuristicEntry, infoFilePath: str, debugMode: bool = False, extra: str = ""):
        self.conf1: heuristicEntry = conf1
        self.conf2: heuristicEntry = conf2
        self.infoFilePath: str = infoFilePath
        self.uid: int= int(1000*time.time())
        self.debugMode: bool = debugMode
        self.extra: str = extra
        

    def generateFiles(self, tmpfolder: str) -> str:
        heuristics = saveHeuristicsWeights([self.conf1, self.conf2], directory = tmpfolder, uid = self.uid, extra = self.extra)
        setting = readInfoFile(self.infoFilePath)
        newInfoPath = os.path.join(tmpFolder, f"newInfo_{self.uid}_{self.extra}.info")
        with open(newInfoPath, "w") as file:
            for i in range(len(setting.engineNames)):
                file.write(f"{setting.engineNames[i]}\n")
                allCmd = "\n".join(setting.engineSettings[i])
                file.write(f"{allCmd}\n")
                file.write(f"\"setoption name heuristicWeightsPath value {heuristics[i]}\";\n")

            file.write(f"[match]\n")
            allCmd = "\n".join(setting.matchSettings)
            file.write(f"{allCmd}\n")
        return newInfoPath

    def launchAndWaitResults(self, evalPath, tmpFolder: str) -> list[score]:
        ret: list[score] = []
        newInfo = self.generateFiles(tmpFolder)
        proc = subprocess.Popen([evalPath, newInfo], stdin = subprocess.DEVNULL, stderr = subprocess.DEVNULL, stdout = subprocess.PIPE, text = True)
        assert proc.stdout is not None
        for line in iter(proc.stdout.readline, ''):
            _line = line.rstrip()
            tokens = _line.split(" ")
            if self.debugMode:
                print(f"[DEBUG] from launchAndWaitResults: line found: '{line}' tokens: '{tokens}'\n")
            if (len(tokens) != 3):
                continue
            ret.append(score(win = int(tokens[0]), lose = int(tokens[1]), draw = int(tokens[2])))
        return ret

class matchStatus(Enum):
    PENDING = 1
    IN_PROGRESS = 2
    FINISHED = 3

class tournamentType(Enum):
    CLASSIC = 1
    BASELINE = 2


def scheduleMatches(popsize: int) -> list[tuple[int, int]]:
    """
    ex for 4 configs
    [0, 1, 2, 3]
    schedule:
        0 vs 1
        0 vs 2
        0 vs 3
        1 vs 2
        1 vs 3
        2 vs 3
    """
    ret: list[tuple[int, int]] = []
    indexes = list(range(popsize))
    for x in range(len(indexes)):
        for y in range(x+1, len(indexes)):
            ret.append((x, y))
    return ret;
def scheduleMatchesBaseline(popsize: int, popBase: int) -> list[tuple[int, int]]:
    """
    ex for 4 configs and 2 baseline
    [0, 1, 2, 3]
    schedule:
        0 vs base_0
        0 vs base_1

        1 vs base_0
        1 vs base_1

        2 vs base_0
        2 vs base_1

        3 vs base_0
        3 vs base_1
    """
    ret: list[tuple[int, int]] = []
    indexes = list(range(popsize))
    for x in range(len(indexes)):
        for y in range(popBase):
            ret.append((x, y))
    return ret;


class matchContainerInfo(object):
    order: list[tuple[int, int]]
    status: list[matchStatus]
    def __init__(self, popsize: int, popBase: int = 0, type: tournamentType = tournamentType.CLASSIC):
        self.order = []
        self.status = []
        self.popsize: int = popsize
        if (type == tournamentType.CLASSIC):
            self.order.extend(scheduleMatches(popsize))
        else:
            self.order.extend(scheduleMatchesBaseline(popsize, popBase))

        for _ in range(len(self.order)):
            self.status.append(matchStatus.PENDING)
    def splitNThreads(self, nThread: int) -> list[list[int]]:
        assert nThread != 0
        ret: list[list[int]] = []
        n = len(self.order)
        sizeEach: int = int(n/nThread)
        remainder = n - (sizeEach * nThread)
        offset: int = 0
        for x in range(nThread):
            ret.append([])
            for y in range(offset, sizeEach + offset):
                ret[x].append(y)
            offset += sizeEach
        for x in range(remainder):
            index = offset + x
            ret[x].append(index)
        return ret


class tournament(object):
    def __init__(self, timeF: timeFormat, templatePath: str|None, logDir: str, evalBin: str|None = None, debugMode: bool = False, nThread: int = 1, type: tournamentType = tournamentType.CLASSIC):
        self.timeFormat: timeFormat = timeF
        self.type = type
        self.matchInv: matchContainerInfo = matchContainerInfo(1)
        self.templatePath: str|None = templatePath 
        self.population: list[chessIndividual] = []
        self.baseline: list[chessIndividual] = []
        self.evalBin: str|None = evalBin
        self.debugMode: bool = debugMode
        if debugMode:
            print("Building tournament with debug on")
        self.logDir: str = logDir
        self.setThread(nThread)
        self.logs: dict = {}
    
    def setThread(self, nThread: int) -> None:
        assert nThread > 0
        self.nThread = nThread

    def dispatchMatch(self, matchInfo: matchContainerInfo) -> None:
        self.matchInv = matchInfo
        indexes = matchInfo.splitNThreads(self.nThread)
        workingThreads: list[threading.Thread] = []
        for threadId, idx in enumerate(indexes):
            workingThreads.append(threading.Thread(target = self.thread_dispatchMatch, args = ([idx, threadId])))
            workingThreads[-1].start()
        for x in workingThreads:
            x.join()
        
    def thread_dispatchMatch(self, idx: list[int], threadId: int) -> None:
        assert self.population is not None
        assert self.templatePath is not None
        for i in idx:
            pair = self.matchInv.order[i]
            opp1 = self.population[pair[0]].position
            if (self.type == tournamentType.BASELINE):
                opp2 = self.baseline[pair[1]].position
            else:
                opp2 = self.population[pair[1]].position

            self.matchInv.status[i] = matchStatus.IN_PROGRESS
            global_scoreBoard.updateScoreBoard(self)

            currentMatch: match = match(conf1 = opp1, conf2 = opp2, infoFilePath=self.templatePath, extra = f"T{threadId}", debugMode = self.debugMode)
            scoreList = currentMatch.launchAndWaitResults(self.evalBin, self.logDir)

            self.matchInv.status[i] = matchStatus.FINISHED
            self.updateScore(pair=pair, score = scoreList)
            global_scoreBoard.updateScoreBoard(self)

    def updateScore(self, pair: tuple[int, int], score: list[score]) -> None:
        if (self.debugMode):
            print(f"[DEBUG] from updateScore: pair: {pair}, score: {score} before adding pop: \n")
            for i in range(len(self.population)):
                print(f"[DEBUG] \t {self.population[i].scoring}, id: {self.population[i].uid}\n")
        self.population[pair[0]].scoring.addEq(score[0])
        if (not self.type == tournamentType.BASELINE):
            self.population[pair[1]].scoring.addEq(score[1])

        if (self.debugMode):
            for i in range(len(self.population)):
                print(f"[DEBUG] \t {self.population[i].scoring}, id: {self.population[i].uid}\n")
    

class chessObjective(obj.objective):
    def __init__(self, tourney: tournament, **parentKwargs):
        self.tourney = tourney
        super().__init__(**parentKwargs)
        self.baseline: list[heuristicEntry] = []
    
    def _evaluate(self, positions: list[npt.NDArray[np.float64]] | npt.NDArray[np.float64] | list[list[float]]) -> list[float]:
        matchInv: matchContainerInfo = matchContainerInfo(len(positions), popBase = len(self.baseline), type = self.tourney.type)
        self.tourney.population = []
        for i in range(len(positions)):
            self.tourney.population.append(
                chessIndividual(
                    position = chessSpec.entryFrom1dArray(np.array(positions[i])), 
                    uid = i, scoring = score(0, 0, 0, False))
                )
        self.tourney.baseline = [chessIndividual(
                    position = pos, uid = x, scoring = score(0, 0, 0, False)) for x, pos in enumerate(self.baseline)]
        self.tourney.dispatchMatch(matchInv)
        return [x.scoring.getScore() for x in self.tourney.population]

    def setBaseline(self, entry: heuristicEntry) -> None:
        self.baseline = [entry]

    def appendBaseline(self, entry: heuristicEntry) -> None:
        self.baseline.append(entry)


# since all the current positions are "similar" enough might
# be a good idea to do a dummy func with only nDim in input
def dummyBounds(lbound: float, rbound: float, nDim: int) -> npt.NDArray[np.float64]:
    """
     ex: for [-10.0; 10] with ndim = 4
     res = np.array(
                    [-10.0, 10], 
                    [-10.0, 10], 
                    [-10.0, 10], 
                    [-10.0, 10]
                    )

    """
    return np.tile(np.array([lbound, rbound]), [nDim, 1])

def dummyStep(step: float, nDim: int) -> npt.NDArray[np.float64]:
    """
     ex: for 0.01 with ndim = 4
     res = np.array(0.01, 0.01, 0.01, 0.01)
    """
    return np.repeat(np.array([step]), nDim)

UPPER_BOUND_WEIGHT = 100
LOWER_BOUND_WEIGHT = -UPPER_BOUND_WEIGHT
STEP_WEIGTH = 1
N_PARAMS = chessSpec.total_idx
def clear() -> None:
    print("\x1B[2J\x1B[H", end = "\r")

if __name__ == "__main__":
    path = "engines/engine_tourney.info"
    tmpFolder = f"engines/heuristics/tmp/tmp_{int(time.time())}"
    evaluationBinPath = "zig-out/bin/evaluate"
    os.makedirs(tmpFolder, exist_ok=True)

    popsize = 16
    maxiter = 32

    cbs = [chessSpec.callbackBaseline()]
    saveOpt: saveOptions = saveOptions(logDir=tmpFolder, prefix = "ben")
    mh = gw.GW(popsize = popsize, maxiter = maxiter, saveLog = True, preEval = True, saveOpt = saveOpt, cbs = cbs)
    tourn = tournament(standardTimeFormat, templatePath = path, evalBin = evaluationBinPath, debugMode = True, logDir = tmpFolder, nThread=4, type = tournamentType.BASELINE)

    mh.setObjective(chessObjective(maximize=True, tourney=tourn, bounds = dummyBounds(LOWER_BOUND_WEIGHT, UPPER_BOUND_WEIGHT, nDim = N_PARAMS), steps = dummyStep(STEP_WEIGTH, nDim = N_PARAMS)))
    assert mh.objective is not None
    mh.objective.setBaseline(chessSpec.entryFromList(chessSpec.simpleBaselineWeights))

    mh.generatePopulation()

    mh.addInvididual(indiv = individual(position = np.array(chessSpec.simpleBaselineWeights), uid = -1))
    mh.addInvididual(indiv = individual(position = np.array(chessSpec.newWeight_0), uid = -1))
    mh.printPopulation()
    
    mh.optimize()

    

