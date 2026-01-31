
import numpy.typing as npt 
import numpy as np

class objective(object):
    def __init__(self, maximize: bool, bounds: npt.NDArray[np.float64] | list[list[float]], steps: npt.NDArray[np.float64] | list[float]):
        assert len(bounds) == len(steps)

        self.maximize: bool = maximize

        self.bounds: npt.NDArray[np.float64]  = np.array(bounds)
        #self.bounds : npt.NDArray[np.float64] | list[list[float]] = []
        #if type(bounds) is list:
        #    self.bounds = np.array(bounds)
        #elif type(bounds) is np.array:
        #    self.bounds = bounds


        self.steps: npt.NDArray[np.float64] = np.array(steps)
        #if type(steps) is list:
        #    self.steps= np.array(steps)
        #elif type(steps) is np.array:
        #    assert type(steps) is not list
        #    self.steps = steps

        #self.steps: npt.NDArray[np.float64] = steps
        self.nDims: int = len(self.steps)

    def evaluate(self, positions: list[npt.NDArray[np.float64]] | npt.NDArray[np.float64] | list[list[float]]) -> list[float]:
        ret = self._evaluate(positions)
        if (self.maximize):
            return ret
        return [-x for x in ret]

    def _evaluate(self, positions: list[npt.NDArray[np.float64]] | npt.NDArray[np.float64] | list[list[float]]) -> list[float]:
        _ = positions
        raise NotImplementedError("this function needs to be implemented")

def dummyObjectiveFunction(position: npt.NDArray[np.float64], target: npt.NDArray[np.float64]):
    return np.sum(np.absolute(position - target))

class dummyObjective(objective):
    def __init__(self, target: list[float], **parentKwargs):
        super().__init__(**parentKwargs)
        self.target: npt.NDArray[np.float64] = np.array(target)

    def _evaluate(self, positions: list[npt.NDArray[np.float64]] | npt.NDArray[np.float64] | list[list[float]]) -> list[float]:
        ret = []
        for pos in positions:
            ret.append(dummyObjectiveFunction(np.array(pos), self.target))
        return ret

if __name__ == "__main__":
    target = [1.5, 1.5]
    steps = [0.1, 0.1]
    bounds = [[0, 10]] * len(target)
    test = dummyObjective(target = target, steps = steps, bounds = bounds, maximize = True)

    print(test.evaluate(positions = [[1.5, 1.5], [0, 0]]))
