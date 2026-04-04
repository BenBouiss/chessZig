from dataclasses import dataclass

import os, time, sys

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))
import curses

import chessSpec, texel

from algo import template, gw, objective


def clear() -> None:
    print("\x1b[2J\x1b[H", end="\r")


"""
Plan of gui implementation.

    - Updated at the mh evaluation start and after each match's end
    
    - Display info:
        - Current mh iter
        - Remaining number of matches
        - Current best individual
        - Number of baselines(?)
        - Score distribution if possible inside one terminal screen size

    - Possibility to interact with the optimization:
        - Quit the search "gracefully"
        - Other

"""

from curses import wrapper
from curses.textpad import Textbox, rectangle


class windowCtx:
    def __init__(self, stdscr=None):
        self.stdscr = stdscr

    def __exit__(self, exc_type, exc_val, exc_tb):
        curses.curs_set(True)

    def mainWindow(self, mh: template.templateSelectionAlgo):
        assert self.stdscr is not None
        titleStr = f"Running {mh.name} {mh.iter} / {mh.maxiter} iter"
        rectangle(self.stdscr, 0, 0, 1 + 1, 1 + len(titleStr))
        self.stdscr.addstr(1, 1, f"{titleStr}")
        self.stdscr.refresh()

    def objectiveSection(self, mh: template.templateSelectionAlgo) -> None:
        assert self.stdscr is not None
        windowOffset = (4, 50)
        self.stdscr.addstr(
            windowOffset[0] - 1,
            windowOffset[1],
            f"Objective info: ",
        )

    def onTournamentBegin(self, mh: template.templateSelectionAlgo) -> None:
        assert self.stdscr is not None
        self.mainWindow(mh)
        indexes = mh.objective.indexesTemplate
        best_indiv = chessSpec.entryFrom1dArray(
            mh.population[0].position, indexes=indexes
        )

        windowOffset = (4, 0)
        self.stdscr.addstr(
            windowOffset[0] - 1,
            windowOffset[1],
            f"Current best (score: {mh.population[0].score}): ",
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
            param = f"{chessSpec.strWeightNames[idx]}: {best_indiv.weights[0].elem[x].val[0]}, {best_indiv.weights[1].elem[x].val[0]}"

            self.stdscr.addstr(windowOffset[0] + x + 1, windowOffset[1] + 1, f"{param}")

        self.stdscr.refresh()

    def onMatchEnd(self, nMatch: int, nMax: int, nRunning: int):
        assert self.stdscr is not None

        barOffset = (24, 2)
        totalSize = 64
        currSize = int((nMatch / nMax) * totalSize)
        _addstr(
            self.stdscr,
            posY=barOffset[0] - 1,
            posX=barOffset[1],
            attr=[
                (f"{nMatch} ", curses.color_pair(1)),
                f"/ {nMax} ",
                (f"{nRunning} running ", curses.color_pair(2)),
            ],
        )
        self.stdscr.refresh()
        if not (nRunning + nMatch >= nMax):
            win = curses.newwin(2, totalSize, barOffset[0], barOffset[1])
            win.attrset(curses.color_pair(0))
            win.border()
            win.refresh()
        if nMatch != 0:
            if nRunning != 0:
                win = curses.newwin(2, currSize + 1, barOffset[0], barOffset[1])
            else:
                win = curses.newwin(2, currSize, barOffset[0], barOffset[1])
            win.attrset(curses.color_pair(1))
            win.border()
            win.refresh()

        if nRunning != 0:
            runningSize = int((nRunning / nMax) * totalSize)
            win = curses.newwin(2, runningSize, barOffset[0], currSize + barOffset[1])
            win.attrset(curses.color_pair(2))
            win.border()
            win.refresh()
            return


def setupWindow() -> windowCtx:
    ret: windowCtx = windowCtx()

    def _setup(stdscr):
        ret.stdscr = stdscr

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


def _addstr(stdscr, posY, posX, attr: list[str | tuple[str, int]]):
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
