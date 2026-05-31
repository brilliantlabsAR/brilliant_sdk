import { BrilliantMsg, StdLua, RxAudio, TxCode, RxAudioSampleRate, RxAudioBitDepth } from 'brilliant-msg';
import frameApp from './lua/audio_clip_frame_app.lua?raw';

/**
 * Demonstrates how to record an audio clip using Frame's microphone and play it back.
 * This example utilizes the RxAudio class to receive audio data from the Frame device
 * in non-streaming mode, then converts the raw PCM data to WAV format for playback
 * using the Web Audio API.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.AudioMin, StdLua.CodeMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it
    await frame.startFrameApp();

    // hook up the RxAudio receiver as non-streaming so all the data comes in one clip
    // sample rate and bit depth should match the microphone.start call in the Lua app
    // see ./lua/audio_clip_frame_app.lua for the parameters
    const sampleRate = RxAudioSampleRate.SAMPLE_RATE_8KHZ;
    const bitDepth = RxAudioBitDepth.BIT_DEPTH_16;
    const rxAudio = new RxAudio({ streaming: false, sampleRate: sampleRate, bitDepth: bitDepth });
    const audioQueue = await rxAudio.attach(frame);

    // Tell Frame to start streaming audio
    // Assuming 0x30 is the correct message ID and new TxCode(1).pack() is the start command
    await frame.sendMessage(0x30, new TxCode({ value: 1 }).pack());

    console.log("Recording audio for 10 seconds...");
    await new Promise(resolve => setTimeout(resolve, 10000));

    // Stop the audio stream
    console.log("Stopping audio...");
    // Assuming new TxCode(0).pack() is the stop command
    await frame.sendMessage(0x30, new TxCode({ value: 0 }).pack());

    // Get the raw PCM audio data from RxAudio
    // RxAudio (non-streaming) puts the complete audio data first, then null
    const pcmData = await audioQueue.get();

    if (pcmData && pcmData.length > 0) {
      console.log("Raw PCM audio data received, length:", pcmData.length);

      // Convert the raw PCM data to WAV format
      // Default audio parameters are 8000 Hz, signed 8-bit, 1 channel.
      // If your Frame device uses different parameters, specify them here.
      // e.g., RxAudio.toWavBytes(pcmData, 16000, 16, 1) for 16kHz sample rate, signed 16-bit.
      const wavBytes = RxAudio.toWavBytes(new Uint8Array(pcmData.buffer), sampleRate, bitDepth, 1);
      console.log("WAV data created, length:", wavBytes.length);

      // Play the audio clip using the Web Audio API
      const audioContext = new (window.AudioContext || window.webkitAudioContext)({
        sampleRate: sampleRate // Set the sample rate for the AudioContext
      });

      // decodeAudioData expects an ArrayBuffer
      const audioBuffer = await audioContext.decodeAudioData(wavBytes.buffer);
      const source = audioContext.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(audioContext.destination);
      // Clean up when playback ends
      source.onended = () => {
        source.disconnect();
        audioContext.close();
      };
      source.start(0);
      console.log("Playing audio clip...");

      // Wait for the audio to finish playing before detaching or disconnecting
      // You might need a more robust way to determine when playback finishes
      await new Promise(resolve => source.onended = resolve);
      console.log("Audio playback finished.");

    } else {
      console.error("No audio data received or data is empty.");
    }

    // Consume the null terminator from the queue
    const endSignal = await audioQueue.get();
    if (endSignal !== null) {
        console.warn("Expected null terminator from audio queue after data, but received:", endSignal);
    }

    // stop the audio listener and clean up its resources
    rxAudio.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler();

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp();

  } catch (error) {
    console.error("Error in run function:", error);
  } finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      if (frame.isConnected()) {
        await frame.disconnect();
        console.log("Disconnected from Frame.");
      }
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
}