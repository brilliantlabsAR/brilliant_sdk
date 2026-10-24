"""Halo-only: stream LC3 audio to the speaker and LC3 microphone audio back to the host while streaming 128x128 4bpp images (TxImageSpriteBlock), reporting whether each stream keeps up."""
import asyncio
import argparse
import io
import os
import time
from pathlib import Path

import lc3
from PIL import Image, ImageDraw

from brilliant_msg import BrilliantMsg, RxAudio, TxCode, TxSprite, TxImageSpriteBlock
from brilliant_ble import BrilliantDeviceType, ble_write_size

# Phone to Frame flags (match lua/audio_duplex_sprites_frame_app.lua)
IMAGE_SPRITE_BLOCK = 0x20
AUDIO_START_MSG = 0x40
AUDIO_STOP_MSG = 0x41

# LC3 with 10 ms frames: bitrate / 800 bytes per frame (40 bytes at 32 kbps)
FRAME_US = 10000
FRAMES_PER_SECOND = 100

HERE = Path(__file__).parent


def make_images(count: int, size: int = 128) -> list[TxSprite]:
    """Square crops of the koala photo, each numbered so new images are visible on the display"""
    src = Image.open(HERE / "images/koala.jpg").convert("RGB")
    side = min(src.width, src.height)
    src = src.crop(((src.width - side) // 2, (src.height - side) // 2,
                    (src.width + side) // 2, (src.height + side) // 2))
    sprites = []
    for n in range(count):
        # pan the crop a little each time so every image is different
        zoom = int(side * 0.8)
        x = int((side - zoom) * n / max(1, count - 1))
        img = src.crop((x, 0, x + zoom, zoom)).resize((size, size), Image.Resampling.LANCZOS)
        ImageDraw.Draw(img).text((4, 4), f"{n:02d}", fill=(255, 255, 0))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        sprites.append(TxSprite.from_image_bytes(buf.getvalue(), max_pixels=size * size))
    return sprites


class SpeakerStream:
    """
    Sends a looped LC3 file to the speaker in real time, keeping `lead` seconds
    queued ahead of playback on the device, and records how late the sender got
    """
    def __init__(self, frame: BrilliantMsg, lc3_data: bytes, frame_bytes: int, frames_per_write: int, lead: float):
        self.frame = frame
        self.frames = [lc3_data[i:i + frame_bytes] for i in range(0, len(lc3_data) - frame_bytes + 1, frame_bytes)]
        self.frames_per_write = frames_per_write
        self.lead_frames = int(lead * FRAMES_PER_SECOND)
        self.sent = 0
        self.writes = 0
        self.max_write_gap = 0.0
        # the smallest amount of audio (s) queued ahead of the playback clock
        self.min_lead = lead

    async def run(self, duration: float):
        start = time.monotonic()
        last_write = start
        while True:
            now = time.monotonic()
            played = (now - start) * FRAMES_PER_SECOND
            if played >= duration * FRAMES_PER_SECOND:
                return
            if self.sent > 0:
                self.min_lead = min(self.min_lead, (self.sent - played) / FRAMES_PER_SECOND)
            # top up the device's queue to lead_frames ahead of where playback should be
            while self.sent < played + self.lead_frames:
                chunk = b"".join(self.frames[(self.sent + i) % len(self.frames)] for i in range(self.frames_per_write))
                await self.frame.send_audio(chunk, await_bt_response=False)
                self.sent += self.frames_per_write
                self.writes += 1
                now = time.monotonic()
                self.max_write_gap = max(self.max_write_gap, now - last_write)
                last_write = now
            await asyncio.sleep(0.01)


class ImageStream:
    """Streams the sprites back to back (or at max_fps) as the strips of one updatable TxImageSpriteBlock"""
    def __init__(self, frame: BrilliantMsg, sprites: list[TxSprite], strip_height: int, max_fps: float):
        self.frame = frame
        self.blocks = [TxImageSpriteBlock(s, sprite_line_height=strip_height) for s in sprites]
        self.max_fps = max_fps
        self.images = 0
        self.bytes = 0

    async def run(self, duration: float):
        # the header once: each later image's strips update the block in place
        await self.frame.send_message(IMAGE_SPRITE_BLOCK, self.blocks[0].pack())
        start = time.monotonic()
        while time.monotonic() - start < duration:
            block = self.blocks[self.images % len(self.blocks)]
            for strip in block.sprite_lines:
                packed = strip.pack()
                await self.frame.send_message(IMAGE_SPRITE_BLOCK, packed)
                self.bytes += len(packed)
            self.images += 1
            if self.max_fps > 0:
                next_due = start + self.images / self.max_fps
                await asyncio.sleep(max(0.0, next_due - time.monotonic()))


class MicStream:
    """Collects the LC3 microphone stream from RxAudio, counting bytes per second"""
    def __init__(self):
        self.lc3 = bytearray()
        self.first = None
        self.last = None

    async def run(self, queue: asyncio.Queue):
        while True:
            chunk = await queue.get()
            if chunk is None:
                return
            now = time.monotonic()
            if self.first is None:
                self.first = now
            self.last = now
            self.lc3 += chunk


async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo and stream speaker audio, microphone audio and images at the same time.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB"; defaults to the first device found',
    )
    parser.add_argument("--duration", type=float, default=20.0, help="seconds to stream for (default 20)")
    parser.add_argument("--volume", type=int, default=80, help="speaker volume 1..100 (default 80)")
    parser.add_argument("--lead", type=float, default=0.3, help="seconds of speaker audio to keep queued on the device (default 0.3)")
    parser.add_argument("--frames-per-write", type=int, default=0, help="LC3 frames per speaker write (default: as many as fill whole link-layer packets)")
    parser.add_argument("--mic-rate", type=int, default=16000, choices=[8000, 16000], help="microphone sample rate (default 16000)")
    parser.add_argument("--mic-kbps", type=int, default=32, help="microphone LC3 bitrate in kbps, 0 for no microphone (default 32)")
    parser.add_argument("--no-images", action="store_true", help="stream audio only, as a baseline")
    parser.add_argument("--no-speaker", action="store_true", help="don't stream speaker audio, as a baseline")
    parser.add_argument("--interval", type=int, default=15, help="connection interval (ms) for the device to ask for, 0 to leave it (the host decides; macOS/iOS grant 15 at best)")
    parser.add_argument("--image-fps", type=float, default=0, help="limit the image rate (default: back to back)")
    parser.add_argument("--strip-height", type=int, default=16, help="rows per image strip (default 16)")
    parser.add_argument("--mic-out", default="mic.wav", help="where to save the decoded microphone audio (default mic.wav)")
    args = parser.parse_args()

    # the speaker clip: LC3 at 8 kHz, 32 kbps, 10 ms frames
    spk_rate, spk_kbps = 8000, 32
    spk_frame_bytes = spk_kbps * 1000 // 800
    lc3_data = (HERE / "audio/female_w1_8k_s16.lc3").read_bytes()

    sprites = [] if args.no_images else make_images(16)

    frame = BrilliantMsg()
    started_audio = False
    try:
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG == '' and 'untagged' or frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        if frame.type != BrilliantDeviceType.HALO:
            print("This example requires a Halo (speaker and LC3 microphone)")
            return

        mtu = frame.ble._connected_client().mtu_size
        write_size = ble_write_size(min(mtu - 3, 512))
        frames_per_write = args.frames_per_write or max(1, write_size // spk_frame_bytes)
        print(f"ATT MTU {mtu} | {frames_per_write} LC3 frames "
              f"({frames_per_write * spk_frame_bytes} bytes) per speaker write")

        await frame.print_short_text('Loading...')
        await frame.upload_stdlua_libs(lib_names=['data', 'image_sprite_block'])
        await frame.upload_frame_app(local_filename=str(HERE / "lua/audio_duplex_sprites_frame_app.lua"))
        frame.attach_print_response_handler(lambda s: print(f"[halo] {s}"))
        await frame.start_frame_app()

        rx_audio = RxAudio(streaming=True)
        mic_queue = await rx_audio.attach(frame)
        mic = MicStream()
        mic_task = asyncio.create_task(mic.run(mic_queue))

        speaker = SpeakerStream(frame, lc3_data, spk_frame_bytes, frames_per_write, args.lead)
        images = ImageStream(frame, sprites, args.strip_height, args.image_fps)

        await frame.send_message(AUDIO_START_MSG, bytes([spk_rate // 1000, spk_kbps, args.volume,
                                                         args.mic_rate // 1000, args.mic_kbps, args.interval]))
        started_audio = True

        start = time.monotonic()
        tasks = [] if args.no_speaker else [speaker.run(args.duration)]
        if sprites:
            tasks.append(images.run(args.duration))
        await asyncio.gather(*tasks)
        elapsed = time.monotonic() - start

        # let the queued speaker audio play out and the last stats print
        await asyncio.sleep(args.lead + 2.5)
        await frame.send_message(AUDIO_STOP_MSG, TxCode(0).pack())
        started_audio = False
        if args.mic_kbps > 0:
            try:
                await asyncio.wait_for(mic_task, timeout=3)
            except asyncio.TimeoutError:
                print("microphone end-of-stream not received")
        mic_task.cancel()
        rx_audio.detach(frame)

        print(f"\n--- {elapsed:.1f} s ---")
        if not args.no_speaker:
            print(f"speaker: {speaker.sent} frames in {speaker.writes} writes "
                  f"({speaker.sent * spk_frame_bytes * 8 / elapsed / 1000:.1f} kbps), "
                  f"min lead {speaker.min_lead * 1000:.0f} ms, longest gap between writes {speaker.max_write_gap * 1000:.0f} ms")
        if sprites:
            print(f"images:  {images.images} ({images.images / elapsed:.2f}/s, "
                  f"{images.bytes * 8 / elapsed / 1000:.0f} kbps)")
        if args.mic_kbps > 0 and mic.first is not None:
            mic_frame_bytes = args.mic_kbps * 1000 // 800
            mic_frames = len(mic.lc3) // mic_frame_bytes
            span = mic.last - mic.first
            print(f"mic:     {mic_frames} frames ({mic_frames / FRAMES_PER_SECOND:.1f} s of audio) "
                  f"received over {span:.1f} s")
            decoder = lc3.Decoder(FRAME_US, args.mic_rate)
            pcm = b"".join(decoder.decode(bytes(mic.lc3[i:i + mic_frame_bytes]), bit_depth=16)
                           for i in range(0, mic_frames * mic_frame_bytes, mic_frame_bytes))
            Path(args.mic_out).write_bytes(RxAudio.to_wav_bytes(pcm, sample_rate=args.mic_rate, bits_per_sample=16))
            print(f"         saved to {os.path.abspath(args.mic_out)}")

        frame.detach_print_response_handler()
        await frame.stop_frame_app()

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if started_audio:
            try:
                await frame.send_message(AUDIO_STOP_MSG, TxCode(0).pack())
            except Exception:
                pass
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
