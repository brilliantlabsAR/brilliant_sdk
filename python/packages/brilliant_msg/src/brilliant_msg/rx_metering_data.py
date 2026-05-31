import asyncio
import logging
import struct
from typing import Optional

from brilliant_msg import BrilliantMsg

logging.basicConfig()
_log = logging.getLogger("RxMeteringData")

class RxMeteringData:
    def __init__(
        self,
        msg_code: int = 0x12,
    ):
        """
        Initialize receive handler for processing metering data.

        Args:
            msg_code: Message type identifier for metering data
        """
        self.msg_code = msg_code

        self.queue: Optional[asyncio.Queue] = None

    def handle_data(self, data: bytes) -> None:
        """
        Process incoming data packets.

        Args:
            data: Bytes containing metering data with flag byte prefix and 6 unsigned bytes (spot r,g,b, matrix r,g,b)
        """
        if not self.queue:
            _log.warning("Received data but queue not initialized - call start() first")
            return

        # Parse six unsigned bytes from the data starting at offset 2
        unpacked = struct.unpack("<BBBBBB", data[1:7])
        # Create the result dictionary
        result = {
            'spot_r': unpacked[0],
            'spot_g': unpacked[1],
            'spot_b': unpacked[2],
            'matrix_r': unpacked[3],
            'matrix_g': unpacked[4],
            'matrix_b': unpacked[5],
        }

        # Queue the data
        asyncio.create_task(self.queue.put(result))

    async def attach(self, frame: BrilliantMsg) -> asyncio.Queue:
        """
        Attach the receive handler to the Frame data response and return a queue that will receive metering data.

        Returns:
            asyncio.Queue that will receive metering data objects
        """
        self.queue = asyncio.Queue()

        # subscribe for notifications
        frame.register_data_response_handler(self, [self.msg_code], self.handle_data)

        return self.queue

    def detach(self, frame: BrilliantMsg) -> None:
        """Detach the receive handler from the Frame data response and clean up resources"""
        frame.unregister_data_response_handler(self)
        self.queue = None