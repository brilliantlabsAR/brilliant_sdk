"""
Unit tests for BrilliantBle.connect() failing part-way. No device required:
fakes stand in for BleakScanner and BleakClient.
"""
import asyncio

import pytest
from bleak import BleakError

import brilliant_ble.brilliant_ble as module
from brilliant_ble import BrilliantBle, BrilliantDeviceType


class FakeDevice:
    name = "Halo 28"


class FakeService:
    def get_characteristic(self, uuid):
        return object()


class FakeServices:
    def get_service(self, uuid):
        return FakeService()


class FakeClient:
    """BleakClient stand-in; each test sets the class-level behaviour."""
    link_up = True          # False: connect() hangs like a Halo refusing this host
    subscribe_error = None  # exception start_notify raises
    instances = []

    def __init__(self, device, disconnected_callback, timeout, **kwargs):
        self.timeout = timeout
        self.disconnected_callback = disconnected_callback
        self.is_connected = False
        self.disconnect_calls = 0
        self.services = FakeServices()
        self._backend = object()  # connect() checks its class for BlueZ
        FakeClient.instances.append(self)

    async def connect(self):
        if not self.link_up:
            # Bleak raises TimeoutError itself once its link-up timeout expires
            await asyncio.sleep(self.timeout)
            raise asyncio.TimeoutError()
        self.is_connected = True

    async def start_notify(self, uuid, handler):
        if self.subscribe_error is not None:
            raise self.subscribe_error

    async def disconnect(self):
        self.disconnect_calls += 1
        if self.is_connected:
            self.is_connected = False
            self.disconnected_callback(self)


@pytest.fixture(autouse=True)
def fake_bleak(monkeypatch):
    async def find_device_by_filter(*args, **kwargs):
        return FakeDevice()

    monkeypatch.setattr(module.BleakScanner, "find_device_by_filter", find_device_by_filter)
    monkeypatch.setattr(module, "BleakClient", FakeClient)
    FakeClient.link_up = True
    FakeClient.subscribe_error = None
    FakeClient.instances = []


def connect(ble, **kwargs):
    return asyncio.run(ble.connect(**kwargs))


def assert_attempt_cleaned_up(ble):
    assert ble._client is None
    assert ble.type == BrilliantDeviceType.UNKNOWN
    assert not ble.is_connected()


def test_connects_with_default_link_timeout():
    ble = BrilliantBle()
    assert connect(ble) == "Halo 28"
    assert ble.type == BrilliantDeviceType.HALO
    assert FakeClient.instances[0].timeout == 5


def test_link_that_never_comes_up_times_out_with_hint():
    FakeClient.link_up = False
    disconnects = []
    ble = BrilliantBle()
    with pytest.raises(asyncio.TimeoutError, match="paired with this host"):
        connect(ble, connect_timeout=0.05, disconnect_handler=lambda: disconnects.append(1))
    assert FakeClient.instances[0].timeout == 0.05
    assert_attempt_cleaned_up(ble)
    assert disconnects == []


def test_failed_subscribe_drops_the_link_without_calling_disconnect_handler():
    FakeClient.subscribe_error = BleakError(
        'Error Domain=CBATTErrorDomain Code=15 "Encryption is insufficient."')
    disconnects = []
    ble = BrilliantBle()
    with pytest.raises(Exception, match="Error subscribing for notifications"):
        connect(ble, disconnect_handler=lambda: disconnects.append(1))
    assert FakeClient.instances[0].disconnect_calls == 1
    assert_attempt_cleaned_up(ble)
    assert disconnects == []
