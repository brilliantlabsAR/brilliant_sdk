import asyncio
import logging
import time
from typing import Optional
from brilliant_msg import BrilliantMsg

logging.basicConfig()
_log = logging.getLogger("RxTap")

class RxTap:
    def __init__(self, tap_flag: int = 0x09, threshold: float = 0.3):
        """
        Initialize a tap handler that aggregates taps within a threshold window.

        Args:
            tap_flag: The message type identifier for tap events (default: 0x09)
            threshold: Time window in seconds to aggregate taps (default: 0.3)
        """
        self.tap_flag = tap_flag
        self.threshold = threshold
        self.queue: Optional[asyncio.Queue] = None
        self._last_tap_time = 0
        self._tap_count = 0
        self._threshold_task: Optional[asyncio.Task] = None

    async def _reset_threshold_timer(self) -> None:
        """Cancel existing threshold timer and start a new one"""
        if self._threshold_task and not self._threshold_task.done():
            self._threshold_task.cancel()

        self._threshold_task = asyncio.create_task(self._threshold_timeout())

    async def _threshold_timeout(self) -> None:
        """Handle threshold timer expiration by sending tap count to queue"""
        try:
            await asyncio.sleep(self.threshold)
            if self.queue and self._tap_count > 0:
                await self.queue.put(self._tap_count)
                self._tap_count = 0
        except asyncio.CancelledError:
            pass

    def handle_data(self, data: bytes) -> None:
        """
        Process an incoming Tap message

        Args:
            data: A single byte with the tap_flag prefix
        """
        if not self.queue:
            _log.warning("Received data but queue not initialized - call start() first")
            return

        current_time = time.time()

        # Debounce taps that occur too close together (40ms)
        if current_time - self._last_tap_time < 0.04:
            self._last_tap_time = current_time
            return

        self._last_tap_time = current_time
        self._tap_count += 1

        # Reset the threshold timer
        asyncio.create_task(self._reset_threshold_timer())

    async def attach(self, frame: BrilliantMsg) -> asyncio.Queue:
        """
        Attach the tap handler to the Frame data response and return a queue that will receive tap counts.

        Returns:
            asyncio.Queue that will receive integers representing tap counts
        """
        self.queue = asyncio.Queue()
        self._last_tap_time = 0
        self._tap_count = 0

        # subscribe for notifications
        frame.register_data_response_handler(self, [self.tap_flag], self.handle_data)

        return self.queue

    def detach(self, frame: BrilliantMsg) -> None:
        """Detach the tap handler from the Frame data response and clean up resources"""
        frame.unregister_data_response_handler(self)
        if self._threshold_task and not self._threshold_task.done():
            self._threshold_task.cancel()
        self.queue = None
        self._tap_count = 0