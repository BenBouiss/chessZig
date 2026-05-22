from __future__ import annotations
import sys, os


sys.path.append(os.path.dirname(__file__))
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

import template
import objective

import numpy as np
import os
import numpy.typing as npt


class DE(template.templateSelectionAlgo):
    def __init__(self, **parentKwargs):
        super().__init__(**parentKwargs)

        self.CR = 0.35
        self.initEta = 2
        self.finalEta = 0.2

        self.eta = self.initEta
        self.nP = 2
        self.name = "DE"

    def updateParam(self) -> None:
        self.eta = self.initEta - (self.initEta - self.finalEta) * int(
            self.iter / self.maxiter
        )

    def step(self):
        assert self.objective is not None
        self.updateParam()
        currentPop = np.array(self.getCurrentPositions())
        new_pos = currentPop.copy()
        n = self.objective.nDims

        for i in range(self.popsize):
            prob = self.numpyRandomGenerator.random(size=n)
            mask = prob <= self.CR
            new_pos[i][mask] = self.snapToCorrectGrid(
                self.eta
                * computeDonorVector(currentPop, self.nP, i, self.numpyRandomGenerator)
            )[mask]

        scores = self.evaluate(new_pos)
        for i in range(self.popsize):
            if scores[i] >= self.population[i].score or not self.optimOpt.useGreedy:
                self.population[i].position = new_pos[i]
                self.population[i].score = scores[i]

        # not necessary but cool
        self.population.sort(key=lambda x: x.score, reverse=True)
        self.best_indiv_list.append(self.population[0])


def computeDonorVector(
    pop: npt.NDArray[np.float64], nPairs: int, index: int, rand: np.random.Generator
) -> npt.NDArray[np.float64]:
    ret = np.zeros(shape=pop[0].shape)
    for _ in range(nPairs):
        indexes = list(range(len(pop)))
        indexes.remove(index)
        candidates_idx = rand.choice(a=indexes, size=2, replace=False)
        ret += pop[candidates_idx[0]] - pop[candidates_idx[1]]
    return ret


if __name__ == "__main__":
    test = objective.makeDummyObjective(
        nDim=10, minV=-10, maxV=10, step=0.1, maximize=False
    )
    print(f"The target is {test.target}")
    saveOpt: template.saveOptions = template.saveOptions(saveLog=False)
    mh = DE(popsize=64, maxiter=1024, saveOpt=saveOpt)
    mh.setObjective(test)
    # mh.addCallback(callbackSave(logDir, prefix="ben"))
    mh.generatePopulation()
    mh.population[0].frozen = True
    mh.optimize()

    mh.printPopulation()
