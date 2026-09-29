# ref: texel_zugblitz

import utils

from enum import Enum
import sys, os, random, glob
from dataclasses import dataclass

import chess
from tqdm import tqdm
import numpy as np
import pandas as pd
import numpy.typing as npt
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader, TensorDataset
import torch.optim.lr_scheduler as lr_scheduler

from texel import trainingOptions
import texel

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

CHUNK_SIZE = 8192
MAX_TOKEN_SIZE = 32

MAX_DEVIATION = 400

baseMaterial = [
    100.0,
    300.0,
    300.0,
    500.0,
    900.0,
    0.0,
    0.0,
]
baseMisc = [6.0, 47.0, 55.0, 18.0, 1.0, 32.0, 48.0, 2.0, 7.0, 2.0, 3.0, 5.0, 5.0, 1.0]

phaseArr = [
    0.0,
    1.0,
    1.0,
    2.0,
    4.0,
    0.0,
    0.0,
]

chessPieceToIdx = {
    chess.PAWN: 0,
    chess.KNIGHT: 1,
    chess.BISHOP: 2,
    chess.ROOK: 3,
    chess.QUEEN: 4,
    chess.KING: 5,
}
PIECES = [
    chess.PAWN,
    chess.KNIGHT,
    chess.BISHOP,
    chess.ROOK,
    chess.QUEEN,
    chess.KING,
]
PIECES_STR = [
    "Pawn",
    "Knight",
    "Bishop",
    "Rook",
    "Queen",
    "King",
]
MISCS_STR = [
    "global_MobilityVal",
    "global_OpenFileRookVal",
    "global_materialBishopPair",
    "global_StructureProtectionVal",
    "global_centerProtectionVal",
    "global_HangingVal",
    "global_pieceThreatScore",
    "global_IsolatedPawnVal",
    "global_StackedPawnVal",
    "global_PassedPawnVal",
    "global_phalanxDuoPawnVal",
    "global_connectionPawnVal",
    "global_KingProximityVal",
    "global_SafetyVal",
]
MISCS_COLS: list[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16]
# all the miscs str from above plus last one for eval


@dataclass
class entry:
    pieces: npt.NDArray[np.int8]
    squares: npt.NDArray[np.int8]
    colors: npt.NDArray[np.int8]
    outcome: float
    eval: np.int16
    miscs: npt.NDArray[np.int16]


@dataclass
class saveConfig:
    trainPath: str
    validPath: str
    nLim: int = -1
    maxPositionPerSave: int = -1


def ensurePath(s: saveConfig):
    if not os.path.exists(s.trainPath):
        os.makedirs(os.path.dirname(s.trainPath), exist_ok=True)
    if not os.path.exists(s.validPath):
        os.makedirs(os.path.dirname(s.validPath), exist_ok=True)


def insertChunkNbr(p: str, chunk: int) -> str:
    if "." in p:
        tok = p.split(".")
        assert len(tok) >= 2, f"malformed string {p}"
        tok[-2] = f"{tok[-2]}_chunk_{chunk}"
        return ".".join(tok)
    return f"{p}_chunk_{chunk}"


class torchWriter:
    def __init__(
        self,
        folderPath: str,
        processId: int = 0,
        chunkSize: int = CHUNK_SIZE,
    ):
        self.folderPath: str = folderPath
        if not os.path.exists(self.folderPath):
            os.makedirs(self.folderPath, exist_ok=True)

        self.processId: int = processId
        self.chunkSize: int = chunkSize

        self.piecesArr: list[torch.Tensor] = []
        self.squaresArr: list[torch.Tensor] = []
        self.colorsArr: list[torch.Tensor] = []
        self.miscsArr: list[torch.Tensor] = []
        self.outcomesArr: list[float] = []
        self.evalsArr: list[float] = []

        self.insertions: int = 0
        self.nSaved: int = 0
        self.chunkSaved: int = 0

    def append(
        self,
        pieces: torch.Tensor,
        colors: torch.Tensor,
        squares: torch.Tensor,
        outcome: float,
        eval: int,
        miscs: torch.Tensor,
    ) -> None:
        if self.insertions == self.chunkSize:
            self.commit()

        self.piecesArr.append(pieces)
        self.colorsArr.append(colors)
        self.squaresArr.append(squares)
        self.outcomesArr.append(outcome)
        self.evalsArr.append(eval)
        self.miscsArr.append(miscs)
        self.insertions += 1

    def commit(self) -> None:
        self.insertions = 0
        self.chunkSaved += 1
        name = f"chunk_{self.nSaved}_{self.processId}_{self.chunkSaved}.pt"
        path = os.path.join(self.folderPath, name)
        torch.save(
            {
                "pieces": torch.stack(self.piecesArr),
                "squares": torch.stack(self.squaresArr),
                "colors": torch.stack(self.colorsArr),
                "miscs": torch.stack(self.miscsArr),
                "outcomes": torch.tensor(self.outcomesArr, dtype=torch.float32),
                "evals": torch.tensor(self.evalsArr, dtype=torch.int16),
            },
            f=path,
        )

        self.piecesArr.clear()
        self.colorsArr.clear()
        self.squaresArr.clear()
        self.miscsArr.clear()
        self.outcomesArr.clear()
        self.evalsArr.clear()


def miscPathToDf(p: str) -> pd.DataFrame:
    if ".csv" in p:
        ret = pd.read_csv(p, sep=",", usecols=MISCS_COLS, dtype=np.int16)
        return ret
    raise NotImplementedError


def boardToEntry(bookFen: str, miscVals: npt.NDArray[np.int16]) -> entry:
    outcomeStr: str = utils.strExtractFromBounds(bookFen, "[", "]")
    if "0.5" in outcomeStr:
        outcome = 0.5
    elif "1.0" in outcomeStr:
        outcome = 1.0
    else:
        outcome = 0.0
    pieces, squares, colors, evals = [], [], [], []
    lIdx = bookFen.find("[")
    b = chess.Board(bookFen[:lIdx])
    for sq, p in b.piece_map().items():
        squares.append(int(sq))
        colors.append(0 if p.color == chess.WHITE else 1)
        pieces.append(chessPieceToIdx[p.piece_type])
    return entry(
        pieces=np.asarray(pieces, dtype=np.int8),
        squares=np.asarray(squares, dtype=np.int8),
        colors=np.asarray(colors, dtype=np.int8),
        outcome=outcome,
        miscs=miscVals[:-1],
        eval=miscVals[-1],
    )


def saveChunk(
    ents: list[entry], saveCfg: saveConfig, chunk: int, valRatio: float
) -> list[str]:
    ret: list[str] = []
    random.shuffle(ents)
    valIdx = int(valRatio * len(ents))
    valEts = ents[:valIdx]
    trainingEts = ents[valIdx:]
    print(
        f"{len(trainingEts)} training samples, {len(valEts)} validation samples chunk {chunk}"
    )
    for d, p, name in (
        [trainingEts, saveCfg.trainPath, "train"],
        [valEts, saveCfg.validPath, "validation"],
    ):
        pp = insertChunkNbr(p, chunk) if (saveCfg.maxPositionPerSave != -1) else p
        ret.append(pp)
        packed = packData(d)
        if packed:
            np.savez_compressed(pp, **packed)
            print(f"Saving {name} at path {pp}")

    return ret


def process_book_to_npz(
    path: str, miscPath: str, valRatio: float, saveCfg: saveConfig
) -> list[list[str]]:

    assert os.path.exists(path), f"File {path} does not exists"
    totalSize = utils.getFileLineNumbers(path) if saveCfg.nLim == -1 else saveCfg.nLim
    print(f"total size of position file {totalSize}")

    vals: list[entry] = []
    miscDF = miscPathToDf(miscPath)
    ret: list[list[str]] = []

    curr = 0
    chunk = 0
    with open(path, "r") as f:
        for idx, line in enumerate(tqdm(f, total=totalSize, desc="Parsing book")):
            vals.append(boardToEntry(line, np.asarray(miscDF.iloc[idx])))
            curr += 1
            if curr == saveCfg.nLim:
                break

            if len(vals) == saveCfg.maxPositionPerSave:
                ret.append(saveChunk(vals, saveCfg, chunk, valRatio))
                vals = []
                chunk += 1

    print(f"{curr} lines extracted")
    if vals:
        ret.append(saveChunk(vals, saveCfg, chunk, valRatio))
    vals = []

    del miscDF
    if saveCfg.maxPositionPerSave and chunk != 0:
        for idx, savePath in enumerate([saveCfg.trainPath, saveCfg.validPath]):
            val = {}

            # for i, p in enumerate(paths):
            #    x = np.load(p)
            #    for k, v in x.items():
            #        if i == 0:
            #            val[k] = v
            #        else:
            #            val[k] = np.concatenate((val[k], v), axis=0)
            # np.savez_compressed(saves.trainPath, **val)
            for i in range(len(ret)):
                x = np.load(ret[i][idx])
                for k, v in x.items():
                    if i == 0:
                        val[k] = v
                    else:
                        val[k] = np.concatenate((val[k], v), axis=0)

            np.savez_compressed(savePath, **val)

    return ret


def packData(data: list[entry]) -> dict:
    if not data:
        return {}

    pieces, squares, colors, outcomes, lengths, miscs = [], [], [], [], [], []
    evals = []

    for d in data:
        pieces.append(d.pieces)
        squares.append(d.squares)
        colors.append(d.colors)
        outcomes.append(d.outcome)
        lengths.append(len(d.pieces))
        miscs.append(d.miscs)
        evals.append(d.eval)

    return {
        "pieces": np.concatenate(pieces, dtype=np.int8),
        "squares": np.concatenate(squares, dtype=np.int8),
        "colors": np.concatenate(colors, dtype=np.int8),
        "outcomes": np.array(outcomes, dtype=np.float16),
        "evals": np.array(evals, dtype=np.int16),
        "lengths": np.array(lengths, dtype=np.uint32),
        "miscs": np.array(miscs, dtype=np.int16),
    }


DEFAULT_TOKEN = 6


def processPackedDataPath(path: str, outDir: str) -> None:
    data = np.load(path)
    if not data:
        return
    lengths = data["lengths"]
    pieces_all = padVect(
        data["pieces"], lengths=lengths, maxLen=MAX_TOKEN_SIZE, padValue=DEFAULT_TOKEN
    )
    squares_all = padVect(
        data["squares"], lengths=lengths, maxLen=MAX_TOKEN_SIZE, padValue=DEFAULT_TOKEN
    )
    colors_all = padVect(
        data["colors"], lengths=lengths, maxLen=MAX_TOKEN_SIZE, padValue=DEFAULT_TOKEN
    )
    outcomes_all = data["outcomes"]
    evals_all = data["evals"]
    miscs_all = data["miscs"]
    print(f"len of lengths {len(lengths)} shape pieces {pieces_all.shape}")

    writer: torchWriter = torchWriter(folderPath=outDir)

    pieces_tensor = torch.from_numpy(pieces_all)
    squares_tensor = torch.from_numpy(squares_all)
    colors_tensor = torch.from_numpy(colors_all)
    miscs_tensor = torch.from_numpy(miscs_all)
    for i in range(len(outcomes_all)):
        writer.append(
            pieces_tensor[i],
            colors_tensor[i],
            squares=squares_tensor[i],
            outcome=outcomes_all[i],
            eval=evals_all[i],
            miscs=miscs_tensor[i],
        )
    writer.commit()


def padVect(
    val: npt.NDArray, lengths: npt.NDArray, maxLen: int, padValue: int
) -> npt.NDArray:
    n = len(lengths)
    out = np.full(shape=(n, maxLen), fill_value=padValue)
    offset = 0
    for i, l in enumerate(lengths):
        writeLen = min(lengths[i], maxLen)
        out[i, :writeLen] = val[offset : offset + writeLen]
        offset += writeLen
    return out


def loadDatasets(dirPath: str) -> TensorDataset:
    assert os.path.exists(dirPath), f"Directory {dirPath} does not exists"
    files = sorted(glob.glob(os.path.join(dirPath, "*.pt")))

    pieces, squares, colors, outcomes, miscs, evals = [], [], [], [], [], []
    for f in files:
        d = torch.load(f)
        pieces.append(d["pieces"])
        colors.append(d["colors"])
        squares.append(d["squares"])
        miscs.append(d["miscs"])
        evals.append(d["evals"])
        outcomes.append(d["outcomes"])
    out = TensorDataset(
        torch.cat(pieces).contiguous(),
        torch.cat(colors).contiguous(),
        torch.cat(squares).contiguous(),
        torch.cat(miscs).contiguous(),
        torch.cat(outcomes).contiguous(),
        torch.cat(evals).contiguous(),
    )
    return out


DEFAULT_FEN: str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 0 [1.0]"


class zugNet(nn.Module):
    def __init__(
        self,
        materialScores: torch.Tensor,
        phaseArr: torch.Tensor,
        nSquares: int,
        maxPhase: int,
        miscScores: torch.Tensor,
    ):
        super(zugNet, self).__init__()
        self.nSquares = nSquares
        self.maxPhase = maxPhase
        self.materialScores = materialScores
        self.miscScores = miscScores
        self.nMisc = len(miscScores)

        self.phaseArr: torch.Tensor
        self.register_buffer("phaseArr", phaseArr)

        init = materialScores.unsqueeze(1).repeat(1, nSquares)
        self.psqt_mg = nn.Parameter(init.clone())
        self.psqt_eg = nn.Parameter(init.clone())

        self.misc_mg = nn.Parameter(miscScores.clone())
        self.misc_eg = nn.Parameter(miscScores.clone())

        self.NOISE = 0.5

        with torch.no_grad():
            self.psqt_mg += torch.randn_like(self.psqt_mg) * self.NOISE
            self.psqt_eg += torch.randn_like(self.psqt_eg) * self.NOISE

            self.misc_mg += torch.randn_like(self.misc_mg) * self.NOISE
            self.misc_eg += torch.randn_like(self.misc_eg) * self.NOISE

        self.K = nn.Parameter(torch.tensor([0.0090], dtype=torch.float32))

    def forward(
        self,
        pieces: torch.Tensor,
        squares: torch.Tensor,
        colors: torch.Tensor,
        miscs: torch.Tensor,
    ):
        """ """
        mask = (pieces != DEFAULT_TOKEN).float()
        squares = torch.where(colors == 0, squares, squares ^ 56)

        idx = pieces.long() * 64 + squares

        mg = self.psqt_mg.view(-1)[idx]
        eg = self.psqt_eg.view(-1)[idx]

        sign = 1.0 - 2.0 * colors.float()
        mg_val = (mg * sign * mask).sum(dim=1) + (self.misc_mg * miscs).sum(dim=1)
        eg_val = (eg * sign * mask).sum(dim=1) + (self.misc_eg * miscs).sum(dim=1)

        phase = (self.phaseArr[pieces.long()] * mask).sum(dim=1)
        phase = (phase / self.maxPhase).clamp(0.0, 1.0)
        val = mg_val * phase + eg_val * (1.0 - phase)
        return val

    def forwardS(
        self,
        pieces: torch.Tensor,
        squares: torch.Tensor,
        colors: torch.Tensor,
        miscs: torch.Tensor,
    ):
        return torch.sigmoid(self.K * self(pieces, squares, colors, miscs))

    def print(self, variablePrint: bool) -> None:
        print(f"shape {self.psqt_eg.shape}")
        for x, p in enumerate(PIECES_STR):
            if not variablePrint:
                print(f"Piece {p}")
                print("MG")
                texel.print2dTensor(self.psqt_mg[x], False, True)
                print("EG")
                texel.print2dTensor(self.psqt_eg[x], False, True)
            else:
                print1dMg_Eg(
                    self.psqt_mg[x].round().int(),
                    self.psqt_eg[x].int(),
                    f"global_{p}_PSQT",
                )

        for idx, (m, e) in enumerate(zip(self.misc_mg, self.misc_eg)):
            print(
                f"{MISCS_STR[idx]} = .{{ {int(torch.round(m))}, {int(torch.round(e))} }};"
            )


def print_board(name: str, l: list[int]):
    print(f"const {name} = [_]scoreType {{", end=" ")
    for sq in range(8):
        row = l[sq * 8 : (sq + 1) * 8]
        [print(f"{x}, ", end="") for x in row]
        print("")
    print("};")


def train(opt: trainingOptions):
    assert opt.validationPath is not None
    assert opt.checkpointsPath is not None

    model = zugNet(
        materialScores=torch.Tensor(baseMaterial).to(DEVICE),
        phaseArr=torch.Tensor(phaseArr).to(DEVICE),
        nSquares=64,
        maxPhase=24,
        miscScores=torch.Tensor(baseMisc).to(DEVICE),
    ).to(DEVICE)

    train_ds = loadDatasets(opt.trainingPath)
    train_loader = DataLoader(
        train_ds,
        batch_size=opt.chunksize,
        shuffle=True,
        num_workers=0,
    )
    valid_ds = loadDatasets(opt.validationPath)
    valid_loader = DataLoader(
        valid_ds,
        batch_size=opt.chunksize,
        shuffle=False,
    )
    criterion = nn.MSELoss()
    optimizer = torch.optim.Adam(
        [
            {
                "params": [model.psqt_mg, model.psqt_eg, model.misc_mg, model.misc_eg],
                "lr": 1.5,
                "weight_decay": 0.0001,
            },
            {"params": [model.K], "lr": 0.01},
        ],
    )
    currBest, epoch = loadCheckpoint(model, optimizer, opt.checkpointsPath)
    if epoch == -1:
        epoch = 0

    scheduler = lr_scheduler.ExponentialLR(optimizer, gamma=0.95)
    while True:
        model.train()
        pbar = tqdm(train_loader, desc=f"Epoch {epoch:03d}", unit="batch", leave=False)

        train_loss = 0
        for batch_idx, (pieces, colors, squares, miscs, outcomes, evals) in enumerate(
            pbar
        ):
            pieces = pieces.to(DEVICE)
            colors = colors.to(DEVICE)
            squares = squares.to(DEVICE)
            miscs = miscs.to(DEVICE)
            outcomes = outcomes.to(DEVICE)
            evals = evals.float().to(DEVICE)

            optimizer.zero_grad()
            if opt.optimizeOutcome:
                outputs = model(pieces, squares, colors, miscs)
                loss = (
                    criterion(outputs, evals)
                    + 0.05 * material_consistency_loss(model)
                    + 0.05 * psqt_deviation_loss(model.psqt_mg, model.psqt_eg)
                )
            else:
                outputs = model.forwardS(pieces, squares, colors, miscs)
                loss = (
                    criterion(outputs, outcomes)
                    + 0.05 * material_consistency_loss(model)
                    + 0.05 * psqt_deviation_loss(model.psqt_mg, model.psqt_eg)
                )
            loss.backward()
            optimizer.step()  # Update the parameters
            train_loss += loss.item()

        train_loss /= len(train_loader)
        validPbar = tqdm(
            valid_loader, desc=f"Epoch {epoch:03d}", unit="batch", leave=False
        )
        model.eval()
        val_loss = 0
        for batch_idx, (pieces, colors, squares, miscs, outcomes, evals) in enumerate(
            validPbar
        ):
            pieces = pieces.to(DEVICE)
            colors = colors.to(DEVICE)
            squares = squares.to(DEVICE)
            miscs = miscs.to(DEVICE)
            outcomes = outcomes.to(DEVICE)
            evals = evals.float().to(DEVICE)

            if opt.optimizeOutcome:
                outputs = model(pieces, squares, colors, miscs)
                val_loss += (
                    criterion(outputs, evals).item()
                    + +0.05 * material_consistency_loss(model)
                    + 0.05 * psqt_deviation_loss(model.psqt_mg, model.psqt_eg)
                )
            else:
                outputs = model.forwardS(pieces, squares, colors, miscs)
                val_loss += (
                    criterion(outputs, outcomes).item()
                    + +0.05 * material_consistency_loss(model)
                    + 0.05 * psqt_deviation_loss(model.psqt_mg, model.psqt_eg)
                )
        val_loss /= len(valid_loader)
        if val_loss < currBest:
            print(
                f"New best loss found at epoch {epoch} prev {currBest} new {val_loss} current lr {scheduler.get_last_lr()}"
            )
            currBest = val_loss
        else:
            scheduler.step()
        saveCheckpoint(model, optimizer, opt.checkpointsPath, epoch, val_loss)
        epoch += 1


def material_consistency_loss(model: zugNet):
    mg_means = model.psqt_mg.mean(dim=1).to(DEVICE)
    eg_means = model.psqt_eg.mean(dim=1).to(DEVICE)
    diff_mg = mg_means[:6] - model.materialScores[:6]
    diff_eg = eg_means[:6] - model.materialScores[:6]

    return (diff_mg**2).sum() + (diff_eg**2).sum()


def psqt_deviation_loss(
    psqts_mg, psqts_eg, max_deviation=MAX_DEVIATION, temperature=5.0
):
    loss = 0.0
    for psqts in [psqts_mg, psqts_eg]:
        mean = psqts.mean(dim=1, keepdim=True).to(DEVICE)
        delta = psqts - mean
        excess = nn.functional.softplus(delta.abs() - max_deviation, beta=temperature)
        loss += excess.pow(2).mean()
    return loss


def saveCheckpoint(
    model: zugNet,
    optimizer: torch.optim.Optimizer,
    checkpointDirPath: str,
    epoch: int,
    val_loss: float,
) -> None:

    if not os.path.exists(checkpointDirPath):
        os.makedirs(checkpointDirPath, exist_ok=True)

    name = f"checkpoint_{epoch}.pt"
    torch.save(
        {
            "epoch": epoch,
            "model": model.state_dict(),
            "optimizer": optimizer.state_dict(),
            "val_loss": val_loss,
        },
        f=os.path.join(checkpointDirPath, name),
    )


def loadCheckpoint(
    model: zugNet, optimizer: torch.optim.Optimizer, checkpointDirPath: str
) -> tuple[float, int]:
    files = glob.glob(os.path.join(checkpointDirPath, "*.pt"))
    bestLoss = float("inf")
    bestEpoch = -1
    if not files:
        return (bestLoss, bestEpoch)
    bestR = None
    for f in files:
        r = torch.load(f)
        l = float(r["val_loss"].detach())
        if bestLoss > l:
            bestLoss = l
            bestR = r
            bestEpoch = r["epoch"]
    assert bestEpoch > -1, f"No checkpoints file found at {checkpointDirPath}"
    assert bestR is not None
    model.load_state_dict(bestR["model"])
    optimizer.load_state_dict(bestR["optimizer"])
    return (bestLoss, bestEpoch)


# for ep in range(opt.epoch):
#    (X, Y) = next(iter(train_loader))
#    for batch in range(len(X)):
#        optimizer.zero_grad()
#        outputs = model(X[batch])
#        loss = criterion(outputs, Y[batch])
#        loss.backward()
#        optimizer.step()  # Update the parameters

#    # if opt.lrScheduler:
#    #    scheduler.step()

#    if ep % 10 == 0:
#        if opt.validationPath is not None:
#            Xvalid, Yvalid = next(iter(valid_loader))
#            outputs = model(Xvalid[0])
#            validationLoss = criterion(outputs, Yvalid[0])
#        else:
#            validationLoss = None

#        print(
#            f"Epoch: {ep}: loss = {loss.item()} validation loss = {validationLoss} {scheduler.get_last_lr()}"
#        )


def print_checkpoint(path: str, variablePrint: bool = False) -> None:
    assert os.path.exists(path)

    model = zugNet(
        materialScores=torch.Tensor(baseMaterial),
        phaseArr=torch.Tensor(phaseArr),
        nSquares=64,
        maxPhase=24,
        miscScores=torch.Tensor(baseMisc),
    ).to(DEVICE)
    res = torch.load(path)
    model.load_state_dict(res["model"])
    print(res)
    model.print(variablePrint)


def print_folder_pt(path: str, variablePrint: bool = False) -> None:
    assert os.path.exists(path)
    files = glob.glob(os.path.join(os.path.dirname(path), "*.pt"))
    for f in files:
        a = torch.load(f)
        print(
            f"file {f} val loss {a['val_loss']} lr {a['optimizer']['param_groups'][0]['lr']}"
        )


bonus_mg = [
    [
        [-175, -92, -74, -73],
        [-77, -41, -27, -15],
        [-61, -17, 6, 12],
        [-35, 8, 40, 49],
        [-34, 13, 44, 51],
        [-9, 22, 58, 53],
        [-67, -27, 4, 37],
        [-201, -83, -56, -26],
    ],
    [
        [-53, -5, -8, -23],
        [-15, 8, 19, 4],
        [-7, 21, -5, 17],
        [-5, 11, 25, 39],
        [-12, 29, 22, 31],
        [-16, 6, 1, 11],
        [-17, -14, 5, 0],
        [-48, 1, -14, -23],
    ],
    [
        [-31, -20, -14, -5],
        [-21, -13, -8, 6],
        [-25, -11, -1, 3],
        [-13, -5, -4, -6],
        [-27, -15, -4, 3],
        [-22, -2, 6, 12],
        [-2, 12, 16, 18],
        [-17, -19, -1, 9],
    ],
    [
        [3, -5, -5, 4],
        [-3, 5, 8, 12],
        [-3, 6, 13, 7],
        [4, 5, 9, 8],
        [0, 14, 12, 5],
        [-4, 10, 6, 8],
        [-5, 6, 10, 8],
        [-2, -2, 1, -2],
    ],
    [
        [271, 327, 271, 198],
        [278, 303, 234, 179],
        [195, 258, 169, 120],
        [164, 190, 138, 98],
        [154, 179, 105, 70],
        [123, 145, 81, 31],
        [88, 120, 65, 33],
        [59, 89, 45, -1],
    ],
]

bonus_eg = [
    [
        [-96, -65, -49, -21],
        [-67, -54, -18, 8],
        [-40, -27, -8, 29],
        [-35, -2, 13, 28],
        [-45, -16, 9, 39],
        [-51, -44, -16, 17],
        [-69, -50, -51, 12],
        [-100, -88, -56, -17],
    ],
    [
        [-57, -30, -37, -12],
        [-37, -13, -17, 1],
        [-16, -1, -2, 10],
        [-20, -6, 0, 17],
        [-17, -1, -14, 15],
        [-30, 6, 4, 6],
        [-31, -20, -1, 1],
        [-46, -42, -37, -24],
    ],
    [
        [-9, -13, -10, -9],
        [-12, -9, -1, -2],
        [6, -8, -2, -6],
        [-6, 1, -9, 7],
        [-5, 8, 7, -6],
        [6, 1, -7, 10],
        [4, 5, 20, -5],
        [18, 0, 19, 13],
    ],
    [
        [-69, -57, -47, -26],
        [-55, -31, -22, -4],
        [-39, -18, -9, 3],
        [-23, -3, 13, 24],
        [-29, -6, 9, 21],
        [-38, -18, -12, 1],
        [-50, -27, -24, -8],
        [-75, -52, -43, -36],
    ],
    [
        [1, 45, 85, 76],
        [53, 100, 133, 135],
        [88, 130, 169, 175],
        [103, 156, 172, 172],
        [96, 166, 199, 199],
        [92, 172, 184, 191],
        [47, 121, 116, 131],
        [11, 59, 73, 78],
    ],
]
pbonus_mg = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [3, 3, 10, 19, 16, 19, 7, -5],
    [-9, -15, 11, 15, 32, 22, 5, -22],
    [-4, -23, 6, 20, 40, 17, 4, -8],
    [13, 0, -13, 1, 11, -2, -13, 5],
    [5, -12, -7, 22, -8, -5, -15, -8],
    [-7, 7, -3, -13, 5, -16, 10, -8],
    [0, 0, 0, 0, 0, 0, 0, 0],
]
pbonus_eg = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [-10, -6, 10, 0, 14, 7, -5, -19],
    [-10, -10, -10, 4, 4, 3, -6, -4],
    [6, -2, -8, -4, -13, -12, -10, -9],
    [10, 5, 4, -5, -5, -5, 14, 9],
    [28, 20, 21, 28, 30, 7, 6, 13],
    [0, -11, 12, 21, 25, 19, 4, 7],
    [0, 0, 0, 0, 0, 0, 0, 0],
]


def print1dMg_Eg(mg, eg, name: str) -> None:
    print(f"{name} = .{{ [_]scoreType {{", end="")
    for i, n in enumerate(mg):
        nbr = int(n)
        if i < 63:
            print(f"{nbr}, ", end="")
        else:
            print(f"{nbr}", end="")
    print("}, [_]scoreType {", end="")

    for i, n in enumerate(eg):
        nbr = int(n)
        if i < 63:
            print(f"{nbr}, ", end="")
        else:
            print(f"{nbr}", end="")
    print("} };")

    pass


def print_stuff():
    for i_p, p in enumerate(PIECES):
        big_arr: list[list[int]] = [[0] * 64 for _ in range(2)]
        for sq in range(64):
            x, y = sq % 8, sq // 8
            if p == chess.PAWN:
                vals = [pbonus_mg[7 - y][x], pbonus_eg[7 - y][x]]
            else:
                vals = [
                    bonus_mg[i_p - 1][7 - y][min(x, 7 - x)],
                    bonus_eg[i_p - 1][7 - y][min(x, 7 - x)],
                ]
            big_arr[0][sq] = vals[0] + int(baseMaterial[i_p])
            big_arr[1][sq] = vals[1] + int(baseMaterial[i_p])

            # if p == chess.KING:
            #    print(vals)
            #    print(big_arr[0][sq], big_arr[1][sq])
            #    print(id(big_arr[0]), id(big_arr[1]))

        print1dMg_Eg(
            big_arr[0],
            big_arr[1],
            f"global_{PIECES_STR[i_p]}_PSQT",
        )


# print(f"Piece {PIECES_STR[i_p]}")
# print("MG")
# texel.print2dTensor(big_arr[0], False, True)
# print("EG")
# texel.print2dTensor(big_arr[1], False, True)


if __name__ == "__main__":
    # path = "out/csv/CCRL-4040.[2370489]_2.book"
    path = "out/book/CCRL-4040.[2370489]_filtered_5388899Pos.book"
    miscPath = "out/csv/CCRL-4040.[2370489]_filtered_5388899Pos_evalCoeff_t.csv"
    nPos = 5_388_899
    # nPos = 2_000_000
    saves = saveConfig(
        trainPath="out/bin/torch/train.npz",
        validPath="out/bin/torch/valid.npz",
        nLim=nPos,
        maxPositionPerSave=1_000_000,
    )
    # ensurePath(saves)
    # process_book_to_npz(path, miscPath, 0.2, saves)
    # processPackedDataPath(saves.trainPath, "out/bin/torch/train")
    # processPackedDataPath(saves.validPath, "out/bin/torch/valid")

    # train(
    #    trainingOptions(
    #        trainingPath="out/bin/torch/valid",
    #        validationPath="out/bin/torch/valid",
    #        checkpointsPath="out/bin/torch/checkpoint",
    #        chunksize=512,
    #        optimizeOutcome=True,
    #    )
    # )

    b = sys.argv[1]
    print(f"Found argument {b} with type {type(b)}")
    print_checkpoint(b, True)
    print_folder_pt(b)

    print_stuff()
