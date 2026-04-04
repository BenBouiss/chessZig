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
    logDir: str = "."
    prefix: str = "result"


DEFAULT_SEED = 42
DEFAULT_INT = 1
DEFAULT_PREVAL = False


class templateSelectionAlgo(object):
    def __init__(
        self,
        popsize: int,
        maxiter: int,
        seed: int = DEFAULT_SEED,
        preEval: bool = DEFAULT_PREVAL,
        cbs: list[callback] | None = None,
        saveLog: bool = False,
        saveOpt: saveOptions = saveOptions(),
        useGreedy: bool = True,
    ):
        self.objective: objective.objective | None = None

        self.running = False
        self.preEval: bool = preEval
        self.useGreedy: bool = useGreedy

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
        self.saveLog: bool = saveLog
        self.saveOpt: saveOptions = saveOpt
        self.name = "Null"

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
        initScore = float("-inf") if self.objective.maximize else float("-inf")

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

    def optimize(self) -> None:
        assert len(self.population) != 0
        assert self.objective is not None
        self.running = True

        if self.preEval and (self.iter == 0):
            # can be used in algo to have a already evaluated
            # random population
            scores = self.evaluate(self.getCurrentPositions())
            for i in range(self.popsize):
                self.population[i].score = scores[i]

        while self.running and self.iter < self.maxiter:
            self.step()

            print(f"[DEBUG] template.optimize: best indiv: {self.best_indiv_list[-1]}")

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
        if self.saveLog:
            self.populationHistory.append(copy.deepcopy(self.population))
            # TODO for now we overwrite the existing file everytime "nasty"
            path = os.path.join(
                self.saveOpt.logDir, f"{self.saveOpt.prefix}_{self.uid}.yaml"
            )
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
        self.preEval = valDict.get("preEval", DEFAULT_PREVAL)
        self.seed = valDict.get("seed", DEFAULT_SEED)

        if self.objective is not None:
            self.objective.loadFromFile(valDict)

        lastFrame = valDict.get("populationHistory", [])
        self.populationHistory = valDict.get("populationHistory", [])

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
        savingDict["preEval"] = self.preEval
        savingDict["seed"] = self.seed
        if self.objective is not None:
            # check fmt if not good need to convert to list of list
            savingDict["objective"] = self.objective.saveToFile()

        savingDict["fmtCode"] = list(self.population[0].position.shape)
        for itr, iterList in enumerate(self.populationHistory):
            iterBuffer = [[], [], [], []]
            for indiv in iterList:
                frame = indiv.saveFrame()
                iterBuffer[FRAME_POSITION_IDX].append(frame[FRAME_POSITION_IDX])
                iterBuffer[FRAME_UID_IDX].append(frame[FRAME_UID_IDX])
                iterBuffer[FRAME_SCORE_IDX].append(frame[FRAME_SCORE_IDX])
                iterBuffer[FRAME_FROZEN_IDX].append(frame[FRAME_FROZEN_IDX])
            if len(iterList) != 0:
                savingDict["populationHistory"].append(iterBuffer)

        print(f"Saving dict {savingDict} to file: {path}")
        with open(path, "w") as file:
            yaml.dump(savingDict, file)


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
