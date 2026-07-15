# OpenAI Realtime (Halo)

Realtime voice conversations with the [OpenAI Realtime API](https://platform.openai.com/docs/guides/realtime) — or any OpenAI-Realtime-compatible backend — through Brilliant Labs Halo glasses. Derived from the sibling `realtime_gemini` example.

This example is **Halo-only**: it uses LC3-encoded audio over Bluetooth LE in **both** directions (16kHz mono, 32kbps, 10ms frames), rather than raw PCM.

## How it works

```
Halo mic --LC3(16k)--> phone --decode+upsample--> PCM16 24kHz --> Realtime endpoint (websocket)
Halo speaker <--LC3(16k)-- phone <--downsample+encode-- PCM16 24kHz <-- endpoint
```

- The Halo microphone encodes LC3 on-device (`frame.microphone.start{encoder='lc3', ...}`); the phone decodes it with [liblc3](https://github.com/google/liblc3) (bundled under `native/`, running in an isolate via FFI) and streams PCM to the endpoint over the Realtime websocket.
- The endpoint's PCM response audio is LC3-encoded on the phone and paced to the Halo speaker in 10ms frames over the audio BLE characteristic.
- **Audio is always 24kHz over the wire**, matching the official OpenAI Realtime API, and the sample-rate conversion is done by liblc3 itself — no separate resampler and nothing to configure. The Halo LC3 streams stay 16kHz, but `lc3_setup_decoder`/`lc3_setup_encoder` take a separate `sr_pcm_hz` (PCM-side rate) so liblc3 up-/down-samples between 16kHz and 24kHz on the fly. (A local backend that only speaks 16kHz would need to resample on its side, as huggingface/speech-to-speech does.)
- Live transcriptions of both the user's and the model's speech are shown in the app, and the model's speech is mirrored on the Halo display.

## Protocol

The client (`lib/openai_realtime.dart`) speaks the current OpenAI Realtime **GA** interface: `session.type: realtime`, nested `audio.{input,output}` config (24kHz `audio/pcm`), and `response.output_audio.delta` events. OpenAI has disabled the older beta shape, and self-hosted OpenAI-Realtime-compatible stacks such as [huggingface/speech-to-speech](https://github.com/huggingface/speech-to-speech) also speak GA — so one shape covers both.

Auth is header-based (`Authorization: Bearer …`, omitted when the key is blank), unlike Gemini's query-parameter key. Server-side VAD is enabled with `interrupt_response` (`turn_detection: {server_vad, interrupt_response}`), so the endpoint auto-commits the input buffer, auto-creates responses, and stops generating on a barge-in — emitting `input_audio_buffer.speech_started` when you start talking.

## Usage

1. **API key** — your OpenAI key (from the [OpenAI dashboard](https://platform.openai.com/api-keys)). Persisted only on-device, sent only as the `Authorization` header. Leave **blank** for a local backend that doesn't require auth.
2. **Endpoint** — the full websocket URL, including any `?model=` query parameter. Defaults to `wss://api.openai.com/v1/realtime?model=gpt-realtime`. Point it at e.g. `ws://<host>:8765/v1/realtime` for a self-hosted stack.
3. Pick a voice, optionally adjust the system instruction, then Connect and Start.
4. **Tap** the Halo button to start/stop the conversation; **double-tap** to skip the rest of a reply.

## Interruption and echo

The app is **full-duplex**: the mic streams continuously, even while a reply is playing, so you can talk over the assistant to interrupt it (barge-in). This relies on the Halo firmware's on-device **acoustic echo canceller** to strip the bone-conduction speaker's bleed out of the mic feed — otherwise the server VAD would hear the assistant's own voice and the reply would interrupt itself.

On a barge-in (`input_audio_buffer.speech_started` while a reply is playing) the client cancels the server's reply (`response.cancel`), drops the reply's trailing audio deltas, and flushes the queued playback so the assistant stops promptly (the server can't unsend audio it already streamed to us).

Two on-device switches (applied at mic start) mirror the Python sample's `--aec-off` / `--no-voice-mode`, both **on** by default:

- **Echo cancellation (AEC)** — removes the speaker bleed so the mic can stay open for barge-in. Turn off for a raw-echo control baseline.
- **Voice mode** — band-passes the AEC output to the AEC's working band so the server VAD only hears near-end speech (removes the out-of-band residual echo the VAD would otherwise trip on).

## Notes

- The model is chosen via the `?model=` query parameter in the endpoint URL (e.g. `gpt-realtime`); a local backend may ignore it.
- Audio is fixed at 24kHz over the wire (the OpenAI Realtime API rate); liblc3 upsamples the Halo's 16kHz mic to 24kHz and downsamples the 24kHz reply to 16kHz. A local backend must accept/emit 24kHz (resampling internally if it works at 16kHz, as huggingface/speech-to-speech does).
- Some backends stream the model transcript as `response.output_audio_transcript.delta`; others (e.g. huggingface/speech-to-speech) send only the final `response.output_audio_transcript.done`. The app handles both.
- If neither `session.created` nor `session.updated` arrives within ~5s (some lenient local backends don't emit them), the client proceeds anyway.
- The websocket may be closed by the server after a while; reconnect/session-resumption is not implemented.
