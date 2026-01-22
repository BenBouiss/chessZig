from dataclasses import dataclass
import numpy as np 
import numpy.typing as npt 
import typing

@dataclass
class engineParams:
    def getPosition(self) -> list[npt.ArrayLike]:
        raise NotImplementedError("this function needs to be implemented")

@dataclass
class individual(object):
    scoring: float = 0
    position: engineParams = engineParams()

class individualContainer(object):
    def __init__(self, popsize: int, positions: list[engineParams]):
        assert popsize == len(positions)
        self.len = popsize
        self.indivList: list[individual] = []
        for pos in positions:
            self.indivList.append(individual(position = pos))


class templateSelectionAlgo(object):
    def __init__(self, popsize: int, positions: list[engineParams]):
        self.popsize = popsize
        self.indivs: individualContainer = individualContainer(popsize, positions)

    def reproduce(self):
        raise NotImplementedError("this function needs to be implemented")
