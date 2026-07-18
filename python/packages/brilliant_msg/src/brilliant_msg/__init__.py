"""
brilliant_msg - Message Package defines Transmit- and Receive-related message classes and their associated Lua handlers for Brilliant Labs Frame and Halo devices (https://brilliant.xyz/)
"""

__version__ = "7.0.0"

from .brilliant_msg import BrilliantMsg

from .tx_auto_exp_settings import TxAutoExpSettings
from .tx_capture_settings import TxCaptureSettings
from .tx_code import TxCode
from .tx_image_sprite_block import TxImageSpriteBlock
from .tx_manual_exp_settings import TxManualExpSettings
from .tx_plain_text import TxPlainText
from .tx_sprite import TxSprite
from .tx_sprite_coords import TxSpriteCoords
from .tx_text_sprite_block import TxTextSpriteBlock

from .rx_audio import RxAudio
from .rx_auto_exp_result import RxAutoExpResult
from .rx_imu import RxIMU
from .rx_metering_data import RxMeteringData
from .rx_photo import RxPhoto
from .rx_tap import RxTap

from .heading import (
    basic_heading,
    tilt_compensated_heading,
    apply_declination,
    degrees_to_cardinal,
)

from .calibration import MagCalibration
