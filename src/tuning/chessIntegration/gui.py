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


@dataclass
class windowComponent:
    offset: list[int]
    size: list[int]
    win: curses.window | None = None

    def grow(self, size: tuple[int, int], stdscr=None) -> None:
        prev = (self.size[0], self.size[1])
        self.size[0] = max(self.size[0], size[0])
        self.size[1] = max(self.size[1], size[1])
        changed: bool = self.size[0] != prev[0] or self.size[1] != prev[1]
        if self.win is None:
            self.win = curses.newwin(
                self.size[0],
                self.size[1],
                self.offset[0],
                self.offset[1],
            )
            self.win.box()
            self.win.refresh()
            return
        elif changed:
            self.win.resize(self.size[0], self.size[1])
        self.win.erase()
        self.win.box()
        self.win.refresh()

    def reset(self, stdscr) -> None:
        assert self.win is not None
        self.win.refresh()


class windowCtx:
    def __init__(self, stdscr=None, useCurses: bool = True):
        self.stdscr = stdscr
        self.useCurses = useCurses
        self.active = False

    def __exit__(self, exc_type, exc_val, exc_tb):
        curses.curs_set(True)
        if self.active:
            restoreWindow(self)

    def mainWindow(self, mh: template.templateSelectionAlgo, win: windowComponent):
        assert self.stdscr is not None
        titleStr = f"Running {mh.name} {mh.iter} / {mh.maxiter} iter"
        if self.useCurses:
            win.grow(size=(3, len(titleStr) + 2))
            self.stdscr.addstr(1, 3, f"{titleStr}")
            self.stdscr.refresh()
        else:
            print(f"{titleStr}")

    def standardWindow(
        self,
        txt: list[str],
        win: windowComponent,
        winTitle: str = "",
    ) -> None:
        assert self.stdscr is not None
        if (len(txt)) == 0:
            return
        maxLength = max([len(s) for s in txt])
        win.grow(size=(len(txt) + 2, 2 + maxLength))
        self.stdscr.addstr(win.offset[0] - 1, win.offset[1], f"{winTitle}")

        for i, s in enumerate(txt):
            win.win.addstr(i + 1, 1, f"{s}")
        win.win.refresh()

    def mhBestIndiv(
        self, mh: template.templateSelectionAlgo, win: windowComponent
    ) -> None:
        assert self.stdscr is not None
        indexes = mh.objective.indexesTemplate
        bestIndiv = mh.getBestIndiv()
        best_indiv = chessSpec.entryFrom1dArray(bestIndiv.position, indexes=indexes)

        win.grow(size=(2 + len(indexes), 44))
        self.stdscr.addstr(
            win.offset[0] - 1,
            win.offset[1],
            f"Current best (score: {round(bestIndiv.score, 3)}): ",
        )
        # rectangle(
        #    self.stdscr,
        #    windowOffset[0],
        #    windowOffset[1],
        #    1 + len(indexes) + windowOffset[0],
        #    windowOffset[1] + 40,
        # )

        self.stdscr.refresh()
        for x, idx in enumerate(indexes):
            assert best_indiv.weights[0].elem[x].val is not None
            assert best_indiv.weights[1].elem[x].val is not None
            param = f"{cst.strWeightNames[idx]}: {best_indiv.weights[0].elem[x].val[0]}, {best_indiv.weights[1].elem[x].val[0]}"

            self.stdscr.addstr(win.offset[0] + x + 1, win.offset[1] + 2, f"{param}")

        self.stdscr.refresh()

    def mhHealthMarkers(
        self, mh: template.templateSelectionAlgo, win: windowComponent
    ) -> None:
        assert self.stdscr is not None
        txt: list[str] = []

        scores = [e.score for e in mh.population]
        poses = np.array(mh.getCurrentPositions())
        stds = poses.std(axis=0)

        self.stdscr.addstr(
            win.offset[0] - 1, win.offset[1], "MetaHeuristics health metrics:"
        )
        txt.append(
            f" Score max: {max(scores): .2e} min: {min(scores): .2e} mean: {(sum(scores) / mh.popsize): .2e}"
        )

        txt.append(
            f" Standard devs max: {max(stds):.2e} min: {min(stds):.2e} mean: {(sum(stds) / mh.popsize): .2e}"
        )
        maxLength = max([len(e) for e in txt])
        maxStrSize = 36

        overFlow = 0
        for e in txt:
            overFlow += len(e) // maxStrSize

        win.grow(size=(len(txt) + 3 + overFlow, 2 + maxStrSize))

        new_lines = 0
        for i, s in enumerate(txt):
            n = len(s)
            count = 0
            while n > 0:
                self.stdscr.addstr(
                    win.offset[0] + new_lines + count + 1,
                    win.offset[1] + 1,
                    f"{s[count * maxStrSize : (count + 1) * maxStrSize]}",
                )
                n -= maxStrSize
                count += 1
            new_lines += count

    def progressBar(
        self, nFinished: int, nMatch: int, nRunning: int, win: windowComponent
    ):
        assert self.stdscr is not None
        assert nMatch != 0

        totalSize = 64
        # win.grow(size=(0, totalSize))
        currSize = int((nFinished / nMatch) * totalSize)
        _addstr(
            self.stdscr,
            posY=win.offset[0] - 1,
            posX=win.offset[1],
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
                offset_YX=(win.offset[0], win.offset[1]),
                color=curses.color_pair(0),
            )
        if nFinished != 0:
            sizeFinish = currSize if (nRunning == 0) else (currSize + 1)
            drawBar(
                size_YX=(2, sizeFinish),
                offset_YX=(win.offset[0], win.offset[1]),
                color=curses.color_pair(1),
            )

        if nRunning != 0:
            runningSize = int((nRunning / nMatch) * totalSize)
            drawBar(
                size_YX=(2, runningSize),
                offset_YX=(win.offset[0], currSize + win.offset[1]),
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


def lastUpdateWindow(stdscr, sw, win: windowComponent):
    txt = f"Last updated at {round(sw.timeSinceStart(), 1)} s"
    win.grow(size=(3, 1 + len(txt) + 3))
    stdscr.addstr(win.offset[0] + 1, win.offset[1] + 1, f"{txt}")
    stdscr.refresh()


LOADING_SYMBOL = ["/", "-", "\\", "|"]


def loadingSymbolWindow(stdscr, tick: int):
    xOffset = 116
    rectangle(stdscr, 0, 0, 2, 2)
    stdscr.addstr(1, 1, f"{LOADING_SYMBOL[tick % len(LOADING_SYMBOL)]}")
    stdscr.refresh()


def main(stdscr):
    pass


if __name__ == "__main__":
    wrapper(main)
