import asyncio
import logging
import math
import struct
from typing import Optional, Tuple
from dataclasses import dataclass

from brilliant_msg import BrilliantMsg

logging.basicConfig()
_log = logging.getLogger("RxIMU")

class SensorBuffer:
    """Buffer class to provide smoothed moving average of samples"""
    def __init__(self, max_size: int):
        self.max_size = max_size
        self._buffer: list[Tuple[float, float, float]] = []

    def add(self, value: Tuple[float, float, float]) -> None:
        self._buffer.append(value)
        if len(self._buffer) > self.max_size:
            self._buffer.pop(0)

    @property
    def average(self) -> Tuple[float, float, float]:
        if not self._buffer:
            return (0.0, 0.0, 0.0)

        sum_x = sum(x for x, _, _ in self._buffer)
        sum_y = sum(y for _, y, _ in self._buffer)
        sum_z = sum(z for _, _, z in self._buffer)
        length = len(self._buffer)

        return (
            sum_x / length,
            sum_y / length,
            sum_z / length
        )

@dataclass
class IMURawData:
    compass: Tuple[float, float, float]
    accel: Tuple[float, float, float]

@dataclass
class IMUData:
    compass: Tuple[float, float, float]
    accel: Tuple[float, float, float]
    raw: Optional[IMURawData] = None

    @property
    def pitch(self) -> float:
        return math.atan2(self.accel[1], self.accel[2]) * 180.0 / math.pi

    @property
    def roll(self) -> float:
        return math.atan2(self.accel[0], self.accel[2]) * 180.0 / math.pi

class RxIMU:
    def __init__(
        self,
        imu_flag: int = 0x0A,
        smoothing_samples: int = 1,
    ):
        """
        Initialize IMU handler for processing magnetometer and accelerometer data.

        Args:
            imu_flag: Message type identifier for IMU data
            smoothing_samples: Number of samples to use for moving average
        """
        self.imu_flag = imu_flag
        self._smoothing_samples = smoothing_samples

        self.queue: Optional[asyncio.Queue] = None
        self._compass_buffer = SensorBuffer(smoothing_samples)
        self._accel_buffer = SensorBuffer(smoothing_samples)

    def handle_data(self, data: bytes) -> None:
        """
        Process incoming IMU data packets.

        Args:
            data: Bytes containing IMU data with flag byte prefix
        """
        if not self.queue:
            _log.warning("Received data but queue not initialized - call start() first")
            return

        # Parse six 32-bit floats from the data starting at offset 2
        values = struct.unpack('<6f', data[2:26])

        # Extract compass and accelerometer values
        raw_compass = (values[0], values[1], values[2])
        raw_accel = (values[3], values[4], values[5])

        # Add to buffers
        self._compass_buffer.add(raw_compass)
        self._accel_buffer.add(raw_accel)

        # Create IMU data with smoothed and raw values
        imu_data = IMUData(
            compass=self._compass_buffer.average,
            accel=self._accel_buffer.average,
            raw=IMURawData(
                compass=raw_compass,
                accel=raw_accel
            )
        )

        # Queue the data
        asyncio.create_task(self.queue.put(imu_data))

    async def attach(self, frame: BrilliantMsg) -> asyncio.Queue:
        """
        Attach the IMU handler to the Frame data response and return a queue that will receive IMU data.

        Returns:
            asyncio.Queue that will receive IMUData objects
        """
        self.queue = asyncio.Queue()

        # subscribe for notifications
        frame.register_data_response_handler(self, [self.imu_flag], self.handle_data)

        return self.queue

    def detach(self, frame: BrilliantMsg) -> None:
        """Detach the IMU handler from the Frame data response and clean up resources"""
        frame.unregister_data_response_handler(self)
        self.queue = None