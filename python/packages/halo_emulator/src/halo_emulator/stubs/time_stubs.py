"""frame.time.* stubs — mirrors firmware 0.8.8 lua_time.c."""
from __future__ import annotations

import datetime
import re
import time as _time
from typing import Any

_ZONE_RE = re.compile(r"^([+-]?)(\d+):(\d+)$")


class TimeStub:
    def __init__(self, runtime: Any) -> None:
        self._runtime = runtime
        self._tz_offset_minutes: int = 0  # signed total, -720..+840
        self._utc_base: float | None = None  # None = use real clock

    # ------------------------------------------------------------------ utc

    def utc(self, timestamp: float | None = None) -> float:
        if timestamp is None:
            if self._utc_base is not None:
                return self._utc_base + _time.monotonic()
            return _time.time()
        timestamp = float(timestamp)
        if timestamp < 0:
            raise ValueError("timestamp must be non-negative")
        self._utc_base = timestamp - _time.monotonic()
        # Firmware echoes the set value back
        return timestamp

    # ------------------------------------------------------------------ zone

    def _format_zone(self) -> str:
        total = self._tz_offset_minutes
        magnitude = abs(total)
        sign = "-" if total < 0 else "+"
        return f"{sign}{magnitude // 60:02d}:{magnitude % 60:02d}"

    def zone(self, offset: str | None = None) -> str:
        """Get, or set and return, the timezone offset ("±HH:MM").

        Both getter and setter return the normalised stored zone, as the
        firmware does since 0.8.8.
        """
        if offset is None:
            return self._format_zone()
        m = _ZONE_RE.match(str(offset))
        if not m:
            raise ValueError("time zone must be in format '+HH:MM' or '-HH:MM'")
        sign = -1 if m.group(1) == "-" else 1
        hour = int(m.group(2))
        minute = int(m.group(3))
        if (sign > 0 and hour > 14) or (sign < 0 and hour > 12):
            raise ValueError("hour must be between -12 and +14")
        if minute not in (0, 30, 45):
            raise ValueError("minute must be 0, 30, or 45")
        if hour == (14 if sign > 0 else 12) and minute != 0:
            raise ValueError("UTC-12 and UTC+14 must have 0 minutes")
        # One signed total, so the sign applies to the minutes as well
        self._tz_offset_minutes = sign * (hour * 60 + minute)
        return self._format_zone()

    # ------------------------------------------------------------------ date

    def date(self, timestamp: float | None = None) -> Any:
        if timestamp is None:
            ts = self.utc()
        else:
            ts = float(timestamp)
            if ts < 0:
                raise ValueError("timestamp must be non-negative")
        # Firmware applies the zone offset to the UTC timestamp, then
        # breaks it down with gmtime (no host-local timezone involved).
        local = ts + self._tz_offset_minutes * 60
        dt = datetime.datetime.fromtimestamp(local, tz=datetime.timezone.utc)
        t = self._runtime.table()
        t.second = dt.second
        t.minute = dt.minute
        t.hour = dt.hour
        t.day = dt.day
        t.month = dt.month
        t.year = dt.year
        t.weekday = (dt.weekday() + 1) % 7  # firmware: 0 = Sunday
        t["day of year"] = dt.timetuple().tm_yday - 1  # firmware: 0-365
        t["is daylight saving"] = False
        return t
