from __future__ import annotations
from dataclasses import dataclass

from enum import Enum
from queue import Queue, Empty

import asyncio
import threading 
import random
import subprocess
import os
import sys 
import time 
import itertools
import typing 

import numpy as np
import numpy.typing as npt 

import algo.template as tp

simplePawnScore = 1
simpleBishopScore = 3
simpleKnightScore = 3
simpleRookScore = 5
simpleQueenScore = 9
simpleCheckMateScore = 99999
simpleStalemateScore = 0
simpleMobilityScore = 0.1
simpleIsolatedPawnScore = 0.2
simpleStackedPawnScore = 0.2

pawnScoreArr = np.array(
    [
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -0.31, 0.08, -0.07, -0.37, -0.36, -0.14, 0.03, -0.31, -0.22, 0.09, 0.05, -0.11, -0.1, -0.02, 0.03, -0.19, -0.26, 0.03, 0.1, 0.09, 0.06, 0.01, 0.0, -0.23, -0.17, 0.16, -0.02, 0.15, 0.14, 0.0, 0.15, -0.13, 0.07, 0.29, 0.21, 0.44, 0.4, 0.31, 0.44, 0.07, 0.78, 0.8300000000000001, 0.86, 0.73, 1.02, 0.8200000000000001, 0.85, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
]
    , dtype = float)

knightScoreArr = np.array([
    -0.0525, 0.015, -0.11249999999999999, -0.09, -0.105, -0.11249999999999999, -0.075, -0.075, 0.1425, 0.15, 0.08249999999999999, 0.045, 0.0525, 0.045, 0.15, 0.12, 0.105, 0.1875, 0.18, 0.11249999999999999, 0.06, 0.1875, 0.15, 0.11249999999999999, 0.0975, 0.075, 0.1275, 0.1725, 0.1275, 0.12, 0.0, 0.0525, 0.1875, 0.1275, 0.15, 0.255, 0.195, 0.1875, 0.11249999999999999, 0.075, -0.0675, 0.2925, -0.24, 0.3075, 0.39, -0.075, 0.21, -0.105, -0.08249999999999999, 0.15, 0.2625, -0.315, -0.2925, 0.23249999999999998, 0.015, -0.16499999999999998, -0.4425, -0.585, -0.615, -0.57, -0.1725, -0.8025, -0.27749999999999997, -0.375,
], dtype = float)

bishopScoreArr = np.array([
    -0.0525, 0.015, -0.11249999999999999, -0.09, -0.105, -0.11249999999999999, -0.075, -0.075, 0.1425, 0.15, 0.08249999999999999, 0.045, 0.0525, 0.045, 0.15, 0.12, 0.105, 0.1875, 0.18, 0.11249999999999999, 0.06, 0.1875, 0.15, 0.11249999999999999, 0.0975, 0.075, 0.1275, 0.1725, 0.1275, 0.12, 0.0, 0.0525, 0.1875, 0.1275, 0.15, 0.255, 0.195, 0.1875, 0.11249999999999999, 0.075, -0.0675, 0.2925, -0.24, 0.3075, 0.39, -0.075, 0.21, -0.105, -0.08249999999999999, 0.15, 0.2625, -0.315, -0.2925, 0.23249999999999998, 0.015, -0.16499999999999998, -0.4425, -0.585, -0.615, -0.57, -0.1725, -0.8025, -0.27749999999999997, -0.375,
], dtype = float)

rookScoreArr = np.array([
    -0.25, -0.2, -0.15, 0.041666666666666664, -0.016666666666666666, -0.15, -0.2583333333333333, -0.26666666666666666, -0.44166666666666665, -0.31666666666666665, -0.2583333333333333, -0.21666666666666667, -0.24166666666666667, -0.35833333333333334, -0.36666666666666664, -0.44166666666666665, -0.35, -0.23333333333333334, -0.35, -0.20833333333333334, -0.20833333333333334, -0.2916666666666667, -0.21666666666666667, -0.3833333333333333, -0.23333333333333334, -0.2916666666666667, -0.13333333333333333, -0.175, -0.10833333333333334, -0.24166666666666667, -0.3833333333333333, -0.25, 0.0, 0.041666666666666664, 0.13333333333333333, 0.10833333333333334, 0.15, -0.03333333333333333, -0.075, -0.05, 0.15833333333333333, 0.2916666666666667, 0.23333333333333334, 0.275, 0.375, 0.225, 0.20833333333333334, 0.125, 0.4583333333333333, 0.24166666666666667, 0.4666666666666667, 0.5583333333333333, 0.4583333333333333, 0.5166666666666666, 0.2833333333333333, 0.5, 0.2916666666666667, 0.24166666666666667, 0.275, 0.03333333333333333, 0.30833333333333335, 0.275, 0.4666666666666667, 0.4166666666666667,
], dtype = float)
queenScoreArr = np.array([
    -0.2925, -0.22499999999999998, -0.23249999999999998, -0.0975, -0.23249999999999998, -0.27, -0.255, -0.315, -0.27, -0.135, 0.0, -0.1425, -0.11249999999999999, -0.11249999999999999, -0.1575, -0.285, -0.22499999999999998, -0.045, -0.0975, -0.08249999999999999, -0.12, -0.08249999999999999, -0.12, -0.20249999999999999, -0.105, -0.11249999999999999, -0.015, -0.0375, -0.0075, -0.075, -0.15, -0.16499999999999998, 0.0075, -0.12, 0.16499999999999998, 0.1275, 0.1875, 0.15, -0.0975, -0.045, -0.015, 0.3225, 0.24, 0.44999999999999996, 0.54, 0.4725, 0.3225, 0.015, 0.105, 0.24, 0.44999999999999996, -0.075, 0.15, 0.57, 0.4275, 0.18, 0.045, 0.0075, -0.06, -0.78, 0.5175, 0.18, 0.6599999999999999, 0.195,
], dtype = float)

kingScoreArr = np.array([
    0.17, 0.3, -0.03, -0.14, 0.06, -0.01, 0.4, 0.18, -0.04, 0.03, -0.14, -0.5, -0.5700000000000001, -0.18, 0.13, 0.04, -0.47000000000000003, -0.42, -0.43, -0.79, -0.64, -0.32, -0.29, -0.32, -0.55, -0.43, -0.52, -0.28, -0.51, -0.47000000000000003, -0.08, -0.5, -0.55, 0.5, 0.11, -0.04, -0.19, 0.13, 0.0, -0.49, -0.62, 0.12, -0.5700000000000001, 0.44, -0.67, 0.28, 0.37, -0.31, -0.32, 0.1, 0.55, 0.56, 0.56, 0.55, 0.1, 0.03, 0.04, 0.54, 0.47000000000000003, -0.99, -0.99, 0.6, 0.8300000000000001, -0.62,
], dtype = float)




class heuristicEntry(tp.engineParams):
    # to be modified during the optim
    def __init__(self, rand: np.random.Generator, fraction_diff: float):
        # rand type np.Random.Generator
        #rand.random()

        self.simpleMobilityScore = 0.1 * (1 + fraction_diff * (rand.random() - 0.5) * 2)
        self.simpleIsolatedPawnScore = 0.2 * (1 + fraction_diff * (rand.random() - 0.5) * 2)
        self.simpleStackedPawnScore = 0.2 * (1 + fraction_diff * (rand.random() - 0.5) * 2)
        self.pawnScoreArr = pawnScoreArr * (1 + fraction_diff * (rand.random(pawnScoreArr.size) - 0.5) * 2)
        self.knightScoreArr = knightScoreArr * (1 + fraction_diff * (rand.random(knightScoreArr.size) - 0.5) * 2)
        self.bishopScoreArr = bishopScoreArr * (1 + fraction_diff * (rand.random(bishopScoreArr.size) - 0.5) * 2)
        self.rookScoreArr = rookScoreArr * (1 + fraction_diff * (rand.random(rookScoreArr.size) - 0.5) * 2)
        self.queenScoreArr = queenScoreArr * (1 + fraction_diff * (rand.random(queenScoreArr.size) - 0.5) * 2)
        self.kingScoreArr = kingScoreArr * (1 + fraction_diff * (rand.random(kingScoreArr.size) - 0.5) * 2)

        self.simpleMobilityScore = round(self.simpleMobilityScore, 2)
        self.simpleIsolatedPawnScore= round(self.simpleIsolatedPawnScore, 2)
        self.simpleStackedPawnScore= round(self.simpleStackedPawnScore, 2)

        self.pawnScoreArr = self.pawnScoreArr.round(2)
        self.knightScoreArr = self.knightScoreArr.round(2)
        self.bishopScoreArr = self.bishopScoreArr.round(2)
        self.rookScoreArr = self.rookScoreArr.round(2)
        self.queenScoreArr = self.queenScoreArr.round(2)
        self.kingScoreArr = self.kingScoreArr.round(2)

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

SLEEP_LOCK_S = 0.01
SLEEP_STDOUT_S = 1
@dataclass
class score:
    win: int
    lose: int
    draw: int
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

    def getStr(self) -> str:
        return f"win: {self.win} lose: {self.lose} draw: {self.draw} score: {self.getScore()}"

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
            #print(f"[DEBUG] lauchAndWaitResults: line found: '{_line}' tokens: {tokens}")
            if (len(tokens) != 3):
                continue
            ret.append(score(win = int(tokens[0]), lose = int(tokens[1]), draw = int(tokens[2])))
        return ret

    #def launchAndWaitResults(self, evalPath, tmpFolder: str):
    #    ret: list[score] = []
    #    newInfo = self.generateFiles(tmpFolder)
    #    proc = subprocess.Popen([evalPath, newInfo], stdin = subprocess.DEVNULL, stderr = subprocess.DEVNULL, stdout = subprocess.PIPE, text = True)
    #    proc.wait
    #    q = Queue()
    #    t = threading.Thread(target = enqueue_output, args = (proc.stdout, q))
    #    t.daemon = True
    #    t.start()
    #    running = True
    #    while running:
    #        try: line = q.get_nowait()
    #        except Empty:
    #            time.sleep(SLEEP_STDOUT_S)
    #        else:
    #            if line == "":
    #                running = False
    #            else:
    #                _line = line.rstrip()
    #                tokens = _line.split(" ")
    #                print(f"[DEBUG] lauchAndWaitResults: line found: '{_line}' tokens: {tokens}")
    #                if (len(tokens) != 3):
    #                    continue
    #                ret.append(score(win = int(tokens[0]), lose = int(tokens[1]), draw = int(tokens[2])))
    #    return ret


def enqueue_output(pipe, queue):
    for line in iter(pipe.readline, ''):
        queue.put(line)
    pipe.close()

@dataclass
class individual(object):
    scoring: score
    position: heuristicEntry  
    uid: int

class matchStatus(Enum):
    PENDING = 1
    IN_PROGRESS = 2
    FINISHED = 3


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

class matchContainerInfo(object):
    order: list[tuple[int, int]]
    status: list[matchStatus]
    def __init__(self, popsize: int):
        self.order = []
        self.status = []
        self.order.extend(scheduleMatches(popsize))
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
    def __init__(self, timeF: timeFormat, popsize: int, seed: int|None, templatePath: str|None, logFolder: str, nRounds: int = 4, evalBin: str|None = None, debugMode: bool = False, nThread: int = 1, includeBasePosition: bool = False):
        self.timeFormat: timeFormat = timeF
        self.popsize: int = popsize
        self.matchInv: matchContainerInfo = matchContainerInfo(popsize)
        self.seed: int|None = seed
        self.randGen = np.random.default_rng(seed)
        self.templatePath: str|None = templatePath 
        self.nRounds: int = nRounds
        self.currentRound: int = 0;
        self.population: list[individual] = []
        self.running: bool = False
        self.evalBin: str|None = evalBin
        self.debugMode: bool = debugMode
        self.logFolder: str = logFolder

        # can very between 0.1 and -0.1
        self.fraction_diff:float = 0.1
        self.nThread: int = nThread
        self.includeBasePosition: bool = False
        self.logs: dict = {}
    def initLogs(self):
        self.logs["best_params_end_round"] = []
    
    def generatePopulation(self) -> None: 
        self.population = []
        for i in range(self.popsize):
            self.population.append(
                individual( 
                    scoring = score(0, 0, 0), 
                    position = heuristicEntry(rand = self.randGen, fraction_diff = self.fraction_diff), 
                    uid = i)
            )
        if (self.includeBasePosition):
            self.population[-1].position = heuristicEntry(rand = self.randGen, fraction_diff = 0)
    

    def setThread(self, nThread: int) -> None:
        assert nThread > 0
        self.nThread = nThread

    def optimize(self) -> None:
        assert self.population is not None
        self.generatePopulation()
        self.updateScoreBoard()
        while self.currentRound < self.nRounds:
            # here we can dispatch in the threads
            self.dispatchMatch(self.matchInv)
            self.onRoundEnd()
            self.currentRound += 1
    def dispatchMatch(self, matchInfo: matchContainerInfo) -> None:
        indexes = matchInfo.splitNThreads(self.nThread)
        workingThreads: list[threading.Thread] = []
        for threadId, idx in enumerate(indexes):
            workingThreads.append(threading.Thread(target = self._dispatchMatch, args = ([idx, threadId])))
            workingThreads[-1].start()
        for x in workingThreads:
            x.join()
        
    def _dispatchMatch(self, idx: list[int], threadId: int) -> None:
        assert self.population is not None
        assert self.templatePath is not None
        for i in idx:
            pair = self.matchInv.order[i]
            opp1 = self.population[pair[0]].position
            opp2 = self.population[pair[1]].position

            self.matchInv.status[i] = matchStatus.IN_PROGRESS

            currentMatch: match = match(conf1 = opp1, conf2 = opp2, infoFilePath=self.templatePath, extra = f"T{threadId}")
            scoreList = currentMatch.launchAndWaitResults(self.evalBin, self.logFolder)

            self.matchInv.status[i] = matchStatus.FINISHED
            self.updateScore(pair=pair, score = scoreList)
            self.updateScoreBoard()

    def updateScore(self, pair: tuple[int, int], score: list[score]) -> None:
        self.population[pair[0]].scoring.addEq(score[0])
        self.population[pair[1]].scoring.addEq(score[1])

    def updateScoreBoard(self) -> None:
        clear()
        print(f"Round: n°{self.currentRound} / {self.nRounds}")
        for i in range(len(self.population)):
            print(f"{i}: {self.population[i].scoring.getStr()}")
        for j in range(len(self.matchInv.status)):
            p = self.matchInv.order[j]
            match self.matchInv.status[j]:
                case matchStatus.PENDING:
                    text = "PENDING"
                case matchStatus.IN_PROGRESS:
                    text = "IN_PROGRESS"
                case matchStatus.FINISHED:
                    text = "FINISHED"
                case _:
                    text = "UNKNOWN"

            print(f"{p[0]} vs {p[1]} status: {text}")


    def onRoundEnd(self) -> None:
        # pass on the scores and apply modifs to the params
        # ideally or smthing
        # sorts inplace 0th best rest lower
        self.population.sort(key = lambda x: x.scoring.getScore(), reverse = True)
        self.logs["best_params_end_round"].append(self.population[0])


def clear() -> None:
    print("\x1B[2J\x1B[H", end = "\r")

def t_split() -> None:
    popsize = 16
    m = matchContainerInfo(popsize)

    splited = m.splitNThreads(3)
    print(splited)

    splited = m.splitNThreads(9)
    print(splited)
    del m
    return

   
if __name__ == "__main__":
    t_split()
    print("ben")
    path = "engines/engine_tourney.info"
    tmpFolder = f"engines/heuristics/tmp/tmp_{int(time.time())}"
    evaluationBinPath = "zig-out/bin/evaluate"
    os.makedirs(tmpFolder, exist_ok=True)
    set = readInfoFile(path)
    set.print()
    tourn = tournament(standardTimeFormat, popsize = 4, seed = 42, templatePath = path, evalBin = evaluationBinPath, debugMode = True, logFolder = tmpFolder, nThread=2)
    tourn.optimize()

    

