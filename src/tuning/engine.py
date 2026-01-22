import numpy as np

import subprocess
import threading 
import time
import os 

class inputChannel:
    def __init__(self):
        self.lock: bool = False
        self.items: list[str] = []

    def acquireLock(self) -> None:
        while (self.lock):
            time.sleep(SLEEP_LOCK_S)
        self.lock = True
    def realeaseLock(self) -> None:
        self.lock = False 

    def putCmd(self, cmd: str) :
        self.acquireLock()
        self.items.append(cmd)
        self.realeaseLock()

    def readBuffer(self) -> str:
        assert len(self.items) != 0
        self.acquireLock()
        ret = self.items.pop(0)
        self.realeaseLock()
        return ret


SLEEP_TIMER_S = 0.1
SLEEP_LOCK_S = 0.01

class engine: 
    def __init__(self, path: str, debugMode: bool):
        self.path = path
        self.p: None | subprocess.Popen = None
        self.channel: inputChannel = inputChannel()
        self.running: bool = False
        self.debugMode = debugMode
        self.workingThreads: list[threading.Thread] = []

    def open(self) -> bool:
        #if os.path.exists(self.path):

        #    print(f"[DEBUG] open.py: path: {self.path} does not exist")
        #    return False

        launchStr = rf"{self.path}"
        print(f"[DEBUG] open.py: launch cmd: {launchStr}")
        self.p = subprocess.Popen([launchStr], stdin = subprocess.PIPE, stdout = subprocess.PIPE, stderr = subprocess.STDOUT, text = True)
        
        self.running = True
        stat = self.startListening()
        if (not stat):
            print(f"[DEBUG] open.py: failed to start listening")
        else:
            print(f"[DEBUG] open.py: started listening")

        return True

    def startListening(self) -> bool: 
        if (not self.running):
            return False
        self.workingThreads.append(threading.Thread(target = self._listen))
        self.workingThreads[-1].start()
        return True
    
    def _listen(self):
        assert self.p is not None
        assert self.p.stdout is not None
        while(self.running):
            time.sleep(SLEEP_TIMER_S)
            for line in iter(self.p.stdout.readline, ''):
                if (self.debugMode):
                    print(f"[DEBUG] _listen.py: got msg: {line} len: {len(line)}")
                self.channel.putCmd(line)
                if (line == ''):
                    print(f"[DEBUG] _listen.py: Empty line found")


    def sendCmd(self, cmd: str) -> None:
        assert self.p is not None
        assert self.p.stdin is not None
        cmdStr = f"{cmd}\n"
        if (self.debugMode):
            print(f"[DEBUG] _sendCmd.py: sent msg len: {cmd}, raw: {cmdStr.encode()}")

        self.p.stdin.write(cmdStr)
        self.p.stdin.flush()

    def close(self):
        if not self.running or self.p is None:
            return
        self.p.kill()
        self.running = False

if __name__ == "__main__":
    print(f"{os.getcwd()}")
    path = "zig-out/bin/engine"
    eng = engine(path, True)
    stat = eng.open()
    assert stat
    time.sleep(2)
    eng.sendCmd("uci")
    eng.sendCmd("isready")

    while True:
        time.sleep(1)

