"""frame.* system-level stubs (sleep, battery, wakeup, etc.)."""
from __future__ import annotations

import time
import threading
from typing import Callable, Any

from halo_emulator.event_queue import EventQueue, Event


class EmulatorStopException(Exception):
    """Raised inside frame.sleep() to break out of a running Lua loop."""


class EmulatorRestartException(Exception):
    """Raised by frame.light_sleep() on wake: the firmware restarts the Lua
    VM and runs main.lua from the top, so the emulator restarts the script."""


# Event type -> frame.wakeup_source() value
_WAKE_SOURCES = {
    "ble": "ble",
    "button_single": "button",
    "button_double": "button",
    "button_long": "button",
    "imu_tap": "imu",
}


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

    # Polling loop shared by sleep / yield — dispatches injected events
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

    # Sleep-mode wait: callbacks do NOT run while asleep; an injected event
    # is a wake source instead. Returns the wake source ("timeout" when the
    # deadline was reached, or None deadline = wait indefinitely).
    def _wait_for_wake(self, seconds: float | None) -> str:
        deadline = None if seconds is None else time.monotonic() + seconds
        while deadline is None or time.monotonic() < deadline:
            if self._stop_event.is_set():
                raise EmulatorStopException("Emulator stopped")
            for event in self._event_queue.drain():
                if event.type == "stop":
                    raise EmulatorStopException("Emulator stopped")
                source = _WAKE_SOURCES.get(event.type)
                if source is not None:
                    return source
            time.sleep(0.001)
        return "timeout"

    def sleep(self, seconds: float | None = None) -> None:
        """frame.sleep(s). With no argument (or 0) the firmware deep-sleeps
        (BLE dropped; wake behaves like a reboot) — the emulator stops."""
        if not seconds:
            raise EmulatorStopException("frame.sleep() deep sleep (shutdown)")
        self._poll(float(seconds))

    def light_sleep(self, seconds: float | None = None) -> None:
        """Light sleep: on wake the firmware restarts the Lua VM and runs
        main.lua from the top — nothing after this call executes."""
        self._wakeup_src = self._wait_for_wake(
            float(seconds) if seconds else None
        )
        raise EmulatorRestartException("light_sleep wake")

    def standby(self, seconds: float | None = None) -> None:
        """Standby resumes in place: execution continues after the call."""
        self._wakeup_src = self._wait_for_wake(
            float(seconds) if seconds else None
        )

    def yield_(self) -> None:
        """frame.yield() — single queue drain."""
        if self._stop_event.is_set():
            raise EmulatorStopException("Emulator stopped")
        for event in self._event_queue.drain():
            if event.type == "stop":
                raise EmulatorStopException("Emulator stopped")
            self._dispatch_fn(event)

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
