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

        windowOffset = (4, 2)
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
        #
        barOffset = (24, 2)
        totalSize = 64
        currSize = int((nMatch / nMax) * totalSize)
        self.stdscr.addstr(
            barOffset[0] - 1,
            barOffset[1],
            f"{nMatch} / {nMax}(eta: ??? s) {nRunning} running  ",
        )
        self.stdscr.refresh()
        win = curses.newwin(
            2,
            totalSize,
            barOffset[0],
            barOffset[1],
        )
        win.attrset(curses.color_pair(0))
        win.border()
        win.refresh()
        if nMatch == 0:
            return
        win = curses.newwin(
            2,
            currSize,
            barOffset[0],
            barOffset[1],
        )
        win.attrset(curses.color_pair(1))
        win.border()
        win.refresh()
        # self.stdscr.refresh()

    def loop(self):
        while True:
            pass


def setupWindow() -> windowCtx:
    ret: windowCtx = windowCtx()

    def _setup(stdscr):
        ret.stdscr = stdscr

    wrapper(_setup)
    curses.curs_set(False)
    curses.noecho()
    curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK)
    curses.curs_set(True)

    return ret


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
