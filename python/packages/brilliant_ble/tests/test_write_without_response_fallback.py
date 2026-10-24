"""
Unit tests for the macOS fallback from writes without response to writes with
response. No device required: a fake client exposes a CoreBluetooth-like
peripheral whose canSendWriteWithoutResponse can be held False, as macOS does
when it stops reporting room for good partway through a long stream.
"""
import asyncio
import time
from types import SimpleNamespace

import pytest

from brilliant_ble import BrilliantBle


class FakePeripheral:
    def __init__(self):
        self.can_send = True

    def canSendWriteWithoutResponse(self):
        return self.can_send


class FakeClient:
    def __init__(self, peripheral=None):
        self.is_connected = True
        self.mtu_size = 515
        self.writes = []   # (characteristic, response) per write
        if peripheral is not None:
            self._backend = SimpleNamespace(_peripheral=peripheral)

    async def write_gatt_char(self, characteristic, data, response=False):
        self.writes.append((characteristic, response))


def make_ble(client):
    ble = BrilliantBle()
    ble._client = client
    ble._tx_characteristic = "tx"
    ble._audio_tx_characteristic = "audio"
    ble.write_without_response_timeout = 0.05
    return ble


@pytest.mark.asyncio
async def test_writes_without_response_when_corebluetooth_has_room():
    client = FakeClient(FakePeripheral())
    ble = make_ble(client)
    await ble.send_audio(b"\x00" * 40)
    await ble._transmit(b"\x01abc", await_bt_response=False)
    assert client.writes == [("audio", False), ("tx", False)]


@pytest.mark.asyncio
async def test_other_backends_never_fall_back():
    client = FakeClient()
    ble = make_ble(client)
    await ble.send_audio(b"\x00" * 40)
    assert client.writes == [("audio", False)]


@pytest.mark.asyncio
async def test_stuck_flag_falls_back_then_stops_waiting_then_recovers():
    peripheral = FakePeripheral()
    client = FakeClient(peripheral)
    ble = make_ble(client)
    peripheral.can_send = False

    start = time.monotonic()
    await ble.send_audio(b"\x00" * 40)
    assert time.monotonic() - start >= ble.write_without_response_timeout
    assert client.writes[-1] == ("audio", True)

    # still stuck: later writes go with response without waiting again
    start = time.monotonic()
    await ble._transmit(b"\x01abc", await_bt_response=False)
    await ble.send_audio(b"\x00" * 40)
    assert time.monotonic() - start < ble.write_without_response_timeout
    assert client.writes[-2:] == [("tx", True), ("audio", True)]

    # room again: back to writes without response
    peripheral.can_send = True
    await ble.send_audio(b"\x00" * 40)
    assert client.writes[-1] == ("audio", False)
    assert not ble._write_without_response_stuck


@pytest.mark.asyncio
async def test_a_brief_full_queue_still_waits_without_falling_back():
    peripheral = FakePeripheral()
    client = FakeClient(peripheral)
    ble = make_ble(client)
    peripheral.can_send = False
    asyncio.get_running_loop().call_later(0.01, setattr, peripheral, "can_send", True)
    await ble.send_audio(b"\x00" * 40)
    assert client.writes == [("audio", False)]


@pytest.mark.asyncio
async def test_concurrent_waiters_fall_back_together():
    peripheral = FakePeripheral()
    client = FakeClient(peripheral)
    ble = make_ble(client)
    ble.write_without_response_timeout = 0.2
    peripheral.can_send = False

    async def late_audio():
        # starts waiting after the transmit; falls back when the transmit gives up
        await asyncio.sleep(0.15)
        await ble.send_audio(b"\x00" * 40)

    start = time.monotonic()
    await asyncio.gather(ble._transmit(b"\x01abc", await_bt_response=False), late_audio())
    assert time.monotonic() - start < 0.3
    assert sorted(client.writes) == [("audio", True), ("tx", True)]
