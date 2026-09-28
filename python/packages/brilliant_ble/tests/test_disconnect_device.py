"""
Device tests for BrilliantBle's behaviour when the BLE link drops. Needs a
Halo: the drop is real, produced by rebooting the device over SMP, so the
Bleak disconnected_callback path is exercised rather than simulated.

    BRILLIANT_DEVICE=1 uv run pytest \\
        packages/brilliant_ble/tests/test_disconnect_device.py --name "Halo AB"

The device reboots once per reboot test and comes back running its main.lua.
"""
import asyncio
import time

import pytest

from brilliant_ble import BrilliantBle, BrilliantDeviceType, NotConnectedError
from brilliant_ble import _smp

pytestmark = pytest.mark.asyncio

# Allows for the peripheral's supervision timeout and a full reboot
DROP_TIMEOUT = 30
RECONNECT_TIMEOUT = 30


async def connect(ble, name, **handlers):
    """Connects, retrying while a rebooting device isn't advertising yet."""
    deadline = time.monotonic() + RECONNECT_TIMEOUT
    while True:
        try:
            await ble.connect(name=name, **handlers)
            break
        except Exception:
            if time.monotonic() > deadline:
                raise
            await asyncio.sleep(1)
    await ble.send_break_signal()
    await ble.drain_print_channel()


async def reboot(ble):
    """Reboots a Halo over SMP; the link drops without the host asking."""
    if ble.type != BrilliantDeviceType.HALO:
        pytest.skip("SMP reboot is Halo only")
    smp = await ble._ota_start()
    try:
        await smp.request(_smp.OP_WRITE, _smp.GROUP_OS, _smp.ID_OS_RESET, {}, timeout=3.0)
    except Exception:
        # the link can go before the response arrives
        pass


async def test_explicit_disconnect_keeps_handler_and_fires_once(device_name):
    calls = []
    handler = lambda: calls.append(1)
    ble = BrilliantBle()
    await connect(ble, device_name, disconnect_handler=handler)

    await ble.disconnect()

    assert calls == [1]
    assert not ble.is_connected()
    assert ble._user_disconnect_handler is handler
    with pytest.raises(NotConnectedError):
        await ble.send_reset_signal()
    with pytest.raises(NotConnectedError):
        ble.max_lua_payload()

    # a second disconnect() is a no-op
    await ble.disconnect()
    assert calls == [1]


async def test_reconnect_on_same_instance(device_name):
    ble = BrilliantBle()
    await connect(ble, device_name)
    await ble.disconnect()

    await connect(ble, device_name)
    assert ble.is_connected()
    assert await ble.send_lua("print('hi')", await_print=True) == "hi"
    await ble.disconnect()


async def test_spontaneous_drop_raises_not_connected_error(device_name):
    dropped = asyncio.Event()
    calls = []

    def handler():
        calls.append(1)
        dropped.set()

    ble = BrilliantBle()
    await connect(ble, device_name, disconnect_handler=handler)
    try:
        await reboot(ble)
        await asyncio.wait_for(dropped.wait(), timeout=DROP_TIMEOUT)

        assert calls == [1]
        assert not ble.is_connected()
        assert ble.name is None

        # the teardown calls that used to raise AttributeError
        for teardown in (ble.send_break_signal, ble.send_reset_signal, ble.send_remove_signal):
            with pytest.raises(NotConnectedError):
                await teardown()
        with pytest.raises(NotConnectedError):
            await ble.send_lua("print(1)")

        # the handler survived the drop and fires again on the same instance
        await connect(ble, device_name, disconnect_handler=handler)
        assert await ble.send_lua("print('back')", await_print=True) == "back"
        await ble.disconnect()
        assert calls == [1, 1]
    finally:
        if ble.is_connected():
            await ble.disconnect()


async def test_drop_while_awaiting_print_fails_fast(device_name):
    ble = BrilliantBle()
    await connect(ble, device_name)
    try:
        # the device is busy and won't print for 20 s; the reboot cuts it short
        pending = asyncio.create_task(
            ble.send_lua("frame.sleep(20) print(1)", await_print=True, timeout=25)
        )
        await asyncio.sleep(0.5)
        started = time.monotonic()
        await reboot(ble)

        with pytest.raises(NotConnectedError):
            await asyncio.wait_for(pending, timeout=DROP_TIMEOUT)
        # well short of the 25 s timeout that the old code waited out
        assert time.monotonic() - started < 20
    finally:
        await connect(ble, device_name)
        await ble.disconnect()
