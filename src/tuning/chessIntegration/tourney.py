from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

import threading
import subprocess
import os, time, sys

import yaml
import numpy as np
import numpy.typing as npt

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from algo import objective as obj
from algo import gw, DE

from algo.template import (
    individual,
    saveOptions,
    templateSelectionAlgo,
    optimizerOption,
)
from algo import template

sys.path.append(os.path.dirname(__file__))
from chessSpec import heuristicEntry, score, chessIndividual
import chessSpec
import tournament as tournamentl
from tournament import timeFormat, tournamentType, tournament

import texelW
import constants as cstsl

import gui as guil
import utils as utilsl

import lock as lockl

SLEEP_STDOUT_S = 1


class windowIndex(Enum):
    TITLE = 0
    LAST_UPDATE = 1
    TOURNEY = 2
    MH_BEST_INDIV = 3
    MH_HEALTH_METRICS = 4
    PROGRESSBAR = 5


class tuiGUI:
    gui = guil.windowCtx()
    useCurses: bool = True
    l: lockl.lock = lockl.lock()
    scoreB: tournamentl.scoreBoard = tournamentl.scoreBoard()
    mh: templateSelectionAlgo | None = None

    running: bool = False
    tickUpdate: bool = False
    roundUpdate: bool = False

    debugMode: bool = False
    sw: tournamentl.stopwatch = tournamentl.stopwatch()
    mainThread: threading.Thread | None = None
    interruptReceived: bool = False
    windows: list[guil.windowComponent] = []
    tick: int = 0

    def __init__(self, debugMode: bool = False, useCurses: bool = True) -> None:
        self.debugMode = debugMode
        self.useCurses = useCurses
        # title
        self.windows.append(guil.windowComponent(offset=[0, 2], size=[2, 0]))

        # last update
        self.windows.append(guil.windowComponent(offset=[0, 104], size=[0, 0]))

        # tourney
        self.windows.append(guil.windowComponent(offset=[10, 0], size=[0, 0]))

        # MH best indiv
        self.windows.append(guil.windowComponent(offset=[10, 50], size=[0, 0]))

        # MH health markers
        self.windows.append(guil.windowComponent(offset=[10, 96], size=[0, 0]))

        # progress bar
        self.windows.append(guil.windowComponent(offset=[30, 0], size=[2, 64]))

    def shouldClose(self) -> bool:
        return self.interruptReceived

    def setScoreBoard(self, sb: tournamentl.scoreBoard) -> None:
        self.scoreB = sb

    def setMH(self, mh: templateSelectionAlgo) -> None:
        self.mh = mh

    def dispatch(self) -> None:
        if self.useCurses:
            self.gui = guil.setupWindow()
            self.gui.stdscr.nodelay(True)
        self.mainThread = threading.Thread(target=self.start, args=([]))
        self.running = True
        self.mainThread.start()

    def start(self) -> None:
        self.running = True
        self.sw.start()
        self.pingTickUpdate()
        while self.running:
            try:
                # mainly used to handle the case where the terminal is resized
                self.updateWindow()
            except Exception as e:
                self.l.release()
                print(f"Exception raised in update method {e}")
            time.sleep(SLEEP_STDOUT_S)
            self.pingTickUpdate()

            if self.useCurses:
                c = self.gui.stdscr.getch()
                if c == ord("q"):
                    print("INTERRUPT RECEIVED")
                    self.interruptReceived = True
                    global_tui.close()
                    self.mh.objective.tourney.running = False
            self.tick += 1

    def pingTickUpdate(self) -> None:
        self.l.acquire()
        self.tickUpdate = True
        self.l.release()

    def pingRoundUpdate(self) -> None:
        self.l.acquire()
        self.roundUpdate = True
        self.l.release()

    def close(self) -> None:
        # clean up the necessary things
        self.running = False
        guil.restoreWindow(self.gui)

    def updateWindow(self) -> None:
        self.l.acquire()
        if not self.useCurses:
            if not self.tickUpdate or not self.running:
                self.l.release()
                return
            self.tickUpdate = False
            self.liteUpdateWindow()
            self.l.release()
            return

        guil.loadingSymbolWindow(self.gui.stdscr, self.tick)
        if (not self.tickUpdate and not self.roundUpdate) or not self.running:
            if self.debugMode:
                pass
            self.l.release()
            return
        if self.tickUpdate:
            self.updateProgress()

        if self.roundUpdate:
            self.updateMHWindow()
            self.settingsWindow()

        self.tickUpdate = False
        self.roundUpdate = False
        self.lastUpdatedWin()
        self.l.release()

    def liteUpdateWindow(self) -> None:
        clear()
        assert self.mh is not None
        assert type(self.mh.objective) is chessObjective
        assert self.mh.objective.tourney.settings is not None
        indexes = self.mh.objective.indexesTemplate
        best_indiv = chessSpec.entryFrom1dArray(
            self.mh.population[0].position, indexes=indexes
        )
        print(f"Iteration: {self.mh.iter} / {self.mh.maxiter}")

        if self.mh.objective.tourney.type == tournamentType.LOS:
            totalMatch = (
                self.mh.objective.tourney.settings.matchSettings.nMatch
                * 2
                * len(self.mh.objective.baseline)
            )
            print(
                f"Current best score = {self.mh.population[0].score}, total LOS = {self.mh.population[0].score / totalMatch}, total match: {totalMatch}"
            )
        else:
            print(f"Current best score = {self.mh.population[0].score}")

        for x, idx in enumerate(indexes):
            assert best_indiv.weights[0].elem[x].val is not None
            assert best_indiv.weights[1].elem[x].val is not None
            param = f"{cstsl.strWeightNames[idx]}: {best_indiv.weights[0].elem[x].val[0]}, {best_indiv.weights[1].elem[x].val[0]}"

            print(f"{param}")

        print(
            f"Progress {self.scoreB.nFinished} / {self.scoreB.nMatch} with {self.scoreB.nRunning} running"
        )

        print(
            f"Tournament info nMatch = {self.mh.objective.tourney.settings.matchSettings.nMatch}, nBaselines = {len(self.mh.objective.baseline)}"
        )

    def lastUpdatedWin(self) -> None:
        assert self.gui.active
        guil.lastUpdateWindow(
            self.gui.stdscr, self.sw, self.windows[windowIndex.LAST_UPDATE.value]
        )

    def settingsWindow(self) -> None:
        if self.mh is None:
            return
        assert type(self.mh.objective) is chessObjective
        tourney = self.mh.objective.tourney
        assert tourney.settings is not None
        txt: list[str] = []
        txt.append(f"Number of matches: {tourney.settings.matchSettings.nMatch}")
        txt.append(f"Tournament type: {tourney.type}")
        if tourney.type.useBaselines():
            txt.append(f"Number of baseline: {len(self.mh.objective.baseline)}")
            if tourney.timeFormat is not None:
                txt.append(
                    f"Time format: {tourney.timeFormat.time} ms + {tourney.timeFormat.inc} "
                )
            if tourney.type == tournamentType.LOS:
                pass
        self.gui.standardWindow(
            txt,
            win=self.windows[windowIndex.TOURNEY.value],
            winTitle="Tournament settings: ",
        )

    def updateMHWindow(self) -> None:
        assert self.gui.active
        if self.mh is None:
            return
        # 3 windows
        # title bar, best indiv, mh health markers
        self.gui.mainWindow(self.mh, self.windows[windowIndex.TITLE.value])

        self.gui.mhBestIndiv(self.mh, self.windows[windowIndex.MH_BEST_INDIV.value])
        self.gui.mhHealthMarkers(
            self.mh, self.windows[windowIndex.MH_HEALTH_METRICS.value]
        )

    def updateProgress(self) -> None:
        if self.scoreB.nMatch != 0:
            self.gui.progressBar(
                nFinished=self.scoreB.nFinished,
                nMatch=self.scoreB.nMatch,
                nRunning=self.scoreB.nRunning,
                win=self.windows[windowIndex.PROGRESSBAR.value],
            )

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.debugMode:
            print("__exit__ invoked")
        if self.running:
            self.running = False
            self.close()
        guil.restoreWindow(self.gui)


def saveHeuristicsWeights(
    entries: list[heuristicEntry], directory: str, uid: int, extra: str
) -> list[str]:
    os.makedirs(directory, exist_ok=True)
    ret: list[str] = []
    for i in range(len(entries)):
        path = os.path.join(directory, f"{uid}_{i}_{extra}.winfo")
        entries[i].saveToFile(path)
        ret.append(path)
    return ret


global_scoreBoard = tournamentl.scoreBoard()
global_tui: tuiGUI = tuiGUI(debugMode=True, useCurses=True)
global_tui.setScoreBoard(global_scoreBoard)


class chessObjective(obj.objective):
    def __init__(self, tourney: tournament, baselineLimit: int = -1, **parentKwargs):
        self.tourney = tourney
        super().__init__(**parentKwargs)
        self.baseline: list[heuristicEntry] = []
        self.indexesTemplate: list[int] = []
        self.baselineLimit = baselineLimit

    def _evaluate(
        self,
        positions: list[npt.NDArray[np.float64]]
        | npt.NDArray[np.float64]
        | list[list[float]],
    ) -> list[float]:

        assert len(self.indexesTemplate) != 0, (
            "Indexes is empty, cannot relate MH position to engine parameter"
        )
        assert self.tourney.settings is not None
        if self.tourney.debugMode:
            print(
                f"Evaluating {len(positions)} positions with {len(self.baseline)} baselines..."
            )

        global_tui.pingRoundUpdate()
        matchInv: tournamentl.matchContainerInfo = tournamentl.matchContainerInfo(
            len(positions), popBase=len(self.baseline), type=self.tourney.type
        )
        entries: list[heuristicEntry] = []
        for i in range(len(positions)):
            entries.append(
                chessSpec.entryFrom1dArray(
                    np.array(positions[i]), indexes=self.indexesTemplate
                )
            )

        pop = saveHeuristicsWeights(
            entries=entries,
            directory=self.tourney.logDir,
            uid=int(time.time()),
            extra="pop",
        )
        baselines = saveHeuristicsWeights(
            entries=self.baseline,
            directory=self.tourney.logDir,
            uid=int(time.time()),
            extra="baseline",
        )

        setting = tournamentl.readInfoFile(self.tourney.templatePath)
        assert len(setting.engineSettings) != 0
        eng = setting.engineSettings[0]
        self.tourney.setPopulation(eng.copyAppendHeuristicWeightOption(pop))
        self.tourney.setBaseline(eng.copyAppendHeuristicWeightOption(baselines))

        global_tui.setScoreBoard(self.tourney.scoreBoard)
        self.tourney.startTournament(matchInv)

        allFiles = pop + baselines
        for f in allFiles:
            try:
                os.remove(f)
            except Exception as e:
                print(f"Caught exception {e} while trying to remove file {f}")
                continue

        if self.tourney.type == tournamentType.LOS:
            ret = [
                chessSpec.computeLOS(wins=x.win, losses=x.lose) * x.nMatch()
                for x in self.tourney.scoreBoard.scores
            ]

            return ret
        return [x.getScore() for x in self.tourney.scoreBoard.scores]

    def setIndexesTemplate(self, idx: list[int]) -> None:
        assert len(idx) == int((self.nDims) / 2), (
            f"Length of the template indexes ({len(idx)}) does not match the number of dimension of this objective ({self.nDims})"
        )
        self.indexesTemplate = idx

    def setBaseline(self, entry: heuristicEntry) -> None:
        self.baseline = [entry]

    def appendBaseline(self, entry: heuristicEntry) -> None:
        if len(self.baseline) == self.baselineLimit:
            self.baseline.pop(0)
            assert self.tourney.settings is not None
            self.tourney.settings.matchSettings.nMatch += 1
        self.baseline.append(entry)

    def _saveToFile(self, log: dict) -> None:
        log["baseline"] = []
        for base in self.baseline:
            ret = [[], []]
            for x, p_w in enumerate(base.weights):
                for w in p_w.elem:
                    assert w.val is not None
                    ret[x].append([w.idx, list(w.val)])
            log["baseline"].append(ret)

        log["tournament"] = self.tourney.saveArgsToDict()
        log["baselineLimit"] = self.baselineLimit
        if self.indexesTemplate != []:
            log["indexesTemplate"] = self.indexesTemplate

    def _loadFromFile(self, config: dict, pathPrepend: str = "") -> None:
        if config.get("baseline") is not None:
            self.baseline = []
            assert type(config["baseline"]) is list
            for e in config["baseline"]:
                assert len(e) == 2, (
                    f"Expected 2 phases in the loaded config file found: {len(e)}"
                )

                self.baseline.append(
                    chessSpec.heuristicEntry(
                        weights=[
                            texelW.texelWeightsFromFlatWeights(e[0]),
                            texelW.texelWeightsFromFlatWeights(e[1]),
                        ]
                    )
                )
        if config.get("tournament") is not None:
            self.tourney = tournamentl.tournamentFromConfigFile(
                config["tournament"], pathPrepend=pathPrepend
            )

        if config.get("indexesTemplate") is not None:
            self.indexesTemplate = config["indexesTemplate"]
        self.baselineLimit = config.get("baselineLimit", -1)


def objectiveFromConfigFile(path: str, pathPrepend: str = "") -> chessObjective:
    assert os.path.exists(path)
    with open(path, "r") as file:
        config = yaml.safe_load(file)
        assert config.get("objective") is not None
        objConfig = config["objective"]
        assert objConfig.get("tournament") is not None
        ret = chessObjective(
            tourney=tournament(),
            maximize=objConfig["maximize"],
            bounds=objConfig["bounds"],
            steps=objConfig["steps"],
        )
        ret._loadFromFile(objConfig, pathPrepend=pathPrepend)
        return ret


UPPER_BOUND_WEIGHT = 100
LOWER_BOUND_WEIGHT = 0
STEP_WEIGTH = 1
N_PARAMS = 2 * len(chessSpec.newIndexes)


def clear() -> None:
    print("\x1b[2J\x1b[H", end="\r")


class guiUpdateCallback(template.callback):
    def __init__(self):
        super().__init__()

    def on_eval(
        self,
        positions: list[npt.NDArray[np.float64]]
        | npt.NDArray[np.float64]
        | list[list[float]],
    ):
        assert self.mh is not None
        _ = positions
        global_tui.pingTickUpdate()


class callbackBaseline(template.callback):
    def __init__(self):
        super().__init__()
        self.LOS_FRAC_THRESH = 0.92

    def on_iter_end(self):
        assert self.mh is not None
        assert self.mh.objective is not None
        assert type(self.mh.objective) is chessObjective
        assert self.mh.objective.tourney.settings is not None
        if self.mh.objective.tourney.type == tournamentType.BASELINE:
            best = self.mh.getBestIndiv()
            nBaseline = len(self.mh.objective.baseline)
            if best.score == nBaseline * 2:
                self.mh.objective.appendBaseline(
                    chessSpec.entryFrom1dArray(
                        best.position, indexes=self.mh.objective.indexesTemplate
                    )
                )
        elif self.mh.objective.tourney.type == tournamentType.LOS:
            best = self.mh.getBestIndiv()
            if (
                best.score
                / (
                    self.mh.objective.tourney.settings.matchSettings.nMatch
                    * 2
                    * len(self.mh.objective.baseline)
                )
            ) > self.LOS_FRAC_THRESH:
                self.mh.objective.appendBaseline(
                    chessSpec.entryFrom1dArray(
                        best.position, indexes=self.mh.objective.indexesTemplate
                    )
                )


@dataclass
class mhUserInput:
    maxiter: int = 0
    popsize: int = 0
    lowerBound: int = LOWER_BOUND_WEIGHT
    upperBound: int = UPPER_BOUND_WEIGHT

    preEvaluation: bool = True
    seed: int = 42
    variant: str = "gw"
    variantParameters: dict | None = None
    optimOpt: optimizerOption = optimizerOption()

    def __repr__(self) -> str:
        ret = "{"
        for i, (k, v) in enumerate(self.__dict__.items()):
            ret += f"{k}: {v}"
            if i != len(self.__dict__) - 1:
                ret += ",\n"
        ret += "}"
        return f"{ret}"

    def fromDict(self, d: dict) -> None:
        for _str in self.__dataclass_fields__.keys():
            new_val = d.get(f"{_str}", self.__dict__[_str])
            if new_val is not None and self.__dict__[_str] is not None:
                assert type(new_val) is type(self.__dict__[_str])
            self.__dict__[_str] = new_val

        if d.get("optimizerOpt"):
            self.optimOpt.useGreedy = d["optimizerOpt"].get(
                "useGreedy", self.optimOpt.useGreedy
            )
            self.optimOpt.debugMode = d["optimizerOpt"].get(
                "debugMode", self.optimOpt.debugMode
            )
            self.optimOpt.preEval = d["optimizerOpt"].get(
                "preEval", self.optimOpt.preEval
            )


@dataclass
class pathsUserInput:
    infoTemplate: str | None = None
    tmpFolder: str | None = None
    resultFolder: str | None = None
    evaluatorBinaryPath: str | None = None
    tournamentBaselinePaths: list[str] | None = None
    metaHeuristicExtraIndividuals: list[str] | None = None

    def __repr__(self) -> str:
        ret = "{"
        for i, (k, v) in enumerate(self.__dict__.items()):
            ret += f"{k}: {v}"
            if i != len(self.__dict__) - 1:
                ret += ",\n"
        ret += "}"
        return f"{ret}"

    def fromDict(self, d: dict) -> None:
        for _str in self.__dataclass_fields__.keys():
            new_val = d.get(f"{_str}", self.__dict__[_str])
            if new_val is not None and self.__dict__[_str] is not None:
                assert type(new_val) is type(self.__dict__[_str])
            self.__dict__[_str] = new_val


@dataclass
class tournamentUserInput:
    timeF: timeFormat | None = None  # defaults to the template timeFormat
    nThreads: int = 1
    tourneyT: tournamentType = tournamentType.LOS
    baselineLimit: int = 4
    deleteTmp: bool = True

    def __repr__(self) -> str:
        ret = "{"
        for i, (k, v) in enumerate(self.__dict__.items()):
            ret += f"{k}: {v}"
            if i != len(self.__dict__) - 1:
                ret += ",\n"
        ret += "}"
        return f"{ret}"

    def fromDict(self, d: dict) -> None:
        for _str in self.__dataclass_fields__.keys():
            if _str == "timeF":
                token = d.get(f"timeFormat", self.__dict__[_str])
                if not token:
                    self.timeF = None
                else:
                    assert type(token) is str
                    vals = token.split(",")
                    assert len(vals) == 2
                    self.timeF = timeFormat(time=int(vals[0]), inc=int(vals[1]))
            elif _str == "tournamentType":
                token = d.get(f"tournamentType", self.tourneyT.name)
                self.tourneyT = tournamentl.strToTournamentType(token)
            else:
                new_val = d.get(f"{_str}", self.__dict__[_str])
                if new_val is not None and self.__dict__[_str] is not None:
                    assert type(new_val) is type(self.__dict__[_str])
                self.__dict__[_str] = new_val


@dataclass
class userInput:
    paths: pathsUserInput = pathsUserInput()
    mhParams: mhUserInput = mhUserInput()
    tournamentParams: tournamentUserInput = tournamentUserInput()

    def __repr__(self) -> str:
        return f"paths: {str(self.paths)}\n\nmhParams: {str(self.mhParams)}\n\nournamentParams: {str(self.tournamentParams)}"


def readUserYamlInput(path: str, pathToRoot: str = "") -> userInput:
    assert os.path.exists(path)
    ret: userInput = userInput()
    with open(path, "r") as f:
        vals = yaml.safe_load(f)
    panic = False
    if vals.get("mh"):
        ret.mhParams.fromDict(vals["mh"])
    else:
        print("[PANIC] missing 'mh' section")
        panic = True

    if vals.get("tournament"):
        ret.tournamentParams.fromDict(vals["tournament"])
    else:
        print("[PANIC] missing 'tournament' section")
        panic = True

    if vals.get("paths"):
        ret.paths.fromDict(vals["paths"])
        for k, v in ret.paths.__dict__.items():
            if v is not None:
                if type(v) is str:
                    ret.paths.__dict__[k] = os.path.join(pathToRoot, v)
                elif type(v) is list:
                    ret.paths.__dict__[k] = [
                        os.path.join(pathToRoot, x) for x in v if x is not None
                    ]
                else:
                    print(f"[PANIC] unknown type {type(v)} found  in path joining")
                    panic = True

    else:
        print("[PANIC] missing 'paths' section")
        panic = True
    if panic:
        assert False, (
            f"Missing sections encountered during userInput gathering of path: {path}"
        )
    return ret


def makeMHFromUserInput(userInp: userInput) -> templateSelectionAlgo:

    assert userInp.paths.tmpFolder is not None
    saveOpt: saveOptions = saveOptions(
        logDir=userInp.paths.tmpFolder,
        prefix="result",
        saveLog=True,
        resDir=userInp.paths.resultFolder,
    )
    optimOpt: optimizerOption = optimizerOption(
        useGreedy=userInp.mhParams.optimOpt.useGreedy,
        preEval=userInp.mhParams.optimOpt.preEval,
        debugMode=userInp.mhParams.optimOpt.debugMode,
    )
    mhName = userInp.mhParams.variant.lower()
    if mhName == "gw" or mhName == "gwo":
        mhConstructor = gw.GW
    elif mhName == "de":
        mhConstructor = DE.DE
    else:
        assert False, f"unknown mh name token {mhName}"
    varKwargs = (
        {}
        if userInp.mhParams.variantParameters is None
        else userInp.mhParams.variantParameters
    )
    ret = mhConstructor(
        popsize=userInp.mhParams.popsize,
        maxiter=userInp.mhParams.maxiter,
        saveOpt=saveOpt,
        optimOpt=optimOpt,
        cbs=[],
        **varKwargs,
    )

    tourn = tournament(
        timeF=userInp.tournamentParams.timeF,
        templatePath=userInp.paths.infoTemplate,
        evalBin=userInp.paths.evaluatorBinaryPath,
        debugMode=False,
        deleteTmp=userInp.tournamentParams.deleteTmp,
        logDir=os.path.join(userInp.paths.tmpFolder, f"tmp_{int(time.time())}"),
        nThreads=userInp.tournamentParams.nThreads,
        type=userInp.tournamentParams.tourneyT,
    )

    ret.setObjective(
        chessObjective(
            maximize=True,
            tourney=tourn,
            bounds=obj.dummyBounds(
                lbound=userInp.mhParams.lowerBound,
                rbound=userInp.mhParams.upperBound,
                nDim=N_PARAMS,
            ),
            steps=obj.dummyStep(STEP_WEIGTH, nDim=N_PARAMS),
            baselineLimit=userInp.tournamentParams.baselineLimit,
        )
    )
    assert type(ret.objective) is chessObjective
    ret.objective.setIndexesTemplate(chessSpec.newIndexes)
    if type(userInp.paths.tournamentBaselinePaths) is list:
        for path in userInp.paths.tournamentBaselinePaths:
            if type(path) is not str:
                continue
            ret.objective.appendBaseline(chessSpec.entryFromWinfoFile(path))

    else:
        if userInp.tournamentParams.tourneyT.useBaselines:
            if (
                userInp.paths.tournamentBaselinePaths is None
                or (userInp.paths.tournamentBaselinePaths) == 0
            ):
                assert False, (
                    "Tournament declared uses baselines but no baseline was given"
                )

    ret.generatePopulation()

    if userInp.paths.metaHeuristicExtraIndividuals is not None:
        for path in userInp.paths.metaHeuristicExtraIndividuals:
            if type(path) is not str:
                continue
            ret.addInvididual(
                indiv=individual(
                    chessSpec.entryFromWinfoFile(path)
                    .maskOut(indexes=chessSpec.newIndexes, defaultValue=0)
                    .get1DArray()
                )
            )
    return ret


def launch_mh(mh: templateSelectionAlgo) -> None:
    assert type(mh.objective) is chessObjective
    global_tui.dispatch()
    global_tui.setMH(mh)
    mh.addCallback(guiUpdateCallback())
    mh.addCallback(chessSpec.callbackHealthCheck())
    if mh.objective.tourney.type.useBaselines():
        mh.addCallback(callbackBaseline())

    mh.optimize()


if __name__ == "__main__":
    pass
