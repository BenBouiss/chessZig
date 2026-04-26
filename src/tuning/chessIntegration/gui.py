from dataclasses import dataclass

import os, time, sys

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

import curses

import numpy as np

import chessSpec, texel
import constants as cst
from algo import template, gw, objective


def clear() -> None:
    print("\x1b[2J\x1b[H", end="\r")


# TUI PLAN
"""
*: spinning thingy
|#############################################################|
|#*# MH Name current iter / maxiter #        #Last gui update#|
|####################################        #################|
|                                                             |
|######################   ################   ################ |
|#Tournament settings #   # Current best #   #   MH health   #|
|#                    #   #              #   #    metrics    #|
|#                    #   #              #   #               #|
|#                    #   #              #   #               #|
|#                    #   #              #   #               #|
|#                    #   #              #   #               #|
|######################   ################   ################ |
|                                                             |
|#log location?                                               |
|                                                             |
|                                                             |
|  cur / tot running  (ETA)                                   |
|#############################################################|
|                        Progress bar                         |
|#############################################################|

"""

"""
Plan of gui implementation.

    - Updated at the mh evaluation start and after each match's end
    
    - Display info:
        - Current mh iter
        - Remaining number of matches
        - Current best individual
        - Number of baselines(?)
        - Score distribution if possible inside one terminal screen size
        - Decouple it from the update coming from the tourney

    - Possibility to interact with the optimization:
        - Quit the search "gracefully"
        - Other

"""

from curses import wrapper
from curses.textpad import Textbox, rectangle


class windowCtx:
    def __init__(self, stdscr=None, useCurses: bool = True):
        self.stdscr = stdscr
        self.useCurses = useCurses
        self.active = False

    def __exit__(self, exc_type, exc_val, exc_tb):
        curses.curs_set(True)
        if self.active:
            restoreWindow(self)

    def mainWindow(self, mh: template.templateSelectionAlgo):
        assert self.stdscr is not None
        titleStr = f"Running {mh.name} {mh.iter} / {mh.maxiter} iter"
        windowOffset = (0, 2)
        if self.useCurses:
            rectangle(
                self.stdscr,
                windowOffset[0],
                windowOffset[1],
                windowOffset[0] + 2,
                windowOffset[1] + 1 + len(titleStr),
            )
            self.stdscr.addstr(1, 3, f"{titleStr}")
            self.stdscr.refresh()
        else:
            print(f"{titleStr}")

    def standardWindow(
        self, txt: list[str], winOffset: tuple[int, int], winTitle: str = ""
    ) -> None:
        assert self.stdscr is not None
        if (len(txt)) == 0:
            return
        self.stdscr.addstr(winOffset[0] - 1, winOffset[1], f"{winTitle}")
        maxLength = max([len(s) for s in txt])
        rectangle(
            self.stdscr,
            winOffset[0],
            winOffset[1],
            winOffset[0] + len(txt) + 2,
            winOffset[1] + 1 + maxLength,
        )
        for i, s in enumerate(txt):
            self.stdscr.addstr(
                winOffset[0] + i + 1,
                winOffset[1] + 1,
                f"{s}",
            )

    def onTournamentBegin(self, mh: template.templateSelectionAlgo) -> None:
        assert self.stdscr is not None
        indexes = mh.objective.indexesTemplate
        bestIndiv = mh.getBestIndiv()
        best_indiv = chessSpec.entryFrom1dArray(bestIndiv.position, indexes=indexes)

        windowOffset = (10, 50)
        self.stdscr.addstr(
            windowOffset[0] - 1,
            windowOffset[1],
            f"Current best (score: {round(bestIndiv.score, 3)}): ",
        )
        rectangle(
            self.stdscr,
            windowOffset[0],
            windowOffset[1],
            1 + len(indexes) + windowOffset[0],
            windowOffset[1] + 40,
        )

        self.stdscr.refresh()
        for x, idx in enumerate(indexes):
            assert best_indiv.weights[0].elem[x].val is not None
            assert best_indiv.weights[1].elem[x].val is not None
            param = f"{cst.strWeightNames[idx]}: {best_indiv.weights[0].elem[x].val[0]}, {best_indiv.weights[1].elem[x].val[0]}"

            self.stdscr.addstr(windowOffset[0] + x + 1, windowOffset[1] + 1, f"{param}")

        self.stdscr.refresh()

    def mhHealthMarkers(self, mh: template.templateSelectionAlgo) -> None:
        assert self.stdscr is not None
        windowOffset = (10, 100)
        txt: list[str] = []

        scores = [e.score for e in mh.population]
        poses = np.array(mh.getCurrentPositions())
        stds = poses.std(axis=0)

        self.stdscr.addstr(
            windowOffset[0] - 1, windowOffset[1], "MetaHeuristics health metrics:"
        )
        txt.append(
            f"Score max: {max(scores): .2e} min: {min(scores): .2e} mean: {(sum(scores) / mh.popsize): .2e}"
        )

        txt.append(
            f"Standard devs max: {max(stds):.2e} min: {min(stds):.2e} mean: {(sum(stds) / mh.popsize): .2e}"
        )
        maxLength = max([len(e) for e in txt])
        maxStrSize = 40

        overFlow = 0
        for e in txt:
            overFlow += len(e) // maxStrSize

        rectangle(
            self.stdscr,
            windowOffset[0],
            windowOffset[1],
            windowOffset[0] + len(txt) + 2 + overFlow,
            windowOffset[1] + 1 + maxStrSize,
        )
        new_lines = 0
        for i, s in enumerate(txt):
            n = len(s)
            count = 0
            while n > 0:
                self.stdscr.addstr(
                    windowOffset[0] + new_lines + count + 1,
                    windowOffset[1] + 1,
                    f"{s[count * maxStrSize : (count + 1) * maxStrSize]}",
                )
                n -= maxStrSize
                count += 1
            new_lines += count

    def onMatchEnd(self, nFinished: int, nMatch: int, nRunning: int):
        assert self.stdscr is not None
        assert nMatch != 0

        barOffset = (36, 0)
        totalSize = 64
        currSize = int((nFinished / nMatch) * totalSize)
        _addstr(
            self.stdscr,
            posY=barOffset[0] - 1,
            posX=barOffset[1],
            attr=[
                (f"{nFinished} ", curses.color_pair(1)),
                f"/ {nMatch} ",
                (f"{nRunning} running ", curses.color_pair(2)),
            ],
        )
        self.stdscr.refresh()
        if (nRunning + nFinished) != nMatch:
            drawBar(
                size_YX=(2, totalSize),
                offset_YX=(barOffset[0], barOffset[1]),
                color=curses.color_pair(0),
            )
        if nFinished != 0:
            sizeFinish = currSize if (nRunning == 0) else (currSize + 1)
            drawBar(
                size_YX=(2, sizeFinish),
                offset_YX=(barOffset[0], barOffset[1]),
                color=curses.color_pair(1),
            )

        if nRunning != 0:
            runningSize = int((nRunning / nMatch) * totalSize)
            if (nRunning + nFinished) == nMatch:
                runningSize += 1
            drawBar(
                size_YX=(2, runningSize),
                offset_YX=(barOffset[0], currSize + barOffset[1]),
                color=curses.color_pair(2),
            )
            return


def drawBar(
    size_YX: tuple[int, int],
    offset_YX: tuple[int, int],
    color: int | None = None,
) -> None:
    win = curses.newwin(size_YX[0], size_YX[1], offset_YX[0], offset_YX[1])
    # win.attrset(curses.color_pair(color))
    if color is not None:
        win.attrset(color)
    win.border()
    win.refresh()


def setupWindow() -> windowCtx:
    ret: windowCtx = windowCtx()

    def _setup(stdscr):
        ret.stdscr = stdscr
        ret.active = True

    wrapper(_setup)
    curses.curs_set(False)
    curses.noecho()
    curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK)
    curses.init_pair(2, curses.COLOR_CYAN, curses.COLOR_BLACK)

    return ret


def restoreWindow(windowCtx):
    _ = windowCtx
    clear()
    curses.curs_set(True)
    curses.endwin()
    print("")
    # curses.reset_shell_mode()


def _addstr(stdscr, posY: int, posX: int, attr: list[str | tuple[str, int]]):
    assert len(attr) != 0
    for i in range(len(attr)):
        frame = attr[i]
        modif = False
        if type(frame) is str:
            _str = frame
        elif type(frame) is tuple:
            _str = frame[0]
            if len(frame) == 2:
                modif = True
        else:
            assert False, f"type: {type(frame)} unhandled"
        assert type(_str) is str

        if i == 0:
            if modif:
                stdscr.addstr(posY, posX, f"{_str}", frame[1])
            else:
                stdscr.addstr(posY, posX, f"{_str}")
        else:
            if modif:
                stdscr.addstr(f"{_str}", frame[1])
            else:
                stdscr.addstr(f"{_str}")


def lastUpdateWindow(stdscr, sw):
    txt = f"Last updated at {round(sw.timeSinceStart(), 2)} s"
    xOffset = 116
    rectangle(stdscr, 0, xOffset, 2, 1 + xOffset + len(txt))
    stdscr.addstr(1, xOffset + 1, f"{txt}")
    stdscr.refresh()


LOADING_SYMBOL = ["/", "-", "\\", "|"]


def loadingSymbolWindow(stdscr, tick: int):
    xOffset = 116
    rectangle(stdscr, 0, 0, 2, 2)
    stdscr.addstr(1, 1, f"{LOADING_SYMBOL[tick % len(LOADING_SYMBOL)]}")
    stdscr.refresh()


def main(stdscr):
    pass
    # tmp = gw.GW(popsize=32, maxiter=16)
    # testPath = "engines/heuristics/tmp/tmp_1775055615/ben_1775055615.yaml"
    # tmp.loadYaml(testPath)
    # tmp.setObjective(tourney.objectiveFromConfigFile(testPath))

    # curses.curs_set(False)
    # curses.noecho()
    # ctx = windowCtx(stdscr, tmp)
    # ctx.mainWindow()

    # ctx.onTournamentBegin(indexes=chessSpec.prevIndexes)

    # stdscr.getch()
    # for i in range(32):
    #    ctx.onMatchEnd(i, 32, 0)
    #    stdscr.getch()
    # stdscr.getch()


if __name__ == "__main__":
    wrapper(main)
