from __future__ import annotations

import sys, os

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from chessIntegration import chessSpec

import unittest
import texel

texel.PSQT_Bishop_idx


class TestArray(unittest.TestCase):
    def test_initialization(self) -> None:
        w: chessSpec.heuristicEntry = chessSpec.entryFromListDup(
            arr=[-1.0, 2.0, -1.0, 20.0, 20.0, 40.0, 80.0, 1.0, 5.0],
            indexes=chessSpec.prevIndexes,
        )
        self.assertTrue(w.weights[0].checkBounds())
        self.assertTrue(w.weights[1].checkBounds())


if __name__ == "__main__":
    unittest.main()
