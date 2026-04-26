from __future__ import annotations

import numpy as np
import sys, os

import numpy.typing as npt
from chessIntegration import chessSpec, tourney
from algo import gw

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))


if __name__ == "__main__":
    # tmp = gw.GW(popsize=32, maxiter=16)
    # testPath = "engines/heuristics/tmp/tmp_1774110858/ben_1774110858.yaml"
    # testPath = "out/heuristics/MH/tmp/tmp_1776310745/result_1776382416.yaml"

    # tmp.loadYaml(testPath)
    # tmp.setObjective(tourney.objectiveFromConfigFile(testPath))
    # assert type(tmp.objective) is tourney.chessObjective
    # tourney.launch_mh(tmp)
    path = "src/tuning/config.yml"
    info = tourney.readUserYamlInput(path)
    metaH = tourney.makeMHFromUserInput(info)
    tourney.launch_mh(metaH)

    # print("ben")
    # tmp.evaluate(tmp.getCurrentPositions())
