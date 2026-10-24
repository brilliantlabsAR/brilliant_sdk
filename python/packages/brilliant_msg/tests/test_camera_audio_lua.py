"""
Drives the device-side camera.lua and audio.lua (and their hand-minified
.min.lua twins) against a mock `frame` API, checking packet sizes and the
non-blocking capture API, and that each .min.lua behaves like its source.
"""
import pathlib

import pytest

lupa = pytest.importorskip("lupa")

import brilliant_msg  # noqa: E402

LUA_DIR = pathlib.Path(brilliant_msg.__file__).parent / "lua"
IMAGE_MSG = 0x07
IMAGE_FINAL_MSG = 0x08
AUDIO_DATA_NON_FINAL_MSG = 0x05

MOCK_FRAME = r"""
sent, sleeps, mic_reads = {}, 0, {}
local image, pos, polls, ready_after = '', 0, 0, 0

function set_image(data, polls_until_ready)
    image, pos, polls, ready_after = data, 0, 0, polls_until_ready
end

frame = {
    HARDWARE_VERSION = 'Halo',
    bluetooth = {
        max_length = function() return max_length end,
        send = function(data) sent[#sent + 1] = data end,
    },
    camera = {
        capture = function(args) pos = 0 end,
        image_ready = function() polls = polls + 1; return polls > ready_after end,
        read = function(n)
            if pos >= #image then return nil end
            local chunk = image:sub(pos + 1, pos + n)
            pos = pos + #chunk
            return chunk
        end,
    },
    microphone = {
        start = function() end,
        stop = function() end,
        read = function(n) mic_reads[#mic_reads + 1] = n; return string.rep('a', n) end,
    },
    time = { utc = function() return 0 end },
    sleep = function(s) sleeps = sleeps + s end,
}
"""


def _runtime(lib_file, max_length):
    lua = lupa.LuaRuntime(encoding=None)
    lua.execute(b"max_length = " + str(max_length).encode())
    lua.execute(MOCK_FRAME.encode())
    module = lua.execute(b"return load(...)()", (LUA_DIR / lib_file).read_bytes())
    return lua, module


def _sent(lua):
    return [bytes(p) for p in lua.globals().sent.values()]


def _image(n):
    return bytes(i % 251 for i in range(n))


@pytest.mark.parametrize("lib_file", ["camera.lua", "camera.min.lua"])
@pytest.mark.parametrize("max_length,chunk", [(508, 240), (247, 240), (100, 99)])
def test_capture_and_send_packet_size(lib_file, max_length, chunk):
    lua, camera = _runtime(lib_file, max_length)
    image = _image(5000)
    lua.globals().set_image(image, 3)

    camera.capture_and_send(lua.table_from({b"resolution": 640, b"quality": b"MEDIUM", b"pan": 0}))

    sent = _sent(lua)
    assert sent[-1] == bytes([IMAGE_FINAL_MSG])
    body = sent[:-1]
    assert all(p[0] == IMAGE_MSG for p in body)
    assert max(len(p) - 1 for p in body) == chunk
    assert b"".join(p[1:] for p in body) == image


@pytest.mark.parametrize("lib_file", ["camera.lua", "camera.min.lua"])
def test_send_pending_non_blocking(lib_file):
    lua, camera = _runtime(lib_file, 508)
    image = _image(1000)  # 240 + 240 + 240 + 240 + 40: five packets
    lua.globals().set_image(image, 2)

    assert camera.is_sending() is False
    assert camera.send_pending(1) is False  # nothing pending

    camera.start_capture(lua.table_from({b"resolution": 640, b"quality": b"MEDIUM", b"pan": 0}))
    assert camera.is_sending() is True

    # not ready for two polls: no packets, and a 1 ms yield each time
    assert camera.send_pending(1) is True
    assert camera.send_pending(1) is True
    assert _sent(lua) == []
    assert lua.globals().sleeps == pytest.approx(0.002)

    assert camera.send_pending(2) is True
    assert len(_sent(lua)) == 2
    assert camera.send_pending(2) is True
    assert len(_sent(lua)) == 4
    # last data packet, then the final-chunk marker on the next read
    assert camera.send_pending(2) is False
    assert camera.is_sending() is False

    sent = _sent(lua)
    assert sent[-1] == bytes([IMAGE_FINAL_MSG])
    assert b"".join(p[1:] for p in sent[:-1]) == image
    assert lua.globals().sleeps == pytest.approx(0.002)  # no sleeping once ready


@pytest.mark.parametrize("lib_file", ["audio.lua", "audio.min.lua"])
@pytest.mark.parametrize("max_length,read", [(508, 240), (247, 240), (100, 98), (101, 100)])
def test_audio_packet_size(lib_file, max_length, read):
    lua, audio = _runtime(lib_file, max_length)

    assert audio.read_and_send_audio() == read

    assert list(lua.globals().mic_reads.values()) == [read]
    sent = _sent(lua)
    assert sent == [bytes([AUDIO_DATA_NON_FINAL_MSG]) + b"a" * read]


def test_audio_packet_size_follows_mtu_changes():
    lua, audio = _runtime("audio.lua", 508)
    audio.read_and_send_audio()
    lua.execute(b"max_length = 100")
    audio.read_and_send_audio()
    assert list(lua.globals().mic_reads.values()) == [240, 98]
