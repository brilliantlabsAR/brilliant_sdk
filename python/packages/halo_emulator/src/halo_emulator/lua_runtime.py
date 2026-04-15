"""Build the lupa Lua 5.3 runtime and register all frame.* stubs."""
from __future__ import annotations

import threading
from pathlib import Path
from typing import Any

import lupa.lua53 as lupa

from halo_emulator.display import DisplayBuffer
from halo_emulator.event_queue import EventQueue
from halo_emulator.stubs.bluetooth import BluetoothStub
from halo_emulator.stubs.button import ButtonStub
from halo_emulator.stubs.compression import CompressionStub
from halo_emulator.stubs.file_stubs import FileStub
from halo_emulator.stubs.imu import ImuStub
from halo_emulator.stubs.microphone import MicrophoneStub
from halo_emulator.stubs.speaker import SpeakerStub
from halo_emulator.stubs.system import SystemStub
from halo_emulator.stubs.time_stubs import TimeStub


def build_lua_runtime(
    display: DisplayBuffer,
    bluetooth: BluetoothStub,
    button: ButtonStub,
    imu: ImuStub,
    system: SystemStub,
    time_stub: TimeStub,
    file_stub: FileStub,
    compression: CompressionStub,
    speaker: SpeakerStub,
    microphone: MicrophoneStub,
    sandbox_dir: Path,
) -> lupa.LuaRuntime:
    """
    Create a Lua 5.3 runtime and populate the global `frame` table with all
    Python stub implementations. Returns the ready-to-use LuaRuntime.
    """
    rt = lupa.LuaRuntime(unpack_returned_tuples=True, encoding="latin-1")

    # Inject runtime reference into stubs that need to build Lua tables
    imu._runtime = rt
    time_stub._runtime = rt

    g = rt.globals()

    # ------------------------------------------------------------------ frame table

    frame = rt.table()

    # ---- constants ----
    frame.HARDWARE_VERSION = "EMULATOR"
    frame.FIRMWARE_VERSION = "0.0.0-emulator"
    frame.GIT_TAG = "emulator"
    frame.SE_REVISION = "0.0.0"

    # ---- system ----
    frame.sleep = system.sleep
    frame.light_sleep = system.light_sleep
    frame.standby = system.standby
    frame.on_wakeup = system.on_wakeup
    frame.stay_awake = system.stay_awake
    frame.reboot = system.reboot
    frame.battery_level = system.battery_level
    frame.battery_voltage = system.battery_voltage
    frame.battery_charging = system.battery_charging
    frame.ship_mode = system.ship_mode
    frame.charge = system.charge
    frame.wakeup_source = system.wakeup_source
    frame.get_eui = system.get_eui
    frame.get_se_revision = system.get_se_revision

    # frame.yield is a Lua keyword — must be set via execute() after registering frame
    g.frame = frame
    rt.execute("frame['yield'] = _py_yield")
    g._py_yield = system.yield_
    rt.execute("frame['yield'] = _py_yield; _py_yield = nil")

    # ---- time ----
    time_tbl = rt.table()
    time_tbl.utc = time_stub.utc
    time_tbl.zone = time_stub.zone
    time_tbl.date = time_stub.date
    frame.time = time_tbl

    # ---- file ----
    file_tbl = rt.table()
    file_tbl.open = file_stub.open
    file_tbl.remove = file_stub.remove
    file_tbl.remove_all = file_stub.remove_all
    file_tbl.rename = file_stub.rename
    file_tbl.listdir = file_stub.listdir
    file_tbl.mkdir = file_stub.mkdir
    frame.file = file_tbl

    # ---- button ----
    btn_tbl = rt.table()
    btn_tbl.single = button.single
    btn_tbl.double = button.double
    btn_tbl.long = button.long
    frame.button = btn_tbl

    # ---- bluetooth ----
    bt_tbl = rt.table()
    bt_tbl.is_connected = bluetooth.is_connected
    bt_tbl.address = bluetooth.address
    bt_tbl.max_length = bluetooth.max_length
    bt_tbl.send = bluetooth.send
    bt_tbl.receive_callback = bluetooth.receive_callback
    frame.bluetooth = bt_tbl

    # ---- imu ----
    imu_tbl = rt.table()
    imu_tbl.tap_callback = imu.tap_callback
    imu_tbl.direction = imu.direction
    imu_tbl.raw = imu.raw
    imu_tbl.config = imu.config
    frame.imu = imu_tbl

    # ---- compression ----
    comp_tbl = rt.table()
    comp_tbl.process_function = compression.process_function
    comp_tbl.decompress = compression.decompress
    frame.compression = comp_tbl

    # ---- speaker (no-op) ----
    spk_tbl = rt.table()
    spk_tbl.start = speaker.start
    spk_tbl.play = speaker.play
    spk_tbl.volume = speaker.volume
    spk_tbl.stop = speaker.stop
    frame.speaker = spk_tbl

    # ---- microphone (no-op) ----
    mic_tbl = rt.table()
    mic_tbl.start = microphone.start
    mic_tbl.read = microphone.read
    mic_tbl.gain = microphone.gain
    mic_tbl.stop = microphone.stop
    mic_tbl.aad_callback = microphone.aad_callback
    frame.microphone = mic_tbl

    # ---- display ----
    disp_tbl = rt.table()
    disp_tbl.assign_color = display.assign_color
    disp_tbl.assign_color_ycbcr = display.assign_color_ycbcr
    disp_tbl.bitmap = display.bitmap
    disp_tbl.text = display.text
    disp_tbl.char = display.char
    disp_tbl.set_font = display.set_font
    disp_tbl.get_font_list = display.get_font_list
    disp_tbl.set_pixel = display.set_pixel
    disp_tbl.line = display.line
    disp_tbl.rect = display.rect
    disp_tbl.circle = display.circle
    disp_tbl.polygon = display.polygon
    disp_tbl.clear = display.clear
    disp_tbl.show = display.show
    disp_tbl.power_save = display.power_save
    disp_tbl.width = display.width
    disp_tbl.height = display.height
    disp_tbl.set_brightness = display.set_brightness
    disp_tbl.get_brightness = display.get_brightness
    disp_tbl.brightness = display.brightness
    disp_tbl.set_pan = display.set_pan
    disp_tbl.get_pan = display.get_pan
    frame.display = disp_tbl

    # ---- final frame registration ----
    g.frame = frame

    # ---- require() override — load modules from sandbox_dir ----
    sandbox_path = str(sandbox_dir).replace("\\", "/")
    rt.execute(f"""
local _sandbox_root = '{sandbox_path}'
local _original_require = require
require = function(modname)
    -- Try path-separated form first: data.min -> data/min.lua
    local full_path = _sandbox_root .. '/' .. modname:gsub('%.', '/') .. '.lua'
    local f = io.open(full_path, 'r')
    if not f then
        -- Fall back to literal-dot form: data.min -> data.min.lua
        -- (used by upload_stdlua_libs and load_file which place files flat)
        full_path = _sandbox_root .. '/' .. modname .. '.lua'
        f = io.open(full_path, 'r')
    end
    if f then
        local src = f:read('*all')
        f:close()
        local chunk, err = load(src, modname, 't')
        if chunk then
            return chunk()
        else
            error(err)
        end
    end
    return _original_require(modname)
end
""")

    return rt
