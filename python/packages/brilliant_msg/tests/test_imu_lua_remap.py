"""
Locks the device-side imu.lua axis remap + scale by driving the *actual* Lua
module through the Halo emulator and inspecting the packed bytes it sends.

This is a regression guard for the "best effort" Halo axis mapping. If the
capture in examples/imu_diagnostic.py shows the mapping is wrong and imu.lua is
corrected, update the EXPECTED values here deliberately (in one place).

imu.lua behaviour (host axes: +X=right, +Y=forward, +Z=up):
  Halo  : magnetometer and accelerometer dies are mounted differently, so each
          has its OWN remap (both verified empirically in Sydney):
            compass: host (X,Y,Z) = ( devX,  devZ, -devY)
            accel  : host (X,Y,Z) = (-devZ,  devY,  devX) / 1000
  Frame : identity mapping; accel scaled by 1/4096
"""
import pathlib
import struct

import pytest

# The emulator (and its lupa/PIL deps) is a workspace package but not a declared
# test dep of brilliant_msg — skip cleanly if it isn't importable.
HaloEmulator = pytest.importorskip("halo_emulator").HaloEmulator

import brilliant_msg  # noqa: E402

IMU_LUA = pathlib.Path(brilliant_msg.__file__).parent / "lua" / "imu.lua"
IMU_DATA_MSG = 0x0A


def _run_send(hardware: str, compass, accel):
    """Load imu.lua in the emulator, set raw values, call send_imu_data, return
    the 6 floats (cx, cy, cz, ax, ay, az) it packed onto the wire."""
    emu = HaloEmulator(print_handler=None)
    emu.load_file(IMU_LUA)  # -> <sandbox>/imu.lua, require('imu') resolves it
    emu.connect()
    emu.execute_lua(f"frame.HARDWARE_VERSION = '{hardware}'")
    emu.set_imu_raw(compass=compass, accel=accel)
    emu.execute_lua(f"local imu = require('imu'); imu.send_imu_data({IMU_DATA_MSG})")

    sent = emu.get_bluetooth_sent()
    assert len(sent) == 1, f"expected exactly one BLE packet, got {len(sent)}"
    packet = sent[0]
    assert len(packet) == 26, f"expected 26-byte packet, got {len(packet)}"

    msg_code, *floats = struct.unpack("<Bxffffff", packet)
    assert msg_code == IMU_DATA_MSG
    return floats


class TestHaloRemap:
    def test_compass_axis_remap(self):
        # native device compass = (1, 2, 3)
        floats = _run_send("EMULATOR", compass=(1.0, 2.0, 3.0), accel=(0.0, 0.0, 0.0))
        cx, cy, cz = floats[0], floats[1], floats[2]
        # host (X,Y,Z) = (devX, devZ, -devY)
        assert (cx, cy, cz) == pytest.approx((1.0, 3.0, -2.0))

    def test_accel_axis_remap_and_scale(self):
        # native device accel = (1000, 2000, 3000) -> /1000 g after remap
        floats = _run_send("EMULATOR", compass=(0.0, 0.0, 0.0), accel=(1000.0, 2000.0, 3000.0))
        ax, ay, az = floats[3], floats[4], floats[5]
        # host (X,Y,Z) = (-devZ, devY, devX) / 1000
        assert (ax, ay, az) == pytest.approx((-3.0, 2.0, 1.0))

    def test_remap_is_a_proper_rotation(self):
        # A gravity-only "up" vector should come back unit length after scaling,
        # i.e. no axis is dropped or duplicated by the remap.
        floats = _run_send("EMULATOR", compass=(0.0, 0.0, 0.0), accel=(0.0, 0.0, 1000.0))
        ax, ay, az = floats[3], floats[4], floats[5]
        mag = (ax * ax + ay * ay + az * az) ** 0.5
        assert mag == pytest.approx(1.0)

    def test_compass_remap_preserves_magnitude(self):
        # Compass remap is a pure axis permutation/sign flip => magnitude preserved.
        floats = _run_send("EMULATOR", compass=(3.0, 4.0, 12.0), accel=(0.0, 0.0, 0.0))
        cx, cy, cz = floats[0], floats[1], floats[2]
        assert (cx * cx + cy * cy + cz * cz) ** 0.5 == pytest.approx(13.0)


class TestFrameRemap:
    def test_identity_mapping_and_scale(self):
        floats = _run_send("Frame", compass=(1.0, 2.0, 3.0), accel=(4096.0, 8192.0, 12288.0))
        assert floats[0:3] == pytest.approx((1.0, 2.0, 3.0))          # compass identity
        assert floats[3:6] == pytest.approx((1.0, 2.0, 3.0))          # accel /4096
