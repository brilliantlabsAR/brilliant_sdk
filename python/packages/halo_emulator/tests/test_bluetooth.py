"""Tests for frame.bluetooth.* stub."""
from __future__ import annotations

import shutil
import time
from pathlib import Path

LUA_DIR = Path(__file__).parent / "lua"


def test_ble_send_captured(emulator, tmp_path):
    """frame.bluetooth.send() output is captured in get_bluetooth_sent()."""
    lua = "frame.bluetooth.send('\\x09\\x01')"
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    emulator.wait(timeout=3.0)

    sent = emulator.get_bluetooth_sent()
    assert len(sent) == 1
    assert sent[0] == b"\x09\x01"


def test_ble_echo(emulator, tmp_path):
    """Injected BLE data triggers receive_callback, which echoes it back."""
    shutil.copy2(LUA_DIR / "ble_echo.lua", tmp_path / "ble_echo.lua")
    emulator.start("ble_echo.lua")

    time.sleep(0.15)  # let Lua register the callback
    payload = b"\x42\x00\x01\x61"
    emulator.inject_bluetooth_data(payload)
    time.sleep(0.3)

    sent = emulator.get_bluetooth_sent()
    assert any(s == payload for s in sent), f"Expected echo of {payload!r}, got {sent!r}"


def test_ble_multiple_sends(emulator, tmp_path):
    lua = """
frame.bluetooth.send('\\x01')
frame.bluetooth.send('\\x02')
frame.bluetooth.send('\\x03')
"""
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    emulator.wait(timeout=3.0)

    sent = emulator.get_bluetooth_sent()
    assert sent == [b"\x01", b"\x02", b"\x03"]


def test_clear_bluetooth_sent(emulator, tmp_path):
    lua = "frame.bluetooth.send('\\xAA')"
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    emulator.wait(timeout=3.0)

    assert len(emulator.get_bluetooth_sent()) == 1
    emulator.clear_bluetooth_sent()
    assert len(emulator.get_bluetooth_sent()) == 0


def test_ble_is_connected(emulator, tmp_path):
    lua = """
if frame.bluetooth.is_connected() then
    frame.bluetooth.send('\\x01')
else
    frame.bluetooth.send('\\x00')
end
"""
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    emulator.wait(timeout=3.0)

    sent = emulator.get_bluetooth_sent()
    assert sent == [b"\x01"], "Emulator should report as connected"
