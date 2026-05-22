from __future__ import annotations

from dataclasses import dataclass
import pandas as pd
import numpy as np
import sys, os, math
from collections.abc import Generator

import torch
import torch.nn as nn
import torch.optim.lr_scheduler as lr_scheduler

import numpy.typing as npt

import texelW
from texelW import texelWeights

# from texelW import
import constants as cst

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))


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


def extractXYFromDF(
    df: pd.DataFrame,
) -> tuple[npt.NDArray[np.float16], npt.NDArray[np.float16]]:
    n_weights = int(df.columns[-3].split("_")[1]) + 1
    rho_mg = (256 - df["Phase"]) / 256
    rho_eg = (df["Phase"]) / 256
    if "Coeff_0_w" in df.columns:
        C_w = df[[f"Coeff_{i}_w" for i in range(n_weights)]]
        C_b = df[[f"Coeff_{i}_b" for i in range(n_weights)]]
        deltaC = C_w.values - C_b.values
    else:
        deltaC = df[[f"Delta_{i}" for i in range(n_weights)]]
    y: npt.NDArray[np.float16] = np.array(df["Outcome"].values)
    x = np.hstack((deltaC, rho_mg.values.reshape(-1, 1), rho_eg.values.reshape(-1, 1)))
    return (x, y)


def fetchNextXY(
    path: str, n_pos: int, nskips: int
) -> tuple[torch.Tensor, torch.Tensor]:
    df = loadTexelWeight(path, n_pos=n_pos, pos_offset=nskips)
    x, y = extractXYFromDF(df)
    del df
    torch_x = torch.from_numpy(x).float()
    torch_y = torch.from_numpy(y.reshape(-1, 1)).float()
    return torch_x, torch_y


class texelNet(nn.Module):
    def __init__(self, n_weights: int):
        super(texelNet, self).__init__()

        self.sigm = nn.Sigmoid()
        self.W_mg = nn.Linear(n_weights, 1, bias=False)
        self.W_eg = nn.Linear(n_weights, 1, bias=False)

        self.float()

    def forward(self, x):
        # return self.sigm(self.W_mg(x[:, :-2]) * x[:, -2] + self.W_eg(x[:, :-2]) * x[:, -1])
        return self.sigm(
            (
                torch.add(
                    torch.mul(self.W_mg(x[:, :-2]), x[:, -2].reshape(-1, 1)),
                    torch.mul(self.W_eg(x[:, :-2]), x[:, -1].reshape(-1, 1)),
                )
            )
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
    setInitWeight(opt, model)
    freezeM = opt.makeFreezeMask()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.01, weight_decay=0.0001)
    # optimizer = torch.optim.Adam(model.parameters(), lr=0.01)
    scheduler = lr_scheduler.StepLR(optimizer, step_size=100, gamma=0.75)

    if fileSize is None:
        size = getFileLineNumbers(opt.path)
    else:
        size = fileSize
    if batch_size <= 0:
        batch_size = opt.pos_per_epoch
    print(f"[DEBUG] training_loop: {size} coeffs found")
    packetSize = size // opt.pos_per_epoch
    packetIdx = -1
    for ep in range(opt.epoch):
        if ep % freq_pos_change == 0:
            # change the x and y
            packetIdx = (packetIdx + 1) % packetSize
            X, Y = fetchNextXY(
                opt.path, n_pos=opt.pos_per_epoch, nskips=packetIdx * opt.pos_per_epoch
            )
            assert batch_size != 0
            amount_batch: int = math.ceil(len(X) / batch_size)

        for batch in range(amount_batch):
            optimizer.zero_grad()  # Zero the gradients

            outputs = model(X[batch * batch_size : (batch + 1) * batch_size])
            loss = criterion(outputs, Y[batch * batch_size : (batch + 1) * batch_size])
            loss.backward()
            # here zero out the grad
            zeroOutGrad(freezeM, model)
            optimizer.step()  # Update the parameters
            if opt.lrScheduler:
                scheduler.step()

        if ep % 10 == 0:
            print(f"Epoch: {ep}: loss = {loss.item()}")


def print2dTensor(w, centipawn: bool = False) -> None:
    if centipawn:
        for x in list(range(8))[::-1]:
            for y in w[x * 8 : (x + 1) * 8]:
                print(f"{int(y * 100)}, ", end="")

            print("")
    else:
        for x in list(range(8))[::-1]:
            for y in w[x * 8 : (x + 1) * 8]:
                print(f"{round(y, 4)}, ", end="")

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
    ):
        assert os.path.exists(path), f"file {path} not found"
        assert path.endswith(".csv"), (
            f"extension of {path} not supported expected .csv file"
        )
        self.path = path
        self.pos_per_epoch = pos_per_epoch
        self.epoch = epoch
        self.tuneCfg = tuneCfg
        self.initWeights = initialWeights
        if type(self.initWeights) is list:
            assert len(self.initWeights) == 2, (
                "Weights must contain both MG and EG section"
            )
        self.lrScheduler = lrScheduler
        if self.tuneCfg.freezingRequired:
            assert self.initWeights is not None, (
                "Some freezing required(one tune param was set to False) but no initial weights given"
            )

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


def printTensorWeight(w, normalize: bool = False) -> None:
    norm = 100 if normalize else 1
    for idx in range(cst.PSQT_Pawn_idx):
        print(f"{cst.strWeightNames[idx]} = {w[idx]}")

    print("pawnArr: ")
    print2dTensor(w[cst.PSQT_Pawn_idx : cst.PSQT_Bishop_idx], normalize)

    print("bishopArr: ")
    print2dTensor(w[cst.PSQT_Bishop_idx : cst.PSQT_Knight_idx], normalize)

    print("knightArr: ")
    print2dTensor(w[cst.PSQT_Knight_idx : cst.PSQT_Rook_idx], normalize)

    print("rookArr: ")
    print2dTensor(w[cst.PSQT_Rook_idx : cst.PSQT_Queen_idx], normalize)

    print("queenArr: ")
    print2dTensor(w[cst.PSQT_Queen_idx : cst.PSQT_King_idx], normalize)

    print("kingArr: ")
    print2dTensor(w[cst.PSQT_King_idx : cst.PSQT_King_idx + 64], normalize)


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
