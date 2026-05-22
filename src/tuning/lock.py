from __future__ import annotations

from dataclasses import dataclass
import time, sys

INACTIVITY_DETECTOR = 30  # seconds


class lock:
    __lock: bool = False

    def acquire(self) -> None:
        entryTime = time.time()
        printed: bool = False
        while self.__lock:
            if (time.time() - entryTime) > INACTIVITY_DETECTOR and not printed:
                print("[ALERT] stuck in lock.acquire")
                print("[ALERT] stuck in lock.acquire")
                print("[ALERT] stuck in lock.acquire")
                print("[ALERT] stuck in lock.acquire")
                printed = True
                sys.exit(1)
            pass
        self.__lock = True

    def release(self) -> None:
        self.__lock = False
