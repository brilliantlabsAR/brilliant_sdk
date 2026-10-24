"""
Rx receivers must deliver data to their queues when handle_data() is invoked
from a thread that is not the event-loop thread. The Halo emulator calls data
handlers synchronously from its Lua thread; receivers that called
asyncio.create_task() from handle_data() raised "no running event loop" there
and silently dropped every message.

Receivers capture the event loop in attach() and hand data over with
call_soon_threadsafe(). A receiver wired by hand from inside the running loop
(queue assigned directly, no attach()) still works via the running-loop fallback.
"""
import asyncio
import struct
import threading

from brilliant_msg import ClickType, RxClick, RxIMU, RxMeteringData, RxTap


class _FakeFrame:
    """Just enough of BrilliantMsg for attach()/detach()."""

    def __init__(self):
        self.handlers = {}

    def register_data_response_handler(self, subscriber, flags, handler):
        self.handlers[subscriber] = (flags, handler)

    def unregister_data_response_handler(self, subscriber):
        self.handlers.pop(subscriber, None)


def _call_from_foreign_thread(fn, *args):
    """Run fn(*args) on a plain thread (no event loop) and re-raise anything it raised."""
    errors = []

    def run():
        try:
            fn(*args)
        except BaseException as e:  # noqa: BLE001 - surface everything to the test
            errors.append(e)

    t = threading.Thread(target=run)
    t.start()
    t.join(timeout=2)
    assert not t.is_alive(), "handler did not return"
    assert not errors, f"handler raised on the foreign thread: {errors[0]!r}"


def _imu_packet(flag: int) -> bytes:
    # flag byte, one reserved byte, then six float32 (compass xyz, accel xyz)
    return bytes([flag, 0]) + struct.pack('<6f', 1.0, 2.0, 3.0, 4.0, 5.0, 6.0)


async def test_rx_imu_delivers_from_foreign_thread():
    frame = _FakeFrame()
    rx = RxIMU(smoothing_samples=1)
    queue = await rx.attach(frame)

    _call_from_foreign_thread(rx.handle_data, _imu_packet(rx.imu_flag))

    imu = await asyncio.wait_for(queue.get(), timeout=1)
    assert imu.raw.compass == (1.0, 2.0, 3.0)
    assert imu.raw.accel == (4.0, 5.0, 6.0)
    rx.detach(frame)


async def test_rx_imu_direct_wiring_without_attach():
    # Hand-wired receiver: queue assigned from inside the running loop, no attach().
    rx = RxIMU(smoothing_samples=1)
    rx.queue = asyncio.Queue()

    rx.handle_data(_imu_packet(rx.imu_flag))

    imu = await asyncio.wait_for(rx.queue.get(), timeout=1)
    assert imu.raw.compass == (1.0, 2.0, 3.0)


async def test_rx_tap_native_kind_from_foreign_thread():
    frame = _FakeFrame()
    rx = RxTap()
    queue = await rx.attach(frame)

    # Halo firmware 0.8.8+: flag byte followed by the native kind (2 = double)
    _call_from_foreign_thread(rx.handle_data, bytes([rx.tap_flag, 2]))

    assert await asyncio.wait_for(queue.get(), timeout=1) == 2
    rx.detach(frame)


async def test_rx_tap_timed_aggregation_from_foreign_thread():
    frame = _FakeFrame()
    rx = RxTap(threshold=0.05)
    queue = await rx.attach(frame)

    # Frame: bare flag byte per tap; the threshold timer must be started on the loop
    _call_from_foreign_thread(rx.handle_data, bytes([rx.tap_flag]))

    assert await asyncio.wait_for(queue.get(), timeout=1) == 1
    rx.detach(frame)


async def test_rx_click_from_foreign_thread():
    frame = _FakeFrame()
    rx = RxClick()
    queue = await rx.attach(frame)

    _call_from_foreign_thread(rx.handle_data, bytes([rx.click_flag, 3]))

    assert await asyncio.wait_for(queue.get(), timeout=1) == ClickType.LONG
    rx.detach(frame)


async def test_rx_metering_data_from_foreign_thread():
    frame = _FakeFrame()
    rx = RxMeteringData()
    queue = await rx.attach(frame)

    _call_from_foreign_thread(rx.handle_data, bytes([rx.msg_code, 1, 2, 3, 4, 5, 6]))

    result = await asyncio.wait_for(queue.get(), timeout=1)
    assert (result['spot_r'], result['matrix_b']) == (1, 6)
    rx.detach(frame)
