# audio_duplex_sprites

Halo-only: streams LC3 audio to the Halo speaker and LC3 microphone audio back to the phone while streaming 128x128 4bpp images to the display, and reports whether each stream keeps up.

The Flutter twin of the Python example `python/packages/brilliant_msg/examples/audio_duplex_sprites.py`; `assets/frame_app.lua` is the same file as its `lua/audio_duplex_sprites_frame_app.lua`.

## What it streams

- **Speaker**: a looped LC3 clip (8 kHz, 32 kbps, 10 ms frames of 40 bytes) written to the audio characteristic with `sendAudio()`, as many frames per write as fill whole link-layer packets, paced to stay 300 ms ahead of playback.
- **Microphone**: LC3 at 16 kHz / 32 kbps, read on the device in whole frames and sent back as `RxAudio` chunks.
- **Images**: 16 numbered 128x128 crops of `assets/koala.jpg`, quantized to 16 colours and sent back to back as the 16-row strips of one updatable `TxImageSpriteBlock`, each strip drawn as it arrives.

The device asks for a 15 ms connection interval when streaming starts and prints its speaker and microphone counters every 2 seconds:

| Field | Meaning |
|---|---|
| `spk_writes`, `spk_bytes` | speaker audio received in the window |
| `rejected` | speaker writes dropped because the 8 KB audio ring was full |
| `ring`, `peak`, `interval` | audio ring level now and at its peak (bytes); the connection interval (ms) |
| `decoded`, `plc` | LC3 frames decoded, and frames concealed because one was bad or missing |
| `silence` | speaker blocks played as silence because no audio was ready (an underrun) |
| `mic_bytes`, `images` | LC3 microphone bytes sent, and complete images drawn |

A healthy run shows `decoded` near 200, and `plc`, `silence` and `rejected` at zero, in every window except the first and last.
