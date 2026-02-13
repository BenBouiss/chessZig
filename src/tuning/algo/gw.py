from __future__ import annotations

import sys, os

sys.path.append(os.path.dirname(__file__))
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

import template 
import objective

import numpy as np
import numpy.typing as npt 
from chessIntegration.chessSpec import callbackSave

# https://www.geeksforgeeks.org/machine-learning/grey-wolf-optimization-introduction/
class GW(template.templateSelectionAlgo):
    def __init__(self, **parentKwargs):
        super().__init__(**parentKwargs)
        assert self.popsize > 3, "GW needs atleast 3"

        # value decreasing with iterations from 2 to 0
        self.a: float = 2


    def step(self):
        new_pos = self.applyFrozenToNewPos(self.computeNewPositions())

        scores = self.evaluate(new_pos)

        for i in range(self.popsize):
            if (scores[i] > self.population[i].score):
                self.population[i].position = new_pos[i]
                self.population[i].score = scores[i]

        self.population.sort(key = lambda x: x.score, reverse = True)
        self.best_indiv_list.append(self.population[0])

    def computeNewPositions(self) -> npt.NDArray[np.float64]:
        """
        Sort population
        Take the 3 best
        for each indiv: 
            compute "distance" to each 3 best
            acc the results and add to current
            eval
            greedy select
        """
        assert self.objective is not None
        alphas = np.array([x.position for x in self.population[0:3]])


        A = (2 * self.a * self.numpyRandomGenerator.random(size = (3, self.objective.nDims))) - self.a
        D = np.empty(shape = (3, self.objective.nDims))
        C = 2 * self.numpyRandomGenerator.random(size = (3, self.objective.nDims))

        # dim (popsize, nDims) "(y, x)"
        new_pos = np.empty(shape = (self.popsize, self.objective.nDims))
        for i in range(self.popsize):
            X = self.population[i].position
            D = (C * alphas) - X
            contributions = alphas - A * D
            new_pos[i] = self.snapToCorrectGrid((contributions[0] + contributions[1] + contributions[2]) / 3)

        return new_pos

    def updateCoefficient(self):
        self.a = 2 * (1 - self.iter / self.maxiter)

    def applyFrozenToNewPos(self, positions: npt.NDArray[np.float64]) -> npt.NDArray[np.float64]: 
        assert self.popsize == len(positions)
        for i in range(self.popsize):
            if (self.population[i].frozen):
                positions[i] = np.array(self.population[i].position)
        return positions



if __name__ == "__main__":

    target = [1.5, 1.5]
    steps = [0.1, 0.1]
    bounds = [[0, 10]] * len(target)
    test = objective.dummyObjective(target = target, steps = steps, bounds = bounds, maximize = True)

    logDir = "logs"
    saveOpt: template.saveOptions = template.saveOptions(logDir=logDir, prefix = "ben")
    mh = GW(popsize = 32, maxiter = 16, saveLog = True, saveOpt = saveOpt)
    mh.setObjective(test)
    #mh.addCallback(callbackSave(logDir, prefix="ben"))
    mh.generatePopulation()
    mh.population[0].frozen = True
    mh.optimize()
    
    mh.printPopulation()
    print("Now loading from yaml")

    tmp = GW(popsize = 32, maxiter = 16)
    tmpFile = os.path.join(mh.saveOpt.logDir, f"{mh.saveOpt.prefix}_{mh.uid}.yaml")
    tmp.loadYaml(tmpFile)
    print(f"Size of pop found: {tmp.popsize}")
    tmp.printPopulation()

