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


@dataclass
class entry:
    pieces: npt.NDArray[np.int8]
    squares: npt.NDArray[np.int8]
    colors: npt.NDArray[np.int8]
    outcome: float
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


CHUNK_SIZE = 8192
MAX_TOKEN_SIZE = 32


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

        self.insertions: int = 0
        self.nSaved: int = 0
        self.chunkSaved: int = 0

    def append(
        self,
        pieces: torch.Tensor,
        colors: torch.Tensor,
        squares: torch.Tensor,
        outcome: float,
        miscs: torch.Tensor,
    ) -> None:
        if self.insertions == self.chunkSize:
            self.commit()

        self.piecesArr.append(pieces)
        self.colorsArr.append(colors)
        self.squaresArr.append(squares)
        self.outcomesArr.append(outcome)
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
            },
            f=path,
        )

        self.piecesArr.clear()
        self.colorsArr.clear()
        self.squaresArr.clear()
        self.miscsArr.clear()
        self.outcomesArr.clear()


baseMaterial = [
    100.0,
    300.0,
    300.0,
    500.0,
    900.0,
    0.0,
    0.0,
]
baseMisc = [6.0, 47.0, 55.0, 18.0, 1.0, 32.0, 48.0, 2.0, 7.0, 2.0, 3.0, 5.0, 5.0]

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
]


def miscPathToDf(p: str) -> pd.DataFrame:
    if ".csv" in p:
        ret = pd.read_csv(
            p, sep=",", usecols=list(range(len(baseMisc))), dtype=np.int16
        )
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
    pieces, squares, colors = [], [], []
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
        miscs=miscVals,
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

    for d in data:
        pieces.append(d.pieces)
        squares.append(d.squares)
        colors.append(d.colors)
        outcomes.append(d.outcome)
        lengths.append(len(d.pieces))
        miscs.append(d.miscs)

    return {
        "pieces": np.concatenate(pieces, dtype=np.int8),
        "squares": np.concatenate(squares, dtype=np.int8),
        "colors": np.concatenate(colors, dtype=np.int8),
        "outcomes": np.array(outcomes, dtype=np.float16),
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

    pieces, squares, colors, outcomes, miscs = [], [], [], [], []
    for f in files:
        d = torch.load(f)
        pieces.append(d["pieces"])
        colors.append(d["colors"])
        squares.append(d["squares"])
        miscs.append(d["miscs"])
        outcomes.append(d["outcomes"])
    out = TensorDataset(
        torch.cat(pieces).contiguous(),
        torch.cat(colors).contiguous(),
        torch.cat(squares).contiguous(),
        torch.cat(miscs).contiguous(),
        torch.cat(outcomes).contiguous(),
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
        return torch.sigmoid(self.K * val)

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
                print(f"global_{p}_PSQT = .{{ [_]scoreType {{", end="")
                for i, n in enumerate(self.psqt_mg[x]):
                    nbr = int(torch.round(n))
                    if i < 63:
                        print(f"{nbr}, ", end="")
                    else:
                        print(f"{nbr}", end="")
                print("}, [_]scoreType {", end="")

                for i, n in enumerate(self.psqt_eg[x]):
                    nbr = int(torch.round(n))
                    if i < 63:
                        print(f"{nbr}, ", end="")
                    else:
                        print(f"{nbr}", end="")
                print("} };")

                # print_board(f"{p}_MG", [torch.round(n) for n in self.psqt_mg[x]])
                # print_board(f"{p}_EG", [torch.round(n) for n in self.psqt_eg[x]])

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
        for batch_idx, (pieces, colors, squares, miscs, outcomes) in enumerate(pbar):
            pieces = pieces.to(DEVICE)
            colors = colors.to(DEVICE)
            squares = squares.to(DEVICE)
            miscs = miscs.to(DEVICE)
            outcomes = outcomes.to(DEVICE)

            optimizer.zero_grad()
            outputs = model(pieces, squares, colors, miscs)
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
        for batch_idx, (pieces, colors, squares, miscs, outcomes) in enumerate(
            validPbar
        ):
            pieces = pieces.to(DEVICE)
            colors = colors.to(DEVICE)
            squares = squares.to(DEVICE)
            miscs = miscs.to(DEVICE)
            outcomes = outcomes.to(DEVICE)

            evals = model(pieces, squares, colors, miscs)
            val_loss += criterion(evals, outcomes).item()
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


def psqt_deviation_loss(psqts_mg, psqts_eg, max_deviation=400.0, temperature=5.0):
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
        l = float(r["val_loss"])
        if bestLoss > l:
            bestLoss = l
            bestR = r
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


if __name__ == "__main__":
    # path = "out/csv/CCRL-4040.[2370489]_2.book"
    path = "out/book/CCRL-4040.[2370489]_filtered_5388899Pos.book"
    miscPath = "out/csv/CCRL-4040.[2370489]_filtered_5388899Pos_evalCoeff_t.csv"
    nPos = 5_388_899
    # nPos = 2_000_000
    # saves = saveConfig(
    #    trainPath="out/bin/torch/train.npz",
    #    validPath="out/bin/torch/valid.npz",
    #    nLim=nPos,
    #    maxPositionPerSave=1_000_000,
    # )
    # ensurePath(saves)
    # process_book_to_npz(path, miscPath, 0.2, saves)
    # processPackedDataPath(saves.trainPath, "out/bin/torch/train")
    # processPackedDataPath(saves.validPath, "out/bin/torch/valid")

    # train(
    #    trainingOptions(
    #        trainingPath="out/bin/torch/valid",
    #        validationPath="out/bin/torch/valid",
    #        checkpointsPath="out/bin/torch/checkpoint",
    #        chunksize=256,
    #    )
    # )

    b = sys.argv[1]
    print(f"Found argument {b} with type {type(b)}")
    print_checkpoint(b, True)
