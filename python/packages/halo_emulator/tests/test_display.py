"""Tests for frame.display.* stub and DisplayBuffer."""
from __future__ import annotations

import shutil
from pathlib import Path

import pytest

LUA_DIR = Path(__file__).parent / "lua"


def _copy_lua(name: str, sandbox: Path) -> None:
    shutil.copy2(LUA_DIR / name, sandbox / name)


def test_framebuffer_initial_size(emulator):
    """Freshly constructed emulator returns a 256×256 image."""
    img = emulator.get_framebuffer()
    assert img.size == (256, 256)


def test_display_text_renders_pixels(emulator, tmp_path):
    _copy_lua("hello_display.lua", tmp_path)
    emulator.start("hello_display.lua")
    emulator.wait(timeout=3.0)

    img = emulator.get_framebuffer()
    assert img.size == (256, 256)

    # At least some pixels should be non-black after rendering white text
    pixels = list(img.getdata())
    bright = sum(1 for r, g, b, a in pixels if r + g + b > 30)
    assert bright > 0, "Expected non-black pixels after text render"


def test_display_clear_fills_color(emulator, tmp_path):
    lua = "frame.display.clear(0xFF0000); frame.display.show()"
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    emulator.wait(timeout=3.0)

    img = emulator.get_framebuffer()
    r, g, b, _ = img.getpixel((128, 128))
    assert r > 200, "Expected red-dominant pixel after clear(0xFF0000)"
    assert g < 50
    assert b < 50


def test_display_set_pixel(emulator, tmp_path):
    lua = """
frame.display.clear(0)
frame.display.set_pixel(5, 5, 0x00FF00)
frame.display.show()
"""
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    emulator.wait(timeout=3.0)

    img = emulator.get_framebuffer()
    r, g, b, _ = img.getpixel((4, 4))  # 1-based → 0-based
    assert g > 200, "Expected green pixel at (5,5)"
    assert r < 50
    assert b < 50


def test_display_shapes(emulator, tmp_path):
    _copy_lua("draw_shapes.lua", tmp_path)
    emulator.start("draw_shapes.lua")
    emulator.wait(timeout=3.0)

    img = emulator.get_framebuffer()
    pixels = list(img.getdata())
    non_black = sum(1 for r, g, b, a in pixels if r + g + b > 10)
    assert non_black > 100, "Expected visible shapes on display"


def test_display_width_height(emulator, tmp_path):
    """frame.display.width() and height() both return 256."""
    lua = """
local w = frame.display.width()
local h = frame.display.height()
-- Send width and height each as two bytes (big-endian uint16)
frame.bluetooth.send(string.char(w >> 8) .. string.char(w & 0xFF)
                  .. string.char(h >> 8) .. string.char(h & 0xFF))
"""
    (tmp_path / "main.lua").write_text(lua)
    emulator.start()
    emulator.wait(timeout=3.0)

    sent = emulator.get_bluetooth_sent()
    assert len(sent) > 0
    data = sent[0]
    assert len(data) == 4
    w = (data[0] << 8) | data[1]
    h = (data[2] << 8) | data[3]
    assert w == 256
    assert h == 256
