from __future__ import annotations

from dataclasses import dataclass
import pandas as pd
import numpy as np
import sys, os, math
import torch
from collections.abc import Generator

import torch.nn as nn
import torch.optim.lr_scheduler as lr_scheduler

import numpy.typing as npt

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

INVALID_VALUE: float = 99999


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
    y = df["Outcome"].values
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


def texelWeightsFromFlatLists(
    arr: list[float], indexes: list[int] | None = None
) -> texelWeights:
    if indexes is None:
        indexes = list(range(len(arr)))
    w = np.array(arr).reshape(-1, 1).astype(float).tolist()
    return texelWeightsFromLists(w, indexes)


def texelWeightsFromLists(
    weights: list[list[float]], indexes: list[int]
) -> texelWeights:
    ret: texelWeights = texelWeights()
    assert len(weights) == len(indexes), (
        f"Length mismatch error: length of weights ({len(weights)}), length of indexes ({len(indexes)})"
    )
    for val, idx in zip(weights, indexes):
        ret.pushArray(val=val, startingIdx=idx)
    return ret


def texelWeightsFromFlatWeights(elems: list[list[int | list[float]]]) -> texelWeights:
    ret = texelWeights()
    for e in elems:
        assert type(e[0]) is int
        assert type(e[1]) is list
        ret.pushArray(val=e[1], startingIdx=e[0])
    return ret


@dataclass
class weight:
    idx: int = 0
    val: None | list[float] = None

    def copy(self) -> weight:
        assert self.val is not None
        return weight(idx=self.idx, val=list(self.val))


class texelWeights:
    def __init__(self):
        self.elem: list[weight] = list()

    def copy(self) -> texelWeights:
        ret: texelWeights = texelWeights()
        for e in self.elem:
            ret.elem.append(e.copy())
        return ret

    def len(self) -> int:
        ret: int = 0
        for e in self.elem:
            assert e.val is not None
            ret += len(e.val)
        return ret

    def getIndexes(self) -> list[int]:
        assert len(self.elem) > 0
        ret = []
        for e in self.elem:
            ret.append(e.idx)
        return ret

    def getArray(
        self, fullLength: bool = False, fillValue: float = INVALID_VALUE
    ) -> list[float]:
        assert len(self.elem) > 0
        assert self.elem[-1].val is not None
        if fullLength:
            ret = [fillValue] * (total_idx)
        else:
            ret = [fillValue] * self.len()

        self.sort()
        self.assertBounds()
        offset = 0
        for e in self.elem:
            assert e.val is not None
            if fullLength:
                ret[e.idx : e.idx + len(e.val)] = e.val
            else:
                ret[offset : offset + len(e.val)] = e.val
                offset += len(e.val)
        return ret

    def checkBounds(self) -> bool:
        for i, e in enumerate(self.elem):
            if e.val is None:
                return False
            if i == (len(self.elem) - 1):
                break
            if not ((e.idx + len(e.val)) <= self.elem[i + 1].idx):
                return False

            # "overlaping weights"
        return True

    def assertBounds(self) -> None:
        assert self.checkBounds(), "Checkbound failed: overlaping weights were found"

    def sort(self) -> None:
        self.elem.sort(key=lambda x: x.idx)

    def pushArray(self, val: list[float], startingIdx: int) -> None:
        self.elem.append(weight(idx=startingIdx, val=list(val)))
        self.sort()
        self.assertBounds()

    def multiply(self, val: float) -> texelWeights:
        for l in self.elem:
            assert l.val is not None
            for x in range(len(l.val)):
                l.val[x] *= val
        return self

    def divide(self, val: float) -> texelWeights:
        for l in self.elem:
            assert l.val is not None
            for x in range(len(l.val)):
                l.val[x] /= val
        return self

    def makeTensor(self, fillValue: int = INVALID_VALUE) -> torch.Tensor:
        return torch.tensor(self.getArray(fullLength=True, fillValue=fillValue))

    def __repr__(self) -> str:
        ret = ""
        for e in self.elem:
            assert e.val is not None
            ret += f" {e.val}"
        return ret

    """
    quick exemple
        >>> class t:
        ...     def __init__(self, vals):
        ...         self.vals = vals
        ...     def t(self):
        ...         for e in self.vals:
        ...             yield e
        ...
        >>> A = t([1,2,3])
        >>> B = t([2,4,8])
        >>> for (x1, x2) in zip(A.t(), B.t()):
        ...     print(x1, x2)
        ...
        1 2
        2 4
        3 8
        >>>

    """

    def iterValid(self) -> Generator[tuple[int, float]]:
        # arr = self.getArray(fullLength=True)
        # for i in range(len(arr)):
        #    if (arr[i] != INVALID_VALUE):
        #        yield (i, arr[i])
        # raise StopIteration
        for e in self.elem:
            assert e is not None
            assert e.val is not None
            yield (e.idx, e.val[0])


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
        mask = [1.0] * (total_idx)
        assert len(mask) == total_idx
        if not self.tuneCfg.tuneCount:
            mask[countPawn_idx : countQueen_idx + 1] = [0] * 5

        assert len(mask) == total_idx
        if not self.tuneCfg.tuneMobility:
            mask[mobility_idx] = 0
            mask[kingMoveCountScore_idx] = 0

        assert len(mask) == total_idx
        if not self.tuneCfg.tuneStructure:
            mask[structureProtection_idx] = 0

        assert len(mask) == total_idx
        if not self.tuneCfg.tunePawnStructure:
            mask[isolatedPawnScore_idx] = 0
            mask[stackedPawnScore_idx] = 0
            mask[passedPawnScore_idx] = 0

        assert len(mask) == total_idx
        if not self.tuneCfg.tunePSQT:
            mask[PSQT_Pawn_idx : PSQT_King_idx + 64] = [0] * (64 * 6)

        assert len(mask) == total_idx
        if not self.tuneCfg.tuneSafety:
            mask[safetyPawn_idx : safetyQueen_idx + 1] = [0] * 5

        assert len(mask) == total_idx
        if not self.tuneCfg.tuneTempo:
            mask[tempoChecksScore_idx] = 0

        assert len(mask) == total_idx
        if not self.tuneCfg.tuneKingStuff:
            mask[kingProximityScore_idx] = 0

        assert len(mask) == total_idx

        return torch.tensor(mask)

    def modifyTensorWithMask(
        self, w: torch.Tensor, idx: int, copy: bool = False
    ) -> torch.Tensor:
        # modifies the w tensor inplace
        assert self.initWeights is not None
        mask = self.makeFreezeMask()
        newW = self.initWeights[idx].makeTensor()
        initValMask = torch.logical_and((mask == 0), (newW != INVALID_VALUE))

        if copy:
            w2 = torch.tensor(w)
            w2[initValMask] = newW[initValMask]
            return w2
        else:
            w[initValMask] = self.initWeights[idx].makeTensor()[initValMask]
            return w


def printTensorWeight(w, normalize: bool = False) -> None:
    norm = 100 if normalize else 1
    for idx in range(PSQT_Pawn_idx):
        print(f"{strWeightNames[idx]} = {w[idx]}")

    print(f"pawnArr: ")
    print2dTensor(w[PSQT_Pawn_idx:PSQT_Bishop_idx], normalize)

    print(f"bishopArr: ")
    print2dTensor(w[PSQT_Bishop_idx:PSQT_Knight_idx], normalize)

    print(f"knightArr: ")
    print2dTensor(w[PSQT_Knight_idx:PSQT_Rook_idx], normalize)

    print(f"rookArr: ")
    print2dTensor(w[PSQT_Rook_idx:PSQT_Queen_idx], normalize)

    print(f"queenArr: ")
    print2dTensor(w[PSQT_Queen_idx:PSQT_King_idx], normalize)

    print(f"kingArr: ")
    print2dTensor(w[PSQT_King_idx : PSQT_King_idx + 64], normalize)


def saveModelWeightToFile(path: str, model: texelNet, convertToCP: bool = True) -> None:
    saveWeightToFile(
        path,
        model.W_mg.weight.detach().numpy()[0],
        model.W_eg.weight.detach().numpy()[0],
        convertToCP=convertToCP,
    )


def texelWeightToFileStr(w: texelWeights, phase: str) -> str:
    ret = ""
    arr = w.getArray(fullLength=True)
    for idx, val in w.iterValid():
        if idx < PSQT_Pawn_idx:
            ret += f"{strWeightNames[idx]}{phase} = {val};\n"
        elif idx == PSQT_Pawn_idx:
            ret += f"pawnPSQT{phase} = {floatArrToString(arr[PSQT_Pawn_idx:PSQT_Bishop_idx])};\n"
        elif idx == PSQT_Bishop_idx:
            ret += f"bishopPSQT{phase} = {floatArrToString(arr[PSQT_Bishop_idx:PSQT_Knight_idx])};\n"
        elif idx == PSQT_Knight_idx:
            ret += f"knightPSQT{phase} = {floatArrToString(arr[PSQT_Knight_idx:PSQT_Rook_idx])};\n"
        elif idx == PSQT_Rook_idx:
            ret += f"rookPSQT{phase} = {floatArrToString(arr[PSQT_Rook_idx:PSQT_Queen_idx])};\n"
        elif idx == PSQT_Queen_idx:
            ret += f"queenPSQT{phase} = {floatArrToString(arr[PSQT_Queen_idx:PSQT_King_idx])};\n"
        elif idx == PSQT_King_idx:
            ret += f"kingPSQT{phase} = {floatArrToString(arr[PSQT_King_idx : PSQT_King_idx + 64])};\n"
        else:
            print(f"[DEBUG] texelWeightToFileStr: unknow value index: {idx}")
            assert False

    return ret


def weightToFileStr(w: npt.NDArray[np.float16], phase: str) -> str:
    ret = ""
    for idx in range(PSQT_Pawn_idx):
        ret += f"{strWeightNames[idx]}{phase}={w[idx]};\n"

    ret += f"pawnPSQT{phase}={floatArrToString(w[PSQT_Pawn_idx:PSQT_Bishop_idx])};\n"
    ret += (
        f"bishopPSQT{phase}={floatArrToString(w[PSQT_Bishop_idx:PSQT_Knight_idx])};\n"
    )
    ret += f"knightPSQT{phase}={floatArrToString(w[PSQT_Knight_idx:PSQT_Rook_idx])};\n"
    ret += f"rookPSQT{phase}={floatArrToString(w[PSQT_Rook_idx:PSQT_Queen_idx])};\n"
    ret += f"queenPSQT{phase}={floatArrToString(w[PSQT_Queen_idx:PSQT_King_idx])};\n"
    ret += (
        f"kingPSQT{phase}={floatArrToString(w[PSQT_King_idx : PSQT_King_idx + 64])};\n"
    )
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


def floatArrToString(arr) -> str:
    tmp = ",".join([f"{x}" for x in arr])
    return f"[{tmp}]"


# texel weight section
total_idx = 0

countPawn_idx = total_idx
total_idx += 1
countKnight_idx = total_idx
total_idx += 1
countBishop_idx = total_idx
total_idx += 1
countRook_idx = total_idx
total_idx += 1
countQueen_idx = total_idx
total_idx += 1

mobility_idx = total_idx
total_idx += 1

kingMoveCountScore_idx = total_idx
total_idx += 1

structureProtection_idx = total_idx
total_idx += 1

isolatedPawnScore_idx = total_idx
total_idx += 1
stackedPawnScore_idx = total_idx
total_idx += 1
passedPawnScore_idx = total_idx
total_idx += 1

tempoChecksScore_idx = total_idx
total_idx += 1

# not used
safetyPawn_idx = total_idx
total_idx += 1
safetyKnight_idx = total_idx
total_idx += 1
safetyBishop_idx = total_idx
total_idx += 1
safetyRook_idx = total_idx
total_idx += 1
safetyQueen_idx = total_idx
total_idx += 1

kingProximityScore_idx = total_idx
total_idx += 1

PSQT_Pawn_idx = total_idx
total_idx += 64
PSQT_Bishop_idx = total_idx
total_idx += 64
PSQT_Knight_idx = total_idx
total_idx += 64
PSQT_Rook_idx = total_idx
total_idx += 64
PSQT_Queen_idx = total_idx
total_idx += 64
PSQT_King_idx = total_idx
total_idx += 64

strWeightNames = [
    "pawnCountScore",
    "bishopCountScore",
    "knightCountScore",
    "rookCountScore",
    "queenCountScore",
    "mobilityScore",
    "mobilityKingScore",
    "structureProtectionScore",
    "isolatedPawnScore",
    "stackedPawnScore",
    "passedPawnScore",
    "tempoChecksScore",
    "safetyPawn",
    "safetyKnight",
    "safetyBishop",
    "safetyRook",
    "safetyQueen",
    "kingProximityScore",
]
