import asyncio
import logging
from typing import Dict, List, Optional
import PIL.Image as Image
import io
from brilliant_msg import BrilliantMsg

logging.basicConfig()
_log = logging.getLogger("RxPhoto")

class RxPhoto:
    # Static storage for JPEG headers
    _jpeg_header_map: Dict[str, bytes] = {}

    def __init__(
        self,
        non_final_chunk_flag: int = 0x07,
        final_chunk_flag: int = 0x08,
        upright: bool = True,
        is_raw: bool = False,
        quality: Optional[str] = None,  # 'VERY_LOW', 'LOW', 'MEDIUM', 'HIGH', 'VERY_HIGH'
        resolution: Optional[int] = None,  # even number between 100 and 720 inclusive
    ):
        """
        Initialize a photo handler that assembles image chunks into complete JPEG images.

        Args:
            non_final_chunk_flag: Flag indicating a non-final chunk of image data
            final_chunk_flag: Flag indicating the final chunk of image data
            upright: Whether to rotate image -90 degrees to correct for sensor orientation
            is_raw: Whether incoming data will be raw (without JPEG header)
            quality: JPEG quality level
            resolution: Image resolution (must be even number between 100 and 720)
        """
        self.non_final_chunk_flag = non_final_chunk_flag
        self.final_chunk_flag = final_chunk_flag
        self.upright = upright
        self.is_raw = is_raw
        self.quality = quality
        self.resolution = resolution

        self.queue: Optional[asyncio.Queue] = None
        self._image_data: List[int] = []
        self._raw_offset: int = 0

    @classmethod
    def has_jpeg_header(cls, quality: str, resolution: int) -> bool:
        """Check if we have a stored JPEG header for the given quality and resolution"""
        return f"{quality}_{resolution}" in cls._jpeg_header_map

    def handle_data(self, data: bytes) -> None:
        """
        Process incoming chunks of image data.

        Args:
            data: Bytes containing image chunk with flag byte prefix
        """
        if not self.queue:
            _log.warning("Received data but queue not initialized - call start() first")
            return

        flag = data[0]
        chunk = data[1:]

        self._image_data.extend(chunk)
        self._raw_offset += len(chunk)

        if flag == self.final_chunk_flag:
            # Process complete image
            asyncio.create_task(self._process_complete_image())

    async def _process_complete_image(self) -> None:
        """Process and queue a complete image once all chunks are received"""
        if self.is_raw:
            # Prepend stored JPEG header for raw images
            key = f"{self.quality}_{self.resolution}"
            if key not in self._jpeg_header_map:
                raise Exception(
                    f"No JPEG header found for quality {self.quality} "
                    f"and resolution {self.resolution} - request full JPEG first"
                )
            final_image = self._jpeg_header_map[key] + bytes(self._image_data)
        else:
            final_image = bytes(self._image_data)
            # Store JPEG header for future raw images
            if self.quality is not None and self.resolution is not None:
                key = f"{self.quality}_{self.resolution}"
                if key not in self._jpeg_header_map:
                    self._jpeg_header_map[key] = final_image[:623]

        if self.upright:
            # Rotate image -90 degrees (or 90 degrees counterclockwise, in PIL)
            img = Image.open(io.BytesIO(final_image))
            img = img.transpose(Image.ROTATE_90)
            output = io.BytesIO()
            img.save(output, format='JPEG')
            final_image = output.getvalue()

        await self.queue.put(final_image)

        # Reset state
        self._image_data.clear()
        self._raw_offset = 0

    async def attach(self, frame: BrilliantMsg) -> asyncio.Queue:
        """
        Attach the photo handler to the Frame data response and return a queue that will receive complete images.

        Returns:
            asyncio.Queue that will receive bytes containing complete JPEG images
        """
        if self.is_raw and (self.quality is None or self.resolution is None):
            raise ValueError("Quality and resolution required when handling raw images")

        self.queue = asyncio.Queue()
        self._image_data = []
        self._raw_offset = 0

        if self.is_raw:
            # Pre-populate image data with stored JPEG header
            key = f"{self.quality}_{self.resolution}"
            if key in self._jpeg_header_map:
                self._image_data.extend(self._jpeg_header_map[key])

        # subscribe for notifications
        frame.register_data_response_handler(self, [self.non_final_chunk_flag, self.final_chunk_flag], self.handle_data)

        return self.queue

    def detach(self, frame: BrilliantMsg) -> None:
        """Detach the photo handler from the Frame data response and clean up resources"""
        frame.unregister_data_response_handler(self)
        self.queue = None
        self._image_data.clear()
        self._raw_offset = 0