"""
Unit tests for send_message() flow control on Halo. No device required: a fake
client models Halo's data receive queue, which drops a write without response
that does not fit, and a consumer task stands in for data.lua, acknowledging
each packet once its (deliberately slow) handler has taken it.
"""
import asyncio

import pytest

from brilliant_ble import BrilliantBle, BrilliantDeviceType, ble_write_size

ACK = b"\x01\x01\x00\x00"
ACK_FAILED = b"\x01\x01\x00\x01"


class FakeHalo:
    """BleakClient stand-in that queues data writes the way Halo firmware does."""

    def __init__(self, ble, mtu=515, queue_size=4096, handler_delay=0.0):
        self.ble = ble
        self.is_connected = True
        self.mtu_size = mtu
        self.queue_size = queue_size
        self.handler_delay = handler_delay
        self.queue = []          # packets waiting for the handler, marker stripped
        self.queued_bytes = 0
        self.received = []       # packets the handler took, in order
        self.dropped = 0
        self.write_sizes = []
        self.max_queued = 0
        self.wake = asyncio.Event()

    async def write_gatt_char(self, characteristic, data, response=False):
        data = bytes(data)
        self.write_sizes.append(len(data))
        if data[:1] != b"\x01":
            return
        frame = data[1:]
        if self.queued_bytes + len(frame) + 2 > self.queue_size:
            self.dropped += 1    # what Halo does to a write without response
            return
        self.queue.append(frame)
        self.queued_bytes += len(frame) + 2
        self.max_queued = max(self.max_queued, self.queued_bytes)
        self.wake.set()

    async def handler(self):
        while True:
            while not self.queue:
                self.wake.clear()
                await self.wake.wait()
            frame = self.queue.pop(0)
            self.queued_bytes -= len(frame) + 2
            await asyncio.sleep(self.handler_delay)
            self.received.append(frame)
            await self.ble._notification_handler(None, bytearray(ACK))

    async def disconnect(self):
        self.is_connected = False


def connected_halo(**kwargs):
    ble = BrilliantBle()
    ble._client = FakeHalo(ble, **kwargs)
    ble._tx_characteristic = object()
    ble._type = BrilliantDeviceType.HALO
    ble._name = "Halo 08"
    # as connect() leaves them
    ble._user_data_response_handler = lambda _: None
    ble._user_print_response_handler = lambda _: None
    return ble


def reassemble(frames):
    """Undo send_message() framing: [code, len16, data...] then [code, data...]."""
    messages = []
    current = None
    for frame in frames:
        if current is None:
            size = frame[1] << 8 | frame[2]
            current = [frame[0], size, bytearray(frame[3:])]
        else:
            current[2] += frame[1:]
        if len(current[2]) == current[1]:
            messages.append((current[0], bytes(current[2])))
            current = None
    return messages


def test_write_size_fills_whole_link_layer_packets():
    assert ble_write_size(512) == 495
    assert ble_write_size(494) == 244
    assert ble_write_size(244) == 244
    assert ble_write_size(243) == 243   # less than one packet: unchanged
    assert ble_write_size(20) == 20


@pytest.mark.parametrize("handler_delay", [0.0, 0.002, 0.01])
def test_slow_handler_loses_nothing(handler_delay):
    ble = connected_halo(handler_delay=handler_delay)
    payloads = [bytes([i]) * size for i, size in enumerate([1, 300, 8192, 5000, 2])]

    async def run():
        consumer = asyncio.create_task(ble._client.handler())
        for i, payload in enumerate(payloads):
            await ble.send_message(0x20 + i, payload)
        await ble.wait_for_acks()
        consumer.cancel()

    asyncio.run(run())
    fake = ble._client
    assert fake.dropped == 0
    assert fake.max_queued <= fake.queue_size
    assert reassemble(fake.received) == [(0x20 + i, p) for i, p in enumerate(payloads)]
    # every data write fills whole link-layer packets, except a message's last
    assert max(fake.write_sizes) == 495


def test_bigger_receive_buffer_allows_more_in_flight():
    ble = connected_halo(queue_size=16384, handler_delay=0.001)
    ble.receive_buffer_size = 16384

    async def run():
        consumer = asyncio.create_task(ble._client.handler())
        await ble.send_message(0x20, b"\xAA" * 20000)
        await ble.wait_for_acks()
        consumer.cancel()

    asyncio.run(run())
    fake = ble._client
    assert fake.dropped == 0
    assert fake.max_queued > 4096


def test_receive_buffer_size_larger_than_device_drops_data():
    # The window really is what prevents loss: overstate the queue and the
    # fake device, like Halo, drops what doesn't fit
    ble = connected_halo(handler_delay=0.005)
    ble.receive_buffer_size = 16384

    async def run():
        consumer = asyncio.create_task(ble._client.handler())
        await ble.send_message(0x20, b"\xAA" * 20000)
        await asyncio.sleep(0.5)
        consumer.cancel()

    asyncio.run(run())
    assert ble._client.dropped > 0


def test_failed_ack_is_raised():
    ble = connected_halo()
    ble._acks_outstanding = 1

    async def run():
        await ble._notification_handler(None, bytearray(ACK_FAILED))
        with pytest.raises(Exception, match="failed to process"):
            await ble.wait_for_acks()

    asyncio.run(run())


def test_other_data_still_reaches_send_data_while_acks_outstanding():
    ble = connected_halo()
    seen = []
    ble._user_data_response_handler = lambda d: seen.append(bytes(d))
    ble._acks_outstanding = 2

    async def run():
        ble._awaiting_data_response = True
        # an app message (code 0x0a) is not an ACK, even mid-transfer
        await ble._notification_handler(None, bytearray(b"\x01\x0a\x00\x00"))
        await ble._notification_handler(None, bytearray(ACK))
        assert bytes(await ble._data_response.get()) == b"\x0a\x00\x00"

    asyncio.run(run())
    assert ble._acks_outstanding == 1
    # user handlers see everything, ACKs included, as before
    assert seen == [b"\x0a\x00\x00", b"\x01\x00\x00"]


def test_device_that_stops_acking_times_out():
    ble = connected_halo()

    async def run():
        # no consumer: nothing is ever acknowledged
        with pytest.raises(Exception, match="didn't respond"):
            await ble.send_message(0x20, b"\x00" * 20000)

    asyncio.run(run())


def test_control_signal_does_not_wait_on_a_stuck_device():
    ble = connected_halo()
    ble._acks_outstanding = 3

    async def run():
        loop = asyncio.get_running_loop()
        start = loop.time()
        await ble.send_break_signal()
        assert loop.time() - start < 2
        assert ble._client.write_sizes[-1] == 1   # the break went out

    asyncio.run(run())


def test_failed_ack_followed_by_silence_raises_the_failure_at_once():
    # data.lua rethrows after a failure ACK, so the app has usually stopped:
    # the failure must surface now, not as a timeout 5 s later
    ble = connected_halo()
    ble._acks_outstanding = 5

    async def run():
        loop = asyncio.get_running_loop()
        start = loop.time()
        loop.call_later(0.05, lambda: asyncio.ensure_future(
            ble._notification_handler(None, bytearray(ACK_FAILED))))
        with pytest.raises(Exception, match="failed to process"):
            await ble.wait_for_acks()
        assert loop.time() - start < 1
        # and nothing stale is left for the next call
        await ble.wait_for_acks()

    asyncio.run(run())


def test_failed_write_does_not_leave_a_phantom_packet_in_flight():
    ble = connected_halo()

    async def failing_write(characteristic, data, response=False):
        raise RuntimeError("write failed")

    ble._client.write_gatt_char = failing_write

    async def run():
        with pytest.raises(RuntimeError):
            await ble.send_message(0x20, b"\x00" * 10)
        assert ble._acks_outstanding == 0

    asyncio.run(run())
