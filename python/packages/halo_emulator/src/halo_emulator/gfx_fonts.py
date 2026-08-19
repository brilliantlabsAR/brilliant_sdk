"""Dogica 8 px GFX fonts, converted from the Halo firmware sources.

Generated from halo-firmware modules/canvas/Fonts/dogica/{Dogica8px.h,
DogicaBold8px.h} (Adafruit-GFX format, ASCII 0x20-0x7E) by a one-off
conversion script -- do not edit by hand.

Dogica font (c) Roberto Mocci, SIL Open Font License 1.1.
"""
from __future__ import annotations

from typing import NamedTuple


class GfxGlyph(NamedTuple):
    bitmap_offset: int
    width: int
    height: int
    x_advance: int
    x_offset: int
    y_offset: int


class GfxFont(NamedTuple):
    first: int
    last: int
    y_advance: int
    bitmaps: bytes
    glyphs: list[GfxGlyph]


DOGICA_8PX = GfxFont(
    first=0x20,
    last=0x7E,
    y_advance=10,
    bitmaps=bytes.fromhex(
        "fa55a04bf492fd207568e2d5c04552a281454aa2624918962740586aa495582555520021"
        "3e420058f08011224488746b5ac5c027084213e074422223e0f042e087c011952f8840fc"
        "3c10c5c07461e8c5c0fc422221007462e8c5c07462f089809045802a22fc0fc088a87442"
        "640080790ad4ab905f0074631fc620f463e8c7c074610845c0f91451451780fc21e843e0"
        "fc21e842007c2138c5e08c63f8c620e924b8f22222c08ca9c94a20888888f0861ced8618"
        "408e6b38c620746318c5c0f463e8420074631ac9a0f463e946207460e0c5c0f908421080"
        "8c6318c5c08c6315288083064c993551008c544546208c62a21080f8444443e0eaac8844"
        "2211d55c69fc94705f18bc843d18c7c07461083c085f18c5e0747f083c3a11e421007c63"
        "1785c0842d98c6204324b8e924a08ca9c9449248c06d264c993240366318c4746318b8f4"
        "631f42007c63178420bc8888741c18b888f888708c6319b48c62a510069a69a5608a8845"
        "4499962cf1248f25488452ff4a2112a46660"
    ),
    glyphs=[
        GfxGlyph(0, 0, 0, 8, 0, 0),
        GfxGlyph(0, 1, 7, 8, 3, -7),
        GfxGlyph(1, 4, 3, 8, 2, -6),
        GfxGlyph(3, 6, 6, 8, 1, -6),
        GfxGlyph(8, 5, 7, 8, 1, -6),
        GfxGlyph(13, 7, 8, 8, 1, -7),
        GfxGlyph(20, 6, 7, 8, 1, -7),
        GfxGlyph(26, 2, 3, 8, 3, -6),
        GfxGlyph(27, 2, 7, 8, 3, -7),
        GfxGlyph(29, 2, 7, 8, 3, -7),
        GfxGlyph(31, 5, 5, 8, 1, -6),
        GfxGlyph(35, 5, 5, 8, 1, -6),
        GfxGlyph(39, 2, 3, 8, 3, -2),
        GfxGlyph(40, 4, 1, 8, 2, -3),
        GfxGlyph(41, 1, 1, 8, 3, -1),
        GfxGlyph(42, 4, 8, 8, 2, -7),
        GfxGlyph(46, 5, 7, 8, 1, -7),
        GfxGlyph(51, 5, 7, 8, 1, -7),
        GfxGlyph(56, 5, 7, 8, 1, -7),
        GfxGlyph(61, 5, 7, 8, 1, -7),
        GfxGlyph(66, 5, 7, 8, 1, -7),
        GfxGlyph(71, 5, 7, 8, 1, -7),
        GfxGlyph(76, 5, 7, 8, 1, -7),
        GfxGlyph(81, 5, 7, 8, 1, -7),
        GfxGlyph(86, 5, 7, 8, 1, -7),
        GfxGlyph(91, 5, 7, 8, 1, -7),
        GfxGlyph(96, 1, 4, 8, 3, -5),
        GfxGlyph(97, 2, 5, 8, 3, -4),
        GfxGlyph(99, 3, 5, 8, 2, -6),
        GfxGlyph(101, 6, 3, 8, 1, -5),
        GfxGlyph(104, 3, 5, 8, 3, -6),
        GfxGlyph(106, 5, 7, 8, 1, -7),
        GfxGlyph(111, 7, 7, 8, 1, -7),
        GfxGlyph(118, 5, 7, 8, 1, -7),
        GfxGlyph(123, 5, 7, 8, 1, -7),
        GfxGlyph(128, 5, 7, 8, 1, -7),
        GfxGlyph(133, 6, 7, 8, 0, -7),
        GfxGlyph(139, 5, 7, 8, 1, -7),
        GfxGlyph(144, 5, 7, 8, 2, -7),
        GfxGlyph(149, 5, 7, 8, 1, -7),
        GfxGlyph(154, 5, 7, 8, 1, -7),
        GfxGlyph(159, 3, 7, 8, 2, -7),
        GfxGlyph(162, 4, 7, 8, 1, -7),
        GfxGlyph(166, 5, 7, 8, 1, -7),
        GfxGlyph(171, 4, 7, 8, 2, -7),
        GfxGlyph(175, 6, 7, 8, 0, -7),
        GfxGlyph(181, 5, 7, 8, 1, -7),
        GfxGlyph(186, 5, 7, 8, 2, -7),
        GfxGlyph(191, 5, 7, 8, 1, -7),
        GfxGlyph(196, 5, 7, 8, 1, -7),
        GfxGlyph(201, 5, 7, 8, 1, -7),
        GfxGlyph(206, 5, 7, 8, 1, -7),
        GfxGlyph(211, 5, 7, 8, 1, -7),
        GfxGlyph(216, 5, 7, 8, 1, -7),
        GfxGlyph(221, 5, 7, 8, 1, -7),
        GfxGlyph(226, 7, 7, 8, 0, -7),
        GfxGlyph(233, 5, 7, 8, 1, -7),
        GfxGlyph(238, 5, 7, 8, 1, -7),
        GfxGlyph(243, 5, 7, 8, 1, -7),
        GfxGlyph(248, 2, 7, 8, 3, -7),
        GfxGlyph(250, 4, 8, 8, 2, -7),
        GfxGlyph(254, 2, 7, 8, 3, -7),
        GfxGlyph(256, 4, 2, 8, 2, -6),
        GfxGlyph(257, 6, 1, 8, 1, 0),
        GfxGlyph(258, 2, 3, 8, 3, -6),
        GfxGlyph(259, 5, 6, 8, 1, -6),
        GfxGlyph(263, 5, 7, 8, 1, -7),
        GfxGlyph(268, 5, 6, 8, 1, -6),
        GfxGlyph(272, 5, 7, 8, 1, -7),
        GfxGlyph(277, 5, 6, 8, 1, -6),
        GfxGlyph(281, 5, 7, 8, 1, -7),
        GfxGlyph(286, 5, 7, 8, 1, -6),
        GfxGlyph(291, 5, 7, 8, 1, -7),
        GfxGlyph(296, 3, 7, 8, 2, -7),
        GfxGlyph(299, 3, 7, 8, 2, -6),
        GfxGlyph(302, 5, 6, 8, 1, -6),
        GfxGlyph(306, 3, 6, 8, 2, -6),
        GfxGlyph(309, 7, 6, 8, 0, -6),
        GfxGlyph(315, 5, 6, 8, 1, -6),
        GfxGlyph(319, 5, 6, 8, 1, -6),
        GfxGlyph(323, 5, 7, 8, 2, -6),
        GfxGlyph(328, 5, 7, 8, 1, -6),
        GfxGlyph(333, 4, 6, 8, 2, -6),
        GfxGlyph(336, 5, 6, 8, 1, -6),
        GfxGlyph(340, 4, 7, 8, 2, -7),
        GfxGlyph(344, 5, 6, 8, 1, -6),
        GfxGlyph(348, 5, 6, 8, 1, -6),
        GfxGlyph(352, 6, 6, 8, 1, -6),
        GfxGlyph(357, 5, 6, 8, 1, -6),
        GfxGlyph(361, 4, 6, 8, 2, -6),
        GfxGlyph(364, 4, 6, 8, 2, -6),
        GfxGlyph(367, 4, 8, 8, 2, -7),
        GfxGlyph(371, 1, 8, 8, 3, -7),
        GfxGlyph(372, 4, 8, 8, 2, -7),
        GfxGlyph(376, 6, 2, 8, 0, -4),
    ],
)

DOGICA_BOLD_8PX = GfxFont(
    first=0x20,
    last=0x7E,
    y_advance=10,
    bitmaps=bytes.fromhex(
        "ffcc6dbd806dfdb36fed807daf43e17adf0046acec581a35376271b3638df99f806f007b"
        "6d98cdb6f033f7bf3030cfcc306f00f8f018cc6633187b3effdf378033c30c30cfc07b30"
        "c6318fc0f830de0c3f8018e7b6fc6180ff0f830f37807b3c3ecf3780ff30c63186007b3c"
        "decf37807b3cdf0c6700c361bc36c630fe03f8c636c07b30ce6003007cc6fedefcc37e7b"
        "3cf3ff3cc0fb3cfecf3f807b3c30c33780fccd9b366cdf00ff0c3ec30fc0ff0c3ec30c00"
        "7f0c37cf37c0cf3cffcf3cc0f66666f0f98c631b80cf6f3cdb6cc0c6318c63e0c78fbffc"
        "78f180cfbff7cf3cc07b3cf3cf3780fb3cfec30c007b3cf3ef67c0fb3cfedb3cc07b3c1e"
        "0f3780fcc30c30c300cf3cf3cf3780cf3cf379e300c3c3dbdbdbff66cf378c7b3cc0cf3c"
        "de30c300fc318c630fc0fb6db8c618c31863edb6f876c0fecd807837f3cdf0c30fb3cf3f"
        "807b3c30c1f00c37f3cf37c07b3ff0c1f03d863e6186007f3cf37c3780c30fbbcf3cc060"
        "e666f0f66666c0cf6f3cdb30ccccc77edbdbdbdbdb3bbcf3cf307b3cf3cde0fb3cf3fb0c"
        "007f3cf37c30c07f318c607b0783cde0c63f8c61e0cf3cf3ddf0cf3cde78c003dbdbdbdb"
        "7ecde30c7b30def6e370f8cccc7c33518c21a6ffff6584318acc77b8"
    ),
    glyphs=[
        GfxGlyph(0, 0, 0, 8, 0, 0),
        GfxGlyph(0, 2, 7, 8, 3, -7),
        GfxGlyph(2, 6, 3, 8, 1, -6),
        GfxGlyph(5, 7, 6, 8, 1, -6),
        GfxGlyph(11, 7, 7, 8, 1, -6),
        GfxGlyph(18, 8, 8, 8, 0, -7),
        GfxGlyph(26, 7, 7, 8, 1, -7),
        GfxGlyph(33, 3, 3, 8, 3, -6),
        GfxGlyph(35, 3, 7, 8, 3, -7),
        GfxGlyph(38, 3, 7, 8, 3, -7),
        GfxGlyph(41, 6, 5, 8, 1, -6),
        GfxGlyph(45, 6, 5, 8, 1, -6),
        GfxGlyph(49, 3, 3, 8, 3, -2),
        GfxGlyph(51, 5, 1, 8, 2, -3),
        GfxGlyph(52, 2, 2, 8, 3, -2),
        GfxGlyph(53, 5, 8, 8, 2, -7),
        GfxGlyph(58, 6, 7, 8, 1, -7),
        GfxGlyph(64, 6, 7, 8, 1, -7),
        GfxGlyph(70, 6, 7, 8, 1, -7),
        GfxGlyph(76, 6, 7, 8, 1, -7),
        GfxGlyph(82, 6, 7, 8, 1, -7),
        GfxGlyph(88, 6, 7, 8, 1, -7),
        GfxGlyph(94, 6, 7, 8, 1, -7),
        GfxGlyph(100, 6, 7, 8, 1, -7),
        GfxGlyph(106, 6, 7, 8, 1, -7),
        GfxGlyph(112, 6, 7, 8, 1, -7),
        GfxGlyph(118, 2, 4, 8, 3, -5),
        GfxGlyph(119, 3, 5, 8, 3, -4),
        GfxGlyph(121, 4, 5, 8, 2, -6),
        GfxGlyph(124, 7, 3, 8, 1, -5),
        GfxGlyph(127, 4, 5, 8, 2, -6),
        GfxGlyph(130, 6, 7, 8, 1, -7),
        GfxGlyph(136, 8, 7, 8, 0, -7),
        GfxGlyph(143, 6, 7, 8, 1, -7),
        GfxGlyph(149, 6, 7, 8, 1, -7),
        GfxGlyph(155, 6, 7, 8, 1, -7),
        GfxGlyph(161, 7, 7, 8, 0, -7),
        GfxGlyph(168, 6, 7, 8, 1, -7),
        GfxGlyph(174, 6, 7, 8, 1, -7),
        GfxGlyph(180, 6, 7, 8, 1, -7),
        GfxGlyph(186, 6, 7, 8, 1, -7),
        GfxGlyph(192, 4, 7, 8, 2, -7),
        GfxGlyph(196, 5, 7, 8, 2, -7),
        GfxGlyph(201, 6, 7, 8, 1, -7),
        GfxGlyph(207, 5, 7, 8, 2, -7),
        GfxGlyph(212, 7, 7, 8, 1, -7),
        GfxGlyph(219, 6, 7, 8, 1, -7),
        GfxGlyph(225, 6, 7, 8, 1, -7),
        GfxGlyph(231, 6, 7, 8, 1, -7),
        GfxGlyph(237, 6, 7, 8, 1, -7),
        GfxGlyph(243, 6, 7, 8, 1, -7),
        GfxGlyph(249, 6, 7, 8, 1, -7),
        GfxGlyph(255, 6, 7, 8, 1, -7),
        GfxGlyph(261, 6, 7, 8, 1, -7),
        GfxGlyph(267, 6, 7, 8, 1, -7),
        GfxGlyph(273, 8, 7, 8, 0, -7),
        GfxGlyph(280, 6, 7, 8, 1, -7),
        GfxGlyph(286, 6, 7, 8, 1, -7),
        GfxGlyph(292, 6, 7, 8, 1, -7),
        GfxGlyph(298, 3, 7, 8, 3, -7),
        GfxGlyph(301, 5, 8, 8, 2, -7),
        GfxGlyph(306, 3, 7, 8, 3, -7),
        GfxGlyph(309, 5, 2, 8, 1, -6),
        GfxGlyph(311, 7, 1, 8, 1, 0),
        GfxGlyph(312, 3, 3, 8, 3, -6),
        GfxGlyph(314, 6, 6, 8, 1, -6),
        GfxGlyph(319, 6, 7, 8, 1, -7),
        GfxGlyph(325, 6, 6, 8, 1, -6),
        GfxGlyph(330, 6, 7, 8, 1, -7),
        GfxGlyph(336, 6, 6, 8, 1, -6),
        GfxGlyph(341, 6, 7, 8, 1, -7),
        GfxGlyph(347, 6, 7, 8, 1, -6),
        GfxGlyph(353, 6, 7, 8, 1, -7),
        GfxGlyph(359, 4, 7, 8, 2, -7),
        GfxGlyph(363, 4, 7, 8, 2, -6),
        GfxGlyph(367, 6, 6, 8, 1, -6),
        GfxGlyph(372, 4, 6, 8, 2, -6),
        GfxGlyph(375, 8, 6, 8, 0, -6),
        GfxGlyph(381, 6, 6, 8, 1, -6),
        GfxGlyph(386, 6, 6, 8, 1, -6),
        GfxGlyph(391, 6, 7, 8, 1, -6),
        GfxGlyph(397, 6, 7, 8, 1, -6),
        GfxGlyph(403, 5, 6, 8, 2, -6),
        GfxGlyph(407, 6, 6, 8, 1, -6),
        GfxGlyph(412, 5, 7, 8, 2, -7),
        GfxGlyph(417, 6, 6, 8, 1, -6),
        GfxGlyph(422, 6, 6, 8, 1, -6),
        GfxGlyph(427, 8, 6, 8, 0, -6),
        GfxGlyph(433, 6, 6, 8, 1, -6),
        GfxGlyph(438, 5, 6, 8, 2, -6),
        GfxGlyph(442, 5, 6, 8, 2, -6),
        GfxGlyph(446, 5, 8, 8, 2, -7),
        GfxGlyph(451, 2, 8, 8, 3, -7),
        GfxGlyph(453, 5, 8, 8, 2, -7),
        GfxGlyph(458, 7, 2, 8, 1, -4),
    ],
)

# font_id -> (name, font), matching the firmware font table order
FONT_LIST: dict[int, tuple[str, GfxFont]] = {
    0: ("Dogica", DOGICA_8PX),
    1: ("DogicaBold", DOGICA_BOLD_8PX),
}
