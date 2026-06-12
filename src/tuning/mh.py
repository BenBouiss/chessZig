from __future__ import annotations

import numpy as np
import sys, os

import numpy.typing as npt
from chessIntegration import chessSpec, tourney
from algo import gw

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

LOS_FRAC_THRESH = 0.55
if __name__ == "__main__":
    path = "src/tuning/config.yml"
    info = tourney.readUserYamlInput(path)
    metaH = tourney.makeMHFromUserInput(info)

    # tourney.global_tui.useCurses = False
    tourney.launch_mh(metaH)
