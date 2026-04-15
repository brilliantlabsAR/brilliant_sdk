"""Tests for button, IMU tap, and other event injection."""
from __future__ import annotations

import shutil
import time
from pathlib import Path

LUA_DIR = Path(__file__).parent / "lua"


def _start_event_callbacks(emulator, tmp_path):
    shutil.copy2(LUA_DIR / "event_callbacks.lua", tmp_path / "event_callbacks.lua")
    emulator.start("event_callbacks.lua")
    time.sleep(0.15)  # let Lua register callbacks


def test_button_single(emulator, tmp_path):
    _start_event_callbacks(emulator, tmp_path)
    emulator.inject_button_single()
    time.sleep(0.2)
    assert b"\x01" in emulator.get_bluetooth_sent()


def test_button_double(emulator, tmp_path):
    _start_event_callbacks(emulator, tmp_path)
    emulator.inject_button_double()
    time.sleep(0.2)
    assert b"\x02" in emulator.get_bluetooth_sent()


def test_button_long(emulator, tmp_path):
    _start_event_callbacks(emulator, tmp_path)
    emulator.inject_button_long()
    time.sleep(0.2)
    assert b"\x03" in emulator.get_bluetooth_sent()


def test_imu_tap(emulator, tmp_path):
    _start_event_callbacks(emulator, tmp_path)
    emulator.inject_imu_tap()
    time.sleep(0.2)
    assert b"\x04" in emulator.get_bluetooth_sent()


def test_multiple_events_in_order(emulator, tmp_path):
    _start_event_callbacks(emulator, tmp_path)
    emulator.inject_button_single()
    emulator.inject_button_double()
    emulator.inject_imu_tap()
    time.sleep(0.3)

    sent = emulator.get_bluetooth_sent()
    assert b"\x01" in sent
    assert b"\x02" in sent
    assert b"\x04" in sent


def test_imu_direction_readable(emulator, tmp_path):
    """frame.imu.direction() returns settable pitch/roll/heading."""
    emulator.set_imu_direction(pitch=12.0, roll=-3.0, heading=90.0)
    lua = """
local d = frame.imu.direction()
-- Encode pitch as integer (0-255 safe range)
local p = math.floor(d.pitch)
frame.bluetooth.send(string.char(p & 0xFF))
"""
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    emulator.wait(timeout=3.0)

    sent = emulator.get_bluetooth_sent()
    assert len(sent) > 0
    assert sent[0][0] == 12


def test_battery_level_settable(emulator, tmp_path):
    emulator.set_battery_level(42)
    lua = "frame.bluetooth.send(string.char(frame.battery_level()))"
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    emulator.wait(timeout=3.0)

    sent = emulator.get_bluetooth_sent()
    assert len(sent) > 0
    assert sent[0][0] == 42


def test_emulator_stops_cleanly(emulator, tmp_path):
    """stop() should terminate a long-running Lua loop."""
    lua = """
while true do
    frame.sleep(0.05)
end
"""
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    time.sleep(0.2)
    assert emulator.is_running()
    emulator.stop()
    time.sleep(0.5)
    assert not emulator.is_running()
