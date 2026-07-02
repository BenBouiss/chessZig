from __future__ import annotations

from dataclasses import dataclass
import pandas as pd
import numpy as np
import sys, os, math
from collections.abc import Generator

import torch
import torch.nn as nn
import torch.optim.lr_scheduler as lr_scheduler
from torch.utils.data import Dataset, DataLoader

import numpy.typing as npt

import texelW
from texelW import texelWeights

# from texelW import
import constants as cst

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))


class CSVDataset(Dataset):
    def __init__(
        self, path: str, chunksize: int, nb_samples: int, optimizeOutcome: bool = True
    ):
        assert os.path.exists(path)
        self.path: str = path
        self.chunksize: int = chunksize
        self.nb_samples: int = nb_samples
        self.len: int = nb_samples // chunksize
        self.optimizeOutcome = optimizeOutcome

    def __len__(self) -> int:
        return self.len

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        pos_offset = self.chunksize * idx
        df = pd.read_csv(
            self.path,
            sep=",",
            dtype=np.float16,
            header=0,
            nrows=self.chunksize,
            skiprows=[1, max(1, pos_offset)],
        )
        n_weights = len(df.columns) - 3
        rho_mg = (256 - df["Phase"]) / 256
        rho_eg = (df["Phase"]) / 256
        deltaC = df[[df.columns[i] for i in range(n_weights)]]
        if self.optimizeOutcome:
            y: npt.NDArray[np.float16] = np.array(df["Outcome"].values).reshape(-1, 1)
        else:
            y: npt.NDArray[np.float16] = np.array(df["Eval"].values).reshape(-1, 1)

        x = np.hstack(
            (deltaC, rho_mg.values.reshape(-1, 1), rho_eg.values.reshape(-1, 1))
        )
        return (torch.from_numpy(x).float(), torch.from_numpy(y).float())


def loadTexelWeight(
    path: str, n_pos: int, pos_offset: int = 0, dtype: npt.DTypeLike = np.float16
) -> pd.DataFrame:
    assert os.path.exists(path)
    ret = pd.read_csv(
        path,
        sep=",",
        dtype=dtype,
        header=0,
        nrows=n_pos,
        skiprows=(1, max(1, pos_offset)),
    )
    assert len(ret) == n_pos, f"expected {n_pos} positions found {len(ret)}"
    return ret


def getFileLineNumbers(path: str) -> int:
    assert os.path.exists(path)
    with open(path, "rbU") as f:
        num_lines = sum(1 for _ in f)
    # remove the header
    return num_lines - 1


K = 10
# K = 0.5


def sigm(x):
    return 1 / (1 + torch.pow(10, -K * x / 400))


class texelNet(nn.Module):
    def __init__(self, n_weights: int):
        super(texelNet, self).__init__()

        self.W_mg = nn.Linear(n_weights, 1, bias=False)
        self.W_eg = nn.Linear(n_weights, 1, bias=False)
        # self.sigm = nn.Sigmoid()
        self.sigm = sigm

        # self.half()
        self.float()

    def forward(self, x):
        # return self.sigm(self.W_mg(x[:, :-2]) * x[:, -2] + self.W_eg(x[:, :-2]) * x[:, -1])
        """
        format of x
        Delta_0, Delta_1 , Delta_2, ..., Delta_n, rho_mg, rho_eg

        """
        return self.sigm(
            (
                torch.add(
                    torch.mul(self.W_mg(x[:, :-2]), x[:, -2].reshape(-1, 1)),
                    torch.mul(self.W_eg(x[:, :-2]), x[:, -1].reshape(-1, 1)),
                )
            )
        )


class texelNetEval(nn.Module):
    def __init__(self, n_weights: int):
        super(texelNetEval, self).__init__()

        self.W_mg = nn.Linear(n_weights, 1, bias=False)
        self.W_eg = nn.Linear(n_weights, 1, bias=False)
        self.sigm = sigm

        self.float()

    def forward(self, x):
        """
        format of x
        Delta_0, Delta_1 , Delta_2, ..., Delta_n, rho_mg, rho_eg

        """
        return torch.add(
            torch.mul(self.W_mg(x[:, :-2]), x[:, -2].reshape(-1, 1)),
            torch.mul(self.W_eg(x[:, :-2]), x[:, -1].reshape(-1, 1)),
        )


def setInitWeight(opt: trainingOptions, model: nn.Module) -> None:
    idx = 0
    for e in model.named_parameters():
        if not "weight" in e[0]:
            continue
        opt.modifyTensorWithMask(e[1].data[0], idx=idx, copy=False)
        idx += 1


def zeroOutGrad(freezeM: torch.Tensor, model: nn.Module) -> None:
    for e in model.named_parameters():
        if not "weight" in e[0]:
            continue
        assert e[1].grad is not None
        e[1].grad.data = torch.mul(freezeM, e[1].grad.data)


def training_loop(
    opt: trainingOptions,
    model: nn.Module,
    freq_pos_change: int = 4,
    fileSize=None,
    batch_size: int = 0,
):
    criterion = nn.MSELoss()
    if opt.initWeights is not None:
        setInitWeight(opt, model)
    freezeM = opt.makeFreezeMask()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.01, weight_decay=0.0001)
    # optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
    # optimizer = torch.optim.Adam(model.parameters(), lr=0.1, weight_decay=0.01)
    scheduler = lr_scheduler.StepLR(optimizer, step_size=100, gamma=0.9)
    # scheduler = lr_scheduler.ExponentialLR(optimizer, gamma=0.95)

    if fileSize is None:
        size = getFileLineNumbers(opt.path)
    else:
        size = fileSize

    print(f"[DEBUG] training_loop: {size} positions found")
    dataset = CSVDataset(
        opt.path,
        chunksize=opt.chunksize,
        nb_samples=size,
        optimizeOutcome=opt.optimizeOutcome,
    )
    trainingDataLoader = DataLoader(dataset, batch_size=1024, shuffle=True)
    if opt.validationPath is not None:
        validationDst = CSVDataset(
            opt.validationPath,
            chunksize=1024,
            nb_samples=300_000,
            optimizeOutcome=opt.optimizeOutcome,
        )
        validationDataLoader = DataLoader(validationDst, batch_size=1, shuffle=True)
    for ep in range(opt.epoch):
        (X, Y) = next(iter(trainingDataLoader))
        for batch in range(len(X)):
            optimizer.zero_grad()
            outputs = model(X[batch])
            loss = criterion(outputs, Y[batch])
            loss.backward()
            optimizer.step()  # Update the parameters

        if opt.lrScheduler:
            scheduler.step()

        if ep % 10 == 0:
            if opt.validationPath is not None:
                Xvalid, Yvalid = next(iter(validationDataLoader))
                outputs = model(Xvalid[0])
                validationLoss = criterion(outputs, Yvalid[0])
            else:
                validationLoss = None

            print(
                f"Epoch: {ep}: loss = {loss.item()} validation loss = {validationLoss} {scheduler.get_last_lr()}"
            )


def print2dTensor(w, centipawn: bool = False, convertToInt: bool = False) -> None:
    norm = 100 if centipawn else 1
    for x in list(range(8))[::-1]:
        for y in w[x * 8 : (x + 1) * 8]:
            if convertToInt:
                print(f"{int(y * norm)}, ", end="")
            else:
                print(f"{(y * norm)}, ", end="")

        print("")


def texelWeightsToTensor(
    w: texelWeights, fillValue: int = cst.INVALID_VALUE
) -> torch.Tensor:
    return torch.tensor(w.getArray(fullLength=True, fillValue=fillValue))


@dataclass
class tuneConfig:
    tuneCount: bool = True
    tuneMobility: bool = True
    tuneStructure: bool = True
    tunePawnStructure: bool = True
    tuneTempo: bool = True
    tuneKingStuff: bool = True
    tuneSafety: bool = True
    tunePSQT: bool = True

    def freezingRequired(self) -> bool:
        return not (
            self.tuneCount
            and self.tuneMobility
            and self.tuneStructure
            and self.tunePawnStructure
            and self.tuneTempo
            and self.tuneKingStuff
            and self.tuneSafety
            and self.tunePSQT
        )


class trainingOptions:
    def __init__(
        self,
        path: str,
        pos_per_epoch: int,
        epoch: int,
        tuneCfg: tuneConfig = tuneConfig(),
        initialWeights: list[texelWeights] | None = None,
        lrScheduler: bool = False,
        initialSkip: int = 0,
        chunksize: int = 32,
        validationPath: str | None = None,
        optimizeOutcome: bool = True,
    ):
        assert os.path.exists(path), f"file {path} not found"
        assert path.endswith(".csv"), (
            f"extension of {path} not supported expected .csv file"
        )
        self.path = path
        self.pos_per_epoch = pos_per_epoch
        self.initialSkip = initialSkip
        self.epoch = epoch
        self.tuneCfg = tuneCfg
        self.initWeights = initialWeights
        self.optimizeOutcome = optimizeOutcome
        if type(self.initWeights) is list:
            assert len(self.initWeights) == 2, (
                "Weights must contain both MG and EG section"
            )
        self.lrScheduler = lrScheduler
        if self.tuneCfg.freezingRequired():
            assert self.initWeights is not None, (
                "Some freezing required(one tune param was set to False) but no initial weights given"
            )
        assert chunksize > 0
        self.chunksize = chunksize
        self.validationPath = validationPath

    def setInitialWeight(self, w: list[texelWeights]) -> None:
        assert len(w) == 2, "Weights must contain both MG and EG section"
        w[0].assertBounds()
        w[1].assertBounds()
        self.initWeights = w

    def makeFreezeMask(self) -> torch.Tensor:
        mask = [1.0] * (cst.total_idx)
        assert len(mask) == cst.total_idx
        if not self.tuneCfg.tuneCount:
            mask[cst.countPawn_idx : cst.countQueen_idx + 1] = [0] * 5

        assert len(mask) == cst.total_idx
        if not self.tuneCfg.tuneMobility:
            mask[cst.mobility_idx] = 0
            mask[cst.kingMoveCountScore_idx] = 0

        assert len(mask) == cst.total_idx
        if not self.tuneCfg.tuneStructure:
            mask[cst.structureProtection_idx] = 0

        assert len(mask) == cst.total_idx
        if not self.tuneCfg.tunePawnStructure:
            mask[cst.isolatedPawnScore_idx] = 0
            mask[cst.stackedPawnScore_idx] = 0
            mask[cst.passedPawnScore_idx] = 0

        assert len(mask) == cst.total_idx
        if not self.tuneCfg.tunePSQT:
            mask[cst.PSQT_Pawn_idx : cst.PSQT_King_idx + 64] = [0] * (64 * 6)

        assert len(mask) == cst.total_idx
        if not self.tuneCfg.tuneSafety:
            mask[cst.safetyPawn_idx : cst.safetyQueen_idx + 1] = [0] * 5

        assert len(mask) == cst.total_idx
        if not self.tuneCfg.tuneTempo:
            mask[cst.tempoChecksScore_idx] = 0

        assert len(mask) == cst.total_idx
        if not self.tuneCfg.tuneKingStuff:
            mask[cst.kingProximityScore_idx] = 0

        assert len(mask) == cst.total_idx

        return torch.tensor(mask)

    def modifyTensorWithMask(
        self, w: torch.Tensor, idx: int, copy: bool = False
    ) -> torch.Tensor:
        # modifies the w tensor inplace
        assert self.initWeights is not None
        mask = self.makeFreezeMask()
        newW = texelWeightsToTensor(self.initWeights[idx])
        initValMask = torch.logical_and((mask == 0), (newW != cst.INVALID_VALUE))

        if copy:
            w2 = torch.tensor(w)
            w2[initValMask] = newW[initValMask]
            return w2
        else:
            w[initValMask] = texelWeightsToTensor(self.initWeights[idx])[initValMask]
            return w


def printTensorWeight(w, normalize: bool = False, convertToInt: bool = False) -> None:
    norm = 100 if normalize else 1
    for idx in range(cst.PSQT_Pawn_idx):
        if convertToInt:
            print(f"{cst.strWeightNames[idx]} = {int(w[idx] * norm)}")
        else:
            print(f"{cst.strWeightNames[idx]} = {w[idx] * norm}")

    print("pawnArr: ")
    print2dTensor(w[cst.PSQT_Pawn_idx : cst.PSQT_Bishop_idx], normalize, convertToInt)

    print("bishopArr: ")
    print2dTensor(w[cst.PSQT_Bishop_idx : cst.PSQT_Knight_idx], normalize, convertToInt)

    print("knightArr: ")
    print2dTensor(w[cst.PSQT_Knight_idx : cst.PSQT_Rook_idx], normalize, convertToInt)

    print("rookArr: ")
    print2dTensor(w[cst.PSQT_Rook_idx : cst.PSQT_Queen_idx], normalize, convertToInt)

    print("queenArr: ")
    print2dTensor(w[cst.PSQT_Queen_idx : cst.PSQT_King_idx], normalize, convertToInt)

    print("kingArr: ")
    print2dTensor(
        w[cst.PSQT_King_idx : cst.PSQT_King_idx + 64], normalize, convertToInt
    )


def saveModelWeightToFile(path: str, model: texelNet, convertToCP: bool = True) -> None:
    saveWeightToFile(
        path,
        model.W_mg.weight.detach().numpy()[0],
        model.W_eg.weight.detach().numpy()[0],
        convertToCP=convertToCP,
    )


def weightToFileStr(w: npt.NDArray[np.float16], phase: str) -> str:
    ret = ""
    for idx in range(cst.PSQT_Pawn_idx):
        ret += f"{cst.strWeightNames[idx]}{phase}={w[idx]};\n"

    ret += f"pawnPSQT{phase}={texelW.floatArrToString(w[cst.PSQT_Pawn_idx : cst.PSQT_Bishop_idx])};\n"
    ret += f"bishopPSQT{phase}={texelW.floatArrToString(w[cst.PSQT_Bishop_idx : cst.PSQT_Knight_idx])};\n"
    ret += f"knightPSQT{phase}={texelW.floatArrToString(w[cst.PSQT_Knight_idx : cst.PSQT_Rook_idx])};\n"
    ret += f"rookPSQT{phase}={texelW.floatArrToString(w[cst.PSQT_Rook_idx : cst.PSQT_Queen_idx])};\n"
    ret += f"queenPSQT{phase}={texelW.floatArrToString(w[cst.PSQT_Queen_idx : cst.PSQT_King_idx])};\n"
    ret += f"kingPSQT{phase}={texelW.floatArrToString(w[cst.PSQT_King_idx : cst.PSQT_King_idx + 64])};\n"
    return ret


def saveWeightToFile(
    path: str,
    w_mg: npt.NDArray[np.float16],
    w_eg: npt.NDArray[np.float16],
    convertToCP: bool = True,
) -> None:
    assert not (os.path.exists(path))

    arr2d_phase = ["_MG", "_EG"]

    with open(path, "w") as f:
        for i, ph in enumerate(arr2d_phase):
            if i == 0:
                w = w_mg
            else:
                w = w_eg

            if convertToCP:
                w = (w * 100).astype(int)
            else:
                w = w.astype(int)
            f.write(weightToFileStr(w, ph))
