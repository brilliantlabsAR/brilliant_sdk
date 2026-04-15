"""frame.compression.* stubs — LZ4 decompression."""
from __future__ import annotations

from typing import Callable


class CompressionStub:
    def __init__(self) -> None:
        self._process_fn: Callable | None = None

    def process_function(self, func: Callable | None) -> None:
        self._process_fn = func

    def decompress(self, data: object, block_size: int) -> None:
        import lz4.frame as lz4f

        if self._process_fn is None:
            raise RuntimeError("frame.compression.decompress: no process_function registered")

        if isinstance(data, (bytes, bytearray)):
            raw = bytes(data)
        else:
            raw = str(data).encode("latin-1")

        decompressed = lz4f.decompress(raw)
        block_size = int(block_size)
        offset = 0
        while offset < len(decompressed):
            chunk = decompressed[offset: offset + block_size]
            self._process_fn(chunk.decode("latin-1"))
            offset += block_size
