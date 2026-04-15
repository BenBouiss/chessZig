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
from algo import gw

from algo.template import individual, saveOptions, templateSelectionAlgo
from algo import template

sys.path.append(os.path.dirname(__file__))
from chessSpec import heuristicEntry, score, chessIndividual
import chessSpec
import texel
import gui as guil
import utils as utilsl


import lock as lockl

baseWeightPath = "engines/heuristics/baseOldWeights.info"

SLEEP_LOCK_S = 0.01
SLEEP_STDOUT_S = 1


@dataclass
class stopwatch:
    # carbon copy of the implementation found in time.zig
    started: bool = False
    startTime: float = 0.0
    savedTime: float = 0.0
    # in seconds

    def start(self) -> None:
        assert not self.started, "Stopwatch is already running"
        self.started = True
        self.startTime = time.time()

    def reset(self) -> None:
        self.started = False
        self.startTime = 0.0
        self.savedTime = 0.0

    def stop(self) -> None:
        self.started = False
        self.savedTime = time.time()

    def timeSinceStart(self) -> float:
        assert self.startTime != 0, "Stopwatch was never started"
        if self.started:
            return time.time() - self.startTime
        else:
            return self.savedTime


@dataclass
class roundStatus:
    nMatch: int = 0
    nFinished: int = 0
    nRunning: int = 0

    def __repr__(self) -> str:
        return f"{self.nFinished}  + {self.nRunning} running / {self.nMatch}"

    def isOver(self) -> bool:
        return self.nMatch == self.nFinished

    def reset(self) -> None:
        self.nMatch = 0
        self.nFinished = 0
        self.nRunning = 0


@dataclass
class scoreBoard:
    l: lockl.lock = lockl.lock()
    sw: stopwatch = stopwatch()
    roundStat: roundStatus = roundStatus()

    def updateScoreBoard(self, matchInv: matchContainerInfo) -> None:
        self.l.acquire()
        nRunning = 0
        nFinished = 0
        for j in range(len(matchInv.status)):
            match matchInv.status[j]:
                case matchStatus.DISPATCHED:
                    nRunning += 1
                case matchStatus.IN_PROGRESS:
                    nRunning += 1
                case matchStatus.FINISHED:
                    nFinished += 1
                case matchStatus.ERROR:
                    nFinished += 1
                case _:
                    pass
        self.roundStat.nFinished = nFinished
        self.roundStat.nRunning = nRunning

        self.l.release()


class tuiGUI:
    gui = guil.windowCtx()
    useCurses: bool = True
    l: lockl.lock = lockl.lock()
    scoreB: scoreBoard = scoreBoard()
    mh: templateSelectionAlgo | None = None

    running: bool = False
    needUpdate: bool = False
    debugMode: bool = False
    sw: stopwatch = stopwatch()
    mainThread: threading.Thread | None = None
    interruptReceived: bool = False
    tick: int = 0

    def __init__(self, debugMode: bool = False, useCurses: bool = True) -> None:
        self.debugMode = debugMode
        self.useCurses = useCurses

    def shouldClose(self) -> bool:
        return self.interruptReceived

    def setScoreBoard(self, sb: scoreBoard) -> None:
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
        self.pingUpdate()
        while self.running:
            try:
                # mainly used to handle the case where the terminal is resized
                self.updateWindow()
            except Exception as e:
                self.l.release()
                print(f"Exception raised in update method {e}")
            time.sleep(SLEEP_STDOUT_S)

            if self.useCurses:
                c = self.gui.stdscr.getch()
                if c == ord("q"):
                    print("INTERRUPT RECEIVED")
                    self.interruptReceived = True
                    global_tui.close()
            self.tick += 1

    def pingUpdate(self) -> None:
        self.l.acquire()
        self.needUpdate = True
        self.l.release()

    def close(self) -> None:
        # clean up the necessary things
        self.running = False
        guil.restoreWindow(self.gui)

    def updateWindow(self) -> None:
        self.l.acquire()
        if not self.useCurses:
            if not self.needUpdate or not self.running:
                self.l.release()
                return
            self.needUpdate = False
            self.liteUpdateWindow()
            self.l.release()
            return

        guil.loadingSymbolWindow(self.gui.stdscr, self.tick)
        if not self.needUpdate or not self.running:
            if self.debugMode:
                pass
            self.l.release()
            return
        self.needUpdate = False
        self.updateMHWindow()
        self.updateProgress()
        self.lastUpdatedWin()
        self.settingsWindow()
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
                * len(self.mh.objective.tourney.baseline)
            )
            print(
                f"Current best score = {self.mh.population[0].score}, total LOS = {self.mh.population[0].score / totalMatch}, total match: {totalMatch}"
            )
        else:
            print(f"Current best score = {self.mh.population[0].score}")

        for x, idx in enumerate(indexes):
            assert best_indiv.weights[0].elem[x].val is not None
            assert best_indiv.weights[1].elem[x].val is not None
            param = f"{texel.strWeightNames[idx]}: {best_indiv.weights[0].elem[x].val[0]}, {best_indiv.weights[1].elem[x].val[0]}"

            print(f"{param}")

        print(
            f"Progress {self.scoreB.roundStat.nFinished} / {self.scoreB.roundStat.nMatch} with {self.scoreB.roundStat.nRunning} running"
        )

        print(
            f"Tournament info nMatch = {self.mh.objective.tourney.settings.matchSettings.nMatch}, nBaselines = {len(self.mh.objective.tourney.baseline)}"
        )

    def lastUpdatedWin(self) -> None:
        assert self.gui.active
        guil.lastUpdateWindow(self.gui.stdscr, self.sw)

    def settingsWindow(self) -> None:
        if self.mh is None:
            return
        assert type(self.mh.objective) is chessObjective
        tourney = self.mh.objective.tourney
        assert tourney.settings is not None
        txt: list[str] = []
        txt.append(f"Tournament settings: ")
        txt.append(f"Number of matches: {tourney.settings.matchSettings.nMatch}")
        txt.append(f"Tournament type: {tourney.type}")
        if tourney.type.useBaselines():
            txt.append(f"Number of baseline: {len(tourney.baseline)}")
            if tourney.timeFormat is not None:
                txt.append(
                    f"Time format: {tourney.timeFormat.time} ms + {tourney.timeFormat.inc} "
                )
            if tourney.type == tournamentType.LOS:
                pass
        self.gui.settingsWindow(txt)

    def updateMHWindow(self) -> None:
        assert self.gui.active
        if self.mh is None:
            return
        self.gui.mainWindow(self.mh)
        self.gui.onTournamentBegin(self.mh)
        self.gui.mhHealthMarkers(self.mh)

    def updateProgress(self) -> None:
        if self.scoreB.roundStat.nMatch != 0:
            self.gui.onMatchEnd(
                nFinished=self.scoreB.roundStat.nFinished,
                nMatch=self.scoreB.roundStat.nMatch,
                nRunning=self.scoreB.roundStat.nRunning,
            )

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.debugMode:
            print("__exit__ invoked")
        if self.running:
            self.running = False
            self.close()
        guil.restoreWindow(self.gui)

    # def __del__(self):
    #    if self.debugMode:
    #        print("__del__ invoked")
    #    if self.running:
    #        self.running = False
    #        self.close()
    #    guil.restoreWindow(self.gui)


@dataclass
class timeFormat:
    # times in ms
    time: int
    inc: int


standardTimeFormat = timeFormat(time=300_000, inc=5000)
blitzTimeFormat = timeFormat(time=300_000, inc=0)
hyperBulletTimeFormat = timeFormat(time=10_000, inc=0)


@dataclass
class matchInfoSettings:
    nMatch: int = 1
    playerSwitch: bool = False
    debugMode: bool = False
    useOpeningBook: bool = False
    openingBookPath: str = ""
    timeF: timeFormat = hyperBulletTimeFormat
    saveLogs: bool = True
    logsLocation: str = "out/logs"

    def __repr__(self) -> str:
        ret = ""
        ret += f"nMatch={self.nMatch};\n"
        ret += f"playerSwitch={self.playerSwitch};\n"
        ret += f"debugMode={self.debugMode};\n"
        ret += f"useOpeningBook={self.useOpeningBook};\n"
        ret += f"openingBookPath={self.openingBookPath};\n"
        ret += f"timeFormat=({self.timeF.time}, {self.timeF.inc});\n"
        ret += f"saveLogs={self.saveLogs};\n"
        ret += f"logsLocation={self.logsLocation};\n"
        return ret


@dataclass
class infoFile:
    engineSettings: list[list[str]]
    engineNames: list[str]
    matchSettings: matchInfoSettings

    def print(self) -> None:
        print("engine settings: ")
        for i in range(len(self.engineSettings)):
            print(self.engineNames[i])
            print(self.engineSettings[i])

        print("match settings: ")
        print(self.matchSettings)

    def setTimeFormat(self, timeF: timeFormat | None) -> None:
        if timeF is None:
            return
        self.matchSettings.timeF = timeF


def readInfoFile(path: str) -> infoFile:
    ret = infoFile([[]], [], matchInfoSettings())
    matchSection: bool = False
    engineIndex = 0
    with open(path, "r") as file:
        for line in file.readlines():
            _line = line.rstrip()
            if not len(_line) or _line.startswith("//"):
                continue
            if _line.startswith("[match]"):
                matchSection = True
                continue
            if _line.startswith("["):
                ret.engineNames.append(_line)
                if len(ret.engineSettings[engineIndex]):
                    engineIndex += 1
                    ret.engineSettings.append([])
                continue
            if matchSection:
                readMatchSettingLine(ret.matchSettings, _line)
            else:
                ret.engineSettings[engineIndex].append(_line.rstrip())
    return ret


def readMatchSettingLine(setting: matchInfoSettings, line: str) -> None:
    _line = line.lower()
    if "nmatch" in _line:
        setting.nMatch = int(
            utilsl.strExtractFromBounds(s=_line, lbound="=", rbound=";")
        )
    elif "playerswitch" in _line:
        setting.playerSwitch = "true" in _line
    elif "debugmode" in _line:
        setting.debugMode = "true" in _line
    elif "useopeningbook" in _line:
        setting.useOpeningBook = "true" in _line
    elif "openingbookpath" in _line:
        setting.openingBookPath = utilsl.strExtractFromBounds(
            s=_line, lbound='"', rbound='"'
        )
    elif "timeformat" in _line:
        vals: str = utilsl.strExtractFromBounds(s=_line, lbound="(", rbound=")")
        tokens = vals.split(",")
        if (len(tokens)) == 2:
            setting.timeF = timeFormat(time=int(tokens[0]), inc=int(tokens[1]))
    elif "logslocation" in _line:
        setting.logsLocation = utilsl.strExtractFromBounds(
            s=_line, lbound='"', rbound='"'
        )
    elif "savelogs" in _line:
        setting.saveLogs = "true" in _line


def saveHeuristicsWeights(
    entries: list[heuristicEntry], directory: str, uid: int, extra: str
) -> list[str]:
    ret: list[str] = []
    for i in range(len(entries)):
        path = os.path.join(directory, f"{uid}_{i}_{extra}.winfo")
        entries[i].saveToFile(path)
        ret.append(path)
    return ret


class matchO(object):
    def __init__(
        self,
        conf1: heuristicEntry,
        conf2: heuristicEntry,
        settings: infoFile,
        debugMode: bool = False,
        extra: str = "",
    ):
        self.conf1: heuristicEntry = conf1
        self.conf2: heuristicEntry = conf2
        self.settings: infoFile = settings
        self.uid: int = int(1000 * time.time())
        self.debugMode: bool = debugMode
        self.extra: str = extra

    def generateFiles(self, tmpfolder: str) -> str:
        heuristics = saveHeuristicsWeights(
            [self.conf1, self.conf2],
            directory=tmpfolder,
            uid=self.uid,
            extra=self.extra,
        )
        newInfoPath = os.path.join(tmpfolder, f"newInfo_{self.uid}_{self.extra}.info")
        with open(newInfoPath, "w") as file:
            for i in range(len(self.settings.engineNames)):
                file.write(f"{self.settings.engineNames[i]}\n")
                allCmd = "\n".join(self.settings.engineSettings[i])
                file.write(f"{allCmd}\n")
                file.write(
                    f'"setoption name heuristicWeightsPath value {heuristics[i]}";\n'
                )
            file.write(f"[match]\n")
            file.write(f"{self.settings.matchSettings}")
            # allCmd = "\n".join(setting.matchSettings.raw)
            # file.write(f"{allCmd}\n")
        return newInfoPath


def launchAndWaitResults(
    m: matchO, evalPath: str, tmpFolder: str, info: threadInfo
) -> list[score]:
    ret: list[score] = []
    newInfo = m.generateFiles(tmpFolder)
    info.runningProc = subprocess.Popen(
        [evalPath, newInfo],
        stdin=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        text=True,
    )
    assert info.runningProc.stdout is not None
    for line in iter(info.runningProc.stdout.readline, ""):
        _line = line.rstrip()
        tokens = _line.split(" ")
        if m.debugMode:
            print(
                f"[DEBUG] from launchAndWaitResults: line found: '{line}' tokens: '{tokens}'\n"
            )
        if len(tokens) != 3:
            continue
        ret.append(score(win=int(tokens[0]), lose=int(tokens[1]), draw=int(tokens[2])))
    return ret


class matchStatus(Enum):
    PENDING = 1
    IN_PROGRESS = 2
    FINISHED = 3
    ERROR = 4
    DISPATCHED = 5


class tournamentType(Enum):
    CLASSIC = 1
    BASELINE = 2
    SPRT = 3
    LOS = 4
    INVALID = 5

    def useBaselines(self) -> bool:
        return (
            self.value == tournamentType.BASELINE.value
            or self.value == tournamentType.SPRT.value
            or self.value == tournamentType.LOS.value
        )

    def __repr__(self) -> str:
        self_name = self.__class__.__name__
        return f"{self_name}.{self.name}"


def valueToTournamentType(val: int) -> tournamentType:
    if val == tournamentType.CLASSIC.value:
        return tournamentType.CLASSIC
    if val == tournamentType.BASELINE.value:
        return tournamentType.BASELINE
    if val == tournamentType.SPRT.value:
        return tournamentType.SPRT
    if val == tournamentType.LOS.value:
        return tournamentType.LOS
    return tournamentType.INVALID


class matchFetchStatus(Enum):
    FOUND = 1
    EMPTY = 2


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
        for y in range(x + 1, len(indexes)):
            ret.append((x, y))
    return ret


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
    return ret


class matchContainerInfo(object):
    order: list[tuple[int, int]]
    status: list[matchStatus]
    l: lockl.lock = lockl.lock()

    def __init__(
        self,
        popsize: int,
        popBase: int = 0,
        type: tournamentType = tournamentType.CLASSIC,
    ):
        self.order = []
        self.status: list[matchStatus] = []
        self.popsize: int = popsize
        if type == tournamentType.CLASSIC:
            self.order.extend(scheduleMatches(popsize))
        else:
            self.order.extend(scheduleMatchesBaseline(popsize, popBase))

        for _ in range(len(self.order)):
            self.status.append(matchStatus.PENDING)
        self.lock = False

    def splitNThreads(self, nThread: int) -> list[list[int]]:
        # used to statically dispatch the matches amongst n threads
        assert nThread != 0
        ret: list[list[int]] = []
        n = len(self.order)
        sizeEach: int = int(n / nThread)
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

    def getMatch(self) -> matchFetchResult:
        self.l.acquire()
        for i in range(len(self.order)):
            if self.status[i] == matchStatus.PENDING:
                # or error here also to retry
                self.status[i] == matchStatus.DISPATCHED
                self.l.release()
                return matchFetchResult(
                    matchOrder=self.order[i], status=matchFetchStatus.FOUND, idx=i
                )

        self.l.release()
        return matchFetchResult(status=matchFetchStatus.EMPTY)


@dataclass
class matchFetchResult:
    matchOrder: tuple[int, int] = (0, 0)
    status: matchFetchStatus = matchFetchStatus.EMPTY
    idx: int = -1


class threadStatus(Enum):
    PENDING = 0
    RUNNING = 1
    CRASHED = 2
    FINISHED = 3


@dataclass
class threadInfo:
    status: threadStatus = threadStatus.PENDING
    interrupt: bool = False
    currentMatch: matchFetchResult = matchFetchResult()
    runningProc: subprocess.Popen | None = None


class tournament(object):
    def __init__(
        self,
        timeF: timeFormat | None = standardTimeFormat,
        templatePath: str | None = None,
        logDir: str = "",
        evalBin: str | None = None,
        debugMode: bool = False,
        nThread: int = 1,
        type: tournamentType = tournamentType.CLASSIC,
        useGUIWait: bool = True,
        baselineLimit: int = -1,
        pathPrepend: str = "",
    ):
        self.debugMode: bool = debugMode
        self.timeFormat: timeFormat | None = timeF
        self.type = type
        self.matchInv: matchContainerInfo = matchContainerInfo(1)
        if templatePath is not None:
            self.templatePath = os.path.join(pathPrepend, templatePath)
            if debugMode:
                print(self.templatePath)
            self.settings: infoFile | None = readInfoFile(self.templatePath)
            if self.timeFormat is None:
                self.timeFormat = self.settings.matchSettings.timeF
            else:
                self.settings.setTimeFormat(self.timeFormat)
        else:
            self.settings: infoFile | None = None

        self.population: list[chessIndividual] = []
        self.baseline: list[chessIndividual] = []
        self.evalBin: str | None = evalBin
        if debugMode:
            print("Building tournament with debug on")
        self.logDir: str = logDir
        self.setThread(nThread)
        self.logs: dict = {}
        self.useGUIWait = useGUIWait
        self.baselineLimit = baselineLimit

    def saveArgsToDict(self) -> dict:
        ret = {}
        ret["timeFormat"] = [self.timeFormat.time, self.timeFormat.inc]
        ret["templatePath"] = self.templatePath
        ret["logDir"] = self.logDir
        ret["evalBin"] = self.evalBin
        ret["debugMode"] = self.debugMode
        ret["nThread"] = self.nThread
        ret["type"] = self.type.value
        return ret

    def setThread(self, nThread: int) -> None:
        assert nThread > 0, f"Invalid(x <= 0) thread amount {nThread}"
        self.nThread = nThread

    def dispatchMatch(self, matchInfo: matchContainerInfo) -> None:
        self.matchInv = matchInfo
        workingThreads: list[threading.Thread] = []
        threadInfos: list[threadInfo] = []
        # for threadId, idx in enumerate(indexes):
        global_scoreBoard.updateScoreBoard(self.matchInv)
        global_tui.pingUpdate()
        for threadId in range(self.nThread):
            threadInfos.append(threadInfo())
            workingThreads.append(
                threading.Thread(
                    target=self.thread_dispatchMatch, args=([threadId, threadInfos[-1]])
                )
            )
            workingThreads[-1].start()
        if self.useGUIWait:
            GUIWaitLoop(self, workingThreads, threadInfos)
        else:
            for x in workingThreads:
                x.join()

        # check for the ERROR match and retry

    def thread_dispatchMatch(self, threadId: int, info: threadInfo) -> None:
        assert self.population is not None
        assert self.settings is not None
        assert self.evalBin is not None
        info.status = threadStatus.RUNNING
        while not info.interrupt:
            res = self.matchInv.getMatch()
            info.currentMatch = res

            if res.status == matchFetchStatus.EMPTY:
                break

            pair = res.matchOrder
            opp1 = self.population[pair[0]].position
            if self.type.useBaselines():
                opp2 = self.baseline[pair[1]].position
            else:
                opp2 = self.population[pair[1]].position

            self.matchInv.status[res.idx] = matchStatus.IN_PROGRESS

            global_scoreBoard.updateScoreBoard(self.matchInv)
            global_tui.pingUpdate()

            currentMatch: matchO = matchO(
                conf1=opp1,
                conf2=opp2,
                settings=self.settings,
                extra=f"T{threadId}",
                debugMode=self.debugMode,
            )

            scoreList = launchAndWaitResults(
                currentMatch, self.evalBin, self.logDir, info
            )

            if len(scoreList) == 0:
                self.matchInv.status[res.idx] = matchStatus.ERROR
            else:
                self.matchInv.status[res.idx] = matchStatus.FINISHED
                self.updateScore(pair=pair, score=scoreList)
            global_scoreBoard.updateScoreBoard(self.matchInv)
            global_tui.pingUpdate()

        info.status = threadStatus.FINISHED

    def updateScore(self, pair: tuple[int, int], score: list[score]) -> None:
        if self.debugMode:
            print(
                f"[DEBUG] from updateScore: pair: {pair}, score: {score} before adding pop: \n"
            )
            for i in range(len(self.population)):
                print(
                    f"[DEBUG] \t {self.population[i].scoring}, id: {self.population[i].uid}\n"
                )
        self.population[pair[0]].scoring.addEq(score[0])
        if not self.type.useBaselines():
            if self.debugMode:
                print(
                    f"[DEBUG] from updateScore: also updating next pair via type: {self.type} \n"
                )
            self.population[pair[1]].scoring.addEq(score[1])

        if self.debugMode:
            for i in range(len(self.population)):
                print(
                    f"[DEBUG] \t {self.population[i].scoring}, id: {self.population[i].uid}\n"
                )


def killAndWait(threads: list[threading.Thread], infos: list[threadInfo]) -> None:
    for e in infos:
        e.interrupt = True
        assert e.runningProc is not None
        e.runningProc.kill()

    for t in threads:
        t.join()


def GUIWaitLoop(
    tourney: tournament, threads: list[threading.Thread], infos: list[threadInfo]
) -> None:
    while not global_tui.shouldClose():
        time.sleep(1)
        if global_scoreBoard.roundStat.isOver():
            break
    if global_tui.shouldClose():
        assert global_tui.mh is not None
        global_tui.mh.running = False
        killAndWait(threads, infos)


global_scoreBoard = scoreBoard()
global_tui: tuiGUI = tuiGUI(debugMode=True, useCurses=True)
global_tui.setScoreBoard(global_scoreBoard)


class chessObjective(obj.objective):
    def __init__(self, tourney: tournament, **parentKwargs):
        self.tourney = tourney
        super().__init__(**parentKwargs)
        self.baseline: list[heuristicEntry] = []
        self.indexesTemplate: list[int] = []

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
        matchInv: matchContainerInfo = matchContainerInfo(
            len(positions), popBase=len(self.baseline), type=self.tourney.type
        )
        self.tourney.population = []
        for i in range(len(positions)):
            self.tourney.population.append(
                chessIndividual(
                    position=chessSpec.entryFrom1dArray(
                        np.array(positions[i]), indexes=self.indexesTemplate
                    ),
                    uid=i,
                    scoring=score(0, 0, 0),
                )
            )
        self.tourney.baseline = [
            chessIndividual(position=pos, uid=x, scoring=score(0, 0, 0))
            for x, pos in enumerate(self.baseline)
        ]

        global_scoreBoard.roundStat.reset()
        global_scoreBoard.roundStat.nMatch = len(matchInv.status)
        self.tourney.dispatchMatch(matchInv)
        if self.tourney.type == tournamentType.LOS:
            ret = [
                chessSpec.computeLOS(wins=x.scoring.win, losses=x.scoring.lose)
                * x.scoring.nMatch()
                for x in self.tourney.population
            ]
            # print([x.scoring.nMatch() for x in self.tourney.population])

            return ret
        return [x.scoring.getScore() for x in self.tourney.population]

    def setIndexesTemplate(self, idx: list[int]) -> None:
        assert len(idx) == int((self.nDims) / 2), (
            f"Length of the template indexes ({len(idx)}) does not match the number of dimension of this objective ({self.nDims})"
        )
        self.indexesTemplate = idx

    def setBaseline(self, entry: heuristicEntry) -> None:
        self.baseline = [entry]

    def appendBaseline(self, entry: heuristicEntry) -> None:
        if len(self.baseline) == self.tourney.baselineLimit:
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
                            texel.texelWeightsFromFlatWeights(e[0]),
                            texel.texelWeightsFromFlatWeights(e[1]),
                        ]
                    )
                )
        if config.get("tournament") is not None:
            self.tourney = tournamentFromConfigFile(
                config["tournament"], pathPrepend=pathPrepend
            )

        if config.get("indexesTemplate") is not None:
            self.indexesTemplate = config["indexesTemplate"]


def tournamentFromConfigFile(config: dict, pathPrepend: str = "") -> tournament:
    return tournament(
        timeF=timeFormat(config["timeFormat"][0], config["timeFormat"][1]),
        templatePath=config["templatePath"],
        logDir=config["logDir"],
        evalBin=config["evalBin"],
        debugMode=config["debugMode"],
        nThread=config["nThread"],
        type=valueToTournamentType(config["type"]),
        pathPrepend=pathPrepend,
    )


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
LOWER_BOUND_WEIGHT = 0
# LOWER_BOUND_WEIGHT = -UPPER_BOUND_WEIGHT
STEP_WEIGTH = 1
N_PARAMS = 12 * 2


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
        global_tui.pingUpdate()


class callbackBaseline(template.callback):
    """ """

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
                    * len(self.mh.objective.tourney.baseline)
                )
            ) > self.LOS_FRAC_THRESH:
                self.mh.objective.appendBaseline(
                    chessSpec.entryFrom1dArray(
                        best.position, indexes=self.mh.objective.indexesTemplate
                    )
                )


@dataclass
class mhUserInput:
    maxiter: int
    popsize: int
    preEvaluation: bool = True
    saveLog: bool = True
    bounds: tuple[int, int] | None = None
    steps: int | None = None
    seed: int = 42


@dataclass
class userInput:
    baseInfoFile: str = ""
    tmpFolderPath: str = ""
    resFolderPath: str = ""
    evaluationBinaryPath: str = "zig-out/bin/evaluate"
    mhParams: mhUserInput | None = None
    debugMode: bool = False
    timeF: timeFormat = hyperBulletTimeFormat


if __name__ == "__main__":
    global_tui.dispatch()
    path = "engines/engine_tourney.info"
    tmpFolder = f"out/heuristics/MH/tmp/tmp_{int(time.time())}"
    yamlFolder = f"out/heuristics/MH/res/tmp_{int(time.time())}"
    evaluationBinPath = "zig-out/bin/evaluate"

    popsize = 16
    maxiter = 32

    cbs = [callbackBaseline(), guiUpdateCallback()]
    saveOpt: saveOptions = saveOptions(logDir=tmpFolder, prefix="result", saveLog=True)
    mh = gw.GW(
        popsize=popsize,
        maxiter=maxiter,
        preEval=True,
        saveOpt=saveOpt,
        cbs=cbs,
    )
    global_tui.setMH(mh)

    tourn = tournament(
        timeF=hyperBulletTimeFormat,
        templatePath=path,
        evalBin=evaluationBinPath,
        debugMode=False,
        logDir=tmpFolder,
        nThread=4,
        type=tournamentType.LOS,
        baselineLimit=4,
    )

    mh.setObjective(
        chessObjective(
            maximize=True,
            tourney=tourn,
            bounds=dummyBounds(LOWER_BOUND_WEIGHT, UPPER_BOUND_WEIGHT, nDim=N_PARAMS),
            steps=dummyStep(STEP_WEIGTH, nDim=N_PARAMS),
        )
    )
    assert type(mh.objective) is chessObjective
    mh.objective.setBaseline(chessSpec.simpleBaselineWeights)
    mh.objective.setIndexesTemplate(chessSpec.newIndexes)
    mh.objective.appendBaseline(chessSpec.newWeight_1)

    mh.generatePopulation()

    mh.addInvididual(
        indiv=individual(
            position=chessSpec.simpleBaselineWeights.maskOut(
                indexes=chessSpec.newIndexes, defaultValue=0
            ).get1DArray()
        )
    )
    mh.addInvididual(
        indiv=individual(
            position=chessSpec.newWeight_0.maskOut(
                chessSpec.newIndexes, defaultValue=0
            ).get1DArray()
        )
    )
    mh.addInvididual(
        indiv=individual(
            position=chessSpec.newWeight_1.maskOut(
                chessSpec.newIndexes, defaultValue=0
            ).get1DArray()
        )
    )

    mh.optimize()
