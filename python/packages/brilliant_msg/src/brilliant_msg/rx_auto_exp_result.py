import asyncio
import logging
import struct
from typing import Optional

from brilliant_msg import BrilliantMsg

logging.basicConfig()
_log = logging.getLogger("RxAutoExpResult")

class RxAutoExpResult:
    def __init__(
        self,
        msg_code: int = 0x11,
    ):
        """
        Initialize receive handler for processing auto exposure result data.

        Args:
            msg_code: Message type identifier for auto exposure result data
        """
        self.msg_code = msg_code

        self.queue: Optional[asyncio.Queue] = None

    def handle_data(self, data: bytes) -> None:
        """
        Process incoming data packets.

        Args:
            data: Bytes containing auto exposure result data with flag byte prefix and 16 floats
        """
        if not self.queue:
            _log.warning("Received data but queue not initialized - call start() first")
            return

        # Parse six signed 16-bit integers from the data starting at offset 2
        unpacked = struct.unpack("<ffffff ff ffff ffff", data[1:65])
        # Create the result dictionary
        result = {
            'error': unpacked[0],
            'shutter': unpacked[1],
            'analog_gain': unpacked[2],
            'red_gain': unpacked[3],
            'green_gain': unpacked[4],
            'blue_gain': unpacked[5],
            'brightness': {
                'center_weighted_average': unpacked[6],
                'scene': unpacked[7],
                'matrix': {
                    'r': unpacked[8],
                    'g': unpacked[9],
                    'b': unpacked[10],
                    'average': unpacked[11]
                },
                'spot': {
                    'r': unpacked[12],
                    'g': unpacked[13],
                    'b': unpacked[14],
                    'average': unpacked[15]
                }
            }
        }

        # Queue the data
        asyncio.create_task(self.queue.put(result))

    async def attach(self, frame: BrilliantMsg) -> asyncio.Queue:
        """
        Attach the receive handler to the Frame data response and return a queue that will receive autoexposure result data.

        Returns:
            asyncio.Queue that will receive autoexposure result objects
        """
        self.queue = asyncio.Queue()

        # subscribe for notifications
        frame.register_data_response_handler(self, [self.msg_code], self.handle_data)

        return self.queue

    def detach(self, frame: BrilliantMsg) -> None:
        """Detach the receive handler from the Frame data response and clean up resources"""
        frame.unregister_data_response_handler(self)
        self.queue = None