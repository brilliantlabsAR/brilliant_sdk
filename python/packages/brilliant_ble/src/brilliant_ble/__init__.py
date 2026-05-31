"""
Low-level library for Bluetooth LE connection to Brilliant Labs Frame and Halo devices (https://brilliant.xyz/)
"""
__all__ = ["frame_ble"]

from .frame_ble import FrameBle
from .frame_ble import BrilliantDeviceType

__version__ = "3.0.0"
