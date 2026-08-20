"""Exercise the display text API on Frame or Halo (auto-detected).

The two devices have different text APIs:
  Frame: 640x400, frame.display.text(str, x, y, {color='NAME', spacing=N}),
         palette-name colours, explicit frame.display.show().
  Halo:  256x256 (1-based), frame.display.text(str, x, y, 0xRRGGBB) takes a
         direct RGB integer; glyph spacing comes from set_font(id, size,
         scale) with size a multiple of 8; show() is a no-op. The Halo
         checks are ported from the halo-firmware device test battery
         (applications/halo/tests/test_text_api.py).
"""
import asyncio
import argparse
from brilliant_ble import BrilliantBle
from brilliant_ble import BrilliantDeviceType

HALO_DISPLAY_W = 256
HALO_DISPLAY_H = 256

# Halo fonts are 8px pixel fonts; a size of N px advances N px per character.
HALO_BASE_PX = 8

# Halo's default 16-entry palette, as RGB for direct text colouring.
HALO_PALETTE = [
    ("WHITE", 0xFFFFFF),
    ("GREY", 0x808080),
    ("RED", 0xFF0000),
    ("PINK", 0xFFC0CB),
    ("DARKBROWN", 0x654321),
    ("BROWN", 0x964B00),
    ("ORANGE", 0xFFA500),
    ("YELLOW", 0xFFFF00),
    ("DARKGREEN", 0x006400),
    ("GREEN", 0x00FF00),
    ("LIGHTGREEN", 0x90EE90),
    ("NIGHTBLUE", 0x191970),
    ("SEABLUE", 0x0000CD),
    ("SKYBLUE", 0x87CEEB),
    ("CLOUDBLUE", 0xF0F8FF),
]


# ---------------------------------------------------------------------------
# Halo
# ---------------------------------------------------------------------------

async def halo_corners(b):
    """Text in all four corners, inset by 1px from each edge."""
    text = "Test"
    w = len(text) * HALO_BASE_PX
    right = HALO_DISPLAY_W - w + 1
    bottom = HALO_DISPLAY_H - HALO_BASE_PX + 1
    await b.send_lua(f"frame.display.text('{text}', 1, 1)")
    await b.send_lua(f"frame.display.text('{text}', {right}, 1)")
    await b.send_lua(f"frame.display.text('{text}', 1, {bottom})")
    await b.send_lua(f"frame.display.text('{text}', {right}, {bottom})")


async def halo_ascii_coverage(b):
    """Every printable ASCII glyph (0x20-0x7E) the fonts actually carry.

    The fonts cover ASCII only, so non-ASCII input renders as missing
    glyphs -- deliberately not tested here.
    """
    y = 1
    for start in range(0x20, 0x7F, 32):
        chunk = "".join(chr(c) for c in range(start, min(start + 32, 0x7F)))
        # escape the Lua string delimiters and backslash
        esc = chunk.replace("\\", "\\\\").replace("'", "\\'")
        await b.send_lua(f"frame.display.text('{esc}', 1, {y})")
        y += HALO_BASE_PX * 2


async def halo_sizes_and_scales(b):
    """Walk the font sizes, then the extra scale multiplier, on each font."""
    fonts = await b.send_lua(
        "local t = frame.display.get_font_list() "
        "local s = '' for i, n in pairs(t) do s = s .. i .. '=' .. n .. ' ' end "
        "print(s)",
        await_print=True,
    )
    print(f"fonts: {fonts}")

    for font_id in (0, 1):
        await b.send_lua("frame.display.clear(0x000000)")
        y = 1
        for size in (8, 16, 24, 32):
            await b.send_lua(f"frame.display.set_font({font_id}, {size})")
            await b.send_lua(f"frame.display.text('Size {size}', 1, {y})")
            y += size + 4
        await asyncio.sleep(2.00)

    # scale multiplies on top of size: size 8 x scale 2 == size 16
    await b.send_lua("frame.display.clear(0x000000)")
    await b.send_lua("frame.display.set_font(0, 8, 2)")
    await b.send_lua("frame.display.text('8px @ scale 2', 1, 1)")
    await b.send_lua("frame.display.set_font(0, 16, 1)")
    await b.send_lua("frame.display.text('16px @ scale 1', 1, 40)")
    await asyncio.sleep(2.00)

    await b.send_lua("frame.display.set_font(0, 8, 1)")


async def halo_colors(b):
    """Each default-palette colour, drawn as a direct RGB text colour."""
    await b.send_lua("frame.display.clear(0x000000)")
    half = (len(HALO_PALETTE) + 1) // 2
    for i, (name, rgb) in enumerate(HALO_PALETTE):
        x = 1 if i < half else HALO_DISPLAY_W // 2
        y = 1 + (i % half) * (HALO_BASE_PX * 2)
        await b.send_lua(f"frame.display.text('{name}', {x}, {y}, 0x{rgb:06X})")


async def halo_bad_arguments(b):
    """Bad input must raise a Lua error rather than silently misbehave."""
    checks = [
        ("frame.display.set_font(0, 12)", "size not a multiple of 8"),
        ("frame.display.set_font(99, 8)", "font id out of range"),
        ("frame.display.set_font(0, 8, 0)", "scale below 1"),
    ]
    failures = []
    for call, why in checks:
        # Print a single short token: printing pcall's own results would emit
        # "false<TAB><error message>", which arrives as several BLE
        # notifications and desynchronises await_print by one reply.
        resp = await b.send_lua(
            f"local ok = pcall(function() {call} end) "
            "print(ok and 'noerror' or 'raised')",
            await_print=True,
        )
        raised = resp is not None and resp.strip() == "raised"
        print(f"  {'ok  ' if raised else 'FAIL'} rejects {why}: {call}")
        if not raised:
            failures.append(why)
    await b.send_lua("frame.display.set_font(0, 8, 1)")
    return failures


async def run_halo(b):
    await b.send_lua("frame.display.power_save(false)")
    await b.send_lua("frame.display.clear(0x000000)")

    await halo_corners(b)
    await asyncio.sleep(2.00)

    await b.send_lua("frame.display.clear(0x000000)")
    await halo_ascii_coverage(b)
    await asyncio.sleep(2.00)

    await halo_sizes_and_scales(b)

    await halo_colors(b)
    await asyncio.sleep(2.00)

    print("argument validation:")
    failures = await halo_bad_arguments(b)

    await b.send_lua("frame.display.clear(0x000000)")
    await b.send_lua("frame.display.power_save(true)")
    return failures


# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

async def run_frame(b):
    await b.send_lua("frame.display.power_save(false)")

    # Print text in all the corners
    await b.send_lua("frame.display.text('Test', 1, 1)")
    await b.send_lua("frame.display.text('Test', 563, 1)")
    await b.send_lua("frame.display.text('Test', 1, 352)")
    await b.send_lua("frame.display.text('Test', 563, 352)")
    await b.send_lua("frame.display.show()")
    await asyncio.sleep(2.00)

    # Test UTF-8 characters
    await b.send_lua("frame.display.text('ÄÖÅ', 50, 50)")
    await b.send_lua("frame.display.show()")
    await asyncio.sleep(2.00)

    # Test spacing
    await b.send_lua("frame.display.text('Test', 50, 50, { spacing = 0})")
    await b.send_lua("frame.display.text('Test', 50, 100, { spacing = 2})")
    await b.send_lua("frame.display.text('Test', 50, 150, { spacing = 4})")
    await b.send_lua("frame.display.text('Test', 50, 200, { spacing = 10})")
    await b.send_lua("frame.display.text('Test', 50, 250, { spacing = 25})")
    await b.send_lua("frame.display.show()")
    await asyncio.sleep(2.00)

    # Print all colors
    await b.send_lua("frame.display.text('WHITE', 1, 1, { color = 'WHITE' })")
    await b.send_lua("frame.display.text('GREY', 1, 50, { color = 'GREY' })")
    await b.send_lua("frame.display.text('RED', 1, 100, { color = 'RED' })")
    await b.send_lua("frame.display.text('PINK', 1, 150, { color = 'PINK' })")
    await b.send_lua("frame.display.text('DARKBROWN', 1, 200, { color = 'DARKBROWN' })")
    await b.send_lua("frame.display.text('BROWN', 1, 250, { color = 'BROWN' })")
    await b.send_lua("frame.display.text('ORANGE', 1, 300, { color = 'ORANGE' })")
    await b.send_lua("frame.display.text('YELLOW', 1, 350, { color = 'YELLOW' })")
    await b.send_lua("frame.display.text('DARKGREEN', 320, 1, { color = 'DARKGREEN' })")
    await b.send_lua("frame.display.text('GREEN', 320, 50, { color = 'GREEN' })")
    await b.send_lua(
        "frame.display.text('LIGHTGREEN', 320, 100, { color = 'LIGHTGREEN' })"
    )
    await b.send_lua(
        "frame.display.text('NIGHTBLUE', 320, 150, { color = 'NIGHTBLUE' })"
    )
    await b.send_lua("frame.display.text('SEABLUE', 320, 200, { color = 'SEABLUE' })")
    await b.send_lua("frame.display.text('SKYBLUE', 320, 250, { color = 'SKYBLUE' })")
    await b.send_lua(
        "frame.display.text('CLOUDBLUE', 320, 300, { color = 'CLOUDBLUE' })"
    )
    await b.send_lua("frame.display.show()")
    await asyncio.sleep(2.00)

    # Change colors
    await b.send_lua("frame.display.assign_color_ycbcr('CLOUDBLUE', 15, 4, 4)")
    await b.send_lua("frame.display.assign_color_ycbcr('WHITE', 7, 4, 4)")
    await b.send_lua("frame.display.assign_color_ycbcr('GREY', 5, 3, 6)")
    await b.send_lua("frame.display.assign_color_ycbcr('RED', 9, 3, 5)")
    await b.send_lua("frame.display.assign_color_ycbcr('PINK', 2, 2, 5)")
    await b.send_lua("frame.display.assign_color_ycbcr('DARKBROWN', 4, 2, 5)")
    await b.send_lua("frame.display.assign_color_ycbcr('BROWN', 9, 2, 5)")
    await b.send_lua("frame.display.assign_color_ycbcr('ORANGE', 13, 2, 4)")
    await b.send_lua("frame.display.assign_color_ycbcr('YELLOW', 4, 4, 3)")
    await b.send_lua("frame.display.assign_color_ycbcr('DARKGREEN', 6, 2, 3)")
    await b.send_lua("frame.display.assign_color_ycbcr('GREEN', 10, 1, 3)")
    await b.send_lua("frame.display.assign_color_ycbcr('LIGHTGREEN', 1, 5, 2)")
    await b.send_lua("frame.display.assign_color_ycbcr('NIGHTBLUE', 4, 5, 2)")
    await b.send_lua("frame.display.assign_color_ycbcr('SEABLUE', 8, 5, 2)")
    await b.send_lua("frame.display.assign_color_ycbcr('SKYBLUE', 13, 4, 3)")
    await asyncio.sleep(5.00)

    # Change them back
    await b.send_lua("frame.display.assign_color_ycbcr('WHITE', 15, 4, 4)")
    await b.send_lua("frame.display.assign_color_ycbcr('GREY', 7, 4, 4)")
    await b.send_lua("frame.display.assign_color_ycbcr('RED', 5, 3, 6)")
    await b.send_lua("frame.display.assign_color_ycbcr('PINK', 9, 3, 5)")
    await b.send_lua("frame.display.assign_color_ycbcr('DARKBROWN', 2, 2, 5)")
    await b.send_lua("frame.display.assign_color_ycbcr('BROWN', 4, 2, 5)")
    await b.send_lua("frame.display.assign_color_ycbcr('ORANGE', 9, 2, 5)")
    await b.send_lua("frame.display.assign_color_ycbcr('YELLOW', 13, 2, 4)")
    await b.send_lua("frame.display.assign_color_ycbcr('DARKGREEN', 4, 4, 3)")
    await b.send_lua("frame.display.assign_color_ycbcr('GREEN', 6, 2, 3)")
    await b.send_lua("frame.display.assign_color_ycbcr('LIGHTGREEN', 10, 1, 3)")
    await b.send_lua("frame.display.assign_color_ycbcr('NIGHTBLUE', 1, 5, 2)")
    await b.send_lua("frame.display.assign_color_ycbcr('SEABLUE', 4, 5, 2)")
    await b.send_lua("frame.display.assign_color_ycbcr('SKYBLUE', 8, 5, 2)")
    await b.send_lua("frame.display.assign_color_ycbcr('CLOUDBLUE', 13, 4, 3)")
    await asyncio.sleep(5.00)

    await b.send_lua("frame.display.power_save(true)")


async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this test.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    b = BrilliantBle()

    name = await b.connect(name=args.name, print_response_handler=lambda s: print(s))

    failures = []
    if b.type == BrilliantDeviceType.HALO:
        # Break main.lua before probing: its output otherwise lands in the
        # reply stream and desynchronises every await_print below.
        await b.send_break_signal()

    fw = await b.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
    tag = await b.send_lua("print(frame.GIT_TAG)", await_print=True)
    batt = await b.send_lua("print(frame.battery_level())", await_print=True)
    print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

    if b.type == BrilliantDeviceType.FRAME:
        await run_frame(b)
    elif b.type == BrilliantDeviceType.HALO:
        failures = await run_halo(b)
        # Resume the app we interrupted with the break signal.
        await b.send_reset_signal()
    else:
        print("Unsupported device type for this test.")

    await b.disconnect()

    if failures:
        raise SystemExit(f"argument validation failed: {', '.join(failures)}")


asyncio.run(main())
