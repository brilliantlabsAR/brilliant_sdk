from dataclasses import dataclass

@dataclass
class TxCode:
    """
    A simple message containing only a message code and an optional byte value.
    Used for signaling the frameside app to take some action.
    """
    value: int = 0

    def pack(self) -> bytes:
        """Pack the message into a single byte."""
        return bytes([self.value & 0xFF])