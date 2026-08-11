import os


def strExtractFromBounds(s: str, lbound: str, rbound: str) -> str:
    assert len(lbound) == len(rbound) == 1, (
        f"Expectec lengths of bounds is 1 found lbound='{lbound}'  rbound='{rbound}'"
    )
    lidx = s.find(lbound)
    ridx = s[::-1].find(rbound)
    if lidx == -1 or ridx == -1:
        return ""
    return s[lidx + 1 : (len(s) - ridx) - 1]


def getFileLineNumbers(path: str) -> int:
    assert os.path.exists(path)
    with open(path, "rbU") as f:
        num_lines = sum(1 for _ in f)
    # remove the header
    return num_lines - 1
