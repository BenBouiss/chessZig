from __future__ import annotations

from dataclasses import dataclass
import time, typing, copy, os, sys, math
import numpy as np
import numpy.typing as npt
import yaml
from enum import Enum

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

import utils as utilsl

import texelW

from texelW import texelWeights

import constants as cst

from algo import template
import lock as lockl

SLEEP_LOCK_S = 0.01


@dataclass
class score:
    win: int = 0
    lose: int = 0
    draw: int = 0
    l = lockl.lock()

    def nMatch(self) -> int:
        return self.win + self.lose + self.draw

    def getScore(self) -> float:
        self.l.acquire()
        ret: float = 0.0
        ret += self.draw / 2
        ret += self.win
        self.l.release()
        return ret

    def addEq(self, other: score) -> None:
        self.l.acquire()
        self.win += other.win
        self.draw += other.draw
        self.lose += other.lose
        self.l.release()

    def __repr__(self) -> str:
        return f"win: {self.win} lose: {self.lose} draw: {self.draw} score: {self.getScore()}"


MG = 0
EG = 1


class heuristicEntry:
    weights: list[texelWeights]

    def __init__(self, weights: list[texelWeights]):
        assert len(weights) == 2
        self.weights = [weights[0].copy(), weights[1].copy()]

    def maskOut(
        self, indexes: list[int], defaultValue: float = cst.INVALID_VALUE
    ) -> heuristicEntry:
        # return the weights masked with the new indexes where non present indexes are marked with cst.INVALID_VALUE or current value
        ret = []
        for i in range(len(self.weights)):
            arr = np.array(self.weights[i].getArray(fullLength=True))
            mask = arr == cst.INVALID_VALUE
            arr[mask] = defaultValue

            ret.append(
                texelW.texelWeightsFromFlatLists(
                    arr[np.array(indexes)].tolist(), indexes=indexes
                )
            )
        return heuristicEntry(weights=ret)

    def saveToFile(self, path: str) -> None:
        # scalar value
        # simpleStackedPawnScore: {d};
        phases = ["_MG", "_EG"]
        with open(path, "w") as file:
            for i in range(len(phases)):
                file.write(texelW.texelWeightToFileStr(self.weights[i], phases[i]))

    def print(self, fileFormat: bool = False) -> None:
        phases = ["_MG", "_EG"]
        weights = [[], []]
        for i in range(len(phases)):
            weights[i] = self.weights[i].getArray(fullLength=True)
        for w in range(len(weights[0])):
            if weights[MG][w] != cst.INVALID_VALUE:
                if w < cst.PSQT_Pawn_idx:
                    # print(w)
                    if fileFormat:
                        print(
                            f"{cst.strWeightNames[w]}{phases[MG]} = {weights[MG][w]};"
                        )
                        print(
                            f"{cst.strWeightNames[w]}{phases[EG]} = {weights[EG][w]};"
                        )
                    else:
                        print(
                            f"{cst.strWeightNames[w]} = {weights[MG][w]} {weights[EG][w]}"
                        )
                else:
                    if (w - cst.PSQT_Pawn_idx) % 64 == 0:
                        # only first indexes good
                        idx = (w - cst.PSQT_Pawn_idx) % 64
                        print(
                            f"{cst.strPQSTNames[idx]}{phases[MG]} = {weights[MG][w : w + 64]};"
                        )
                        print(
                            f"{cst.strPQSTNames[idx]}{phases[EG]} = {weights[EG][w : w + 64]};"
                        )

    def get1DArray(self) -> npt.NDArray[np.float64]:
        return np.concatenate(
            [self.weights[MG].getArray(), self.weights[EG].getArray()]
        )

    def pushArray(self, val: list[float], idx: int, phase: phaseE) -> None:
        if phase == phaseE.MG:
            self.weights[MG].pushArray(val=val, startingIdx=idx)
        elif phase == phaseE.EG:
            self.weights[EG].pushArray(val=val, startingIdx=idx)
        else:
            self.weights[MG].pushArray(val=val, startingIdx=idx)
            self.weights[EG].pushArray(val=val, startingIdx=idx)


def entryFrom1dArray(
    arr: npt.NDArray[np.float64], indexes: list[int] | None = None
) -> heuristicEntry:
    w = arr.reshape(2, -1, 1).astype(float).tolist()
    if indexes is None:
        indexes = list(range(len(w[0])))
    ret = heuristicEntry(
        weights=[
            texelW.texelWeightsFromLists(w[0], indexes),
            texelW.texelWeightsFromLists(w[1], indexes),
        ]
    )
    return ret


def entryFromListDup(
    arr: list[float], indexes: list[int] | None = None
) -> heuristicEntry:
    return entryFrom2dList([arr, arr], indexes)


def entryFrom1dList(
    arr: list[float], indexes: list[int] | None = None
) -> heuristicEntry:
    nsize = int(len(arr) / 2)
    return entryFrom2dList([list(arr[0:nsize]), list(arr[nsize:])], indexes)


def entryFrom2dList(
    arr: list[list[float]], indexes: list[int] | None = None
) -> heuristicEntry:
    assert len(arr) == 2
    ret = heuristicEntry(
        weights=[
            texelW.texelWeightsFromFlatLists(arr[0], indexes),
            texelW.texelWeightsFromFlatLists(arr[1], indexes),
        ]
    )
    return ret


def entryFromTexelWeights(w: texelWeights) -> heuristicEntry:
    ret: heuristicEntry = heuristicEntry(weights=[w.copy(), w.copy()])
    return ret


class phaseE(Enum):
    MG = 0
    EG = 1
    ALL = 2


def entryFromWinfoFile(path: str) -> heuristicEntry:
    assert os.path.exists(path)
    ret = heuristicEntry(weights=[texelWeights(), texelWeights()])
    with open(path, "r") as file:
        for line in file.readlines():
            _line = line.rstrip().lower()
            if "mg" in _line:
                token = phaseE.MG
            elif "eg" in _line:
                token = phaseE.EG
            else:
                token = phaseE.ALL

            found: bool = False
            for i in range(len(cst.strWeightNames)):
                s = cst.strWeightNames[i]
                if _line.startswith(s.lower()):
                    found = True
                    val = utilsl.strExtractFromBounds(s=_line, lbound="=", rbound=";")
                    if not len(val):
                        continue

                    ret.pushArray(val=[float(val)], idx=cst.allIndexes[i], phase=token)
                    break
            if found:
                continue

            for i in range(len(cst.strPQSTNames)):
                s = cst.strPQSTNames[i]
                if _line.startswith(s.lower()):
                    if "[" in _line:
                        _str = utilsl.strExtractFromBounds(
                            s=_line, lbound="[", rbound="]"
                        )
                        if not len(_str):
                            continue
                        val = [float(x) for x in _str.split(",")]

                        ret.pushArray(
                            val=val,
                            idx=cst.allIndexes[i + cst.PSQT_Pawn_idx],
                            phase=token,
                        )

    return ret


@dataclass
class chessIndividual(object):
    position: heuristicEntry
    uid: int
    scoring: score


weight_ext = ".winfo"


class callbackSave(template.callback):
    """ """

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
        if self.mh.objective is not None:
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
            if len(iterList) != 0:
                savingDict["populationHistory"].append(iterBuffer)

        # print(f"Saving dict {savingDict} to file: {path}")

        with open(path, "w") as file:
            yaml.dump(savingDict, file)


class callbackHealthCheck(template.callback):
    """ """

    def __init__(self):
        super().__init__()
        self.STD_THRESHOLD = 5
        self.POP_THRESHOLD = 0.5

    def on_iter_start(self):
        assert self.mh is not None
        assert self.mh.objective is not None
        poses = np.array(self.mh.getCurrentPositions())
        stds = poses.std(axis=0)
        mask: npt.NDArray[np.bool] = stds < self.STD_THRESHOLD
        nDimReq = mask.sum()
        if nDimReq == 0:
            return

        pop = sorted(self.mh.population, key=lambda x: x.score)
        # first elem is the lowest score

        for idx in range(int(self.mh.popsize * self.POP_THRESHOLD)):
            pop[idx].position[mask] = self.mh.generateRandArray()[mask]
            pop[idx].score = (
                float("-inf") if self.mh.objective.maximize else float("inf")
            )


# https://www.chessprogramming.org/Match_Statistics#cite_note-26
def computeLOS(wins: int, losses: int):
    if (wins + losses) == 0:
        return 0
    return 0.5 * (1 + math.erf((wins - losses) / math.sqrt(2 * wins + 2 * losses)))


def LL(x: int) -> float:
    """
    https://www.chessprogramming.org/Match_Statistics#cite_note-26
        E = 1 / ( 1 + 10-Δ/400)
    """
    return 1 / (1 + 10 ** (-x / 400))


def LLR(elo_0: int, elo_1, wins: int, draws: int, losses: int) -> float:
    """
    s0 = LL(elo0)
    s1 = LL(elo1)
    LLR ~= 0.5 * (( s1 - s0 ) * (2 * score - s0 - s1)) / (Var(score))
    where Var(score) = (-score**2 + (draws * 0.5**2 + wins * 1**2)) / N
    where N = wins + draws + losses
    """
    if wins == 0 or draws == 0:
        return 0.0
    N = wins + draws + losses
    n_wins, n_draws = wins / N, draws / N
    score = n_wins + 0.5 * n_draws
    varScore = ((n_wins + n_draws * 0.25) - (score**2)) / N
    s0 = LL(elo_0)
    s1 = LL(elo_1)
    return 0.5 * ((s1 - s0) * (2 * score - s0 - s1)) / (varScore)


def computeSPRT(
    elo_0: int, elo_1: int, alpha: int, beta: int, wins: int, draws: int, losses: int
) -> SPRT_result:
    """
    elo_0, elo_1 elo bound to check gain in elo
    might be nice elo_0 = 0, 10 for mh thingy

    https://www.chessprogramming.org/Sequential_Probability_Ratio_Test
    alpha, beta default 0.05 both?

    H0 : Elo_Player1 ≤ Elo_Player2
    H1 : Elo_Player1 > Elo_Player2

    """
    llr = LLR(elo_0, elo_1, wins, draws, losses)
    LA = math.log(beta / (1 - alpha))
    LB = math.log((1 - beta) / (alpha))
    if llr > LB:
        return SPRT_result.H1
    if llr < LA:
        return SPRT_result.H0
    return SPRT_result.NULL


class SPRT_result(Enum):
    H0 = 1
    H1 = 2
    NULL = 3

    def __repr__(self) -> str:
        self_name = self.__class__.__name__
        return f"{self_name}.{self.name}"


# p , n, b, r, q
simplePieceCount: list[float] = [100, 300, 300, 500, 900]

# simpleBaselineWeights: list[float] = [-1.0, 2.0, -1.0, 20.0, 20.0, 40.0, 80.0, 1.0, 5.0]

prevIndexes = [
    cst.mobility_idx,
    cst.structureProtection_idx,
    cst.isolatedPawnScore_idx,
    cst.stackedPawnScore_idx,
    cst.passedPawnScore_idx,
    cst.safetyKnight_idx,
    cst.safetyBishop_idx,
    cst.safetyRook_idx,
    cst.safetyQueen_idx,
]
currentIndexes = list(range(cst.mobility_idx, cst.safetyQueen_idx + 1))
currentIndexes.remove(cst.safetyPawn_idx)
defaultWeights: heuristicEntry = entryFromListDup(
    arr=[5, 10, 1, 1, 1, 2, 25, 20, 20, 40, 80], indexes=currentIndexes
)

newIndexes = list(range(cst.mobility_idx, cst.kingProximityScore_idx + 1))
newIndexes.remove(cst.safetyPawn_idx)
# cst.INVALID_VALUE, #pawn safety is not used

simpleBaselineWeights: heuristicEntry = entryFromListDup(
    arr=[-1.0, 2.0, -1.0, 20.0, 20.0, 40.0, 80.0, 1.0, 5.0],
    indexes=prevIndexes,
)


# obtained after 14 iter and 8 popsize
newWeight_0: heuristicEntry = entryFromListDup(
    arr=[0.0, -3.0, 100.0, -3.0, 18.0, -0.0, 87.0, 20.0, 11.0], indexes=prevIndexes
)
newWeight_0_bis: list[float] = [1.0, 3.0, 95.0, -3.0, 18.0, -0.0, 87.0, 20.0, 11.0]

newWeight_1: heuristicEntry = entryFrom2dList(
    arr=[
        [10.0, 100.0, 9.0, 32.0, 38.0, 100.0, -2.0, 2.0, 42.0],
        [-2.0, 100.0, 67.0, -2.0, 100.0, 32.0, 20.0, 100.0, -2.0],
    ],
    indexes=prevIndexes,
)
