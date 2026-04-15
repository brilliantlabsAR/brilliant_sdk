"""frame.* system-level stubs (sleep, battery, wakeup, etc.)."""
from __future__ import annotations

import time
import threading
from typing import Callable, Any

from halo_emulator.event_queue import EventQueue, Event


class EmulatorStopException(Exception):
    """Raised inside frame.sleep() to break out of a running Lua loop."""


class SystemStub:
    def __init__(
        self,
        event_queue: EventQueue,
        dispatch_fn: Callable[[Event], None],
        stop_event: threading.Event,
    ) -> None:
        self._event_queue = event_queue
        self._dispatch_fn = dispatch_fn
        self._stop_event = stop_event
        self._battery_level: int = 85
        self._battery_voltage: int = 4100  # mV
        self._battery_charging: bool = False
        self._wakeup_src: str = "timeout"
        self._eui: str = "EMUEMU00EMUEMU00"
        self._stay_awake_flag: bool = True
        self._on_wakeup_cb: Callable | None = None

    # Polling loop shared by sleep / light_sleep / standby / yield
    def _poll(self, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self._stop_event.is_set():
                raise EmulatorStopException("Emulator stopped")
            for event in self._event_queue.drain():
                if event.type == "stop":
                    raise EmulatorStopException("Emulator stopped")
                self._dispatch_fn(event)
            time.sleep(0.001)

    def sleep(self, seconds: float = 0.0) -> None:
        self._poll(float(seconds) if seconds else 0.0)

    def light_sleep(self, seconds: float = 0.0) -> None:
        self._poll(float(seconds) if seconds else 0.0)

    def standby(self, seconds: float = 0.0) -> None:
        self._poll(float(seconds) if seconds else 0.0)
        if self._on_wakeup_cb is not None:
            self._on_wakeup_cb()

    def yield_(self) -> None:
        """frame.yield() — single queue drain."""
        if self._stop_event.is_set():
            raise EmulatorStopException("Emulator stopped")
        for event in self._event_queue.drain():
            if event.type == "stop":
                raise EmulatorStopException("Emulator stopped")
            self._dispatch_fn(event)

    def on_wakeup(self, cb: Callable | None) -> None:
        self._on_wakeup_cb = cb

    def stay_awake(self, enabled: bool | None = None) -> bool | None:
        if enabled is None:
            return self._stay_awake_flag
        self._stay_awake_flag = bool(enabled)
        return None

    def reboot(self) -> None:
        raise EmulatorStopException("frame.reboot() called")

    def battery_level(self) -> int:
        return self._battery_level

    def battery_voltage(self) -> int:
        return self._battery_voltage

    def battery_charging(self) -> bool:
        return self._battery_charging

    def ship_mode(self) -> None:
        raise EmulatorStopException("frame.ship_mode() called")

    def charge(self, enable: bool | None = None) -> None:
        pass

    def wakeup_source(self) -> str:
        return self._wakeup_src

    def get_eui(self) -> str:
        return self._eui

    def get_se_revision(self) -> str:
        return "0.0.0"
