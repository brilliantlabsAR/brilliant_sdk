"""frame.imu.* stubs."""
from __future__ import annotations

from typing import Callable, Any


class ImuStub:
    def __init__(self, runtime: Any) -> None:
        """
        `runtime` is the lupa LuaRuntime instance, needed to construct Lua tables
        so that Lua code can call pairs() on the returned values.
        """
        self._runtime = runtime
        self._tap_cb: Callable | None = None
        self._pitch: float = 0.0
        self._roll: float = 0.0
        self._heading: float = 0.0
        self._compass = {"x": 0, "y": 0, "z": 0}
        self._accel = {"x": 0, "y": 0, "z": 0}

    # ---- called from Lua ----

    def tap_callback(self, func: Callable | None) -> None:
        self._tap_cb = func

    def direction(self) -> Any:
        t = self._runtime.table()
        t.pitch = self._pitch
        t.roll = self._roll
        t.heading = self._heading
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

    def fire_tap(self) -> None:
        if self._tap_cb is not None:
            self._tap_cb()

    # ---- called from Python (test / REPL) ----

    def set_direction(self, pitch: float, roll: float, heading: float) -> None:
        self._pitch = float(pitch)
        self._roll = float(roll)
        self._heading = float(heading)

    def set_raw(
        self,
        compass: tuple[float, float, float],
        accel: tuple[float, float, float],
    ) -> None:
        self._compass = {"x": compass[0], "y": compass[1], "z": compass[2]}
        self._accel = {"x": accel[0], "y": accel[1], "z": accel[2]}
