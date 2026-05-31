"""
Tests for simple Tx message packing: TxCode, TxPlainText, TxSpriteCoords,
TxCaptureSettings, and TxAutoExpSettings.

All tests are pure data-transformation tests — no BLE connection required.
"""
import struct
import pytest

from brilliant_msg import (
    TxCode,
    TxPlainText,
    TxSpriteCoords,
    TxCaptureSettings,
    TxAutoExpSettings,
)


class TestTxCode:
    def test_default_packs_to_zero(self):
        assert TxCode().pack() == b'\x00'

    def test_arbitrary_value(self):
        assert TxCode(value=0x40).pack() == bytes([0x40])

    def test_max_byte_value(self):
        assert TxCode(value=255).pack() == b'\xff'

    def test_output_is_single_byte(self):
        assert len(TxCode(value=42).pack()) == 1

    def test_value_masked_to_byte(self):
        # Values > 255 are masked via & 0xFF
        assert TxCode(value=256).pack() == b'\x00'
        assert TxCode(value=257).pack() == b'\x01'


class TestTxPlainText:
    def test_header_layout(self):
        msg = TxPlainText(text="Hi", x=10, y=20, palette_offset=3, spacing=5)
        data = msg.pack()
        x, y, pal, spc = struct.unpack('>HHBB', data[:6])
        assert (x, y, pal, spc) == (10, 20, 3, 5)

    def test_text_appended_after_header(self):
        msg = TxPlainText(text="Hi", x=10, y=20, palette_offset=3, spacing=5)
        data = msg.pack()
        assert data[6:] == b'Hi'

    def test_total_length(self):
        msg = TxPlainText(text="ABC")
        assert len(msg.pack()) == 6 + 3  # 6-byte header + 3 ASCII bytes

    def test_defaults(self):
        msg = TxPlainText(text="X")
        x, y, pal, spc = struct.unpack('>HHBB', msg.pack()[:6])
        assert (x, y, pal, spc) == (1, 1, 1, 4)

    def test_utf8_multibyte_text(self):
        msg = TxPlainText(text="caf\u00e9")  # é is 2 bytes in UTF-8
        data = msg.pack()
        assert data[6:] == "café".encode('utf-8')
        assert len(data) == 6 + len("café".encode('utf-8'))

    def test_palette_offset_masked_to_nibble(self):
        # palette_offset & 0x0F
        msg = TxPlainText(text="A", palette_offset=0x1F)
        assert msg.pack()[4] == 0x0F

    def test_big_endian_coordinates(self):
        msg = TxPlainText(text="T", x=0x0102, y=0x0304)
        data = msg.pack()
        assert data[0:2] == b'\x01\x02'
        assert data[2:4] == b'\x03\x04'


class TestTxSpriteCoords:
    def test_pack_layout(self):
        msg = TxSpriteCoords(code=0x20, x=100, y=200, offset=5)
        code, x, y, offset = struct.unpack('>BHHB', msg.pack())
        assert (code, x, y, offset) == (0x20, 100, 200, 5)

    def test_total_length(self):
        assert len(TxSpriteCoords(code=1, x=1, y=1).pack()) == 6

    def test_default_offset_is_zero(self):
        msg = TxSpriteCoords(code=1, x=1, y=1)
        assert msg.pack()[-1] == 0

    def test_code_masked_to_byte(self):
        msg = TxSpriteCoords(code=0x1FF, x=1, y=1)
        assert msg.pack()[0] == 0xFF

    def test_big_endian_coordinates(self):
        msg = TxSpriteCoords(code=0, x=0x0102, y=0x0304)
        data = msg.pack()
        assert data[1:3] == b'\x01\x02'
        assert data[3:5] == b'\x03\x04'


class TestTxCaptureSettings:
    def test_total_length(self):
        assert len(TxCaptureSettings().pack()) == 6

    def test_defaults(self):
        data = TxCaptureSettings().pack()
        quality, half_res, pan_shifted, raw = struct.unpack('>BHHB', data)
        assert quality == 4
        assert half_res == 512 // 2
        assert pan_shifted == 0 + 140   # zero pan → stored as 140
        assert raw == 0

    def test_resolution_is_halved(self):
        _, half_res, _, _ = struct.unpack('>BHHB', TxCaptureSettings(resolution=720).pack())
        assert half_res == 360

    def test_pan_negative_minimum(self):
        _, _, pan_shifted, _ = struct.unpack('>BHHB', TxCaptureSettings(pan=-140).pack())
        assert pan_shifted == 0

    def test_pan_positive_maximum(self):
        _, _, pan_shifted, _ = struct.unpack('>BHHB', TxCaptureSettings(pan=140).pack())
        assert pan_shifted == 280

    def test_raw_flag_true(self):
        assert TxCaptureSettings(raw=True).pack()[-1] == 0x01

    def test_raw_flag_false(self):
        assert TxCaptureSettings(raw=False).pack()[-1] == 0x00

    def test_quality_index_range(self):
        for q in range(5):
            data = TxCaptureSettings(quality_index=q).pack()
            assert data[0] == q


class TestTxAutoExpSettings:
    def test_total_length(self):
        assert len(TxAutoExpSettings().pack()) == 9

    def test_metering_index_byte(self):
        for idx in range(3):
            assert TxAutoExpSettings(metering_index=idx).pack()[0] == idx

    def test_exposure_float_scaled_to_full_range(self):
        data_zero = TxAutoExpSettings(exposure=0.0).pack()
        data_full = TxAutoExpSettings(exposure=1.0).pack()
        assert data_zero[1] == 0
        assert data_full[1] == 255

    def test_exposure_speed_float_scaled(self):
        data = TxAutoExpSettings(exposure_speed=0.0).pack()
        assert data[2] == 0

    def test_white_balance_speed_byte_index(self):
        # Layout: B B B H B B H → index 6 is white_balance_speed
        data = TxAutoExpSettings(white_balance_speed=0.0).pack()
        assert data[6] == 0
        data = TxAutoExpSettings(white_balance_speed=1.0).pack()
        assert data[6] == 255

    def test_shutter_limit_big_endian_uint16(self):
        data = TxAutoExpSettings(shutter_limit=16383).pack()
        assert struct.unpack('>H', data[3:5])[0] == 16383

    def test_analog_gain_limit_byte(self):
        # Layout: B B B H B B H → index 5 is analog_gain_limit
        data = TxAutoExpSettings(analog_gain_limit=42).pack()
        assert data[5] == 42

    def test_rgb_gain_limit_big_endian_uint16(self):
        data = TxAutoExpSettings(rgb_gain_limit=1023).pack()
        assert struct.unpack('>H', data[7:9])[0] == 1023

    def test_defaults_pack_without_error(self):
        data = TxAutoExpSettings().pack()
        assert len(data) == 9
