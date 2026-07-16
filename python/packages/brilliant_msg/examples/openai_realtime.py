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

Full-duplex barge-in: you can talk over a reply to interrupt it. This leans on
the Halo firmware's on-device acoustic echo canceller to strip the bone-conduction
speaker's bleed out of the mic - otherwise the server's voice-activity detector
would hear the assistant's own voice and interrupt itself. The AEC alone is enough
for a forgiving VAD (e.g. a local Silero server), but OpenAI's server VAD is
sensitive enough to trip on the post-AEC echo residual - transcribing it as a
phantom user turn and answering it, a self-interruption spiral. So during playback
the mic is held closed to the server by a client-side RMS gate and only opened once
the near-end level confirms you are really talking (see BARGE_RMS; --barge-rms 0
disables it for full duplex). On a barge-in we also drop the rest of the current
reply and flush the queued playback so the assistant stops promptly (the server
can't cancel audio it already finished streaming to us, so the client drains it).

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
import time
from collections import deque

import lc3
import numpy as np
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

# After this long with no new reply audio (and nothing queued), treat playback
# as finished. Used INSTEAD of response.done to decide when a reply is "playing"
# for barge-in, because some backends (e.g. jarvis in server-VAD mode) never
# send response.done - keying on it would leave a reply flagged active forever,
# so every later user turn would spuriously barge (flushing 0 frames).
PLAYBACK_IDLE_S = 1.0

# How long after the device finishes playing (per the playback clock) a reply still
# counts as playing, covering on-device / in-flight buffer latency. The client sends
# audio faster than real time but the device plays it out in real time, so the
# barge-in gate must stay armed for the whole physical playout - not just while the
# client queue is non-empty - or the reply's tail leaks its echo past the gate.
PLAYBACK_TAIL_S = 0.6

# RMS barge-in gate. A sensitive server VAD (notably OpenAI's, which also runs
# transcription) can trip on the assistant's own post-AEC echo residual, transcribe
# it as a phantom user turn and answer it - a self-interruption loop. The gate is
# applied ONLY while a reply is playing: when the assistant is silent the mic streams
# straight through (normal turn-taking needs no raised voice); while it plays, the
# mic is held closed to the server until the near-end (DC-removed / AC) RMS confirms
# the wearer is talking OVER it. The bar must sit ABOVE the echo peak, not just the
# quiet floor - too low and echo both opens the gate AND keeps it from re-closing.
# Set --barge-rms 0 to disable the gate (full duplex; fine for a backend that does
# not trip on the residual). See tests/aec/README.md "server-VAD-alone A/B".
BARGE_RMS = 400.0          # AC-RMS a mic read must clear to barge OVER a live reply
BARGE_CONFIRM_FRAMES = 3   # consecutive above-threshold reads to open the mic gate
BARGE_HANGOVER_MS = 400.0  # sub-threshold audio after which the open gate re-closes

# glasses display: monospace 9pt, ~21 chars fit across the 256px width
HALO_CHARS_PER_LINE = 21


def mic_start_payload(gain: int, aec: bool, voice: bool) -> bytes:
    """START_LISTENING payload: three named bytes, one field each, decoded by
    the frame app's START_LISTENING handler:
        [0] gain code 0..20 (10 = 0 dB)   [1] aec 0/1   [2] voice 0/1
    This maps 1:1 onto frame.microphone.start{gain=}, .aec(bool), .voice(bool).
    """
    return bytes([max(0, min(20, gain)), 1 if aec else 0, 1 if voice else 0])


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


def session_update(voice: str, instructions: str,
                   vad_threshold: float = 0.6,
                   vad_silence_ms: int = None) -> dict:
    """The OpenAI Realtime GA session.update message (24 kHz PCM)."""
    turn_detection = {"type": "server_vad",
                      # interrupt_response lets the server stop generating when it
                      # detects a barge-in; the client still flushes its own queued
                      # playback (below), since the server can't cancel audio it has
                      # already streamed to us.
                      "interrupt_response": True,
                      # VAD activation threshold (default 0.5). Raising it makes the
                      # assistant's own residual echo less likely to trip the VAD -
                      # but the echo IS speech-shaped, so this scores it high and a
                      # higher threshold also costs real barges: the client RMS gate
                      # (near-end ENERGY, --barge-rms) is the sharper separator. Kept
                      # exposed (--vad-threshold) to tune or stack with the gate.
                      "threshold": vad_threshold}
    if vad_silence_ms is not None:
        turn_detection["silence_duration_ms"] = vad_silence_ms
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
                    "turn_detection": turn_detection,
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

    def __init__(self, frame: BrilliantMsg, ws, frames_per_write: int,
                 barge_rms: float = BARGE_RMS,
                 barge_confirm_frames: int = BARGE_CONFIRM_FRAMES,
                 barge_hangover_ms: float = BARGE_HANGOVER_MS):
        self.frame = frame
        self.ws = ws
        self.frames_per_write = frames_per_write

        # RMS barge-in gate (see BARGE_RMS): near-end confirmation before the mic
        # is opened to the server during playback, so the assistant's echo can't
        # be transcribed as a phantom turn and spiral. barge_rms<=0 disables it.
        self.barge_rms = barge_rms
        self.barge_confirm_frames = max(1, barge_confirm_frames)
        self.barge_hangover_ms = barge_hangover_ms
        self.gate_open = False        # currently forwarding near-end during playback
        self.gate_hot = 0             # consecutive above-threshold reads (to open)
        self.gate_peak = 0.0          # loudest read while arming (logged on open)
        self.gate_quiet_ms = 0.0      # accumulated sub-threshold audio (to close)
        self._preroll: deque = deque(maxlen=self.barge_confirm_frames)  # onset back-fill

        # liblc3 does the resampling inside the codec: coded 16 kHz Halo LC3 <->
        # 24 kHz PCM over the wire. The decoder upsamples the mic to 24 kHz; the
        # encoder downsamples the server's 24 kHz reply back to 16 kHz.
        self.decoder = lc3.Decoder(FRAME_US, HALO_RATE, 1, output_sample_rate_hz=SERVER_RATE)
        self.encoder = lc3.Encoder(FRAME_US, HALO_RATE, 1, input_sample_rate_hz=SERVER_RATE)

        self.speaker_queue: asyncio.Queue = asyncio.Queue()  # LC3 frames to play out
        self._mic_lc3_buf = bytearray()  # unaligned LC3 bytes from the mic
        self._spk_pcm_buf = bytearray()  # server PCM awaiting frame alignment
        self.last_audio_time = None  # monotonic time of the last reply audio delta
        self.play_until = 0.0  # monotonic time the device finishes playing what we sent
        self._assistant_text = ""  # accumulates the current reply transcript
        self._saw_transcript_delta = False  # did this turn stream transcript deltas?

        # barge-in state
        self.barged = False  # client has cancelled the current reply; drop its tail
        self.current_response_id = None  # id of the reply currently streaming audio
        self.cancelled_response_id = None  # id cancelled on barge; drop only its tail

    def _recent_audio(self) -> bool:
        """True if a reply is actively streaming - audio arrived within the last
        PLAYBACK_IDLE_S. Used instead of a sticky response_active flag so that a
        backend which never sends response.done can't leave a reply flagged live
        forever (which would make every later user turn spuriously barge)."""
        return (self.last_audio_time is not None
                and time.monotonic() - self.last_audio_time < PLAYBACK_IDLE_S)

    def _playback_pending(self) -> bool:
        """True while the DEVICE is still playing a reply out (not merely while the
        client still holds audio).

        Keys on the playback clock (see PLAYBACK_TAIL_S), not on when audio was
        received: the client drains its queue seconds before the device finishes
        the physical playout, so using the queue/recent-audio as "done" reopens the
        mic - gate off - mid-playout and leaks the reply's tail to the server. The
        queue check stays as a floor for the instant between enqueue and the first
        send that advances the clock.

        Deliberately does NOT consider `_spk_pcm_buf`: it holds the trailing sub-
        frame (<10 ms) that never filled a whole 480-byte block and is never
        played, so treating it as "playing" would gate every later user turn."""
        return (not self.speaker_queue.empty()
                or time.monotonic() < self.play_until + PLAYBACK_TAIL_S)

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

            if not pcm:
                continue

            await self._forward_mic(bytes(pcm))

    async def _send_mic(self, pcm: bytes):
        await self.ws.send(json.dumps({
            "type": "input_audio_buffer.append",
            "audio": base64.b64encode(pcm).decode("ascii"),
        }))

    async def _forward_mic(self, pcm: bytes):
        """Forward a mic block to the server, RMS-gated during playback.

        With the gate disabled (--barge-rms 0) or when no reply is playing, the
        mic streams straight through - normal full-duplex listening / turn-taking.
        While a reply IS playing, the mic is held closed and only opened once the
        near-end AC-RMS clears the gate for `barge_confirm_frames` consecutive
        reads, so the server never hears (and so never transcribes and answers)
        the assistant's own echo. On open we back-fill the buffered onset so the
        barge's first word isn't clipped; the gate then stays open through the
        utterance, re-closing after BARGE_HANGOVER_MS of near-silence."""
        if self.barge_rms <= 0 or not self._playback_pending():
            # gate disabled, or nothing playing: stream through; reset gate state
            self.gate_open = False
            self.gate_hot = 0
            self.gate_quiet_ms = 0.0
            self._preroll.clear()
            await self._send_mic(pcm)
            return

        samples = np.frombuffer(pcm, dtype=np.int16)
        # DC-removed (AC) RMS: echo residual is low-energy post-AEC even though it
        # is speech-shaped, so measure energy (std), not level (see BARGE_RMS).
        rms = float(np.std(samples.astype(np.float64))) if samples.size > 1 else 0.0
        dur_ms = 1000.0 * samples.size / SERVER_RATE

        if self.gate_open:
            # stay open through the utterance; close after a beat of near-silence
            if rms < self.barge_rms:
                self.gate_quiet_ms += dur_ms
            else:
                self.gate_quiet_ms = 0.0
            if self.gate_quiet_ms < self.barge_hangover_ms:
                await self._send_mic(pcm)
                return
            self.gate_open = False  # fell quiet: re-close and re-arm below
            self.gate_hot = 0
            self.gate_quiet_ms = 0.0

        # gate closed: buffer the onset and count consecutive above-threshold reads
        self._preroll.append(pcm)
        if rms >= self.barge_rms:
            self.gate_hot += 1
            self.gate_peak = max(self.gate_peak, rms)
        else:
            self.gate_hot = 0
            self.gate_peak = 0.0
        if self.gate_hot >= self.barge_confirm_frames:
            # confirmed near-end: open, back-fill the buffered onset, then stream.
            # Log the RMS that opened it: an open near the threshold (rather than
            # well above it) is echo leaking through - raise --barge-rms if so.
            print(f"[gate open] near-end rms={self.gate_peak:.0f}", flush=True)
            self.gate_open = True
            self.gate_quiet_ms = 0.0
            self.gate_hot = 0
            self.gate_peak = 0.0
            for buffered in self._preroll:
                await self._send_mic(buffered)
            self._preroll.clear()
        # else: closed + unconfirmed -> drop this block (echo-only); the server
        # never sees it, so it can't spiral

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
            # advance the playback clock: the device plays these frames out in real
            # time (10 ms each) from wherever it's currently up to, so the gate stays
            # armed for the full physical playout (see PLAYBACK_TAIL_S)
            self.play_until = max(self.play_until, time.monotonic()) + len(frames) * 0.010
            # pace slightly faster than realtime (each frame is 10 ms of audio)
            await asyncio.sleep(len(frames) * 0.009)

    def _flush_playback(self) -> int:
        """Drop all queued/partial playback; return the frame count dropped."""
        dropped = 0
        while not self.speaker_queue.empty():
            self.speaker_queue.get_nowait()
            dropped += 1
        self._spk_pcm_buf.clear()
        return dropped

    async def _client_barge_in(self):
        """The server VAD flagged near-end speech over a live reply. The server
        stops generating on its own (interrupt_response, set in the session), so
        here the client only flushes the queued playback - that is what actually
        stops the echo, since the server can't unsend audio it already streamed
        to us and up to several seconds of it may be buffered here. We latch
        `barged` (to drop the reply's trailing deltas) only if it is still
        generating; if it already completed there is no tail to drop and latching
        would wrongly mute the next reply. Tag the cancelled reply by id so only
        its tail is dropped.

        We deliberately do NOT send response.cancel: with interrupt_response the
        server has usually already cancelled the response by now, so it would
        race and error with "Cancellation failed: no active response found"."""
        live = self._recent_audio()
        self.barged = live
        self.cancelled_response_id = self.current_response_id if live else None
        dropped = self._flush_playback()
        print(f"\n[barge-in] flushed {dropped} queued frames", flush=True)

    # --- OpenAI event stream ----------------------------------------------
    async def receive(self):
        async for message in self.ws:
            event = json.loads(message)
            etype = event.get("type")

            if etype == "response.created":
                self.barged = False
                self.cancelled_response_id = None
                self.current_response_id = (event.get("response") or {}).get("id")
                self._assistant_text = ""
                self._saw_transcript_delta = False
            elif etype == "response.output_audio.delta":
                rid = event.get("response_id")
                if self.barged:
                    # drop ONLY the cancelled reply's tail; a delta from a new
                    # reply (or any delta when the backend omits ids) means the
                    # barge is over - so the latch can never get stuck silencing
                    # every future reply if response.done/created never arrive
                    if rid is not None and rid == self.cancelled_response_id:
                        continue
                    self.barged = False
                    self.cancelled_response_id = None
                # Mark the reply live off the audio stream (see _recent_audio):
                # some backends (e.g. jarvis in server-VAD mode) emit neither
                # response.created nor response.done, so a fresh audio delta is
                # the only reliable "a reply is playing" signal.
                self.current_response_id = rid
                self.last_audio_time = time.monotonic()
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
                    print(f"\nYou: {transcript}", flush=True)
            elif etype == "response.output_audio_transcript.done":
                # some backends (e.g. huggingface/speech-to-speech) send the
                # assistant transcript only here, not as deltas - render it then
                if not self._saw_transcript_delta:
                    full = (event.get("transcript") or "").strip()
                    if full:
                        print(f"Assistant: {full}", flush=True)
                        await self._show(wrap_for_halo(full))
                else:
                    print()  # newline after the streamed transcript
            elif etype == "input_audio_buffer.speech_started":
                # The server VAD heard near-end speech. If a reply is playing,
                # barge in: the on-device AEC keeps the assistant's own voice
                # out of the mic, so a speech_started here is the user talking.
                if not self.barged and self._playback_pending():
                    await self._client_barge_in()
            elif etype == "response.done":
                # (OpenAI sends this; jarvis doesn't - the barge logic no longer
                # depends on it, but honour it when present.) Clear the barge
                # latch so the NEXT reply plays; the queued playback was already
                # flushed at barge-in and the cancelled reply's tail deltas are
                # dropped by id, so there is nothing left to flush here.
                self.barged = False
                self.cancelled_response_id = None
                self.current_response_id = None
                self.last_audio_time = None
            elif etype == "error":
                err = event.get("error", {})
                print(f"\n[error] {err.get('message', err)}", flush=True)

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
    p.add_argument("--volume", type=int, default=SPEAKER_VOLUME,
                   help="Halo speaker volume 1..100 (default 100)")
    p.add_argument("--barge-rms", type=float, default=BARGE_RMS,
                   help="RMS barge-in gate: near-end AC-RMS a mic read must clear "
                        "to open the mic to the server DURING playback, so the "
                        "assistant's echo can't self-interrupt a sensitive server "
                        "VAD (default 150). 0 disables the gate (full duplex)")
    p.add_argument("--barge-confirm-frames", type=int, default=BARGE_CONFIRM_FRAMES,
                   help="consecutive above-threshold mic reads to open the gate "
                        "(debounce; higher = fewer false barges, slightly slower onset)")
    p.add_argument("--barge-hangover-ms", type=float, default=BARGE_HANGOVER_MS,
                   help="sub-threshold audio after which an open gate re-closes "
                        "(keep short so it doesn't forward echo into the next reply)")
    p.add_argument("--vad-threshold", type=float, default=0.6,
                   help="server VAD activation threshold 0..1 (default 0.6; raise "
                        "to make echo less likely to trip it - blunter than the gate)")
    p.add_argument("--vad-silence-ms", type=int, default=None,
                   help="server VAD silence_duration_ms (turn-end hangover)")
    p.add_argument("--name", default=None,
                   help="Halo device local name to connect to (e.g. \"Halo XX\"); "
                        "defaults to the first Halo found")
    p.add_argument("--no-voice-mode", dest="voice_mode", action="store_false",
                   help="disable the on-device AEC voice mode (band-pass) on the mic")
    p.add_argument("--aec-off", dest="aec", action="store_false",
                   help="disable the on-device AEC entirely (control baseline)")
    p.set_defaults(voice_mode=True, aec=True)
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
        name = await frame.connect(name=args.name)
        if frame.type != BrilliantDeviceType.HALO:
            print("This example requires a Halo (LC3 audio in both directions)")
            return

        await frame.send_break_signal()
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")
        await frame.print_short_text("Connecting...")
        await frame.upload_stdlua_libs(lib_names=["data", "code", "plain_text"])
        lua_path = os.path.join(os.path.dirname(__file__), "lua",
                                "openai_realtime_frame_app.lua")
        await frame.upload_frame_app(local_filename=lua_path)
        frame.attach_print_response_handler()
        await frame.start_frame_app()

        headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        print(f"Connecting to {args.url} ...", flush=True)
        async with connect(args.url, additional_headers=headers, max_size=None) as ws:
            await ws.send(json.dumps(session_update(
                args.voice, args.instructions,
                vad_threshold=args.vad_threshold,
                vad_silence_ms=args.vad_silence_ms)))

            frames_per_write = max(1, frame.max_lua_payload() // LC3_FRAME_BYTES)
            session = Session(frame, ws, frames_per_write,
                              barge_rms=args.barge_rms,
                              barge_confirm_frames=args.barge_confirm_frames,
                              barge_hangover_ms=args.barge_hangover_ms)

            rx_audio = RxAudio(streaming=True)
            mic_queue = await rx_audio.attach(frame)

            gate = ("off" if args.barge_rms <= 0
                    else f"rms>={args.barge_rms:.0f}x{args.barge_confirm_frames}")
            print(f"mic: gain={MIC_GAIN_VALUE - 10} aec={'on' if args.aec else 'off'} "
                  f"voice_mode={'on' if args.voice_mode else 'off'} "
                  f"volume={args.volume} barge_gate={gate} "
                  f"vad_threshold={args.vad_threshold}", flush=True)

            await frame.send_message(START_PLAYBACK_MSG, TxCode(args.volume).pack())
            await frame.send_message(
                START_LISTENING_MSG,
                mic_start_payload(MIC_GAIN_VALUE, aec=args.aec, voice=args.voice_mode))
            started_audio = True
            await session._show("Listening...")
            print("Session started - speak to the Halo. Ctrl-C to quit.\n", flush=True)

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
                    print(f"\n[stopped] {exc!r}", flush=True)

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
