from __future__ import annotations

from abc import ABC
from enum import Enum
from dataclasses import dataclass

import numpy as np
import numpy.typing as npt
import yaml

import os, sys, time, typing, copy

sys.path.append(os.path.dirname(__file__))

import objective


@dataclass
class individual:
    position: npt.NDArray[np.float64]
    uid: int = -1
    score: float = 0
    frozen: bool = False

    def __repr__(self) -> str:
        return f"uid: {self.uid}, score: {self.score}, position: {self.position}, frozen: {self.frozen}"

    def saveFrame(self) -> list[float]:
        return [self.position.tolist(), self.uid, float(self.score), self.frozen]


FRAME_POSITION_IDX = 0
FRAME_UID_IDX = 1
FRAME_SCORE_IDX = 2
FRAME_FROZEN_IDX = 3


@dataclass
class saveOptions:
    # TODO: actually use this dir, currently only used if resDir not provided
    logDir: str = "."
    resDir: str | None = None
    prefix: str = "result"
    saveLog: bool = True

    def __init__(
        self,
        logDir: str = ".",
        prefix: str = "result",
        saveLog: bool = True,
        resDir: str | None = None,
    ):
        os.makedirs(logDir, exist_ok=True)
        self.logDir = logDir
        self.resDir = resDir
        self.prefix = prefix
        self.saveLog = saveLog

    def loadFromDict(self, d: dict | None) -> None:
        if d is None:
            return
        self.logDir = d.get("logDir", self.logDir)
        self.resDir = d.get("resDir", self.resDir)
        self.prefix = d.get("prefix", self.prefix)
        self.saveLog = d.get("saveLog", self.saveLog)


@dataclass
class optimizerOption:
    useGreedy: bool = True
    preEval: bool = True
    debugMode: bool = False

    def loadFromDict(self, d: dict | None) -> None:
        if d is None:
            return
        self.useGreedy = d.get("useGreedy", self.useGreedy)
        self.preEval = d.get("preEval", self.preEval)
        self.debugMode = d.get("debugMode", self.debugMode)


DEFAULT_SEED = 42
DEFAULT_INT = 1


class templateSelectionAlgo(object):
    def __init__(
        self,
        popsize: int,
        maxiter: int,
        seed: int = DEFAULT_SEED,
        cbs: list[callback] | None = None,
        saveOpt: saveOptions = saveOptions(),
        optimOpt: optimizerOption = optimizerOption(),
    ):
        self.objective: objective.objective | None = None

        self.running = False
        self.optimOpt = optimOpt

        self.maxiter: int = maxiter
        self.iter: int = 0
        self.uid = int(time.time())

        self.seed = seed
        self.numpyRandomGenerator = np.random.default_rng(seed)

        self.popsize: int = popsize
        self.population: list[individual] = []
        # TODO clean up and remove redundant info
        self.populationHistory: list[list[individual]] = []
        self.best_indiv_list: list[individual] = []
        self.callbacks: list[callback] = []

        if cbs is not None:
            for cb in cbs:
                self.addCallback(cb)
        self.saveOpt: saveOptions = saveOpt
        self.name = "Null"

    def isDebugMode(self) -> bool:
        return self.optimOpt.debugMode

    def addCallback(self, cb: callback) -> None:
        cb.setMh(self)
        self.callbacks.append(cb)

    def setObjective(self, obj: objective.objective):
        self.objective = obj

    def generatePopulation(self) -> None:
        assert self.objective is not None
        self.population = []
        delta = self.objective.bounds[:, 1] - self.objective.bounds[:, 0]

        # TODO: v???v
        initScore = float("-inf") if self.objective.maximize else float("inf")

        for i in range(self.popsize):
            randMask = self.numpyRandomGenerator.random(size=self.objective.nDims)
            indiv = individual(
                position=self.snapToCorrectGrid(
                    self.objective.bounds[:, 0] + delta * randMask
                ),
                uid=i,
                score=initScore,
            )
            self.population.append(indiv)

    def generateRandArray(self) -> npt.NDArray[np.float64]:
        assert self.objective is not None

        delta = self.objective.bounds[:, 1] - self.objective.bounds[:, 0]
        randMask = self.numpyRandomGenerator.random(size=self.objective.nDims)
        return self.snapToCorrectGrid(self.objective.bounds[:, 0] + delta * randMask)

    def snapToSteps(self, position: npt.NDArray[np.float64]) -> npt.NDArray[np.float64]:
        assert self.objective is not None
        return self.objective.steps * np.rint(position / self.objective.steps)

    def snapToCorrectGrid(
        self, position: npt.NDArray[np.float64]
    ) -> npt.NDArray[np.float64]:
        assert self.objective is not None
        ret = self.snapToSteps(position)
        ret = np.min([ret, self.objective.bounds[:, 1]], axis=0)
        ret = np.max([ret, self.objective.bounds[:, 0]], axis=0)
        return ret

    def applyFrozenToNewPos(
        self, positions: npt.NDArray[np.float64]
    ) -> npt.NDArray[np.float64]:
        assert self.popsize == len(positions)
        for i in range(self.popsize):
            if self.population[i].frozen:
                positions[i] = np.array(self.population[i].position)
        return positions

    def optimize(self) -> None:
        assert len(self.population) != 0
        assert self.objective is not None
        self.running = True

        if self.optimOpt.preEval and (self.iter == 0):
            # can be used in algo to have a already evaluated
            # random population
            scores = self.evaluate(self.getCurrentPositions())
            for i in range(self.popsize):
                self.population[i].score = scores[i]

        while self.running and self.iter < self.maxiter:
            self.on_iter_start()

            self.step()

            if self.isDebugMode():
                print(
                    f"[DEBUG] template.optimize: best indiv: {self.best_indiv_list[-1]}"
                )

            self.iter += 1

            self.on_iter_end()

        self.on_optim_end()

    def step(self) -> None:
        raise NotImplementedError("this function needs to be implemented")

    def evaluate(
        self,
        positions: list[npt.NDArray[np.float64]]
        | npt.NDArray[np.float64]
        | list[list[float]],
    ) -> list[float]:
        assert self.objective is not None
        self.on_eval(positions)
        return self.objective.evaluate(positions)

    def on_iter_start(self):
        for cb in self.callbacks:
            cb.on_iter_start()

    def on_iter_end(self):
        for cb in self.callbacks:
            cb.on_iter_end()
        self.populationHistory.append(copy.deepcopy(self.population))
        if self.saveOpt.saveLog:
            # TODO for now we overwrite the existing file everytime "nasty"
            dirPath = (
                self.saveOpt.resDir
                if self.saveOpt.resDir is not None
                else self.saveOpt.logDir
            )
            os.makedirs(dirPath, exist_ok=True)
            path = os.path.join(dirPath, f"{self.saveOpt.prefix}_{self.uid}.yaml")
            self.saveToFile(path)

    def on_optim_start(self):
        for cb in self.callbacks:
            cb.on_optim_start()

    def on_optim_end(self):
        for cb in self.callbacks:
            cb.on_optim_end()

    def on_eval(
        self,
        positions: list[npt.NDArray[np.float64]]
        | npt.NDArray[np.float64]
        | list[list[float]],
    ):
        for cb in self.callbacks:
            cb.on_eval(positions)

    def on_eval_end(self, scores: list[float]) -> None:
        for cb in self.callbacks:
            cb.on_eval_end(scores)

    def getCurrentPositions(self) -> list[npt.NDArray[np.float64]]:
        return [x.position for x in self.population]

    def getBestIndiv(self) -> individual:
        assert self.objective is not None
        bestIdx = 0
        for idx, indiv in enumerate(self.population):
            if indiv.score > self.population[bestIdx].score:
                bestIdx = idx
        return self.population[bestIdx]

    def printPopulation(self) -> None:
        for i in range(self.popsize):
            print(self.population[i])

    def addInvididual(self, indiv: individual) -> None:
        if indiv.uid == -1:
            indiv.uid = self.popsize
        self.population.append(indiv)
        self.popsize += 1

    def loadYaml(self, path: str) -> None:
        assert os.path.exists(path), "File not found"
        with open(path, "r") as file:
            valDict = yaml.safe_load(file)

        self.iter = valDict.get("iter", DEFAULT_INT)
        self.maxiter = valDict.get("maxiter", DEFAULT_INT)
        self.popsize = valDict.get("popsize", DEFAULT_INT)
        self.seed = valDict.get("seed", DEFAULT_SEED)
        self.saveOpt.loadFromDict(valDict.get("saveOptions", None))
        self.optimOpt.loadFromDict(valDict.get("optimizerOption", None))

        if self.objective is not None:
            self.objective.loadFromFile(valDict)

        lastFrame = valDict.get("populationHistory", [])
        self.populationHistory = loadPopulationHistory(
            valDict.get("populationHistory", [])
        )

        if len(lastFrame) == 0:
            return
        lastFrame = lastFrame[-1]
        for i in range(len(lastFrame[0])):
            if len(lastFrame) == FRAME_FROZEN_IDX + 1:
                currentIndiv = individual(
                    position=np.array(lastFrame[FRAME_POSITION_IDX][i]),
                    uid=lastFrame[FRAME_UID_IDX][i],
                    score=lastFrame[FRAME_SCORE_IDX][i],
                    frozen=lastFrame[FRAME_FROZEN_IDX][i],
                )
                self.population.append(currentIndiv)
            elif len(lastFrame) == FRAME_SCORE_IDX + 1:
                currentIndiv = individual(
                    position=np.array(lastFrame[FRAME_POSITION_IDX][i]),
                    uid=lastFrame[FRAME_UID_IDX][i],
                    score=lastFrame[FRAME_SCORE_IDX][i],
                )
                self.population.append(currentIndiv)

    def saveToFile(self, path: str) -> None:
        # can be overloaded by other algo to save more things
        savingDict: dict = {}
        savingDict["populationHistory"] = []
        savingDict["iter"] = self.iter
        savingDict["maxiter"] = self.maxiter
        savingDict["popsize"] = self.popsize
        savingDict["seed"] = self.seed
        savingDict["saveOptions"] = self.saveOpt.__dict__
        savingDict["optimizerOption"] = self.optimOpt.__dict__
        if self.objective is not None:
            # check fmt if not good need to convert to list of list
            savingDict["objective"] = self.objective.saveToFile()

        savingDict["fmtCode"] = list(self.population[0].position.shape)
        for itr, iterList in enumerate(self.populationHistory):
            # save format: idx: 0 = mh iteration

            iterBuffer = [[], [], [], []]
            for indiv in iterList:
                frame = indiv.saveFrame()
                iterBuffer[FRAME_POSITION_IDX].append(frame[FRAME_POSITION_IDX])
                iterBuffer[FRAME_UID_IDX].append(frame[FRAME_UID_IDX])
                iterBuffer[FRAME_SCORE_IDX].append(frame[FRAME_SCORE_IDX])
                iterBuffer[FRAME_FROZEN_IDX].append(frame[FRAME_FROZEN_IDX])
            if len(iterList) != 0:
                savingDict["populationHistory"].append(iterBuffer)

        # print(f"Saving dict {savingDict} to file: {path}")
        with open(path, "w") as file:
            yaml.dump(savingDict, file)


def loadPopulationHistory(
    l: list[typing.Any],
) -> list[list[individual]]:
    ret: list[list[individual]] = []
    for itr in range(len(l)):
        frame = l[itr]
        nIndiv = len(frame[0])
        ret.append([])
        for i in range(nIndiv):
            ret[itr].append(
                individual(
                    position=np.array(frame[FRAME_POSITION_IDX][i]),
                    uid=frame[FRAME_UID_IDX][i],
                    score=frame[FRAME_SCORE_IDX][i],
                    frozen=frame[FRAME_FROZEN_IDX][i],
                )
            )

    return ret


class callback(ABC):
    def __init__(self):
        self.mh: templateSelectionAlgo | None = None

    def setMh(self, mh: templateSelectionAlgo) -> None:
        self.mh = mh

    def on_iter_start(self):
        pass

    def on_iter_end(self):
        pass

    def on_optim_start(self):
        pass

    def on_optim_end(self):
        pass

    def on_eval(
        self,
        positions: list[npt.NDArray[np.float64]]
        | npt.NDArray[np.float64]
        | list[list[float]],
    ):
        _ = positions
        pass

    def on_eval_end(self, scores: list[float]):
        _ = scores
        pass
