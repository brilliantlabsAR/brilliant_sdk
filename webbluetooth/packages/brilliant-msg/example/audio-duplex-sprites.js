import { BrilliantMsg, StdLua, TxSprite, TxImageSpriteBlock, TxCode, RxAudio } from 'brilliant-msg';
import { BrilliantDeviceType, bleWriteSize } from 'brilliant-ble';
import frameApp from './lua/audio_duplex_sprites_frame_app.lua?raw';

// Phone to Frame flags (match the Lua app)
const IMAGE_SPRITE_BLOCK_MSG = 0x20;
const AUDIO_START_MSG = 0x40;
const AUDIO_STOP_MSG = 0x41;

// LC3 with 10 ms frames: bitrate / 800 bytes per frame (40 bytes at 32 kbps)
const FRAMES_PER_SECOND = 100;

// the speaker clip: LC3 at 8 kHz, 32 kbps, 10 ms frames
const SPEAKER_RATE = 8000;
const SPEAKER_KBPS = 32;
const SPEAKER_FRAME_BYTES = SPEAKER_KBPS * 1000 / 800;
const SPEAKER_VOLUME = 80;
// seconds of speaker audio to keep queued on the device
const SPEAKER_LEAD = 0.3;
const MIC_RATE = 16000;
const MIC_KBPS = 32;
// ask Halo to request this connection interval (ms); the host decides
const CONNECTION_INTERVAL_MS = 15;
const STRIP_HEIGHT = 16;

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

/**
 * Square crops of the koala photo, each numbered so new images are visible on the display
 */
async function makeImages(count, size = 128) {
  const response = await fetch(new URL('./images/koala.jpg', import.meta.url));
  const src = await createImageBitmap(await response.blob());
  const side = Math.min(src.width, src.height);
  const zoom = Math.floor(side * 0.8);
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');

  const blocks = [];
  for (let n = 0; n < count; n++) {
    // pan the crop a little each time so every image is different
    const x = (src.width - side) / 2 + Math.floor((side - zoom) * n / Math.max(1, count - 1));
    ctx.drawImage(src, x, (src.height - side) / 2, zoom, zoom, 0, 0, size, size);
    ctx.font = 'bold 14px sans-serif';
    ctx.fillStyle = 'rgb(255, 255, 0)';
    ctx.fillText(String(n).padStart(2, '0'), 4, 18);
    const png = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    const sprite = await TxSprite.fromImageBytes(new Uint8Array(await png.arrayBuffer()), size * size);
    blocks.push(new TxImageSpriteBlock({ image: sprite, spriteLineHeight: STRIP_HEIGHT }));
  }
  return blocks;
}

/**
 * Halo only: streams LC3 audio to the speaker and LC3 microphone audio back while
 * streaming 128x128 4bpp images to the display, and reports whether each stream keeps up.
 *
 * - Speaker: a looped LC3 clip (8 kHz, 32 kbps, 10 ms frames of 40 bytes) written to the
 *   audio characteristic with sendAudio(), as many frames per write as fill whole
 *   link-layer packets, paced to stay 300 ms ahead of playback.
 * - Microphone: LC3 at 16 kHz / 32 kbps, sent back in whole frames as RxAudio chunks.
 * - Images: 16 numbered 128x128 crops of koala.jpg, quantized to 16 colours and sent back
 *   to back as the 16-row strips of one updatable TxImageSpriteBlock.
 *
 * The device prints its speaker and microphone counters every 2 seconds: a healthy run shows
 * decoded near 200, and plc, silence and rejected at zero in every window but the first and last.
 * Streams for 30 seconds; add ?duration=120 to the page URL to stream for longer.
 */
export async function run() {
  const frame = new BrilliantMsg();
  const durationMs = (Number(new URLSearchParams(window.location.search).get('duration')) || 30) * 1000;
  let rxAudio;

  try {
    console.log("Connecting to Halo...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    if (frame.ble.type !== BrilliantDeviceType.HALO) {
      console.log('This example requires a Halo (speaker and LC3 microphone)');
      return;
    }

    const maxWrite = parseInt(await frame.ble.sendLua('print(frame.bluetooth.max_length())', { awaitPrint: true }));
    const framesPerWrite = Math.max(1, Math.floor(bleWriteSize(maxWrite) / SPEAKER_FRAME_BYTES));
    console.log(`Max write ${maxWrite} bytes | ${framesPerWrite} LC3 frames (${framesPerWrite * SPEAKER_FRAME_BYTES} bytes) per speaker write`);

    await frame.printShortText('Loading...');
    const blocks = await makeImages(16);
    const lc3Data = new Uint8Array(await (await fetch(new URL('./audio/female_w1_8k_s16.lc3', import.meta.url))).arrayBuffer());
    const lc3Frames = [];
    for (let i = 0; i + SPEAKER_FRAME_BYTES <= lc3Data.length; i += SPEAKER_FRAME_BYTES) {
      lc3Frames.push(lc3Data.subarray(i, i + SPEAKER_FRAME_BYTES));
    }

    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.ImageSpriteBlockMin]);
    await frame.uploadFrameApp(frameApp);

    // the device prints its speaker/microphone stats every 2 seconds
    frame.attachPrintResponseHandler((s) => console.log(s.startsWith('stats') ? `[halo] ${s.substring(6)}` : s));
    await frame.startFrameApp();

    // microphone: count the LC3 bytes as they arrive (8-bit chunks are one element per byte)
    rxAudio = new RxAudio({ streaming: true });
    const micQueue = await rxAudio.attach(frame);
    let micBytes = 0;
    const micDone = (async () => {
      let chunk;
      while ((chunk = await micQueue.get()) !== null) {
        micBytes += chunk.length;
      }
    })();

    await frame.sendMessage(AUDIO_START_MSG, new Uint8Array([
      SPEAKER_RATE / 1000, SPEAKER_KBPS, SPEAKER_VOLUME, MIC_RATE / 1000, MIC_KBPS, CONNECTION_INTERVAL_MS]));

    const start = performance.now();
    const running = () => performance.now() - start < durationMs;

    // speaker: keep SPEAKER_LEAD seconds queued ahead of where playback should be
    let sent = 0;
    let writes = 0;
    let minLead = SPEAKER_LEAD;
    let maxWriteGap = 0;
    let lastWrite = 0;
    const speaker = async () => {
      const leadFrames = SPEAKER_LEAD * FRAMES_PER_SECOND;
      while (running()) {
        const played = (performance.now() - start) * FRAMES_PER_SECOND / 1000;
        if (sent > 0) minLead = Math.min(minLead, (sent - played) / FRAMES_PER_SECOND);
        while (sent < played + leadFrames) {
          const chunk = new Uint8Array(framesPerWrite * SPEAKER_FRAME_BYTES);
          for (let i = 0; i < framesPerWrite; i++) {
            chunk.set(lc3Frames[(sent + i) % lc3Frames.length], i * SPEAKER_FRAME_BYTES);
          }
          await frame.ble.sendAudio(chunk);
          sent += framesPerWrite;
          writes++;
          const now = performance.now() - start;
          maxWriteGap = Math.max(maxWriteGap, now - lastWrite);
          lastWrite = now;
        }
        await sleep(10);
      }
    };

    // images: the header once, then each image's strips update the block in place
    let images = 0;
    let imageBytes = 0;
    const imageStream = async () => {
      await frame.sendMessage(IMAGE_SPRITE_BLOCK_MSG, blocks[0].pack());
      while (running()) {
        for (const strip of blocks[images % blocks.length].spriteLines) {
          const packed = strip.pack();
          await frame.sendMessage(IMAGE_SPRITE_BLOCK_MSG, packed);
          imageBytes += packed.length;
        }
        images++;
      }
    };

    await Promise.all([speaker(), imageStream()]);
    const elapsed = (performance.now() - start) / 1000;

    // let the queued speaker audio play out and the last stats print
    await sleep(SPEAKER_LEAD * 1000 + 2500);
    await frame.sendMessage(AUDIO_STOP_MSG, new TxCode({ value: 0 }).pack());
    await Promise.race([micDone, sleep(3000)]);

    console.log(`--- ${elapsed.toFixed(1)} s ---`);
    console.log(`speaker: ${sent} frames in ${writes} writes (${(sent * SPEAKER_FRAME_BYTES * 8 / elapsed / 1000).toFixed(1)} kbps), ` +
      `min lead ${Math.round(minLead * 1000)} ms, longest gap between writes ${Math.round(maxWriteGap)} ms`);
    console.log(`images: ${images} (${(images / elapsed).toFixed(2)}/s, ${Math.round(imageBytes * 8 / elapsed / 1000)} kbps)`);
    const micFrames = Math.floor(micBytes / (MIC_KBPS * 1000 / 800));
    console.log(`mic: ${micFrames} frames (${(micFrames / FRAMES_PER_SECOND).toFixed(1)} s of audio)`);
  }
  catch (error) {
    console.error("Error:", error);
    if (frame.isConnected()) {
      try { await frame.sendMessage(AUDIO_STOP_MSG, new TxCode({ value: 0 }).pack()); } catch (e) { }
    }
  }
  finally {
    if (rxAudio) rxAudio.detach(frame);
    if (frame.isConnected()) {
      frame.detachPrintResponseHandler();
      await frame.stopFrameApp();
      await frame.disconnect();
    }
  }
}
