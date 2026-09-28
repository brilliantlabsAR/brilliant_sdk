"""
Low-level library for Bluetooth LE connection to Brilliant Labs Frame and Halo devices (https://brilliant.xyz/)
"""
__all__ = ["brilliant_ble"]

from .brilliant_ble import BrilliantBle
from .brilliant_ble import BrilliantDeviceType
from .brilliant_ble import NotConnectedError
from .brilliant_ble import OtaError
from .brilliant_ble import chunk_lua_string

from importlib.metadata import PackageNotFoundError, version as _pkg_version

try:
    __version__ = _pkg_version("brilliant-ble")
except PackageNotFoundError:  # running from a source tree without an install
    __version__ = "0.0.0.dev0"