"""
Unit tests for BrilliantBle's behaviour when the BLE link drops. No device
required: a fake client stands in for BleakClient, and a drop is simulated by
calling the disconnect handler the way Bleak's disconnected_callback does.
"""
import asyncio

import pytest

from brilliant_ble import BrilliantBle, BrilliantDeviceType, NotConnectedError


class FakeClient:
    def __init__(self):
        self.is_connected = True
        self.mtu_size = 247
        self.writes = []

    async def write_gatt_char(self, characteristic, data, response=False):
        self.writes.append(bytes(data))

    async def disconnect(self):
        self.is_connected = False


def connected_ble(disconnect_handler=lambda: None):
    """A BrilliantBle in the state connect() leaves it in, over a FakeClient."""
    ble = BrilliantBle()
    ble._client = FakeClient()
    ble._tx_characteristic = object()
    ble._type = BrilliantDeviceType.HALO
    ble._name = "Halo 08"
    ble._user_disconnect_handler = disconnect_handler
    return ble


def drop(ble):
    """Simulates Bleak reporting an unexpected disconnect."""
    client = ble._client
    client.is_connected = False
    ble._disconnect_handler(client)


def test_not_connected_error_is_catchable_as_before():
    # send_message() raised ValueError for this case before NotConnectedError
    assert issubclass(NotConnectedError, ValueError)
    assert issubclass(NotConnectedError, ConnectionError)


def test_transmit_after_drop_raises_not_connected_error():
    ble = connected_ble()
    drop(ble)

    async def run():
        with pytest.raises(NotConnectedError):
            await ble.send_reset_signal()
        with pytest.raises(NotConnectedError):
            await ble.send_break_signal()
        with pytest.raises(NotConnectedError):
            await ble.send_remove_signal()
        with pytest.raises(NotConnectedError):
            await ble.send_lua("print(1)")
        with pytest.raises(NotConnectedError):
            await ble.send_data(bytearray(b"\x00"))
        with pytest.raises(NotConnectedError):
            await ble.send_audio(bytearray(b"\x00"))
        with pytest.raises(NotConnectedError):
            await ble.send_message(0x20, b"\x00")

    asyncio.run(run())


def test_transmit_before_connect_raises_not_connected_error():
    async def run():
        with pytest.raises(NotConnectedError):
            await BrilliantBle().send_lua("print(1)")

    asyncio.run(run())


def test_max_payload_raises_when_not_connected():
    ble = connected_ble()
    assert ble.max_lua_payload() == 244
    assert ble.max_data_payload() == 243

    drop(ble)
    with pytest.raises(NotConnectedError):
        ble.max_lua_payload()
    with pytest.raises(NotConnectedError):
        ble.max_data_payload()


def test_drop_clears_connection_state():
    ble = connected_ble()
    assert ble.is_connected()

    drop(ble)

    assert not ble.is_connected()
    assert ble._client is None
    assert ble._tx_characteristic is None
    assert ble.name is None
    assert ble.type == BrilliantDeviceType.UNKNOWN


def test_user_disconnect_handler_survives_a_drop():
    calls = []
    ble = connected_ble(disconnect_handler=lambda: calls.append(1))

    drop(ble)
    assert calls == [1]

    # reconnect on the same instance: the handler still fires
    ble._client = FakeClient()
    drop(ble)
    assert calls == [1, 1]


def test_disconnect_calls_user_handler_once():
    calls = []
    ble = connected_ble(disconnect_handler=lambda: calls.append(1))
    client = ble._client

    async def bleak_disconnect():
        # Bleak fires disconnected_callback during an explicit disconnect too
        client.is_connected = False
        ble._disconnect_handler(client)

    client.disconnect = bleak_disconnect
    asyncio.run(ble.disconnect())

    assert calls == [1]
    assert not ble.is_connected()


def test_late_callback_from_old_client_is_ignored():
    calls = []
    ble = connected_ble(disconnect_handler=lambda: calls.append(1))
    old_client = ble._client
    drop(ble)

    ble._client = FakeClient()
    ble._disconnect_handler(old_client)

    assert ble.is_connected()
    assert calls == [1]


def test_drop_while_awaiting_print_fails_fast():
    ble = connected_ble()

    async def run():
        pending = asyncio.create_task(ble.send_lua("print(1)", await_print=True, timeout=5))
        await asyncio.sleep(0)
        drop(ble)
        with pytest.raises(NotConnectedError):
            await asyncio.wait_for(pending, timeout=1)

    asyncio.run(run())


def test_drop_while_awaiting_data_fails_fast():
    ble = connected_ble()

    async def run():
        pending = asyncio.create_task(ble.send_data(bytearray(b"\x00"), await_data=True, timeout=5))
        await asyncio.sleep(0)
        drop(ble)
        with pytest.raises(NotConnectedError):
            await asyncio.wait_for(pending, timeout=1)

    asyncio.run(run())


def test_drain_print_channel_returns_on_drop():
    ble = connected_ble()

    async def run():
        pending = asyncio.create_task(ble.drain_print_channel(quiet=5, max_total=5))
        await asyncio.sleep(0)
        drop(ble)
        await asyncio.wait_for(pending, timeout=1)

    asyncio.run(run())
