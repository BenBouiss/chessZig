from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

import threading
import subprocess
import os, time, sys, copy, glob

import yaml
import numpy as np
import numpy.typing as npt

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))
sys.path.append(os.path.dirname(__file__))

from chessSpec import score

import utils as utilsl

import lock as lockl

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


class scoreBoard:
    l: lockl.lock = lockl.lock()
    sw: stopwatch = stopwatch()

    nMatch: int = 0
    nFinished: int = 0
    nRunning: int = 0
    scores: list[score] = []
    popsize: int = 0

    def setPopsize(self, popsize: int) -> None:
        self.popsize = popsize
        self.scores = [score() for _ in range(popsize)]

    def updateScore(
        self, pair: tuple[int, int], res: list[score], baselineMode: bool = False
    ) -> None:

        self.scores[pair[0]].addEq(res[0])
        if not baselineMode:
            self.scores[pair[1]].addEq(res[1])

    def __repr__(self) -> str:
        return f"{self.nFinished}  + {self.nRunning} running / {self.nMatch}"

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
        self.nFinished = nFinished
        self.nRunning = nRunning
        self.nMatch = len(matchInv.status)
        self.l.release()

    def isOver(self) -> bool:
        return self.nMatch == self.nFinished

    def reset(self) -> None:
        self.nMatch = 0
        self.nFinished = 0
        self.nRunning = 0


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
    printToScreen: bool = True

    def __repr__(self) -> str:
        ret = ""
        ret += f"nMatch={self.nMatch};\n"
        ret += f"playerSwitch={self.playerSwitch};\n"
        ret += f"debugMode={self.debugMode};\n"
        ret += f"useOpeningBook={self.useOpeningBook};\n"
        ret += f'openingBookPath="{self.openingBookPath}";\n'
        ret += f"timeFormat=({self.timeF.time}, {self.timeF.inc});\n"
        ret += f"saveLogs={self.saveLogs};\n"
        ret += f'logsLocation="{self.logsLocation}";\n'
        ret += f"printToScreen={self.printToScreen};\n"
        return ret

    def toDict(self) -> dict:
        ret = {}

        ret["nMatch"] = self.nMatch
        ret["playerSwitch"] = self.playerSwitch
        ret["debugMode"] = self.debugMode
        ret["useOpeningBook"] = self.useOpeningBook
        ret["openingBookPath"] = self.openingBookPath
        ret["timeF"] = [self.timeF.time, self.timeF.inc]
        ret["saveLogs"] = self.saveLogs
        ret["logsLocation"] = self.logsLocation
        ret["printToScreen"] = self.printToScreen
        return ret


@dataclass
class engineInfo:
    path: str = ""
    name: str = ""
    settings: list[str] | None = None

    def copyAppendOption(self, opt: list[str]) -> list[engineInfo]:
        ret: list[engineInfo] = []
        for o in opt:
            curr = self.copy()
            if curr.settings is None:
                curr.settings = []
            curr.settings.append(o)
            ret.append(curr)
        return ret

    def copyAppendHeuristicWeightOption(self, opt: list[str]) -> list[engineInfo]:
        ret: list[engineInfo] = []
        for o in opt:
            curr = self.copy()
            if curr.settings is None:
                curr.settings = []
            curr.settings.append(f"setoption name heuristicWeightsPath value {o}")
            ret.append(curr)
        return ret

    def copy(self) -> engineInfo:
        if self.settings is None:
            return engineInfo(path=self.path, name=self.name, settings=self.settings)
        return engineInfo(path=self.path, name=self.name, settings=self.settings.copy())

    def toDict(self) -> dict:
        ret = {}
        ret["path"] = self.path
        ret["name"] = self.name
        ret["settings"] = self.settings
        return ret

    def fromDict(self, d: dict) -> None:
        self.path = d.get("path", self.path)
        self.name = d.get("name", self.name)
        self.settings = d.get("settings", self.settings)

    def __repr__(self) -> str:
        ret = ""
        ret += f'path="{self.path}";\n'
        ret += f'name="{self.name}";\n'
        if self.settings is not None:
            for x in self.settings:
                ret += f'"{x}";\n'

        return ret


def infoFileFromDict(d: dict) -> infoFile:
    ret: infoFile = infoFile(
        engineSettings=[],
        matchSettings=matchInfoSettings(),
    )
    if d.get("matchSettings") is not None:
        ret.matchSettings = matchInfoSettings(**d["matchSettings"])
        if d["matchSettings"].get("timeF") is not None:
            ret.matchSettings.timeF = timeFormat(
                time=d["matchSettings"]["timeF"][0], inc=d["matchSettings"]["timeF"][1]
            )
    if d.get("engineSettings") is not None:
        for x in d.get("engineSettings", []):
            assert type(x) is dict, (
                f"Expected format dict for entry engineSettings found {type(x)}"
            )
            tmp = engineInfo()
            tmp.fromDict(x)
            ret.engineSettings.append(tmp)
    return ret


@dataclass
class infoFile:
    engineSettings: list[engineInfo]
    matchSettings: matchInfoSettings

    def copy(self) -> infoFile:
        return infoFile(
            engineSettings=[copy.deepcopy(x) for x in self.engineSettings],
            matchSettings=copy.deepcopy(self.matchSettings),
        )

    def print(self) -> None:
        print("engine settings: ")
        for i in range(len(self.engineSettings)):
            print(self.engineSettings[i].path)
            print(self.engineSettings[i].name)
            print(self.engineSettings[i].settings)

        print("match settings: ")
        print(self.matchSettings)

    def setTimeFormat(self, timeF: timeFormat | None) -> None:
        if timeF is None:
            return
        self.matchSettings.timeF = timeF

    def toDict(self) -> dict:
        return {
            "engineSettings": [x.toDict() for x in self.engineSettings],
            "matchSettings": self.matchSettings.toDict(),
        }


def readInfoFile(path: str) -> infoFile:
    ret = infoFile([], matchInfoSettings())
    matchSection: bool = False
    engineIndex = -1
    with open(path, "r") as file:
        for line in file.readlines():
            _line = line.rstrip()
            if not len(_line) or _line.startswith("//"):
                continue
            if _line.startswith("[match]"):
                matchSection = True
                continue
            if _line.startswith("["):
                engineIndex += 1
                ret.engineSettings.append(engineInfo())
                continue
            if matchSection:
                readMatchSettingLine(ret.matchSettings, _line)
            else:
                assert engineIndex >= 0, (
                    f"No [engine] found but engine section setting encountered in file {path}"
                )
                readEngineSettingLine(ret.engineSettings[engineIndex], _line)
    return ret


def extractInfoFilesFromDir(path: str) -> list[infoFile]:
    files = glob.glob(os.path.join(path, "*.info"))
    assert len(files) != 0, f"No .info files found at {path}"
    return listPathToListInfoFile(files)


def listPathToListInfoFile(files: list[str]) -> list[infoFile]:
    ret: list[infoFile] = []
    for f in files:
        ret.append(readInfoFile(f))
    return ret


def readEngineSettingLine(info: engineInfo, line: str) -> None:
    _line = line.lower()
    if _line.startswith("name"):
        info.name = utilsl.strExtractFromBounds(s=_line, lbound='"', rbound='"')
    elif "path" in _line:
        info.path = utilsl.strExtractFromBounds(s=_line, lbound='"', rbound='"')
    else:
        setting = utilsl.strExtractFromBounds(s=_line, lbound='"', rbound='"')
        if not len(setting):
            return
        if info.settings is None:
            info.settings = [setting]
        else:
            info.settings.append(setting)


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
    elif "printtoscreen" in _line:
        setting.printToScreen = "true" in _line


class matchO(object):
    def __init__(
        self,
        settings: infoFile,
        debugMode: bool = False,
        extra: str = "",
    ):
        self.settings: infoFile = settings
        self.uid: int = int(1000 * time.time())
        self.debugMode: bool = debugMode
        self.extra: str = extra

    def generateFile(self, tmpfolder: str) -> str:
        newInfoPath = os.path.join(tmpfolder, f"newInfo_{self.uid}_{self.extra}.info")
        with open(newInfoPath, "w") as file:
            for i in range(len(self.settings.engineSettings)):
                file.write(f"[engine{i}]\n")
                file.write(f"{self.settings.engineSettings[i]}")
                if self.settings.matchSettings.saveLogs:
                    file.write(
                        f'"setoption name logspath value {os.path.join(self.settings.matchSettings.logsLocation, f"engine_{self.uid}_{self.extra}_{i}.log")}";\n'
                    )
            file.write(f"[match]\n")
            file.write(f"{self.settings.matchSettings}")
        return newInfoPath


def launchAndWaitResults(
    m: matchO, evalPath: str, tmpFolder: str, info: threadInfo, deleteTmp: bool
) -> list[score]:
    ret: list[score] = []
    path = m.generateFile(tmpFolder)
    newInfo = path
    crashPath = os.path.join(
        tmpFolder, f"crashreport_{m.uid}_{m.extra}_{int(time.time())}.log"
    )

    with open(crashPath, "w") as crashFile:
        info.runningProc = subprocess.Popen(
            [evalPath, newInfo],
            stdin=subprocess.DEVNULL,
            stderr=crashFile,
            stdout=subprocess.PIPE,
            text=True,
        )
        status = info.runningProc.wait()

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

    if deleteTmp:
        try:
            os.remove(path)
        except Exception as e:
            _ = e

    if len(ret) == 0:
        pass
    else:
        os.remove(crashPath)
    info.runningProc.terminate()
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
    for k, v in tournamentType._value2member_map_.items():
        if k == val:
            assert type(v) is tournamentType
            return v
    return tournamentType.INVALID


def strToTournamentType(val: str) -> tournamentType:
    if val == tournamentType.CLASSIC.name:
        return tournamentType.CLASSIC
    if val == tournamentType.BASELINE.name:
        return tournamentType.BASELINE
    if val == tournamentType.SPRT.name:
        return tournamentType.SPRT
    if val == tournamentType.LOS.name:
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

    def getMatch(self) -> matchFetchResult:
        self.l.acquire()
        for i in range(len(self.order)):
            if (
                self.status[i] == matchStatus.PENDING
                or self.status[i] == matchStatus.ERROR
            ):
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


"""
Instead of keeping track of the population as a list of heuristicEntry for the mh, we keep track of it as a list of engineInfo's as it contains a engine path, engine "name" (useless), engine settings which can contain the setoption name heuristicsWeightPath. 
For the purpose of possible SPRT, aim path at directory and extracts all .info found which all contains the engine's settings, a path and possible options.
"""


class tournament(object):
    def __init__(
        self,
        timeF: timeFormat | None = None,
        templatePath: str | None = None,
        logDir: str | None = None,
        saveLog: bool = True,
        deleteTmp: bool = True,
        evalBin: str | None = None,
        debugMode: bool = False,
        nThreads: int = 1,
        type: tournamentType = tournamentType.CLASSIC,
        pathPrepend: str = "",
    ):
        self.running = False
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

        self.saveLog = saveLog
        self.deleteTmp = deleteTmp

        self.population: list[engineInfo] = []
        self.baseline: list[engineInfo] = []
        self.popsize: int = 0
        self.scoreBoard = scoreBoard()

        self.evalBin: str | None = evalBin
        if debugMode:
            print("Building tournament with debug on")
        if logDir is None:
            self.logDir = os.getcwd()
        else:
            self.logDir: str = logDir
            os.makedirs(self.logDir, exist_ok=True)

        self.setThread(nThreads)
        self.logs: dict = {}

    def saveArgsToDict(self) -> dict:
        ret = {}
        if self.timeFormat is not None:
            ret["timeFormat"] = [self.timeFormat.time, self.timeFormat.inc]
        ret["logDir"] = self.logDir
        ret["evalBin"] = self.evalBin
        ret["debugMode"] = self.debugMode
        ret["nThreads"] = self.nThreads
        ret["type"] = self.type.value

        ret["templatePath"] = self.templatePath
        if self.settings is not None:
            ret["settings"] = self.settings.toDict()
        return ret

    def setThread(self, nThreads: int) -> None:
        assert nThreads > 0, f"Invalid(x <= 0) thread amount {nThreads}"
        self.nThreads = nThreads

    def setPopulation(self, pop: list[engineInfo]) -> None:
        self.population = []
        for x in pop:
            self.population.append(x.copy())
        self.popsize = len(pop)
        self.scoreBoard.setPopsize(len(pop))

    def setBaseline(self, pop: list[engineInfo]) -> None:
        self.baseline = []
        for x in pop:
            self.baseline.append(x.copy())

    def startTournament(self, matchInfo: matchContainerInfo) -> None:
        self.running = True
        self.scoreBoard.setPopsize(self.popsize)
        self.matchInv = matchInfo
        workingThreads: list[threading.Thread] = []
        threadInfos: list[threadInfo] = []
        # for threadId, idx in enumerate(indexes):
        self.scoreBoard.updateScoreBoard(self.matchInv)
        for threadId in range(self.nThreads):
            threadInfos.append(threadInfo())
            workingThreads.append(
                threading.Thread(
                    target=self.thread_dispatchMatch, args=([threadId, threadInfos[-1]])
                )
            )
            workingThreads[-1].start()
        self.wait(workingThreads, threadInfos)

    def wait(
        self, workingThreads: list[threading.Thread], threadInfos: list[threadInfo]
    ) -> None:
        while not self.scoreBoard.isOver() and self.running:
            time.sleep(SLEEP_STDOUT_S)

        if not self.scoreBoard.isOver():
            killAndWait(workingThreads, threadInfos)

    def thread_dispatchMatch(self, threadId: int, info: threadInfo) -> None:
        assert self.population is not None
        assert len(self.population) != 0
        assert self.settings is not None
        assert self.evalBin is not None
        info.status = threadStatus.RUNNING
        while not info.interrupt:
            res = self.matchInv.getMatch()
            info.currentMatch = res

            if res.status == matchFetchStatus.EMPTY or res.idx == -1:
                break

            currSettings = self.settings.copy()
            pair = res.matchOrder
            opp1 = self.population[pair[0]]
            if self.type.useBaselines():
                opp2 = self.baseline[pair[1]]
            else:
                opp2 = self.population[pair[1]]

            currSettings.engineSettings[0] = opp1
            currSettings.engineSettings[0].name = "1"

            currSettings.engineSettings[1] = opp2
            currSettings.engineSettings[1].name = "2"

            self.matchInv.status[res.idx] = matchStatus.IN_PROGRESS

            self.scoreBoard.updateScoreBoard(self.matchInv)

            currentMatch: matchO = matchO(
                settings=currSettings,
                extra=f"T{threadId}",
                debugMode=self.debugMode,
            )

            scoreList = launchAndWaitResults(
                currentMatch, self.evalBin, self.logDir, info, self.deleteTmp
            )

            if len(scoreList) == 0:
                self.matchInv.status[res.idx] = matchStatus.ERROR
            else:
                self.matchInv.status[res.idx] = matchStatus.FINISHED
                self.scoreBoard.updateScore(
                    pair=pair, res=scoreList, baselineMode=self.type.useBaselines()
                )
            self.scoreBoard.updateScoreBoard(self.matchInv)

        info.status = threadStatus.FINISHED


def killAndWait(threads: list[threading.Thread], infos: list[threadInfo]) -> None:
    for e in infos:
        e.interrupt = True
        assert e.runningProc is not None
        e.runningProc.kill()

    for t in threads:
        t.join()


def tournamentFromConfigFile(config: dict, pathPrepend: str = "") -> tournament:
    if config.get("settings") is not None:
        ret = tournament(
            timeF=timeFormat(config["timeFormat"][0], config["timeFormat"][1]),
            templatePath=None,
            logDir=config["logDir"],
            evalBin=config["evalBin"],
            debugMode=config["debugMode"],
            nThreads=config["nThreads"],
            type=valueToTournamentType(config["type"]),
            pathPrepend=pathPrepend,
        )
        ret.settings = infoFileFromDict(config["settings"])
        ret.templatePath = config["templatePath"]
    else:
        ret = tournament(
            timeF=timeFormat(config["timeFormat"][0], config["timeFormat"][1]),
            templatePath=config["templatePath"],
            logDir=config["logDir"],
            evalBin=config["evalBin"],
            debugMode=config["debugMode"],
            nThreads=config["nThreads"],
            type=valueToTournamentType(config["type"]),
            pathPrepend=pathPrepend,
        )
    return ret


if __name__ == "__main__":
    pass
