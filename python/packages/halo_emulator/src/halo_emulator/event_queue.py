from __future__ import annotations
import queue
from dataclasses import dataclass, field
from typing import Any


@dataclass
class Event:
    type: str  # 'ble', 'button_single', 'button_double', 'button_long', 'imu_tap', 'stop'
    data: Any = field(default=None)


class EventQueue:
    """Thread-safe event queue for injecting events from Python into the Lua thread."""

    def __init__(self) -> None:
        self._q: queue.Queue[Event] = queue.Queue()

    def put(self, event: Event) -> None:
        self._q.put_nowait(event)

    def get_nowait(self) -> Event | None:
        try:
            return self._q.get_nowait()
        except queue.Empty:
            return None

    def drain(self) -> list[Event]:
        events: list[Event] = []
        while True:
            e = self.get_nowait()
            if e is None:
                break
            events.append(e)
        return events
