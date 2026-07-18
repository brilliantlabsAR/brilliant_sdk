"""
Tests for Rx message parsing and supporting classes: RxAudio.to_wav_bytes,
RxMeteringData, RxAutoExpResult, RxIMU (including IMUData and SensorBuffer),
RxTap, and BrilliantMsg handler dispatch.

Tests that call handle_data() are async because those methods use
asyncio.create_task() internally to write to their queues.
"""
import asyncio
import math
import struct

import pytest

from brilliant_msg import (
    BrilliantMsg,
    RxAudio,
    RxAutoExpResult,
    RxIMU,
    RxMeteringData,
    RxTap,
)
from brilliant_msg.rx_imu import IMUData, IMURawData, SensorBuffer


# ---------------------------------------------------------------------------
# RxAudio.to_wav_bytes  (static, no asyncio needed)
# ---------------------------------------------------------------------------

class TestToWavBytes:
    def test_header_starts_with_riff(self):
        wav = RxAudio.to_wav_bytes(b'\x00' * 8)
        assert wav[:4] == b'RIFF'

    def test_wave_marker_present(self):
        wav = RxAudio.to_wav_bytes(b'\x00' * 8)
        assert wav[8:12] == b'WAVE'

    def test_fmt_chunk_present(self):
        wav = RxAudio.to_wav_bytes(b'\x00' * 8)
        assert wav[12:16] == b'fmt '

    def test_data_chunk_present(self):
        wav = RxAudio.to_wav_bytes(b'\x00' * 8)
        assert wav[36:40] == b'data'

    def test_header_total_size(self):
        # Standard PCM WAV header is 44 bytes
        pcm = b'\x00' * 16
        wav = RxAudio.to_wav_bytes(pcm)
        assert len(wav) == 44 + len(pcm)

    def test_file_size_field(self):
        pcm = b'\x00' * 100
        wav = RxAudio.to_wav_bytes(pcm)
        # RIFF file_size = 36 + data_size
        file_size = struct.unpack('<I', wav[4:8])[0]
        assert file_size == 36 + 100

    def test_data_size_field(self):
        pcm = b'\x00' * 50
        wav = RxAudio.to_wav_bytes(pcm)
        data_size = struct.unpack('<I', wav[40:44])[0]
        assert data_size == 50

    def test_sample_rate_in_header(self):
        wav = RxAudio.to_wav_bytes(b'\x00' * 8, sample_rate=16000)
        sample_rate = struct.unpack('<I', wav[24:28])[0]
        assert sample_rate == 16000

    def test_pcm_format_is_1(self):
        wav = RxAudio.to_wav_bytes(b'\x00' * 4)
        audio_format = struct.unpack('<H', wav[20:22])[0]
        assert audio_format == 1  # PCM

    def test_8bit_signed_zero_maps_to_unsigned_128(self):
        # Signed 0 → unsigned 128 (WAV midpoint silence)
        wav = RxAudio.to_wav_bytes(bytes([0x00]), bits_per_sample=8)
        assert wav[44] == 128

    def test_8bit_signed_127_maps_to_255(self):
        wav = RxAudio.to_wav_bytes(bytes([127]), bits_per_sample=8)
        assert wav[44] == 255

    def test_8bit_signed_negative128_maps_to_0(self):
        # -128 stored as unsigned 128 in a byte; → 0 in WAV
        wav = RxAudio.to_wav_bytes(bytes([128]), bits_per_sample=8)
        assert wav[44] == 0

    def test_8bit_signed_minus1_maps_to_127(self):
        # -1 stored as 255 in a byte; → 127 in WAV
        wav = RxAudio.to_wav_bytes(bytes([255]), bits_per_sample=8)
        assert wav[44] == 127

    def test_16bit_pcm_not_converted(self):
        # 16-bit samples are passed through unchanged
        sample = struct.pack('<h', -1000)   # -1000 as signed int16
        wav = RxAudio.to_wav_bytes(sample, bits_per_sample=16)
        assert wav[44:46] == sample


# ---------------------------------------------------------------------------
# IMUData computed properties  (no asyncio needed)
# ---------------------------------------------------------------------------

class TestIMUData:
    def test_pitch_flat(self):
        # Gravity along +Z: accel = (0, 0, 1) → pitch = 0°
        d = IMUData(compass=(0, 0, 0), accel=(0.0, 0.0, 1.0))
        assert d.pitch == pytest.approx(0.0, abs=1e-6)

    def test_pitch_90_degrees(self):
        # accel = (0, 1, 0) → atan2(1, 0) = 90°
        d = IMUData(compass=(0, 0, 0), accel=(0.0, 1.0, 0.0))
        assert d.pitch == pytest.approx(90.0, abs=1e-6)

    def test_roll_flat(self):
        d = IMUData(compass=(0, 0, 0), accel=(0.0, 0.0, 1.0))
        assert d.roll == pytest.approx(0.0, abs=1e-6)

    def test_roll_90_degrees(self):
        # accel = (1, 0, 0) → atan2(1, 0) = 90°
        d = IMUData(compass=(0, 0, 0), accel=(1.0, 0.0, 0.0))
        assert d.roll == pytest.approx(90.0, abs=1e-6)

    def test_pitch_formula(self):
        accel = (0.5, 0.3, 0.8)
        d = IMUData(compass=(0, 0, 0), accel=accel)
        expected = math.atan2(accel[1], accel[2]) * 180.0 / math.pi
        assert d.pitch == pytest.approx(expected, abs=1e-9)

    def test_roll_formula(self):
        accel = (0.5, 0.3, 0.8)
        d = IMUData(compass=(0, 0, 0), accel=accel)
        expected = math.atan2(accel[0], accel[2]) * 180.0 / math.pi
        assert d.roll == pytest.approx(expected, abs=1e-9)


# ---------------------------------------------------------------------------
# SensorBuffer  (no asyncio needed)
# ---------------------------------------------------------------------------

class TestSensorBuffer:
    def test_empty_buffer_average_is_zero(self):
        buf = SensorBuffer(5)
        assert buf.average == (0.0, 0.0, 0.0)

    def test_single_sample_average_equals_sample(self):
        buf = SensorBuffer(5)
        buf.add((3.0, 6.0, 9.0))
        assert buf.average == (3.0, 6.0, 9.0)

    def test_two_sample_average(self):
        buf = SensorBuffer(5)
        buf.add((4.0, 8.0, 12.0))
        buf.add((2.0, 4.0,  6.0))
        # true division: (4+2)/2=3, (8+4)/2=6, (12+6)/2=9
        assert buf.average == (3.0, 6.0, 9.0)

    def test_fractional_average_preserved(self):
        # Regression guard: accel values are ~-1..1 g, so the average must NOT be
        # floored (the old '//' floored 0.5 -> 0.0, corrupting pitch/roll).
        buf = SensorBuffer(5)
        buf.add((0.5, 0.25, 0.9))
        avg = buf.average
        assert avg[0] == pytest.approx(0.5)
        assert avg[1] == pytest.approx(0.25)
        assert avg[2] == pytest.approx(0.9)

    def test_two_sample_fractional_average(self):
        buf = SensorBuffer(5)
        buf.add((0.2, 0.4, 0.6))
        buf.add((0.4, 0.6, 0.8))
        avg = buf.average
        assert avg[0] == pytest.approx(0.3)
        assert avg[1] == pytest.approx(0.5)
        assert avg[2] == pytest.approx(0.7)

    def test_oldest_sample_evicted_when_full(self):
        buf = SensorBuffer(2)
        buf.add((100.0, 0.0, 0.0))   # will be evicted
        buf.add((10.0, 0.0, 0.0))
        buf.add((20.0, 0.0, 0.0))
        avg_x, _, _ = buf.average
        # Only last two samples: (10+20)/2 = 15
        assert avg_x == 15.0

    def test_size_limit_maintained(self):
        buf = SensorBuffer(3)
        for i in range(10):
            buf.add((float(i), 0.0, 0.0))
        assert len(buf._buffer) == 3


# ---------------------------------------------------------------------------
# RxMeteringData.handle_data  (async: uses asyncio.create_task)
# ---------------------------------------------------------------------------

class TestRxMeteringData:
    async def test_handle_data_parses_six_rgb_bytes(self):
        rx = RxMeteringData()
        rx.queue = asyncio.Queue()
        # msg_code byte + 6 unsigned values
        data = bytes([0x12, 100, 150, 200, 50, 75, 125])
        rx.handle_data(data)
        await asyncio.sleep(0)   # let create_task run
        result = rx.queue.get_nowait()
        assert result == {
            'spot_r': 100, 'spot_g': 150, 'spot_b': 200,
            'matrix_r': 50, 'matrix_g': 75, 'matrix_b': 125,
        }

    async def test_handle_data_ignores_first_byte(self):
        rx = RxMeteringData()
        rx.queue = asyncio.Queue()
        # Regardless of the flag byte value the six data bytes start at offset 1
        for flag in (0x00, 0x12, 0xFF):
            rx.queue = asyncio.Queue()
            rx.handle_data(bytes([flag, 1, 2, 3, 4, 5, 6]))
            await asyncio.sleep(0)
            result = rx.queue.get_nowait()
            assert result['spot_r'] == 1

    async def test_no_queue_does_not_raise(self):
        rx = RxMeteringData()
        # queue is None by default — should log a warning and return cleanly
        rx.handle_data(bytes([0x12, 0, 0, 0, 0, 0, 0]))


# ---------------------------------------------------------------------------
# RxAutoExpResult.handle_data  (async)
# ---------------------------------------------------------------------------

class TestRxAutoExpResult:
    async def test_handle_data_parses_sixteen_floats(self):
        rx = RxAutoExpResult()
        rx.queue = asyncio.Queue()

        values = [0.1, 16383.0, 1.5, 2.0, 3.0, 4.0, 0.5, 0.6,
                  10.0, 20.0, 30.0, 15.0, 5.0, 6.0, 7.0, 3.5]
        data = bytes([0x11]) + struct.pack('<16f', *values)
        rx.handle_data(data)
        await asyncio.sleep(0)
        result = rx.queue.get_nowait()

        assert result['error'] == pytest.approx(values[0], rel=1e-5)
        assert result['shutter'] == pytest.approx(values[1], rel=1e-5)
        assert result['analog_gain'] == pytest.approx(values[2], rel=1e-5)
        assert result['red_gain'] == pytest.approx(values[3], rel=1e-5)
        assert result['green_gain'] == pytest.approx(values[4], rel=1e-5)
        assert result['blue_gain'] == pytest.approx(values[5], rel=1e-5)

    async def test_brightness_nested_structure(self):
        rx = RxAutoExpResult()
        rx.queue = asyncio.Queue()

        values = [0.0] * 6 + [0.5, 0.6, 10.0, 20.0, 30.0, 15.0, 5.0, 6.0, 7.0, 3.5]
        data = bytes([0x11]) + struct.pack('<16f', *values)
        rx.handle_data(data)
        await asyncio.sleep(0)
        result = rx.queue.get_nowait()

        b = result['brightness']
        assert b['center_weighted_average'] == pytest.approx(values[6], rel=1e-5)
        assert b['scene'] == pytest.approx(values[7], rel=1e-5)
        assert b['matrix']['r'] == pytest.approx(values[8], rel=1e-5)
        assert b['matrix']['average'] == pytest.approx(values[11], rel=1e-5)
        assert b['spot']['r'] == pytest.approx(values[12], rel=1e-5)
        assert b['spot']['average'] == pytest.approx(values[15], rel=1e-5)


# ---------------------------------------------------------------------------
# RxIMU.handle_data  (async)
# ---------------------------------------------------------------------------

class TestRxIMU:
    def _make_imu_packet(self, compass: tuple, accel: tuple) -> bytes:
        """Build a data packet with 2 ignored header bytes followed by 6 floats."""
        return bytes(2) + struct.pack('<6f', *compass, *accel)

    async def test_handle_data_parses_compass_and_accel(self):
        rx = RxIMU()
        rx.queue = asyncio.Queue()

        compass = (1.0, 2.0, 3.0)
        accel = (0.0, 0.0, 9.81)
        rx.handle_data(self._make_imu_packet(compass, accel))
        await asyncio.sleep(0)
        imu: IMUData = rx.queue.get_nowait()

        # With smoothing_samples=1 the average equals the raw value
        assert imu.raw.compass == pytest.approx(compass, rel=1e-5)
        assert imu.raw.accel == pytest.approx(accel, rel=1e-5)

    async def test_smoothing_averages_multiple_samples(self):
        rx = RxIMU(smoothing_samples=2)
        rx.queue = asyncio.Queue()

        rx.handle_data(self._make_imu_packet((0.0, 0.0, 0.0), (0.0, 0.0, 0.0)))
        await asyncio.sleep(0)
        rx.queue.get_nowait()

        rx.handle_data(self._make_imu_packet((10.0, 20.0, 30.0), (4.0, 6.0, 8.0)))
        await asyncio.sleep(0)
        imu: IMUData = rx.queue.get_nowait()

        # average of (0,0,0) and (10,20,30) via true division = (5, 10, 15)
        assert imu.compass == pytest.approx((5.0, 10.0, 15.0))
        # accel averaged too, and fractional precision preserved
        assert imu.accel == pytest.approx((2.0, 3.0, 4.0))

    async def test_imu_data_pitch_and_roll_computed(self):
        rx = RxIMU()
        rx.queue = asyncio.Queue()

        accel = (0.0, 1.0, 0.0)   # tilted 90° → pitch = 90°
        rx.handle_data(self._make_imu_packet((0.0, 0.0, 0.0), accel))
        await asyncio.sleep(0)
        imu: IMUData = rx.queue.get_nowait()

        assert imu.pitch == pytest.approx(90.0, abs=1e-4)
        assert imu.roll == pytest.approx(0.0, abs=1e-4)


# ---------------------------------------------------------------------------
# RxTap  (async)
# ---------------------------------------------------------------------------

class TestRxTap:
    async def test_single_tap_queued_after_threshold(self):
        rx = RxTap(threshold=0.05)
        rx.queue = asyncio.Queue()

        rx.handle_data(bytes([0x09]))
        await asyncio.sleep(0)   # let create_task run

        count = await asyncio.wait_for(rx.queue.get(), timeout=0.5)
        assert count == 1

    async def test_debounce_ignores_rapid_second_tap(self):
        rx = RxTap(threshold=0.05)
        rx.queue = asyncio.Queue()

        # Two taps with no time between them
        rx.handle_data(bytes([0x09]))
        rx.handle_data(bytes([0x09]))   # within 40 ms debounce window → ignored
        await asyncio.sleep(0)

        count = await asyncio.wait_for(rx.queue.get(), timeout=0.5)
        assert count == 1  # only one tap registered

    async def test_no_queue_does_not_raise(self):
        rx = RxTap()
        rx.handle_data(bytes([0x09]))   # queue is None; should log and return


# ---------------------------------------------------------------------------
# BrilliantMsg handler dispatch  (async)
# ---------------------------------------------------------------------------

class TestBrilliantMsgHandlerDispatch:
    async def test_registered_handler_called_for_matching_code(self):
        frame = BrilliantMsg()
        received = []

        class Sub:
            pass

        sub = Sub()
        frame.register_data_response_handler(sub, [0x01], lambda d: received.append(d))
        await frame._handle_data_response(b'\x01\xde\xad')

        assert received == [b'\x01\xde\xad']

    async def test_unregistered_code_not_dispatched(self):
        frame = BrilliantMsg()
        received = []

        class Sub:
            pass

        sub = Sub()
        frame.register_data_response_handler(sub, [0x01], lambda d: received.append(d))
        await frame._handle_data_response(b'\x02\xbe\xef')   # code 0x02 not registered

        assert received == []

    async def test_handler_removed_after_unregister(self):
        frame = BrilliantMsg()
        received = []

        class Sub:
            pass

        sub = Sub()
        frame.register_data_response_handler(sub, [0x01], lambda d: received.append(d))
        frame.unregister_data_response_handler(sub)
        await frame._handle_data_response(b'\x01\xff')

        assert received == []

    async def test_multiple_subscribers_for_same_code(self):
        frame = BrilliantMsg()
        log_a, log_b = [], []

        class SubA:
            pass
        class SubB:
            pass

        frame.register_data_response_handler(SubA(), [0x05], lambda d: log_a.append(d))
        frame.register_data_response_handler(SubB(), [0x05], lambda d: log_b.append(d))
        await frame._handle_data_response(b'\x05\xaa')

        assert len(log_a) == 1
        assert len(log_b) == 1

    async def test_handler_registered_for_multiple_codes(self):
        frame = BrilliantMsg()
        received = []

        class Sub:
            pass

        frame.register_data_response_handler(Sub(), [0x07, 0x08],
                                             lambda d: received.append(d[0]))
        await frame._handle_data_response(b'\x07\x00')
        await frame._handle_data_response(b'\x08\x00')

        assert received == [0x07, 0x08]

    async def test_empty_data_does_not_raise(self):
        frame = BrilliantMsg()
        await frame._handle_data_response(b'')   # empty → no dispatch
