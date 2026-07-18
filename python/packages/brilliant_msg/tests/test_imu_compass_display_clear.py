"""
Regression guard for the Halo "clear between updates" fix (IMU compass task 3).

Halo draws directly to display memory — there is no double-buffering, so a redraw
must be preceded by an explicit ``frame.display.clear()`` or successive updates
overdraw. Frame instead presents a fresh buffer on every ``show()``, so the
``frame.display.text(' ', 1, 1)`` + ``show()`` "space trick" wipes the previous
frame there but is a no-op on Halo.

The imu_compass frame-side app (a Flutter example) branches on
``frame.HARDWARE_VERSION`` to issue a real clear on Halo. This test drives the
*actual* ``clear_display`` helper from that file through the Halo emulator (an
immediate-mode display, like real Halo) and asserts the framebuffer is genuinely
cleared, and that the Frame-only space trick is a no-op on that display (which is
exactly why the Halo branch has to exist). It also structurally guards the
inline clear-before-draw in the text/streaming handlers.
"""
import pathlib
import re

import pytest

# The emulator (and its lupa/PIL deps) is a workspace package but not a declared
# test dep of brilliant_msg — skip cleanly if it isn't importable.
HaloEmulator = pytest.importorskip("halo_emulator").HaloEmulator

# flutter/.../imu_compass/assets/frame_app.lua, relative to the monorepo root.
_REPO_ROOT = pathlib.Path(__file__).resolve().parents[4]
FRAME_APP_LUA = (
    _REPO_ROOT
    / "flutter/packages/simple_brilliant_app/example/imu_compass/assets/frame_app.lua"
)


def _frame_app_source() -> str:
    assert FRAME_APP_LUA.is_file(), f"frame_app.lua not found at {FRAME_APP_LUA}"
    return FRAME_APP_LUA.read_text()


def _extract_clear_display(source: str) -> str:
    """Slice the real ``function clear_display() ... end`` block out of the file."""
    m = re.search(r"function clear_display\(\).*?\nend\n", source, re.DOTALL)
    assert m is not None, "clear_display() not found in frame_app.lua"
    return m.group(0)


def _has_ink(emu) -> bool:
    """True if the framebuffer has any non-black pixel."""
    return emu.get_framebuffer().convert("RGB").getbbox() is not None


def _new_emu_with_clear_display():
    emu = HaloEmulator(print_handler=None)
    emu.connect()
    emu.execute_lua(_extract_clear_display(_frame_app_source()))
    return emu


class TestClearDisplayHelper:
    def test_halo_path_actually_clears(self):
        # Halo (HARDWARE_VERSION != 'Frame') must issue a real frame.display.clear().
        emu = _new_emu_with_clear_display()
        emu.execute_lua("frame.HARDWARE_VERSION = 'EMULATOR'")
        emu.execute_lua("frame.display.text('Loading...', 1, 1)")
        assert _has_ink(emu), "precondition: text should have been drawn"

        emu.execute_lua("clear_display()")
        assert not _has_ink(emu), "Halo path must clear the framebuffer before redraw"

    def test_frame_space_trick_is_a_noop_on_immediate_display(self):
        # The Frame branch draws a space + show(). On an immediate-mode (Halo-like)
        # display that does NOT clear anything — which is the whole reason the Halo
        # branch is required. Guards against "just use the Frame path everywhere".
        emu = _new_emu_with_clear_display()
        emu.execute_lua("frame.HARDWARE_VERSION = 'Frame'")
        emu.execute_lua("frame.display.text('Loading...', 1, 1)")
        assert _has_ink(emu)

        emu.execute_lua("clear_display()")
        assert _has_ink(emu), "Frame space-trick should not wipe an immediate-mode display"


class TestHandlersClearBeforeDraw:
    """Structural guard: the redraw handlers clear on the Halo path before drawing."""

    def test_text_handler_clears_on_halo_before_drawing(self):
        src = _frame_app_source()
        m = re.search(r"handlers\[TEXT_MSG\] = function.*?\n\tend\n", src, re.DOTALL)
        assert m is not None, "TEXT_MSG handler not found"
        body = m.group(0)
        # A Halo-gated clear() must appear before the first display.text() draw.
        clear_pos = body.find("frame.display.clear()")
        draw_pos = body.find("frame.display.text(")
        assert clear_pos != -1, "TEXT_MSG handler must clear on the Halo path"
        assert clear_pos < draw_pos, "clear must precede the redraw"
        assert "HARDWARE_VERSION" in body[:clear_pos], "clear must be gated to non-Frame"

    def test_start_imu_handler_clears_on_halo_before_drawing(self):
        src = _frame_app_source()
        m = re.search(r"handlers\[START_IMU_MSG\] = function.*?\n\tend\n", src, re.DOTALL)
        assert m is not None, "START_IMU_MSG handler not found"
        body = m.group(0)
        clear_pos = body.find("frame.display.clear()")
        draw_pos = body.find('frame.display.text("Streaming')
        assert clear_pos != -1, "START_IMU_MSG handler must clear on the Halo path"
        assert clear_pos < draw_pos, "clear must precede the redraw"
