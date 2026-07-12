#!/usr/bin/env python3
"""Realtime voice conversation on Brilliant Halo via the OpenAI Realtime API.

Halo-only. Streams the Halo microphone (LC3, 16 kHz) to an OpenAI Realtime
endpoint - or any OpenAI-Realtime **GA** compatible backend, e.g. a local
huggingface/speech-to-speech server - and plays the reply back through the
Halo speaker. The assistant's transcript is mirrored on the glasses display.

Audio is always 24 kHz PCM over the wire, matching the official OpenAI Realtime
API. liblc3 (via the ``lc3py`` package) does the conversion inside the codec:
the Halo LC3 streams stay at 16 kHz while the decoder outputs / encoder accepts
24 kHz PCM. So there's no separate resampler, and no rate to configure.

Half-duplex: the mic is muted while the assistant is speaking, because the
bone-conduction speaker bleeds into the mic and there is no echo cancellation
yet. This keeps the session simple and linear - the server's voice-activity
detection starts a reply when you stop talking; talk again after it finishes.

Usage:
    export OPENAI_API_KEY=sk-...
    uv run python packages/brilliant_msg/examples/openai_realtime.py

    # a local backend that needs no key:
    uv run python packages/brilliant_msg/examples/openai_realtime.py \\
        --url ws://192.168.1.10:8765/v1/realtime --api-key ''

Requires the "examples" extra (websockets, lc3py):
    uv sync --all-packages --extra examples
"""
import argparse
import asyncio
import base64
import json
import os
import signal

import lc3
from websockets.asyncio.client import connect

from brilliant_ble import BrilliantDeviceType
from brilliant_msg import BrilliantMsg, RxAudio, TxCode, TxPlainText

# --- message codes (must match lua/openai_realtime_frame_app.lua) ---
CLEAR_MSG = 0x10
TEXT_MSG = 0x12
START_LISTENING_MSG = 0x30
STOP_LISTENING_MSG = 0x31
START_PLAYBACK_MSG = 0x40
STOP_PLAYBACK_MSG = 0x41

# --- LC3 / audio config ---
HALO_RATE = 16000  # coded LC3 rate on the Halo mic + speaker
FRAME_US = 10000  # 10 ms LC3 frames
BITRATE = 32000  # 32 kbps
LC3_FRAME_BYTES = BITRATE // 8 * FRAME_US // 1_000_000  # 40 bytes / frame

DEFAULT_URL = "wss://api.openai.com/v1/realtime?model=gpt-realtime"
SERVER_RATE = 24000  # PCM rate over the wire, per the official OpenAI Realtime API
PCM_FRAME_BYTES = SERVER_RATE // 100 * 2  # 10 ms of 24 kHz PCM16 = 480 bytes
MIC_GAIN_VALUE = 10  # device maps 0..20 -> gain -10..10; 10 -> gain 0
SPEAKER_VOLUME = 100  # the Halo speaker is quiet, so run it at full volume

# glasses display: monospace 9pt, ~21 chars fit across the 256px width
HALO_CHARS_PER_LINE = 21


def wrap_for_halo(text: str, max_lines: int = 4) -> str:
    """Word-wrap text for the Halo display and keep the last `max_lines` lines."""
    lines: list[str] = []
    line = ""
    for word in text.split():
        w = word
        while len(w) > HALO_CHARS_PER_LINE:
            if line:
                lines.append(line)
                line = ""
            lines.append(w[:HALO_CHARS_PER_LINE])
            w = w[HALO_CHARS_PER_LINE:]
        candidate = w if not line else f"{line} {w}"
        if len(candidate) > HALO_CHARS_PER_LINE:
            lines.append(line)
            line = w
        else:
            line = candidate
    if line:
        lines.append(line)
    return "\n".join(lines[-max_lines:])


def session_update(voice: str, instructions: str) -> dict:
    """The OpenAI Realtime GA session.update message (24 kHz PCM)."""
    return {
        "type": "session.update",
        "session": {
            "type": "realtime",
            "output_modalities": ["audio"],
            "instructions": instructions,
            "audio": {
                "input": {
                    "format": {"type": "audio/pcm", "rate": SERVER_RATE},
                    "transcription": {"model": "whisper-1"},
                    "turn_detection": {"type": "server_vad"},
                },
                "output": {
                    "format": {"type": "audio/pcm", "rate": SERVER_RATE},
                    "voice": voice,
                },
            },
        },
    }


class Session:
    """Bridges the Halo audio streams and an OpenAI Realtime websocket."""

    def __init__(self, frame: BrilliantMsg, ws, frames_per_write: int):
        self.frame = frame
        self.ws = ws
        self.frames_per_write = frames_per_write

        # liblc3 does the resampling inside the codec: coded 16 kHz Halo LC3 <->
        # 24 kHz PCM over the wire. The decoder upsamples the mic to 24 kHz; the
        # encoder downsamples the server's 24 kHz reply back to 16 kHz.
        self.decoder = lc3.Decoder(FRAME_US, HALO_RATE, 1, output_sample_rate_hz=SERVER_RATE)
        self.encoder = lc3.Encoder(FRAME_US, HALO_RATE, 1, input_sample_rate_hz=SERVER_RATE)

        self.speaker_queue: asyncio.Queue = asyncio.Queue()  # LC3 frames to play out
        self._mic_lc3_buf = bytearray()  # unaligned LC3 bytes from the mic
        self._spk_pcm_buf = bytearray()  # server PCM awaiting frame alignment
        self.response_active = False  # a reply is being generated
        self._assistant_text = ""  # accumulates the current reply transcript
        self._saw_transcript_delta = False  # did this turn stream transcript deltas?

    def _speaking(self) -> bool:
        """Half-duplex gate: True while a reply is generating or still playing out."""
        return self.response_active or not self.speaker_queue.empty()

    # --- Halo mic -> OpenAI -----------------------------------------------
    async def pump_mic(self, mic_queue: asyncio.Queue):
        while True:
            chunk = await mic_queue.get()
            if chunk is None:  # end-of-stream marker
                continue
            self._mic_lc3_buf += chunk

            pcm = bytearray()
            while len(self._mic_lc3_buf) >= LC3_FRAME_BYTES:
                frame_bytes = bytes(self._mic_lc3_buf[:LC3_FRAME_BYTES])
                del self._mic_lc3_buf[:LC3_FRAME_BYTES]
                pcm += self.decoder.decode(frame_bytes, bit_depth=16)

            # drop mic audio while the assistant is speaking (no echo cancellation)
            if not pcm or self._speaking():
                continue
            await self.ws.send(json.dumps({
                "type": "input_audio_buffer.append",
                "audio": base64.b64encode(bytes(pcm)).decode("ascii"),
            }))

    # --- OpenAI -> Halo speaker -------------------------------------------
    def _enqueue_playback(self, pcm: bytes):
        self._spk_pcm_buf += pcm
        while len(self._spk_pcm_buf) >= PCM_FRAME_BYTES:
            frame_pcm = bytes(self._spk_pcm_buf[:PCM_FRAME_BYTES])
            del self._spk_pcm_buf[:PCM_FRAME_BYTES]
            self.speaker_queue.put_nowait(
                self.encoder.encode(frame_pcm, LC3_FRAME_BYTES, bit_depth=16))

    async def pump_speaker(self):
        while True:
            frames = [await self.speaker_queue.get()]
            while len(frames) < self.frames_per_write:
                try:
                    frames.append(self.speaker_queue.get_nowait())
                except asyncio.QueueEmpty:
                    break
            await self.frame.send_audio(b"".join(frames), await_bt_response=False)
            # pace slightly faster than realtime (each frame is 10 ms of audio)
            await asyncio.sleep(len(frames) * 0.009)

    # --- OpenAI event stream ----------------------------------------------
    async def receive(self):
        async for message in self.ws:
            event = json.loads(message)
            etype = event.get("type")

            if etype == "response.created":
                self.response_active = True
                self._assistant_text = ""
                self._saw_transcript_delta = False
            elif etype == "response.output_audio.delta":
                self._enqueue_playback(base64.b64decode(event["delta"]))
            elif etype == "response.output_audio_transcript.delta":
                delta = event.get("delta", "")
                self._saw_transcript_delta = True
                self._assistant_text += delta
                print(delta, end="", flush=True)
                await self._show(wrap_for_halo(self._assistant_text))
            elif etype == "conversation.item.input_audio_transcription.completed":
                transcript = (event.get("transcript") or "").strip()
                if transcript:
                    print(f"\nYou: {transcript}")
            elif etype == "response.output_audio_transcript.done":
                # some backends (e.g. huggingface/speech-to-speech) send the
                # assistant transcript only here, not as deltas - render it then
                if not self._saw_transcript_delta:
                    full = (event.get("transcript") or "").strip()
                    if full:
                        print(f"Assistant: {full}")
                        await self._show(wrap_for_halo(full))
                else:
                    print()  # newline after the streamed transcript
            elif etype == "response.done":
                self.response_active = False
            elif etype == "error":
                err = event.get("error", {})
                print(f"\n[error] {err.get('message', err)}")

    async def _show(self, text: str):
        try:
            await self.frame.send_message(
                TEXT_MSG, TxPlainText(text=text, x=15, y=50).pack())
        except Exception:
            pass  # a dropped display update is not worth interrupting audio


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--url", default=os.environ.get("OPENAI_REALTIME_URL", DEFAULT_URL),
                   help="Realtime websocket URL (env OPENAI_REALTIME_URL)")
    p.add_argument("--api-key", default=None,
                   help="API key; defaults to env OPENAI_API_KEY. Pass '' for a "
                        "local backend with no auth")
    p.add_argument("--voice", default="alloy", help="assistant voice")
    p.add_argument("--instructions",
                   default="You are a helpful assistant speaking to the user "
                           "through their smart glasses. Be natural, direct and "
                           "concise - answer in a sentence or two.",
                   help="system instruction")
    return p.parse_args()


async def main():
    args = parse_args()
    api_key = args.api_key if args.api_key is not None else os.environ.get("OPENAI_API_KEY", "")

    frame = BrilliantMsg()
    started_audio = False
    try:
        await frame.connect()
        if frame.type != BrilliantDeviceType.HALO:
            print("This example requires a Halo (LC3 audio in both directions)")
            return

        await frame.send_break_signal()
        await frame.print_short_text("Connecting...")
        await frame.upload_stdlua_libs(lib_names=["data", "code", "plain_text"])
        lua_path = os.path.join(os.path.dirname(__file__), "lua",
                                "openai_realtime_frame_app.lua")
        await frame.upload_frame_app(local_filename=lua_path)
        frame.attach_print_response_handler()
        await frame.start_frame_app()

        headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        print(f"Connecting to {args.url} ...")
        async with connect(args.url, additional_headers=headers, max_size=None) as ws:
            await ws.send(json.dumps(session_update(args.voice, args.instructions)))

            frames_per_write = max(1, frame.max_lua_payload() // LC3_FRAME_BYTES)
            session = Session(frame, ws, frames_per_write)

            rx_audio = RxAudio(streaming=True)
            mic_queue = await rx_audio.attach(frame)

            await frame.send_message(START_PLAYBACK_MSG, TxCode(SPEAKER_VOLUME).pack())
            await frame.send_message(START_LISTENING_MSG, TxCode(MIC_GAIN_VALUE).pack())
            started_audio = True
            await session._show("Listening...")
            print("Session started - speak to the Halo. Ctrl-C to quit.\n")

            # run until Ctrl-C or a task ends (e.g. the websocket closes)
            stop = asyncio.Event()
            loop = asyncio.get_running_loop()
            for sig in (signal.SIGINT, signal.SIGTERM):
                try:
                    loop.add_signal_handler(sig, stop.set)
                except NotImplementedError:
                    pass  # e.g. Windows
            tasks = [
                asyncio.create_task(session.receive()),
                asyncio.create_task(session.pump_mic(mic_queue)),
                asyncio.create_task(session.pump_speaker()),
            ]
            waiters = set(tasks) | {asyncio.create_task(stop.wait())}
            done, pending = await asyncio.wait(waiters, return_when=asyncio.FIRST_COMPLETED)
            for t in pending:
                t.cancel()
            for t in done:
                exc = t.exception()
                if exc and not isinstance(exc, asyncio.CancelledError):
                    print(f"\n[stopped] {exc!r}")

            rx_audio.detach(frame)
    except KeyboardInterrupt:
        pass
    finally:
        try:
            if started_audio:
                await frame.send_message(STOP_LISTENING_MSG, TxCode().pack())
                await frame.send_message(STOP_PLAYBACK_MSG, TxCode().pack())
            frame.detach_print_response_handler()
            await frame.stop_frame_app()
        except Exception:
            pass
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
