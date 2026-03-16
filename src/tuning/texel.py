from __future__ import annotations

from dataclasses import dataclass
import pandas as pd
import numpy as np
import sys, os, math
import torch

import torch.nn as nn
import torch.optim.lr_scheduler as lr_scheduler

import numpy.typing as npt 
from chessIntegration import chessSpec

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

def loadTexelWeight(path: str, n_pos: int, pos_offset: int = 0, dtype: npt.DTypeLike = np.float16) -> pd.DataFrame:
    assert os.path.exists(path)
    ret = pd.read_csv(path, sep = ",", dtype = dtype, header = 0, nrows=n_pos, skiprows=(1, max(1, pos_offset)))
    assert len(ret) == n_pos, f"expected {n_pos} positions found {len(ret)}"
    return ret

def getFileLineNumbers(path: str) -> int:
    assert os.path.exists(path)
    with open(path, "rbU") as f:
        num_lines = sum(1 for _ in f)
    #remove the header
    return num_lines - 1

def extractXYFromDF(df: pd.DataFrame) -> tuple[npt.NDArray[np.float16], npt.NDArray[np.float16]]:
    n_weights = int(df.columns[-3].split("_")[1]) + 1
    rho_mg = (256 - df["Phase"]) / 256
    rho_eg = (df["Phase"]) / 256
    C_w = df[[f"Coeff_{i}_w" for i in range(n_weights) ]]
    C_b = df[[f"Coeff_{i}_b" for i in range(n_weights) ]]
    deltaC = C_w.values - C_b.values
    y = df["Outcome"].values
    x = np.hstack((deltaC, rho_mg.values.reshape(-1, 1), rho_eg.values.reshape(-1, 1)))
    return (x, y)

def fetchNextXY(path: str, n_pos: int, nskips: int) -> tuple[torch.Tensor]:
    df = loadTexelWeight(path, n_pos = n_pos, pos_offset=nskips)
    x, y = extractXYFromDF(df)
    del df
    torch_x = torch.from_numpy(x).float()
    torch_y = torch.from_numpy(y.reshape(-1, 1)).float()
    return torch_x, torch_y

class texelNet(nn.Module):
    def __init__(self, n_weights: int):
        super(texelNet, self).__init__()

        self.sigm = nn.Sigmoid()
        self.W_mg = nn.Linear(n_weights, 1, bias = False)
        self.W_eg = nn.Linear(n_weights, 1, bias = False)

        self.float()
        
    def forward(self, x):
        #return self.sigm(self.W_mg(x[:, :-2]) * x[:, -2] + self.W_eg(x[:, :-2]) * x[:, -1])
        return self.sigm(
            (torch.add(
                torch.mul(self.W_mg(x[:, :-2]), x[:, -2].reshape(-1, 1)), 
                torch.mul(self.W_eg(x[:, :-2]), x[:, -1].reshape(-1, 1))
                )
            )
        )

def setInitWeight(opt: trainingOptions, model: nn.Module) -> None:
    for e in model.named_parameters():
        if not "weight" in e[0]:
            continue
        opt.modifyTensorWithMask(e[1].data[0], copy = False)

def zeroOutGrad(freezeM: torch.Tensor, model: nn.Module) -> None:
    for e in model.named_parameters():
        if not "weight" in e[0]:
            continue
        e[1].grad.data = torch.mul(freezeM, e[1].grad.data)
            


def training_loop(opt: trainingOptions, model: nn.Module, freq_pos_change: int = 4, fileSize = None, batch_size: int = 0):
    criterion = nn.MSELoss()
    setInitWeight(opt, model)
    freezeM = opt.makeFreezeMask()
    optimizer = torch.optim.Adam(model.parameters(), lr=1)
    scheduler = lr_scheduler.StepLR(optimizer, step_size=20, gamma=0.75)
    if (fileSize is None):
        size = getFileLineNumbers(opt.path)
    else:
        size = fileSize
    if (batch_size <= 0):
        batch_size = opt.pos_per_epoch
    print(f"[DEBUG] training_loop: {size} coeffs found")
    packetSize = size // opt.pos_per_epoch
    packetIdx = -1
    for ep in range(opt.epoch):
        
        if (ep % freq_pos_change == 0):
            # change the x and y
            packetIdx = (packetIdx + 1) % packetSize
            X, Y = fetchNextXY(opt.path, n_pos = opt.pos_per_epoch, nskips=packetIdx*opt.pos_per_epoch)
            amount_batch = math.ceil(len(X) / batch_size)

        optimizer.zero_grad()  # Zero the gradients
        for batch in range(amount_batch):
            outputs = model(X[batch*batch_size:(batch + 1)*batch_size])
            loss = criterion(outputs, Y[batch*batch_size:(batch + 1)*batch_size])
            loss.backward()

        # here zero out the grad
        zeroOutGrad(freezeM, model)
        optimizer.step()  # Update the parameters
        scheduler.step()

        if (ep % 10 == 0):
            print(f"Epoch: {ep}: loss = {loss.item()}")

def print2dTensor(w, centipawn: bool = False) -> None:
    if centipawn:
        factor = 100
    else:
        factor = 1

    for x in list(range(8))[::-1]:
        for y in w[x*8 : (x+1)*8]:
            print(f"{round(y*factor, 4)}, ", end="")
                
        print("")

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

structureProtection_idx = total_idx
total_idx += 1

isolatedPawnScore_idx = total_idx
total_idx += 1
stackedPawnScore_idx = total_idx
total_idx += 1
passedPawnScore_idx = total_idx
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

#not used
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

@dataclass
class weight:
    idx: int = 0
    val: None|list[float] = None

class texelWeights: 
    def __init__(self):
        self.elem: list[weight] = list()

    def getArray(self) -> list[float]:
        assert len(self.elem) > 0
        assert self.elem[-1].val is not None
        ret = [0.0] * (self.elem[-1].idx + len(self.elem[-1].val))
        self.elem.sort(key = lambda x: x.idx)
        assert(self.checkBounds())
        for e in self.elem:
            assert e.val is not None
            ret[e.idx:e.idx+len(e.val)] = e.val
        return ret

    def checkBounds(self) -> bool:
        for i, e in enumerate(self.elem):
            if e.val is None:
                return False
            if i == (len(self.elem)-1):
                break
            if not((e.idx + len(e.val)) <= self.elem[i+1].idx):
                return False
            #, "overlaping weights"
        return True

    def pushArray(self, val: list[float], startingIdx: int) -> None:
        self.elem.append(weight(idx = startingIdx, val = list(val)))
        self.elem.sort(key = lambda x: x.idx)

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


    def makeTensor(self) -> torch.Tensor:
        return torch.tensor(self.getArray())

    def __repr__(self) -> str:
        ret = ""
        for e in self.elem:
            assert e.val is not None
            ret += f" {e.val}"
        return ret

@dataclass
class tuneConfig:
    tuneCount: bool = True 
    tuneMobility: bool = True 
    tuneStructure: bool = True
    tunePawnStructure: bool = True
    tunePSQT: bool = True
    tuneSafety: bool = True

class trainingOptions:
    def __init__(self, path: str, pos_per_epoch: int, epoch: int, tuneCfg: tuneConfig = tuneConfig(),
                 initialWeights: texelWeights|None = None):
                    assert os.path.exists(path)
                    self.path = path
                    self.pos_per_epoch = pos_per_epoch
                    self.epoch = epoch
                    self.tuneCfg = tuneCfg 
                    self.initWeights = initialWeights

    def setInitialWeight(self, w: texelWeights) -> None:
        assert(w.checkBounds())
        self.initWeights = w

    def makeFreezeMask(self) -> torch.Tensor:
        mask = [1.0] * (total_idx)
        if (not self.tuneCfg.tuneCount):
            mask[countPawn_idx:countQueen_idx+1] = [0] * 5

        if (not self.tuneCfg.tuneMobility):
            mask[mobility_idx] = 0

        if (not self.tuneCfg.tuneStructure):
            mask[structureProtection_idx] = 0 

        if (not self.tuneCfg.tunePawnStructure):
            mask[isolatedPawnScore_idx] = 0 
            mask[stackedPawnScore_idx] = 0 
            mask[passedPawnScore_idx] = 0 

        if (not self.tuneCfg.tunePSQT):
            mask[PSQT_Pawn_idx:PSQT_King_idx+64] = [0] * (PSQT_King_idx+64 - PSQT_Pawn_idx)

        if (not self.tuneCfg.tuneSafety):
            mask[safetyPawn_idx:safetyQueen_idx+1] = [0] * 5

        return torch.tensor(mask)

    def modifyTensorWithMask(self, w: torch.Tensor, copy: bool = False) -> torch.Tensor:
        # modifies the w tensor inplace 
        assert self.initWeights is not None
        mask = self.makeFreezeMask()
        initValMask = (mask == 0)
        if copy:
            w2 = torch.tensor(w)
            w2[initValMask] = self.initWeights.makeTensor()[initValMask]
            return w2
        else:
            w[initValMask] = self.initWeights.makeTensor()[initValMask]
            return w

    def makeTensorInitW(self) -> torch.Tensor:
        assert self.initWeights is not None
        return self.initWeights.makeTensor()

def printTensorWeight(w, normalize: bool = False) -> None:
    print(f"pawnCount: {w[countPawn_idx]}, bishopCount: {w[countBishop_idx]}, knightCount: {w[countKnight_idx]}, rookCount: {w[countRook_idx]}, queenCount: {w[countQueen_idx]} ")
    print(f"moveCount: {w[mobility_idx]}, structureProtection: {w[structureProtection_idx]}")
    print(f"isolatedScore: {w[isolatedPawnScore_idx]}, stackedScore: {w[stackedPawnScore_idx]}, passedScore: {w[passedPawnScore_idx]}")
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
    print2dTensor(w[PSQT_King_idx:PSQT_King_idx+64], normalize)
    
    print(f"pawnSafety: {w[safetyPawn_idx]}, bishopSafety: {w[safetyBishop_idx]}, \
    knightSafety: {w[safetyKnight_idx]}, rookSafety: {w[safetyRook_idx]}, queenSafety: {w[safetyQueen_idx]} ")


def saveModelWeightToFile(path: str, model: nn.Module) -> None:
    saveWeightToFile(path, 
                     model.W_mg.weight.detach().numpy()[0],
                     model.W_eg.weight.detach().numpy()[0])

    

def saveWeightToFile(path: str, w_mg: npt.NDArray[np.float16], w_eg: npt.NDArray[np.float16], convertToCP: bool = True) -> None:
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
                
            f.write(f"pawnCountScore{ph} = {w[countPawn_idx]};\nbishopCountScore{ph} = {w[countBishop_idx]};\nknightCountScore{ph} = {w[countKnight_idx]};\nrookCountScore{ph} = {w[countRook_idx]};\nqueenCountScore{ph} = {w[countQueen_idx]};\n")
            f.write(f"mobilityScore{ph} = {w[mobility_idx]};\nstructureProtectionScore{ph} = {w[structureProtection_idx]};\n")
            f.write(f"isolatedPawnScore{ph} = {w[isolatedPawnScore_idx]};\nstackedPawnScore{ph} = {w[stackedPawnScore_idx]};\npassedPawnScore{ph} = {w[passedPawnScore_idx]};\n")

            f.write(f"pawnPSQT{ph}: {floatArrToString(w[PSQT_Pawn_idx:PSQT_Bishop_idx])};\n")
            f.write(f"bishopPSQT{ph}: {floatArrToString(w[PSQT_Bishop_idx:PSQT_Knight_idx])};\n")
            f.write(f"knightPSQT{ph}: {floatArrToString(w[PSQT_Knight_idx:PSQT_Rook_idx])};\n")
            f.write(f"rookPSQT{ph}: {floatArrToString(w[PSQT_Rook_idx:PSQT_Queen_idx])};\n")
            f.write(f"queenPSQT{ph}: {floatArrToString(w[PSQT_Queen_idx:PSQT_King_idx])};\n")
            f.write(f"kingPSQT{ph}: {floatArrToString(w[PSQT_King_idx:PSQT_King_idx+64])};\n")


def floatArrToString(arr) -> str:
    tmp = ",".join([f"{x}" for x in arr])
    return f"[{tmp}]"

if __name__ == "__main__":
    a = texelWeights()
    a.pushArray([chessSpec.simpleBaselineWeights[chessSpec.mobility_idx]], mobility_idx)
    a.pushArray([chessSpec.simpleBaselineWeights[chessSpec.structureProtection_idx]], structureProtection_idx)
    a.pushArray(chessSpec.simpleBaselineWeights[chessSpec.isolatedPawnScore_idx:chessSpec.passedPawnScore_idx+1], isolatedPawnScore_idx)
    a.pushArray(chessSpec.simpleBaselineWeights[chessSpec.safetyKnight_idx:chessSpec.safetyQueen_idx+1], safetyKnight_idx )
    print(a)

    opt: trainingOptions = trainingOptions(
        tuneCfg = tuneConfig(tuneCount = False, 
                tuneMobility =False, 
                tuneStructure = False, 
                tunePawnStructure = False, 
                tunePSQT = True, 
                tuneSafety = False), 
        initialWeights=a)

    print(opt.makeTensorInitW())

    b = opt.makeFreezeMask()
    print(opt.modifyTensorWithMask(b))
    print(b)
    
    # model = texelNet()
    # criterion = nn.MSELoss()
    # optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
    # torch_x = torch.from_numpy(x)
    # torch_y = torch.from_numpy(y)
    # for epoch in range(100):
    #     optimizer.zero_grad()  # Zero the gradients
    #     outputs = model(torch_x)
    #     loss = criterion(outputs, torch_y)
    #     loss.backward()  # Backward pass
    #     optimizer.step()  # Update the parameters
