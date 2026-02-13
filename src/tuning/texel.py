import pandas as pd
import numpy as np
import sys, os
import torch
import torch.nn as nn
import numpy.typing as npt 

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

def loadTexelWeight(path: str, n_pos: int, pos_offset: int = 0) -> pd.DataFrame:
    assert os.path.exists(path)
    ret = pd.read_csv(path, sep = ",", dtype = np.float16, header = 0, nrows=n_pos, skiprows=pos_offset)
    assert len(ret) == n_pos, f"expected {n_pos} positions found {len(ret)}"
    return ret

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

class texelNet(nn.Module):
    def __init__(self, n_weights: int):
        super(texelNet, self).__init__()

        self.sigm = nn.Sigmoid()
        self.W_mg = nn.Linear(n_weights, 1)
        self.W_eg = nn.Linear(n_weights, 1)
        self.float()
        
    def forward(self, x):
        #return self.sigm(self.W_mg(x[:, :-2]) * x[:, -2] + self.W_eg(x[:, :-2]) * x[:, -1])
        return self.sigm(torch.add(torch.mul(self.W_mg(x[:, :-2]), x[:, -2].reshape(-1, 1)), torch.mul(self.W_eg(x[:, :-2]),  x[:, -1].reshape(-1, 1))))

if __name__ == "__main__":
    path = "logs/test_weights.csv"
    df = loadTexelWeight(path)
    x, y = extractXYFromDF(df)
    
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
