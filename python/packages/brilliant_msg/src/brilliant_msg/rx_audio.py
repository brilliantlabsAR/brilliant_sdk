import asyncio
import logging
import struct
from typing import Optional
from io import BytesIO

from brilliant_msg import BrilliantMsg

logging.basicConfig()
_log = logging.getLogger("RxAudio")

class RxAudio:
    def __init__(
        self,
        non_final_chunk_flag: int = 0x05,
        final_chunk_flag: int = 0x06,
        streaming: bool = False
    ):
        """
        Initialize audio handler for processing audio data chunks.

        Args:
            non_final_chunk_flag: Flag indicating a non-final chunk of audio data
            final_chunk_flag: Flag indicating the final chunk of audio data
            streaming: If True, emit chunks as they arrive; if False, accumulate and emit complete clip
        """
        self.non_final_chunk_flag = non_final_chunk_flag
        self.final_chunk_flag = final_chunk_flag
        self.streaming = streaming

        self.queue: Optional[asyncio.Queue] = None
        self._audio_buffer = BytesIO()
        self._raw_offset = 0

    def handle_data(self, data: bytes) -> None:
        """
        Process incoming audio data packets with either a non-final or a final msg code.

        Args:
            data: Bytes containing audio data with flag byte prefix
        """
        if not self.queue:
            _log.warning("Received data but queue not initialized - call start() first")
            return

        flag = data[0]
        chunk = data[1:]

        if self.streaming:
            if len(chunk) > 0:
                # In streaming mode, immediately queue each chunk
                asyncio.create_task(self.queue.put(bytes(chunk)))

            if flag == self.final_chunk_flag:
                # Signal end of stream with None
                asyncio.create_task(self.queue.put(None))

        else:
            # In single-clip mode, accumulate chunks
            self._audio_buffer.write(chunk)
            self._raw_offset += len(chunk)

            if flag == self.final_chunk_flag:
                # Get the complete audio data and reset buffer
                complete_audio = self._audio_buffer.getvalue()
                self._audio_buffer = BytesIO()
                self._raw_offset = 0

                # Queue the complete audio clip
                asyncio.create_task(self.queue.put(complete_audio))
                # Signal end with None
                asyncio.create_task(self.queue.put(None))

    async def attach(self, frame: BrilliantMsg) -> asyncio.Queue:
        """
        Attach the audio handler to the Frame data response and return a queue that will receive audio data.

        Returns:
            asyncio.Queue that will receive bytes containing audio data.
            In streaming mode, receives chunks as they arrive.
            In single-clip mode, receives complete audio clip at once.
            A None value indicates end of stream/clip.
        """
        self.queue = asyncio.Queue()
        self._audio_buffer = BytesIO()
        self._raw_offset = 0

        # subscribe to the data response feed
        frame.register_data_response_handler(self, [self.non_final_chunk_flag, self.final_chunk_flag], self.handle_data)

        return self.queue

    def detach(self, frame: BrilliantMsg) -> None:
        """Detach the audio handler from the Frame data response and clean up resources"""
        # unsubscribe from the data response feed
        frame.unregister_data_response_handler(self)
        self.queue = None
        self._audio_buffer = BytesIO()
        self._raw_offset = 0

    @staticmethod
    def to_wav_bytes(
        pcm_data: bytes,
        sample_rate: int = 8000,
        bits_per_sample: int = 8,
        channels: int = 1
    ) -> bytes:
        """
        Create a WAV file from PCM data.

        Args:
            pcm_data: Raw PCM audio data - signed 8-bit or 16-bit samples straight from Frame (8-bit signed will be converted to unsigned 8-bit for WAV)
            sample_rate: Audio sample rate in Hz
            bits_per_sample: Number of bits per sample
            channels: Number of audio channels

        Returns:
            Bytes containing complete WAV file
        """
        byte_rate = sample_rate * channels * bits_per_sample // 8
        data_size = len(pcm_data)
        file_size = 36 + data_size

        # Create WAV header
        header = struct.pack(
            '<4sI4s'    # RIFF chunk descriptor
            '4sI'       # fmt chunk
            'HHIIHH'    # fmt chunk data
            '4sI',      # data chunk header

            # RIFF chunk
            b'RIFF',
            file_size,
            b'WAVE',

            # fmt chunk
            b'fmt ',
            16,                         # Subchunk1Size (16 for PCM)
            1,                          # AudioFormat (1 for PCM)
            channels,                   # NumChannels
            sample_rate,                # SampleRate
            byte_rate,                  # ByteRate
            channels * bits_per_sample // 8,  # BlockAlign
            bits_per_sample,            # BitsPerSample

            # data chunk header
            b'data',
            data_size
        )

        # Convert 8-bit signed PCM to unsigned 8-bit for WAV format (16-bit PCM is left as-is)
        if bits_per_sample == 8:
            # Iterate over each sample and reinterpret as signed 8-bit then convert to unsigned 8-bit
            pcm_data = bytearray(pcm_data)
            for i in range(len(pcm_data)):
                # Convert signed 8-bit (-128 to 127) to unsigned 8-bit (0 to 255)
                pcm_data[i] = (pcm_data[i] if pcm_data[i] < 128 else pcm_data[i] - 256) + 128

            pcm_data = bytes(pcm_data)

        return header + pcm_data
