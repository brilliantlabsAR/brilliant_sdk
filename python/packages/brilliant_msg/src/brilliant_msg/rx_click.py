import asyncio
import logging
from enum import IntEnum
from typing import Optional

from brilliant_msg import BrilliantMsg

logging.basicConfig()
_log = logging.getLogger("RxClick")


class ClickType(IntEnum):
    """Halo button click types, as encoded by the device in the second byte."""
    SINGLE = 1
    DOUBLE = 2
    LONG = 3


class RxClick:
    """
    Receives Halo button click events (single/double/long).

    There is no device-side Lua library for clicks: the frame app registers
    frame.button.single/double/long callbacks and sends
    string.char(click_flag) .. string.char(click_type) over Bluetooth.
    """

    def __init__(self, click_flag: int = 0x0B):
        """
        Args:
            click_flag: The message type identifier for click events (default: 0x0B)
        """
        self.click_flag = click_flag
        self.queue: Optional[asyncio.Queue] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    def handle_data(self, data: bytes) -> None:
        """
        Process an incoming click message: [click_flag, click_type].

        Safe to call from any thread (the emulator invokes handlers from its
        Lua thread), so the queue is fed via the attach()-time event loop.
        """
        if not self.queue or not self._loop:
            _log.warning("Received data but not attached - call attach() first")
            return

        if len(data) < 2:
            _log.warning("Click message too short: %r", data)
            return

        try:
            click_type = ClickType(data[1])
        except ValueError:
            _log.warning("Unknown click type: %d", data[1])
            return

        self._loop.call_soon_threadsafe(self.queue.put_nowait, click_type)

    async def attach(self, frame: BrilliantMsg) -> asyncio.Queue:
        """
        Attach to the Frame data response and return a queue of ClickType values.
        """
        self.queue = asyncio.Queue()
        self._loop = asyncio.get_running_loop()

        frame.register_data_response_handler(self, [self.click_flag], self.handle_data)

        return self.queue

    def detach(self, frame: BrilliantMsg) -> None:
        """Detach from the Frame data response and clean up resources."""
        frame.unregister_data_response_handler(self)
        self.queue = None
        self._loop = None
