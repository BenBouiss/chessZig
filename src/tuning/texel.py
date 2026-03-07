import pandas as pd
import numpy as np
import sys, os, math
import torch
import torch.nn as nn
import numpy.typing as npt 

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
        self.W_mg = nn.Linear(n_weights, 1)
        self.W_eg = nn.Linear(n_weights, 1)

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

def training_loop(path: str, pos_per_epoch: int, epoch: int, model: nn.Module, 
                  freq_pos_change: int = 4, fileSize = None, batch_size: int = 0):
    criterion = nn.MSELoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.01, weight_decay=0.0001)
    if (fileSize is None):
        size = getFileLineNumbers(path)
    else:
        size = fileSize
    if (batch_size <= 0):
        batch_size = pos_per_epoch
    print(f"[DEBUG] training_loop: {size} coeffs found")
    packetSize = size // pos_per_epoch
    packetIdx = -1
    for ep in range(epoch):
        
        if (ep % freq_pos_change == 0):
            # change the x and y
            packetIdx = (packetIdx + 1) % packetSize
            X, Y = fetchNextXY(path, n_pos = pos_per_epoch, nskips=packetIdx*pos_per_epoch)
            amount_batch = math.ceil(len(X) / batch_size)
        optimizer.zero_grad()  # Zero the gradients
        for batch in range(amount_batch):
            outputs = model(X[batch*batch_size:(batch + 1)*batch_size])
            loss = criterion(outputs, Y[batch*batch_size:(batch + 1)*batch_size])
            loss.backward()
        optimizer.step()  # Update the parameters
        if (ep % 10 == 0):
            print(f"Epoch: {ep}: loss = {loss.item()}")

def print2dTensor(w, normalize: bool = False) -> None:
    if normalize:
        if (max(abs(w)) > 10):
            factor = 10
        else:
            factor = 100
    else:
        factor = 1
    for x in list(range(8))[::-1]:
        for y in w[x*8 : (x+1)*8]:
            if (normalize):
                print(f"{int(y*factor)}, ", end="")
            else:
                print(f"{round(y, 4)}, ", end="")
                
        print("")

def printTensorWeight(w, normalize: bool = False) -> None:
    print(f"pawnCount: {w[0]}, bishopCount: {w[1]}, knightCount: {w[2]}, rookCount: {w[3]}, queenCount: {w[4]} ")
    print(f"moveCount: {w[5]}, structureProtection: {w[6]}")
    print(f"isolatedScore: {w[7]}, stackedScore: {w[8]}, passedScore: {w[9]}")
    print(f"pawnArr: ")
    print2dTensor(w[10:74], normalize)
    
    print(f"bishopArr: ")
    print2dTensor(w[74:138], normalize)
    
    print(f"knightArr: ")
    print2dTensor(w[138:202], normalize)
    
    print(f"rookArr: ")
    print2dTensor(w[202:266], normalize)
    
    print(f"queenArr: ")
    print2dTensor(w[266:330], normalize)
    
    print(f"kingArr: ")
    print2dTensor(w[330:394], normalize)
    
    print(f"pawnSafety: {w[394]}, bishopSafety: {w[395]}, \
          knightSafety: {w[396]}, rookSafety: {w[397]}, queenSafety: {w[398]} ")
    
if __name__ == "__main__":
    pass
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
