"""Firmware 0.8.9 parity tests: palette, fonts, require, time, tap, sound, mic, speaker."""
from __future__ import annotations

import time

import pytest

from halo_emulator import HaloEmulator
from halo_emulator.display import _DEFAULT_PALETTE, DisplayBuffer


# ---------------------------------------------------------------- palette

def test_default_palette_matches_firmware():
    # Firmware defaults (lua_display.c, RGB since 0.8.8) — CSS named colours
    assert _DEFAULT_PALETTE[2] == (128, 128, 128)   # GREY
    assert _DEFAULT_PALETTE[3] == (255, 0, 0)       # RED
    assert _DEFAULT_PALETTE[6] == (150, 75, 0)      # BROWN
    assert _DEFAULT_PALETTE[12] == (25, 25, 112)    # NIGHTBLUE
    assert _DEFAULT_PALETTE[15] == (240, 248, 255)  # CLOUDBLUE
    assert len(_DEFAULT_PALETTE) == 16


def test_assign_color_index_is_zero_based():
    d = DisplayBuffer()
    d.assign_color(3, 1, 2, 3)
    assert d._palette[3] == (1, 2, 3)
    d.assign_color("RED", 9, 8, 7)
    assert d._palette[3] == (9, 8, 7)
    with pytest.raises(ValueError):
        d.assign_color(16, 0, 0, 0)
    with pytest.raises(ValueError):
        d.assign_color(0, 0, 0, 256)


def test_bitmap_palette_offset_does_not_wrap():
    d = DisplayBuffer()
    # 4bpp bitmap, one row of pixels: indices 0, 1, 15
    data = bytes([0x01, 0xF0])  # pixels: 0, 1, 15, 0
    d.bitmap(1, 1, 4, 16, 14, data)
    img = d._display
    # index 0 -> transparent (background stays black)
    assert img.getpixel((0, 0))[:3] == (0, 0, 0)
    # index 1 + offset 14 = 15 -> CLOUDBLUE
    assert img.getpixel((1, 0))[:3] == _DEFAULT_PALETTE[15]
    # index 15 + offset 14 = 29 > 15 -> dropped (no wrap)
    assert img.getpixel((2, 0))[:3] == (0, 0, 0)


def test_bitmap_offset_applies_to_custom_palette():
    d = DisplayBuffer()

    class Opts:
        x_scale = None
        y_scale = None
        palette_data = bytes([0, 0, 0, 10, 10, 10, 20, 20, 20])

    data = bytes([0x10])  # 4bpp pixels: 1, 0
    d.bitmap(1, 1, 2, 16, 1, data, Opts())
    # index 1 + offset 1 = 2 -> custom entry 2 = (20, 20, 20)
    assert d._display.getpixel((0, 0))[:3] == (20, 20, 20)


def test_bitmap_color_format_validation():
    d = DisplayBuffer()
    with pytest.raises(ValueError, match="Must be 0, 2, 4, or 16"):
        d.bitmap(1, 1, 8, 3, 0, bytes(8))
    with pytest.raises(ValueError, match="palette_offset"):
        d.bitmap(1, 1, 8, 2, 16, bytes(8))


# ---------------------------------------------------------------- fonts / text

def test_dogica_monospace_advance():
    d = DisplayBuffer()
    from halo_emulator.gfx_fonts import DOGICA_8PX
    assert all(g.x_advance == 8 for g in DOGICA_8PX.glyphs)
    assert DOGICA_8PX.first == 0x20 and DOGICA_8PX.last == 0x7E
    assert DOGICA_8PX.y_advance == 10


def test_set_font_validation():
    d = DisplayBuffer()
    d.set_font(1, 16, 1)  # DogicaBold at 16px
    assert d._font_id == 1 and d._font_mult == 2
    with pytest.raises(ValueError, match="invalid font id"):
        d.set_font(2)
    with pytest.raises(ValueError, match="multiple of 8"):
        d.set_font(0, 12)
    with pytest.raises(ValueError, match="invalid scale"):
        d.set_font(0, 8, 0)


def test_text_y_is_top_of_cap_box():
    d = DisplayBuffer()
    d.text("H", 10, 10, 0xFFFFFF)
    img = d._display
    # 'H' glyph: w=5 h=7 xOff=1 yOff=-7; cap box top at y=10 (1-based) = row 9
    white_rows = [
        y for y in range(256)
        if any(img.getpixel((x, y))[:3] == (255, 255, 255) for x in range(30))
    ]
    assert min(white_rows) == 9
    assert max(white_rows) == 15  # 7 rows of cap height


def test_text_skips_out_of_range_codepoints():
    d = DisplayBuffer()
    d.text("\n\t", 10, 10, 0xFFFFFF)  # control chars: no pixels, no advance
    img = d._display
    assert img.getpixel((10, 10))[:3] == (0, 0, 0)


def test_get_font_list_shape(emulator):
    emulator.connect()
    name0 = emulator.execute_lua("return frame.display.get_font_list()[0]")
    name1 = emulator.execute_lua("return frame.display.get_font_list()[1]")
    assert (name0, name1) == ("Dogica", "DogicaBold")


# ---------------------------------------------------------------- brightness / power_save

def test_brightness_level_percent_mapping():
    d = DisplayBuffer()
    d.set_brightness(2)
    assert d.brightness() == 100
    assert d.get_brightness() == 2
    d.brightness(60)  # non-exact percent
    assert d.get_brightness() == 0  # firmware fallback
    with pytest.raises(ValueError):
        d.set_brightness(3)
    with pytest.raises(ValueError):
        d.brightness(101)


def test_power_save_getter():
    d = DisplayBuffer()
    assert d.power_save() is False
    d.power_save(True)
    assert d.power_save() is True
    with pytest.raises(ValueError, match="argument must be boolean"):
        d.power_save(1)


# ---------------------------------------------------------------- require

def test_require_caches_and_returns_module_value(tmp_path, emulator):
    (emulator._sandbox_dir / "mymod.lua").write_text(
        "counter = (counter or 0) + 1\nreturn {value = 42}\n"
    )
    emulator.connect()
    assert emulator.execute_lua("return require('mymod').value") == 42
    # Second require comes from package.loaded: the chunk must not re-run
    emulator.execute_lua("require('mymod')")
    assert emulator.execute_lua("return counter") == 1
    assert emulator.execute_lua("return package.loaded['mymod'].value") == 42


def test_require_valueless_module_cached_as_true(emulator):
    (emulator._sandbox_dir / "sidefx.lua").write_text("x = 1\n")
    emulator.connect()
    assert emulator.execute_lua("return require('sidefx')") is True


# ---------------------------------------------------------------- time

def test_zone_setter_returns_normalised_zone(emulator):
    emulator.connect()
    assert emulator.execute_lua("return frame.time.zone('+3:30')") == "+03:30"
    assert emulator.execute_lua("return frame.time.zone()") == "+03:30"
    assert emulator.execute_lua("return frame.time.zone('-05:30')") == "-05:30"


def test_zone_negative_offset_applies_sign_to_minutes(emulator):
    emulator.connect()
    emulator.execute_lua("frame.time.utc(3600)")  # 01:00 UTC
    emulator.execute_lua("frame.time.zone('-00:30')")
    assert emulator.execute_lua("return frame.time.date().minute") == 30
    assert emulator.execute_lua("return frame.time.date().hour") == 0


def test_zone_validation(emulator):
    emulator.connect()
    for bad in ("'nonsense'", "'+15:00'", "'-13:00'", "'+01:15'", "'+14:30'"):
        with pytest.raises(Exception):
            emulator.execute_lua(f"frame.time.zone({bad})")


def test_date_fields(emulator):
    emulator.connect()
    # 2026-08-20 is a Thursday (weekday 4, 0=Sunday)
    emulator.execute_lua("frame.time.utc(1786867200)")
    assert emulator.execute_lua("return frame.time.date().weekday") in range(7)
    assert emulator.execute_lua("return frame.time.date()['day of year']") >= 0
    assert emulator.execute_lua("return frame.time.date()['is daylight saving']") is False


# ---------------------------------------------------------------- system

def test_on_wakeup_is_removed(emulator):
    emulator.connect()
    assert emulator.execute_lua("return frame.on_wakeup") is None


def test_light_sleep_restarts_script(emulator):
    (emulator._sandbox_dir / "main.lua").write_text(
        "frame.bluetooth.send('\\xAA')\n"
        "frame.light_sleep(0.05)\n"
        "frame.bluetooth.send('\\xBB')  -- unreachable: VM restarts on wake\n"
    )
    emulator.start("main.lua")
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline and len(emulator.get_bluetooth_sent()) < 2:
        time.sleep(0.01)
    emulator.stop()
    sent = emulator.get_bluetooth_sent()
    assert len(sent) >= 2
    assert all(m == b"\xaa" for m in sent)  # only the pre-sleep line ran, twice+


def test_standby_resumes_in_place(emulator):
    (emulator._sandbox_dir / "main.lua").write_text(
        "frame.standby(0.05)\n"
        "frame.bluetooth.send(frame.wakeup_source())\n"
    )
    emulator.start("main.lua")
    emulator.wait(timeout=2.0)
    assert emulator.get_bluetooth_sent() == [b"timeout"]


# ---------------------------------------------------------------- imu / tap

def test_tap_callback_receives_kind(emulator):
    (emulator._sandbox_dir / "main.lua").write_text(
        "frame.imu.tap_callback(function(kind)\n"
        "    frame.bluetooth.send(kind)\n"
        "end)\n"
        "while true do frame.sleep(0.01) end\n"
    )
    emulator.start("main.lua")
    time.sleep(0.2)
    emulator.inject_imu_tap("double")
    emulator.inject_imu_tap("triple")
    time.sleep(0.2)
    emulator.stop()
    assert emulator.get_bluetooth_sent() == [b"double", b"triple"]


def test_tap_config_defaults_and_update(emulator):
    emulator.connect()
    assert emulator.execute_lua("return frame.imu.tap_config().threshold") == 200
    assert emulator.execute_lua("return frame.imu.tap_config().mode") == "normal"
    assert emulator.execute_lua("return frame.imu.tap_config().axis") == "z"
    assert emulator.execute_lua(
        "return frame.imu.tap_config({threshold=500}).threshold"
    ) == 500
    with pytest.raises(Exception):
        emulator.execute_lua("frame.imu.tap_config({threshold=2000})")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.imu.tap_config({mode='bogus'})")


def test_imu_heading_always_zero(emulator):
    emulator.set_imu_direction(10.0, 20.0, 99.0)
    emulator.connect()
    assert emulator.execute_lua("return frame.imu.direction().heading") == 0.0
    assert emulator.execute_lua("return frame.imu.direction().pitch") == 10.0


# ---------------------------------------------------------------- sound

def test_sound_api(emulator):
    emulator.connect()
    assert emulator.execute_lua(
        "return frame.sound.play_async('blip', {duration_ms=50})"
    ) is True
    assert emulator.execute_lua("return frame.sound.is_playing()") is True
    emulator.execute_lua("frame.sound.stop()")
    assert emulator.execute_lua("return frame.sound.is_playing()") is False
    ok, err, code = emulator.execute_lua(
        "local ok, err, code = frame.sound.play('bogus'); return ok, err, code"
    )
    assert ok is None and err == "unknown sound preset" and code == -2
    with pytest.raises(Exception):
        emulator.execute_lua("frame.sound.play('blip', {sample_rate=44100})")


# ---------------------------------------------------------------- speaker

def test_speaker_start_validation(emulator):
    emulator.connect()
    emulator.execute_lua(
        "frame.speaker.start{encoder='lc3', sample_rate=16000, duration=1000, "
        "channels=1, bitrate=32000, volume=50}"
    )
    # 0.8.9 per-stream loudness fields; start() while streaming reconfigures
    emulator.execute_lua("frame.speaker.start{gain=12, budget=100}")
    # any encoder other than 'lc3' falls back to pcm, as on firmware
    emulator.execute_lua("frame.speaker.start{encoder='mp3'}")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.start()")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.start{sample_rate=44100}")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.start{channels=3}")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.start{bit_depth=8}")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.start{encoder='lc3', duration=500}")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.start{encoder='lc3', bitrate=100000}")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.start{volume=101}")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.start{gain=13}")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.start{budget=5}")


def test_speaker_play_and_volume_semantics(emulator):
    emulator.connect()
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.play('\\x00\\x01')")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.volume(80)")
    emulator.execute_lua("frame.speaker.start{volume=30}")
    assert emulator.execute_lua("return frame.speaker.volume()") == 30
    emulator.execute_lua("frame.speaker.play('')")
    emulator.execute_lua("frame.speaker.volume(80)")
    assert emulator.execute_lua("return frame.speaker.volume()") == 80
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.volume(101)")
    emulator.execute_lua("frame.speaker.stop()")
    emulator.execute_lua("frame.speaker.stop()")  # no-op when already stopped
    with pytest.raises(Exception):
        emulator.execute_lua("frame.speaker.play('\\x00')")


# ---------------------------------------------------------------- microphone

def test_microphone_read_semantics(emulator):
    emulator.connect()
    # nil while stopped
    assert emulator.execute_lua("return frame.microphone.read(64)") is None
    assert emulator.execute_lua("return frame.microphone.status()") == "stopped"
    emulator.execute_lua("frame.microphone.start{sample_rate=16000, bit_depth=8}")
    assert emulator.execute_lua("return frame.microphone.status()") == "streaming"
    # "" while streaming with no data
    assert emulator.execute_lua("return frame.microphone.read(64)") == ""
    emulator.inject_microphone_data(b"\x01\x02\x03\x04\x05\x06")
    # partial read, even-truncated
    assert emulator.execute_lua("return #frame.microphone.read(4)") == 4
    assert emulator.execute_lua("return #frame.microphone.read(64)") == 2


def test_microphone_validation(emulator):
    emulator.connect()
    with pytest.raises(Exception):
        emulator.execute_lua("frame.microphone.start{sample_rate=44100}")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.microphone.start{bit_depth=12}")
    with pytest.raises(Exception):
        emulator.execute_lua(
            "frame.microphone.start{encoder='lc3', duration=500}"
        )
    with pytest.raises(Exception):
        emulator.execute_lua("frame.microphone.start(); frame.microphone.read(3)")
    with pytest.raises(Exception):
        emulator.execute_lua("frame.microphone.read(4098)")


def test_microphone_aec_voice_toggles(emulator):
    emulator.connect()
    assert emulator.execute_lua("return frame.microphone.aec()") is False
    emulator.execute_lua("frame.microphone.aec(true)")
    assert emulator.execute_lua("return frame.microphone.aec()") is True
    assert emulator.execute_lua("return frame.microphone.voice()") is False


# ---------------------------------------------------------------- bluetooth

def test_empty_send_transmits_nothing(emulator):
    emulator.connect()
    emulator.execute_lua("frame.bluetooth.send('')")
    emulator.execute_lua("frame.bluetooth.send('x')")
    assert emulator.get_bluetooth_sent() == [b"x"]


def test_firmware_version_marker(emulator):
    emulator.connect()
    assert emulator.execute_lua("return frame.FIRMWARE_VERSION") == "0.8.9-emulator"
