from __future__ import annotations

from dataclasses import dataclass


class lock:
    __lock: bool = False

    def acquire(self) -> None:
        while self.__lock:
            pass
        self.__lock = True

    def release(self) -> None:
        self.__lock = False
