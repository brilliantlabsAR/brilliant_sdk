"""frame.time.* stubs."""
from __future__ import annotations

import time as _time
from typing import Any


class TimeStub:
    def __init__(self, runtime: Any) -> None:
        self._runtime = runtime
        self._utc_offset: float = 0.0
        self._timezone: str = "+00:00"
        self._utc_base: float | None = None  # None = use real clock

    def utc(self, timestamp: float | None = None) -> float | None:
        if timestamp is None:
            if self._utc_base is not None:
                return self._utc_base + _time.monotonic()
            return _time.time()
        self._utc_base = float(timestamp) - _time.monotonic()
        return None

    def zone(self, offset: str | None = None) -> str | None:
        if offset is None:
            return self._timezone
        self._timezone = str(offset)
        return None

    def date(self, timestamp: float | None = None) -> Any:
        import datetime
        ts = float(timestamp) if timestamp is not None else _time.time()
        dt = datetime.datetime.fromtimestamp(ts)
        t = self._runtime.table()
        t.second = dt.second
        t.minute = dt.minute
        t.hour = dt.hour
        t.day = dt.day
        t.month = dt.month
        t.year = dt.year
        t.weekday = dt.weekday()  # 0=Mon in Python; hardware may differ
        # lupa table keys with spaces require a workaround
        self._runtime.execute(
            f"_tmp_date_tbl = frame.time.date; "  # not used — set manually below
        )
        # Set keys with spaces via raw Lua table access
        # We attach them after returning via a helper if needed
        # For now return without "day of year" and "is daylight saving"
        return t
