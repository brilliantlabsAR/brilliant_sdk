"""frame.imu.* stubs."""
from __future__ import annotations

from typing import Any, Callable

TAP_KINDS = ("single", "double", "triple")

# Firmware defaults (bma580_driver.c tap detector config, 0.8.8)
_TAP_CONFIG_DEFAULTS: dict[str, Any] = {
    "mode": "normal",
    "axis": "z",
    "threshold": 200,
    "max_peaks": 6,
    "gesture_duration": 30,
    "wait_for_timeout": True,
    "peak_duration": 4,
    "shock_duration": 6,
    "quiet_between_taps": 8,
    "quiet_after_gesture": 6,
}

# Valid ranges for the integer tap_config fields
_TAP_CONFIG_RANGES: dict[str, tuple[int, int]] = {
    "threshold": (0, 1023),
    "max_peaks": (0, 7),
    "gesture_duration": (0, 63),
    "peak_duration": (0, 15),
    "shock_duration": (0, 15),
    "quiet_between_taps": (0, 15),
    "quiet_after_gesture": (0, 15),
}

_TAP_MODES = ("sensitive", "normal", "robust")
_TAP_AXES = ("x", "y", "z")


class ImuStub:
    def __init__(self, runtime: Any) -> None:
        """
        `runtime` is the lupa LuaRuntime instance, needed to construct Lua tables
        so that Lua code can call pairs() on the returned values.
        """
        self._runtime = runtime
        self._tap_cb: Callable | None = None
        self._tap_config: dict[str, Any] = dict(_TAP_CONFIG_DEFAULTS)
        self._pitch: float = 0.0
        self._roll: float = 0.0
        self._compass = {"x": 0, "y": 0, "z": 0}
        self._accel = {"x": 0, "y": 0, "z": 0}

    # ---- called from Lua ----

    def tap_callback(self, func: Callable | None) -> None:
        self._tap_cb = func

    def tap_config(self, options: Any = None) -> Any:
        """Get or update the tap-detector tuning (firmware tap_config())."""
        if options is not None:
            for key in _TAP_CONFIG_RANGES:
                try:
                    val = getattr(options, key)
                except AttributeError:
                    val = None
                if val is not None:
                    lo, hi = _TAP_CONFIG_RANGES[key]
                    val = int(val)
                    if not lo <= val <= hi:
                        raise ValueError(f"{key} must be between {lo} and {hi}")
                    self._tap_config[key] = val
            try:
                wft = options.wait_for_timeout
            except AttributeError:
                wft = None
            if wft is not None:
                self._tap_config["wait_for_timeout"] = bool(wft)
            try:
                mode = options.mode
            except AttributeError:
                mode = None
            if mode is not None:
                if str(mode) not in _TAP_MODES:
                    raise ValueError("mode must be 'sensitive', 'normal' or 'robust'")
                self._tap_config["mode"] = str(mode)
            try:
                axis = options.axis
            except AttributeError:
                axis = None
            if axis is not None:
                if str(axis) not in _TAP_AXES:
                    raise ValueError("axis must be 'x', 'y' or 'z'")
                self._tap_config["axis"] = str(axis)
        t = self._runtime.table()
        for key, val in self._tap_config.items():
            t[key] = val
        return t

    def direction(self) -> Any:
        t = self._runtime.table()
        t.pitch = self._pitch
        t.roll = self._roll
        # heading is a deliberate stub on the firmware: always 0.0
        # (compute a compass heading host-side from raw()).
        t.heading = 0.0
        return t

    def raw(self) -> Any:
        compass = self._runtime.table()
        compass.x = self._compass["x"]
        compass.y = self._compass["y"]
        compass.z = self._compass["z"]
        accel = self._runtime.table()
        accel.x = self._accel["x"]
        accel.y = self._accel["y"]
        accel.z = self._accel["z"]
        t = self._runtime.table()
        t.compass = compass
        t.accelerometer = accel
        return t

    def config(self, options: Any = None) -> None:
        pass  # No-op in emulator

    # ---- called from event dispatch (Lua thread) ----

    def fire_tap(self, kind: str = "single") -> None:
        """One callback per gesture, with the tap kind — as firmware 0.8.8."""
        if self._tap_cb is not None:
            self._tap_cb(kind)

    # ---- called from Python (test / REPL) ----

    def set_direction(self, pitch: float, roll: float, heading: float = 0.0) -> None:
        # `heading` is accepted for backwards compatibility but ignored:
        # the firmware always reports heading = 0.0.
        self._pitch = float(pitch)
        self._roll = float(roll)

    def set_raw(
        self,
        compass: tuple[float, float, float],
        accel: tuple[float, float, float],
    ) -> None:
        self._compass = {"x": compass[0], "y": compass[1], "z": compass[2]}
        self._accel = {"x": accel[0], "y": accel[1], "z": accel[2]}
