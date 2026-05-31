# Examples of `brilliant-msg` npm package usage
## Background
Frame is a pair of smart glasses that communicates via Bluetooth Low Energy with a host device, and runs Lua code on its VM. Lua code is sent to Frame in the application startup sequence.
Each example contains a Javascript file and a corresponding Lua file that is copied to Frame on startup using uploadFrameApp() after the required standard Lua libs are uploaded.
The host-side Javascript program and the device-side Lua program pass messages to each other identified by a single-byte message code, so these codes must match exactly for handlers to correctly process messages.
Numerous examples follow that demonstrate many features of the Frame SDK and the corresponding host-side and device-side code.
See: https://docs.brilliant.xyz/frame/frame-sdk/

## audio clip
// JavaScript file: audio-clip.js
```javascript
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
    const bitDepth = RxAudioBitDepth.BIT_DEPTH_8;
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
```


// Corresponding Lua file: lua/audio_clip_frame_app.lua
```lua
local data = require('data.min')
local code = require('code.min')
local audio = require('audio.min')

-- Phone to Frame msg codes
AUDIO_SUBS_MSG = 0x30

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[AUDIO_SUBS_MSG] = code.parse_code

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	local streaming = false

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if (data.app_data[AUDIO_SUBS_MSG] ~= nil) then

						if data.app_data[AUDIO_SUBS_MSG].value == 1 then
							audio_data = ''
							streaming = true
							audio.start({sample_rate=8000, bit_depth=8})
							frame.display.text("\u{F0010}", 300, 1)
						else
							-- 'stop' message
							-- don't set streaming = false here, it will be set
							-- when all the audio data is flushed
							audio.stop()
							frame.display.text(" ", 1, 1)
						end

						frame.display.show()
						data.app_data[AUDIO_SUBS_MSG] = nil
					end

				end

				-- send any pending audio data back
				-- Streams until AUDIO_SUBS_MSG is sent from host with a value of 0
				if streaming then
					-- read_and_send_audio() sends one MTU worth of samples
					-- so loop up to 10 times until we have caught up or the stream has stopped
					local sent = audio.read_and_send_audio()
					for i = 1, 10 do
						if sent == nil or sent == 0 then
							break
						end
						sent = audio.read_and_send_audio()
					end
					if sent == nil then
						streaming = false
					end

					-- 8kHz/8 bit is 8000b/s, which is ~33 packets/second, or 1 every 30ms
					frame.sleep(0.001)
				else
					-- not streaming, sleep for longer
					frame.sleep(0.1)
				end
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## audio stream
// JavaScript file: audio-stream.js
```javascript
import { BrilliantMsg, StdLua, TxCode, RxAudio, RxAudioSampleRate, RxAudioBitDepth } from 'brilliant-msg';
import frameApp from './lua/audio_stream_frame_app.lua?raw';

// Define the AudioWorkletProcessor code as a string
const pcmPlayerProcessorCode = `
class PCMPlayerProcessor extends AudioWorkletProcessor {
    constructor(options) {
        super(options);
        // A simple FIFO queue for audio chunks (Float32Array)
        this._buffer = [];
        this._totalSamplesQueued = 0;
        // Buffer up to a few seconds of audio to handle network jitter, etc.
        // 8000Hz * 1 channel * 5 seconds = 40000 samples
        this._maxBufferedSamples = (sampleRate || 8000) * 5;


        this.port.onmessage = (event) => {
            if (event.data === null) { // Null can be a signal to prepare for shutdown
                // For this example, we'll just let any buffered audio play out.
                // A more sophisticated processor could handle this to stop sooner.
                return;
            }
            if (this._totalSamplesQueued + event.data.length <= this._maxBufferedSamples) {
                this._buffer.push(event.data); // event.data is a Float32Array chunk
                this._totalSamplesQueued += event.data.length;
            } else {
                console.warn('PCMPlayerProcessor: Buffer full, dropping audio data.');
            }
        };
    }

    process(inputs, outputs, parameters) {
        const output = outputs[0];
        const outputChannel = output[0]; // Assuming mono output

        let samplesWrittenThisBlock = 0;

        for (let i = 0; i < outputChannel.length; i++) {
            if (this._buffer.length > 0 && this._buffer[0].length > 0) {
                outputChannel[i] = this._buffer[0][0]; // Get sample
                this._buffer[0] = this._buffer[0].subarray(1); // "Consume" sample (inefficient for large arrays, but simple for demo)

                if (this._buffer[0].length === 0) {
                    this._buffer.shift(); // Remove empty chunk from queue
                }
                this._totalSamplesQueued--;
                samplesWrittenThisBlock++;
            } else {
                outputChannel[i] = 0; // Output silence if no data available
            }
        }
        // Return true to keep the processor alive.
        // Return false to allow it to be garbage-collected if it's silent and no more data is expected.
        return true;
    }
}
registerProcessor('pcm-player-processor', PCMPlayerProcessor);
`;

/**
 * Demonstrates streaming audio data from a Frame device and playing it in real-time.
 * This example uses the RxAudio class in streaming mode to receive audio chunks
 * (either 8-bit or 16-bit PCM). These chunks are then converted to Float32Array
 * and sent to a custom AudioWorkletProcessor for playback via the Web Audio API.
 * The stream runs for a fixed duration before automatically stopping and cleaning up.
 */
export async function run() {
    const frame = new BrilliantMsg();
    let audioContext;
    let pcmPlayerNode;
    let audioQueue; // To store the RxAudio queue
    let rxAudio; // To store the RxAudio instance
    let keepStreaming = true; // Flag to control the streaming loop

    // --- IMPORTANT AUDIO PARAMETERS ---
    // These should match the microphone.start call in the Lua app './lua/audio_frame_app.lua'
    const sampleRate = RxAudioSampleRate.SAMPLE_RATE_8KHZ;
    const bitDepth = RxAudioBitDepth.BIT_DEPTH_8;

    try {
        console.log("Connecting to Frame...");
        const deviceId = await frame.connect();
        console.log('Connected to:', deviceId);

        const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', { awaitPrint: true });
        console.log(`Battery Level/Memory used: ${battMem}`);

        await frame.printShortText('Loading...');
        await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.AudioMin, StdLua.CodeMin]);
        await frame.uploadFrameApp(frameApp);
        frame.attachPrintResponseHandler(console.log);
        await frame.startFrameApp();

        // 1. Setup Web Audio API
        audioContext = new (window.AudioContext || window.webkitAudioContext)({
            sampleRate: sampleRate // Set the sample rate for the AudioContext
        });

        // Create a Blob URL for the AudioWorklet processor
        const blob = new Blob([pcmPlayerProcessorCode], { type: 'application/javascript' });
        const processorUrl = URL.createObjectURL(blob);

        await audioContext.audioWorklet.addModule(processorUrl);
        URL.revokeObjectURL(processorUrl); // Clean up Blob URL once module is loaded

        pcmPlayerNode = new AudioWorkletNode(audioContext, 'pcm-player-processor');
        pcmPlayerNode.connect(audioContext.destination);

        // 2. Setup RxAudio for streaming
        rxAudio = new RxAudio({ streaming: true, sampleRate: sampleRate, bitDepth: bitDepth }); // Initialize in streaming mode
        audioQueue = await rxAudio.attach(frame); //

        // 3. Tell Frame to start sending audio data
        console.log("Requesting Frame to start audio stream...");
        await frame.sendMessage(0x30, new TxCode({ value: 1 }).pack()); // Start audio command

        console.log("Audio streaming started. Listening for data...");

        // 4. Asynchronous loop to get audio data and send it to the player
        const processAudioChunks = async () => {
            while (keepStreaming) {
                const chunk = await audioQueue.get(); // Get Uint8Array chunk or null

                if (chunk === null) {
                    console.log("End of audio stream signal (null chunk) received from RxAudio.");
                    keepStreaming = false; // Stop the loop
                    if (pcmPlayerNode) {
                         pcmPlayerNode.port.postMessage(null); // Optionally signal processor
                    }
                    break;
                }

                if (chunk.length > 0 && pcmPlayerNode && keepStreaming) {
                    if (chunk instanceof Int8Array) {
                        const float32Chunk = RxAudio.pcm8BitToFloat32(chunk);
                        pcmPlayerNode.port.postMessage(float32Chunk);
                    } else if (chunk instanceof Int16Array) {
                        const float32Chunk = RxAudio.pcm16BitToFloat32(chunk);
                        pcmPlayerNode.port.postMessage(float32Chunk);
                    }
                }
            }
            console.log("Audio processing loop finished.");
        };

        const audioProcessingPromise = processAudioChunks();

        // 5. Stream for a certain duration (e.g., 20 seconds for this example)
        console.log("Streaming audio to speakers for 20 seconds...");
        await new Promise(resolve => setTimeout(resolve, 20000));

        console.log("20 seconds elapsed. Stopping audio stream...");

    } catch (error) {
        console.error("Error during audio streaming:", error);
    } finally {
        keepStreaming = false; // Ensure the loop stops in case of error or normal completion

        console.log("Cleaning up resources...");

        // 6. Tell Frame to stop sending audio data
        if (frame.isConnected()) {
            try {
                console.log("Requesting Frame to stop audio stream...");
                await frame.sendMessage(0x30, new TxCode({ value: 0 }).pack()); // Stop audio command
            } catch (e) {
                console.error("Error sending stop stream command to Frame:", e);
            }
        }

        // Detach RxAudio. This should be done before closing the audio context or node.
        if (rxAudio && frame) {
            try {
                rxAudio.detach(frame); //
                console.log("RxAudio detached.");
            } catch (e) {
                console.error("Error detaching RxAudio:", e);
            }
        }

        // Disconnect and close Web Audio API resources
        if (pcmPlayerNode) {
            try {
                pcmPlayerNode.disconnect();
                console.log("AudioWorkletNode disconnected.");
            } catch (e) {
                console.error("Error disconnecting AudioWorkletNode:", e);
            }
        }
        if (audioContext && audioContext.state !== 'closed') {
            try {
                await audioContext.close();
                console.log("AudioContext closed.");
            } catch (e) {
                console.error("Error closing AudioContext:", e);
            }
        }

        // Stop the Lua app and disconnect from Frame
        if (frame.isConnected()) {
            try {
                frame.detachPrintResponseHandler();
                await frame.stopFrameApp();
                await frame.disconnect();
                console.log("Disconnected from Frame.");
            } catch (e) {
                console.error("Error during final Frame cleanup:", e);
            }
        }
        console.log("Cleanup complete.");
    }
}

```


// Corresponding Lua file: lua/audio_stream_frame_app.lua
```lua
local data = require('data.min')
local code = require('code.min')
local audio = require('audio.min')

-- Phone to Frame msg codes
AUDIO_SUBS_MSG = 0x30

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[AUDIO_SUBS_MSG] = code.parse_code

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	local streaming = false

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if (data.app_data[AUDIO_SUBS_MSG] ~= nil) then

						if data.app_data[AUDIO_SUBS_MSG].value == 1 then
							audio_data = ''
							streaming = true
							audio.start({sample_rate=8000, bit_depth=8})
							frame.display.text("\u{F0010}", 300, 1)
						else
							-- 'stop' message
							-- don't set streaming = false here, it will be set
							-- when all the audio data is flushed
							audio.stop()
							frame.display.text(" ", 1, 1)
						end

						frame.display.show()
						data.app_data[AUDIO_SUBS_MSG] = nil
					end

				end

				-- send any pending audio data back
				-- Streams until AUDIO_SUBS_MSG is sent from host with a value of 0
				if streaming then
					-- read_and_send_audio() sends one MTU worth of samples
					-- so loop up to 10 times until we have caught up or the stream has stopped
					local sent = audio.read_and_send_audio()
					for i = 1, 10 do
						if sent == nil or sent == 0 then
							break
						end
						sent = audio.read_and_send_audio()
					end
					if sent == nil then
						streaming = false
					end

					-- 8kHz/8 bit is 8000b/s, which is ~33 packets/second, or 1 every 30ms
					frame.sleep(0.001)
				else
					-- not streaming, sleep for longer
					frame.sleep(0.1)
				end
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## audio video stream
// JavaScript file: audio-video-stream.js
```javascript
import { BrilliantMsg, StdLua, TxCode, TxCaptureSettings, RxAudio, RxPhoto, RxAudioSampleRate } from 'brilliant-msg';
import frameApp from './lua/audio_video_stream_frame_app.lua?raw';

// --- AudioWorkletProcessor code as a string ---
const pcmPlayerProcessorCode = `
class PCMPlayerProcessor extends AudioWorkletProcessor {
    constructor(options) {
        super(options);
        this._buffer = [];
        this._totalSamplesQueued = 0;
        // 'sampleRate' is a global in AudioWorkletGlobalScope
        this._maxBufferedSamples = (sampleRate || 8000) * 5;

        this.port.onmessage = (event) => {
            if (event.data === null) {
                // Signal to stop processing and clear buffer
                this._buffer = [];
                this._totalSamplesQueued = 0;
                console.log('PCMPlayerProcessor: Received null, clearing buffer and stopping.');
                return;
            }
            if (this._totalSamplesQueued + event.data.length <= this._maxBufferedSamples) {
                this._buffer.push(event.data);
                this._totalSamplesQueued += event.data.length;
            } else {
                console.warn('PCMPlayerProcessor: Buffer full, dropping audio data.');
            }
        };
    }

    process(inputs, outputs, parameters) {
        const outputChannel = outputs[0][0];
        for (let i = 0; i < outputChannel.length; i++) {
            if (this._buffer.length > 0 && this._buffer[0].length > 0) {
                outputChannel[i] = this._buffer[0][0];
                this._buffer[0] = this._buffer[0].subarray(1);
                if (this._buffer[0].length === 0) {
                    this._buffer.shift();
                }
                this._totalSamplesQueued--;
            } else {
                outputChannel[i] = 0;
            }
        }
        return true;
    }
}
registerProcessor('pcm-player-processor', PCMPlayerProcessor);
`;

// --- Asynchronous Audio Processing Function ---
async function runAudioProcessing(frame, audioQueue, pcmPlayerNode, getKeepRunning, signalShutdown, rxAudio) {
    console.log('Starting audio processing loop...');
    const AUDIO_GET_TIMEOUT_MS = 5000; // Timeout for audioQueue.get() to allow periodic checks

    try {
        while (getKeepRunning()) {
            if (!frame.isConnected()) {
                if (getKeepRunning()) { // Only signal if we are supposed to be running
                    console.warn("Frame disconnected. Signaling shutdown from audio loop.");
                    signalShutdown();
                }
                break;
            }

            let audioSamples = null;
            try {
                const audioPromise = audioQueue.get();
                const timeoutPromise = new Promise(resolve => setTimeout(() => resolve('timeout'), AUDIO_GET_TIMEOUT_MS));
                const result = await Promise.race([audioPromise, timeoutPromise]);

                if (result === 'timeout') {
                    // console.debug("Audio get timed out, checking connection/keepRunning status.");
                    continue; // Loop again to check keepRunning and frame.isConnected
                }
                audioSamples = result;

            } catch (audioError) {
                if (getKeepRunning()) {
                    console.error("Error getting audio from queue:", audioError);
                }
                signalShutdown(); // Critical error, signal shutdown
                break;
            }

            if (audioSamples === null) { // Indicates queue was closed or detached
                console.log("Audio stream appears to have ended (queue returned null).");
                signalShutdown(); // Signal shutdown as audio source is gone
                break;
            }

            if (audioSamples.length > 0 && pcmPlayerNode && pcmPlayerNode.port) {
                const float32Chunk = RxAudio.pcm8BitToFloat32(audioSamples);
                pcmPlayerNode.port.postMessage(float32Chunk);
            }
        }
    } catch (error) { // Catch errors from operations like pcm8BitToFloat32 or other unexpected issues
        console.error("Unhandled error in audio processing loop:", error);
        if (getKeepRunning()) signalShutdown(); // Signal shutdown if an unexpected error occurs
    } finally {
        console.log("Audio processing loop finished.");
    }
}

// --- Asynchronous Photo Processing Function ---
async function runPhotoProcessing(frame, photoQueue, getKeepRunning, photoIntervalMs, signalShutdown, rxPhoto) {
    console.log('Starting photo processing loop...');
    let lastPhotoRequestTimeMs = 0;

    async function requestAndProcessPhoto() {
        if (!getKeepRunning() || !frame.isConnected()) return false;

        console.log("Requesting photo...");
        const captureSettings = new TxCaptureSettings({});
        try {
            await frame.sendMessage(0x0d, captureSettings.pack());
            lastPhotoRequestTimeMs = Date.now();

            console.log("Waiting for photo data...");
            const jpegBytesPromise = photoQueue.get();
            const photoTimeoutPromise = new Promise(resolve => setTimeout(() => resolve('timeout'), 10000)); // 10s timeout for photo
            const photoResult = await Promise.race([jpegBytesPromise, photoTimeoutPromise]);

            if (!getKeepRunning()) return false;

            if (photoResult === 'timeout') {
                console.warn("Photo receive timed out.");
                return true; // Continue photo loop
            }
            if (photoResult === null) { // Queue closed or detached
                console.log("Photo queue returned null (e.g., detached). Stopping photo processing for this stream.");
                // If photo stream ends, it doesn't necessarily mean we stop everything unless frame is also disconnected.
                if (rxPhoto && rxPhoto.isDetached && rxPhoto.isDetached() && !frame.isConnected()) {
                    signalShutdown();
                }
                return false; // Stop this photo loop
            }

            const jpegBytes = photoResult;
            if (jpegBytes && jpegBytes.length > 0) {
                console.log("Photo received, length:", jpegBytes.length);
                if (!imageDisplayElement) {
                    const imageDiv = document.getElementById('image1');
                    if (!imageDiv) {
                        console.error("Could not find div with id 'image1' for displaying photos.");
                        return true; // Continue loop, maybe the div will appear later or handle gracefully
                    }
                    imageDisplayElement = document.createElement('img');
                    imageDisplayElement.style.maxWidth = "100%";
                    imageDisplayElement.style.paddingTop = "5px";
                    // Clear any existing content in the div before adding the new image
                    while (imageDiv.firstChild) {
                        imageDiv.removeChild(imageDiv.firstChild);
                    }
                    imageDiv.appendChild(imageDisplayElement);
                }
                const oldUrl = imageDisplayElement.src;
                if (oldUrl && oldUrl.startsWith('blob:')) {
                    URL.revokeObjectURL(oldUrl);
                }
                imageDisplayElement.src = URL.createObjectURL(new Blob([jpegBytes], { type: 'image/jpeg' }));
            } else {
                console.warn("No photo data received or photo was empty.");
            }
            return true; // Continue photo loop
        } catch (photoError) {
            if (getKeepRunning()) {
                console.error("Error during photo capture/retrieval:", photoError);
                if (!frame.isConnected()) { // If error is due to disconnection
                    signalShutdown();
                    return false; // Stop photo loop
                }
            }
            return true; // Continue photo loop unless critical error determined above
        }
    }

    try {
        // Attempt initial photo if conditions are met
        if (getKeepRunning() && frame.isConnected()) {
            if (!await requestAndProcessPhoto()) return; // Stop if initial photo failed critically and signaled no continuation
        }

        while (getKeepRunning()) {
            const currentTimeMs = Date.now();
            // Ensure lastPhotoRequestTimeMs is initialized for the first calculation if initial request didn't run
            const timeSinceLastRequest = lastPhotoRequestTimeMs === 0 ? photoIntervalMs : (currentTimeMs - lastPhotoRequestTimeMs);
            let delay = photoIntervalMs - timeSinceLastRequest;

            if (delay <= 0) {
                if (frame.isConnected()) {
                    if (!await requestAndProcessPhoto()) break; // Stop loop if photo processing signals to stop
                } else if (getKeepRunning()) {
                    // console.debug("Photo loop: Frame disconnected, waiting for shutdown or reconnect.");
                    delay = photoIntervalMs; // Wait longer before re-checking
                } else {
                    break; // Not running anymore
                }
            }
            const waitTime = Math.max(200, delay > 0 ? delay : photoIntervalMs); // Min wait 200ms
            await new Promise(resolve => setTimeout(resolve, waitTime));
        }
    } catch (error) {
        console.error("Unhandled error in photo processing loop:", error);
        if (getKeepRunning()) signalShutdown();
    } finally {
        console.log("Photo processing loop finished.");
    }
}

// --- Main application ---
let imageDisplayElement = null; // Single image element for display

/**
 * Demonstrates simultaneously streaming audio and periodically capturing photos from a Frame device.
 * This example utilizes:
 * - `RxAudio` for receiving and processing streaming audio data.
 * - `RxPhoto` for capturing and receiving photo data.
 * - The Web Audio API with a custom `AudioWorkletProcessor` for real-time audio playback.
 * - Dynamic HTML image element updates to display the latest captured photo.
 * It also includes robust handling for starting, stopping, and cleaning up resources
 * for both audio and photo streams, including device connection and application lifecycle.
 */
export async function run() {
    const frame = new BrilliantMsg();
    let audioContext;
    let pcmPlayerNode;
    let audioQueue;
    let photoQueue;
    let rxAudio;
    let rxPhoto;
    let keepRunning = true;
    const photoIntervalMs = 5000; // Request a photo every 5 seconds
    const getKeepRunning = () => keepRunning;

    const SAMPLE_RATE = RxAudioSampleRate.SAMPLE_RATE_8KHZ; // Sample rate for audio processing
    const BIT_DEPTH = 8; // Bit depth for audio processing

    try {
        console.log("Connecting to Frame...");
        await frame.connect();
        console.log('Connected to Frame.');

        const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', { awaitPrint: true });
        console.log(`Battery Level/Memory used: ${battMem}`);

        await frame.printShortText('Loading...');
        await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CodeMin, StdLua.AudioMin, StdLua.CameraMin]);
        await frame.uploadFrameApp(frameApp);
        frame.attachPrintResponseHandler(console.log);
        await frame.startFrameApp();
        console.log("Frame app started.");

        audioContext = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: SAMPLE_RATE });
        const blob = new Blob([pcmPlayerProcessorCode], { type: 'application/javascript' });
        const processorUrl = URL.createObjectURL(blob);
        await audioContext.audioWorklet.addModule(processorUrl);
        URL.revokeObjectURL(processorUrl);

        pcmPlayerNode = new AudioWorkletNode(audioContext, 'pcm-player-processor', {
            processorOptions: { sampleRate: SAMPLE_RATE }
        });
        pcmPlayerNode.connect(audioContext.destination);

        rxAudio = new RxAudio({ streaming: true, sampleRate: SAMPLE_RATE, bitDepth: BIT_DEPTH });
        audioQueue = await rxAudio.attach(frame);

        rxPhoto = new RxPhoto({ upright: true });
        photoQueue = await rxPhoto.attach(frame);

        let shutdownPromiseResolve;
        const shutdownPromise = new Promise(resolve => { shutdownPromiseResolve = resolve; });

        const signalShutdown = () => {
            if (keepRunning) {
                console.log("Shutdown signaled.");
                keepRunning = false;
                if (pcmPlayerNode && pcmPlayerNode.port) {
                    try { pcmPlayerNode.port.postMessage(null); } catch(e) { console.warn("Error posting null to pcmPlayerNode port during shutdown signal:", e); }
                }
                if (shutdownPromiseResolve) {
                    shutdownPromiseResolve();
                }
            }
        };

        console.log("Requesting Frame to start audio stream...");
        await frame.sendMessage(0x30, new TxCode({ value: 1 }).pack());

        // Start asynchronous processing loops
        const audioProcessingPromise = runAudioProcessing(frame, audioQueue, pcmPlayerNode, getKeepRunning, signalShutdown, rxAudio);
        const photoProcessingPromise = runPhotoProcessing(frame, photoQueue, getKeepRunning, photoIntervalMs, signalShutdown, rxPhoto);

        // Catch unhandled promise rejections from the processing loops to ensure shutdown is triggered
        audioProcessingPromise.catch(error => {
            console.error("Critical error in audio processing:", error);
            signalShutdown();
        });
        photoProcessingPromise.catch(error => {
            console.error("Critical error in photo processing:", error);
            // Decide if photo errors are critical enough to stop everything.
            // For now, let's assume they are if they escape the loop's own handling.
            signalShutdown();
        });

        console.log('Audio and photo processing initiated. Waiting for shutdown signal...');

        // Let it run for 20 seconds or until shutdown is otherwise signaled
        await new Promise(resolve => setTimeout(resolve, 20000));

        console.log("Requesting Frame to stop audio stream...");
        await frame.sendMessage(0x30, new TxCode({ value: 0 }).pack());

        await shutdownPromise; // Wait until shutdown is signaled

    } catch (error) {
        console.error("An error occurred in the main application flow:", error);
        // Ensure shutdown is signaled if an error occurs in the main setup/try block
        if (keepRunning) { // Check if shutdown wasn't already signaled
            keepRunning = false; // Set flag
            if (pcmPlayerNode && pcmPlayerNode.port) {
                 try { pcmPlayerNode.port.postMessage(null); } catch(e) { console.warn("Error posting null to pcmPlayerNode port during main error:", e); }
            }
            // If shutdownPromiseResolve is defined, resolve it.
            // This path might be hit if error occurs before shutdownPromiseResolve is assigned or if signalShutdown wasn't called.
        }
    } finally {
        console.log("Cleaning up resources...");
        // Ensure keepRunning is false so loops know to stop.
        if (keepRunning) {
            keepRunning = false;
            if (pcmPlayerNode && pcmPlayerNode.port) {
                try { pcmPlayerNode.port.postMessage(null); } catch(e) { console.warn("Error posting null to pcmPlayerNode port in finally:", e); }
            }
        }

        if (frame && frame.isConnected()) {
            try {
                console.log("Requesting Frame to stop audio stream...");
                await frame.sendMessage(0x30, new TxCode({ value: 0 }).pack());
            } catch (e) {
                console.error("Error sending stop audio command to Frame:", e);
            }
        }

        if (rxAudio && frame && frame.isConnected()) { // Check frame & isConnected before detach
            try {
                rxAudio.detach(frame);
                console.log("RxAudio detached.");
            } catch (e) {
                console.error("Error detaching RxAudio:", e);
            }
        } else if (rxAudio) {
             console.log("RxAudio: Frame not connected, skipping detach.");
        }

        if (rxPhoto && frame && frame.isConnected()) { // Check frame & isConnected
            try {
                rxPhoto.detach(frame);
                console.log("RxPhoto detached.");
            } catch (e) {
                console.error("Error detaching RxPhoto:", e);
            }
        } else if (rxPhoto) {
            console.log("RxPhoto: Frame not connected, skipping detach.");
        }

        if (pcmPlayerNode) {
            try {
                pcmPlayerNode.disconnect(); // Disconnect from AudioContext destination
                console.log("AudioWorkletNode disconnected.");
            } catch (e) { console.warn("Error disconnecting AudioWorkletNode:", e); }
        }
        if (audioContext && audioContext.state !== 'closed') {
            try {
                await audioContext.close();
                console.log("AudioContext closed.");
            } catch (e) { console.warn("Error closing AudioContext:", e); }
        }

        if (frame) { // Check if frame object exists
            if (frame.isConnected()) {
                try {
                    frame.detachPrintResponseHandler();
                    await frame.stopFrameApp();
                    console.log("Frame app stopped.");
                } catch (e) {
                    console.error("Error stopping Frame app:", e);
                }
                try {
                    await frame.disconnect();
                    console.log("Disconnected from Frame.");
                } catch (e) {
                    console.error("Error disconnecting from Frame:", e);
                }
            } else {
                console.log("Frame not connected, skipping app stop and disconnect calls.");
            }
        }
        if (imageDisplayElement && imageDisplayElement.src.startsWith('blob:')) {
             URL.revokeObjectURL(imageDisplayElement.src); // Clean up last blob URL
        }
        console.log("Cleanup complete.");
    }
}

```


// Corresponding Lua file: lua/audio_video_stream_frame_app.lua
```lua
local data = require('data.min')
local code = require('code.min')
local audio = require('audio.min')
local camera = require('camera.min')

-- Phone to Frame msg codes
AUDIO_SUBS_MSG = 0x30
CAPTURE_SETTINGS_MSG = 0x0d

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[AUDIO_SUBS_MSG] = code.parse_code
data.parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

function show_flash()
    frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
    frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	local streaming = false
	local last_auto_exp_time = 0

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if (data.app_data[AUDIO_SUBS_MSG] ~= nil) then

						if data.app_data[AUDIO_SUBS_MSG].value == 1 then
							audio_data = ''
							streaming = true
							audio.start({sample_rate=8000, bit_depth=8})
							frame.display.text("\u{F0010}", 300, 1)
						else
							-- don't set streaming = false here, it will be set
							-- when all the audio data is flushed
							audio.stop()
							frame.display.text(" ", 1, 1)
						end

						frame.display.show()
						data.app_data[AUDIO_SUBS_MSG] = nil
					end

					if (data.app_data[CAPTURE_SETTINGS_MSG] ~= nil) then
						-- visual indicator of capture and send
						show_flash()
						rc, err = pcall(camera.capture_and_send, data.app_data[CAPTURE_SETTINGS_MSG])
						clear_display()

						if rc == false then
							print(err)
						end

						data.app_data[CAPTURE_SETTINGS_MSG] = nil
					end

				end

				-- send any pending audio data back
				-- Streams until AUDIO_SUBS_MSG is sent from host with a value of 0
				if streaming then
					sent = audio.read_and_send_audio()

					if (sent == nil) then
						streaming = false
					end

					-- 8kHz/8 bit is 8000b/s, which is 33 packets/second, or 1 every 30ms
					frame.sleep(0.001)
				else
					-- not streaming, sleep for longer
					frame.sleep(0.1)
				end

				-- run the autoexposure loop every 100ms
				if camera.is_auto_exp then
					local t = frame.time.utc()
					if (t - last_auto_exp_time) > 0.1 then
						camera.run_auto_exposure()
						last_auto_exp_time = t
					end
				end

			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## auto exposure
// JavaScript file: auto-exposure.js
```javascript
import { BrilliantMsg, StdLua, TxCaptureSettings, TxAutoExpSettings, RxPhoto, RxAutoExpResult, TxCode } from 'brilliant-msg';
import frameApp from './lua/auto_exposure_frame_app.lua?raw';

/**
 * Demonstrates taking a sequence of photos using the Frame camera with custom auto exposure settings.
 * This example showcases:
 * - Setting initial auto exposure parameters using `TxAutoExpSettings`.
 * - Receiving detailed auto exposure algorithm outputs via `RxAutoExpResult`.
 * - Iteratively triggering single steps of the auto exposure algorithm on the Frame device.
 * - Capturing photos after each step using `TxCaptureSettings` to request the image and `RxPhoto` to receive it.
 * - Displaying the captured photos on a web page.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin, StdLua.CodeMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxPhoto receiver
    const rxPhoto = new RxPhoto();
    const photoQueue = await rxPhoto.attach(frame);

    // hook up the RxAutoExpResult receiver
    const rxAutoExpResult = new RxAutoExpResult();
    const autoExpQueue = await rxAutoExpResult.attach(frame);

    // take the default auto exposure settings
    // and send them to Frame before iterating over the auto exposure steps
    await frame.sendMessage(0x0e, new TxAutoExpSettings({}).pack());

    // create the element to display the photo
    const img = document.createElement('img');
    const imageDiv = document.getElementById('image1');
    if (imageDiv) {
      // Clear any existing content in the div
      while (imageDiv.firstChild) {
        imageDiv.removeChild(imageDiv.firstChild);
      }
      imageDiv.appendChild(img);
    }

    // Iterate 20 times
    for (let i = 0; i < 20; i++) {
      // send the code to trigger the single step of the auto exposure algorithm
      await frame.sendMessage(0x0f, new TxCode({}).pack());

      // receive the auto exposure output from Frame
      const autoExpResult = await autoExpQueue.get();
      console.log("Auto exposure result received:", autoExpResult);

      // NOTE: it takes up to 200ms for exposure settings to take effect
      await new Promise(resolve => setTimeout(resolve, 200));

      // Request the photo by sending a TxCaptureSettings message
      await frame.sendMessage(0x0d, new TxCaptureSettings({}).pack());

      // get the jpeg bytes as soon as they're ready
      const jpegBytes = await photoQueue.get();
      console.log("Photo received, length:", jpegBytes.length);

      // display the image on the web page
      img.src = URL.createObjectURL(new Blob([jpegBytes], { type: 'image/jpeg' }));
    }

    // stop the photo listener and clean up its resources
    rxPhoto.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/auto_exposure_frame_app.lua
```lua
local data = require('data.min')
local camera = require('camera.min')
local code = require('code.min')

-- Phone to Frame msg codes
CAPTURE_SETTINGS_MSG = 0x0d
AUTOEXP_SETTINGS_MSG = 0x0e
AUTOEXP_STEP_MSG = 0x0f

-- register the message parser so it's automatically called when matching data comes in
data.parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings
data.parsers[AUTOEXP_SETTINGS_MSG] = camera.parse_auto_exp_settings
data.parsers[AUTOEXP_STEP_MSG] = code.parse_code

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

function show_flash()
    frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
    frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	clear_display()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
				local items_ready = data.process_raw_items()

				if items_ready > 0 then

					if (data.app_data[CAPTURE_SETTINGS_MSG] ~= nil) then
						-- visual indicator of capture and send
						show_flash()
						rc, err = pcall(camera.capture_and_send, data.app_data[CAPTURE_SETTINGS_MSG])
						clear_display()

						if rc == false then
							print(err)
						end

						data.app_data[CAPTURE_SETTINGS_MSG] = nil
					end

					if (data.app_data[AUTOEXP_SETTINGS_MSG] ~= nil) then
						camera.set_auto_exp_settings(data.app_data[AUTOEXP_SETTINGS_MSG])
						data.app_data[AUTOEXP_SETTINGS_MSG] = nil
					end

					if (data.app_data[AUTOEXP_STEP_MSG] ~= nil) then
						-- run one step of the autoexposure algorithm
						autoexp_result = camera.run_auto_exposure()
						-- also send back the table of values
						camera.send_autoexp_result(autoexp_result)

						-- TODO hack: reset r/g/b gains to low levels
						-- in their original proportions: 1.9:1:2.2 (*64)
						-- frame.camera.write_register(0x5180, 0x00)
						-- frame.camera.write_register(0x5181, 0x79)
						-- frame.camera.write_register(0x5182, 0x00)
						-- frame.camera.write_register(0x5183, 0x40)
						-- frame.camera.write_register(0x5184, 0x00)
						-- frame.camera.write_register(0x5185, 0x8C)

						data.app_data[AUTOEXP_STEP_MSG] = nil
					end

				end

				frame.sleep(0.1)
			end
		)
		-- Catch the break signal here and clean up the display
		if rc == false then
			-- send the error back on the stdout stream
			print(err)
			frame.display.text(" ", 1, 1)
			frame.display.show()
			frame.sleep(0.04)
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## camera
// JavaScript file: camera.js
```javascript
import { BrilliantMsg, StdLua, TxCaptureSettings, RxPhoto } from 'brilliant-msg';
import frameApp from './lua/camera_frame_app.lua?raw';

/**
 * Demonstrates how to take a photo using the Frame camera and display it on a webpage.
 * This example involves:
 * - Sending `TxCaptureSettings` to the Frame device to request a photo.
 * - Using `RxPhoto` to receive the JPEG image data from the Frame.
 * - Displaying the captured photo within an HTML image element on the webpage.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxPhoto receiver
    const rxPhoto = new RxPhoto();
    const photoQueue = await rxPhoto.attach(frame);

    // give Frame some time for the autoexposure to settle
    console.log("Waiting 2s for autoexposure to settle...");
    await new Promise(resolve => setTimeout(resolve, 2000));
    console.log("Taking photo...");

    // Request the photo by sending a TxCaptureSettings message
    await frame.sendMessage(0x0d, new TxCaptureSettings({}).pack());

    // get the jpeg bytes as soon as they're ready
    const jpegBytes = await photoQueue.get();
    console.log("Photo received, length:", jpegBytes.length);

    // display the image on the web page
    const img = document.createElement('img');
    img.src = URL.createObjectURL(new Blob([jpegBytes], { type: 'image/jpeg' }));
    const imageDiv = document.getElementById('image1');
    if (imageDiv) {
      // Clear any existing content in the div
      while (imageDiv.firstChild) {
        imageDiv.removeChild(imageDiv.firstChild);
      }
      imageDiv.appendChild(img);
    }

    // stop the photo listener and clean up its resources
    rxPhoto.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/camera_frame_app.lua
```lua
local data = require('data.min')
local camera = require('camera.min')

-- Phone to Frame msg codes
CAPTURE_SETTINGS_MSG = 0x0d

-- register the message parser so it's automatically called when matching data comes in
data.parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

function show_flash()
    frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
    frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	clear_display()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
				local items_ready = data.process_raw_items()

				if items_ready > 0 then

					if (data.app_data[CAPTURE_SETTINGS_MSG] ~= nil) then
						-- visual indicator of capture and send
						show_flash()
						rc, err = pcall(camera.capture_and_send, data.app_data[CAPTURE_SETTINGS_MSG])
						clear_display()

						if rc == false then
							print(err)
						end

						data.app_data[CAPTURE_SETTINGS_MSG] = nil
					end

				end

				if camera.is_auto_exp then
					camera.run_auto_exposure()
				end

				frame.sleep(0.1)
			end
		)
		-- Catch the break signal here and clean up the display
		if rc == false then
			-- send the error back on the stdout stream
			print(err)
			frame.display.text(" ", 1, 1)
			frame.display.show()
			frame.sleep(0.04)
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## camera sprite
// JavaScript file: camera-sprite.js
```javascript
import { BrilliantMsg, StdLua, TxCaptureSettings, RxPhoto, TxSprite, TxImageSpriteBlock } from 'brilliant-msg';
import frameApp from './lua/camera_sprite_frame_app.lua?raw';

/**
 * Creates or updates an <img> element within a specified div to display a JPEG image.
 * @param {Uint8Array} imageBytes - The byte array of the JPEG image.
 * @param {string} mimeType - The mime type of the image bytes, e.g. 'image/jpeg'.
 * @param {string} divId - The ID of the div element to display the image in.
 */
function displayImage(imageBytes, mimeType, divId) {
  const img = document.createElement('img');
  img.src = URL.createObjectURL(new Blob([imageBytes], { type: mimeType }));
  const imageDiv = document.getElementById(divId);
  if (imageDiv) {
    imageDiv.innerHTML = ''; // Clear any existing content
    imageDiv.appendChild(img);
  }
}

/**
 * Demonstrates a round-trip image manipulation workflow with a Frame device.
 * This example involves:
 * 1. Capturing a photo from the Frame camera using `TxCaptureSettings` to initiate and `RxPhoto` to receive the image data.
 * 2. Displaying this original photo on the webpage.
 * 3. Converting the received JPEG photo into a `TxSprite` using `TxSprite.fromImageBytes`, which involves resizing and color quantization.
 * 4. Displaying the generated sprite (as a PNG) on the webpage for comparison.
 * 5. Creating a `TxImageSpriteBlock` from this `TxSprite`, which splits the sprite into smaller, transmittable lines.
 * 6. Sending this `TxImageSpriteBlock` (header first, then each sprite line) back to the Frame device for display on its screen.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin, StdLua.ImageSpriteBlockMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxPhoto receiver
    const rxPhoto = new RxPhoto();
    const photoQueue = await rxPhoto.attach(frame);

    // give Frame some time for the autoexposure to settle
    console.log("Waiting 2s for autoexposure to settle...");
    await new Promise(resolve => setTimeout(resolve, 2000));
    console.log("Taking photo...");

    // Request the photo by sending a TxCaptureSettings message
    await frame.sendMessage(0x0d, new TxCaptureSettings({}).pack());

    // get the jpeg bytes as soon as they're ready
    const jpegBytes = await photoQueue.get();
    console.log("Photo received, length:", jpegBytes.length);

    // display the source image on the web page
    displayImage(jpegBytes, 'image/jpeg', 'image1');

    // send the photo back to Frame as a sprite block
    console.log("Sending sprite back to Frame for display...");
    const sprite = await TxSprite.fromImageBytes(jpegBytes);

    // display the sprite on the web page
    displayImage(sprite.toPngBytes(), 'image/png', 'image2');

    const isb = new TxImageSpriteBlock({ image: sprite, spriteLineHeight: 20 });
    // send the Image Sprite Block header
    await frame.sendMessage(0x20, isb.pack());

    // then send all the slices
    for (const spr of isb.spriteLines) {
      await frame.sendMessage(0x20, spr.pack());
    }

    // sleep for 20 seconds to allow the user to see the image
    console.log("Displaying sprite for 20 seconds...");
    await new Promise(resolve => setTimeout(resolve, 20000));

    // stop the photo listener and clean up its resources
    rxPhoto.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/camera_sprite_frame_app.lua
```lua
local data = require('data.min')
local camera = require('camera.min')
local image_sprite_block = require('image_sprite_block.min')

-- Phone to Frame msg codes
CAPTURE_SETTINGS_MSG = 0x0d
IMAGE_SPRITE_BLOCK = 0x20

-- register the message parser so it's automatically called when matching data comes in
data.parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings
data.parsers[IMAGE_SPRITE_BLOCK] = image_sprite_block.parse_image_sprite_block

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

function show_flash()
    frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
    frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	clear_display()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
				local items_ready = data.process_raw_items()

				if items_ready > 0 then

					if (data.app_data[CAPTURE_SETTINGS_MSG] ~= nil) then
						show_flash()
						rc, err = pcall(camera.capture_and_send, data.app_data[CAPTURE_SETTINGS_MSG])
						clear_display()

						if rc == false then
							print(err)
						end

						data.app_data[CAPTURE_SETTINGS_MSG] = nil
					end

					if (data.app_data[IMAGE_SPRITE_BLOCK] ~= nil) then
						-- show the image sprite block
						local isb = data.app_data[IMAGE_SPRITE_BLOCK]

						-- it can be that we haven't got any sprites yet, so only proceed if we have a sprite
						if isb.current_sprite_index > 0 then
							-- either we have all the sprites, or we want to do progressive/incremental rendering
							if isb.progressive_render or (isb.active_sprites == isb.total_sprites) then

								for index = 1, isb.active_sprites do
										local spr = isb.sprites[index]
										local y_offset = isb.sprite_line_height * (index - 1)

										-- set the palette the first time, all the sprites should have the same palette
										if index == 1 then
												image_sprite_block.set_palette(spr.num_colors, spr.palette_data)
										end

										frame.display.bitmap(1, y_offset + 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
								end

								frame.display.show()
							end
						end
					end

				end

				if camera.is_auto_exp then
					camera.run_auto_exposure()
				end

				frame.sleep(0.1)
			end
		)
		-- Catch the break signal here and clean up the display
		if rc == false then
			-- send the error back on the stdout stream
			print(err)
			frame.display.text(" ", 1, 1)
			frame.display.show()
			frame.sleep(0.04)
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## code value
// JavaScript file: code-value.js
```javascript
import { BrilliantMsg, StdLua, TxCode } from 'brilliant-msg';
import frameApp from './lua/code_value_frame_app.lua?raw';

/**
 * Demonstrates sending a sequence of `TxCode` messages to a Frame device.
 * Each `TxCode` message carries a single-byte value, which is iteratively updated.
 * The corresponding Frame Lua application (`code_value_frame_app.lua`) is expected
 * to receive these messages and print the contained value to its standard output.
 * This example showcases a basic control message pattern.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CodeMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // iterate 10 times and sleep for 1 second between each iteration
    for (let i = 1; i <= 10; i++) {
      await frame.sendMessage(0x42, new TxCode({ value: i }).pack());
      await new Promise(resolve => setTimeout(resolve, 1000));
    }

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/code_value_frame_app.lua
```lua
local data = require('data.min')
local code = require('code.min')

-- Phone to Frame msg codes
USER_CODE_MSG = 0x42

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[USER_CODE_MSG] = code.parse_code

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if data.app_data[USER_CODE_MSG] ~= nil then
						local code = data.app_data[USER_CODE_MSG]
						frame.display.text('Code received: ' .. tostring(code.value), 1, 1)
						frame.display.show()

						-- clear the object and run the garbage collector right away
						data.app_data[USER_CODE_MSG] = nil
						collectgarbage('collect')
					end

				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## imu stream
// JavaScript file: imu-stream.js
```javascript
import { BrilliantMsg, StdLua, TxCode, RxIMU } from 'brilliant-msg';
import frameApp from './lua/imu_stream_frame_app.lua?raw';

/**
 * Demonstrates streaming Inertial Measurement Unit (IMU) data from a Frame device.
 * This example involves:
 * - Sending `TxCode` messages to start and stop the IMU data stream on the Frame device.
 * - Using `RxIMU` to receive IMU data, which includes compass and accelerometer readings.
 * - Calculating pitch and roll from the accelerometer data.
 * - Displaying the raw compass, accelerometer, and calculated pitch/roll values on the webpage.
 * - Printing the received IMU data objects to the console.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.IMUMin, StdLua.CodeMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxIMU receiver
    const rxIMU = new RxIMU({smoothingSamples: 5});
    const imuQueue = await rxIMU.attach(frame);

    // Start the IMU updates
    console.log("Starting IMU stream...");
    await frame.sendMessage(0x40, new TxCode({ value: 1 }).pack());

    // find the element to display the IMU data
    const imuDataDiv = document.getElementById('text1');
    if (imuDataDiv) {
      // Clear any existing content in the div
      while (imuDataDiv.firstChild) {
        imuDataDiv.removeChild(imuDataDiv.firstChild);
      }
    }

    // loop 100 times - await for the IMU data to be received then print it to the console
    for (let i = 0; i < 100; i++) {
      const imuData = await imuQueue.get();
      console.log("IMU Data:", imuData);

      // Update the display element with the IMU data
      // breaking out the smoothed compass and accel arrays of 3 ints
      // and also the pitch and roll angles
      imuDataDiv.innerHTML = `
        <div>IMU Data:</div>
        <div>Compass: ${imuData.compass.join(', ')}</div>
        <div>Accelerometer: ${imuData.accel.join(', ')}</div>
        <div>Pitch: ${imuData.pitch.toFixed(2)}</div>
        <div>Roll: ${imuData.roll.toFixed(2)}</div>
      `;
    }

    console.log("Stopping IMU stream...");
    await frame.sendMessage(0x40, new TxCode({ value: 0 }).pack());

    // stop the listener and clean up its resources
    rxIMU.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/imu_stream_frame_app.lua
```lua
local data = require('data.min')
local code = require('code.min')
local imu = require('imu.min')

-- Phone to Frame msg codes
IMU_SUBS_MSG = 0x40

-- Frame to Phone msg codes
IMU_DATA_MSG = 0x0A

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[IMU_SUBS_MSG] = code.parse_code

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	local streaming = false

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

                    if (data.app_data[IMU_SUBS_MSG] ~= nil) then

                        if data.app_data[IMU_SUBS_MSG].value == 1 then
                            -- start subscription to IMU
                            streaming = true
							frame.display.text('Streaming IMU', 1, 1)
							frame.display.show()
                        else
                            -- cancel subscription to IMU
                            streaming = false
							frame.display.text('Not streaming IMU', 1, 1)
							frame.display.show()
                        end

                        data.app_data[IMU_SUBS_MSG] = nil
                    end

				end

				-- poll and send the raw IMU data (3-axis magnetometer, 3-axis accelerometer)
				-- Streams until STOP_IMU_MSG is sent from host
				if streaming then
					imu.send_imu_data(IMU_DATA_MSG)
				end

				frame.sleep(0.2)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## live camera feed
// JavaScript file: live-camera-feed.js
```javascript
import { BrilliantMsg, StdLua, TxCaptureSettings, RxPhoto } from 'brilliant-msg';
import frameApp from './lua/live_camera_feed_frame_app.lua?raw';

/**
 * Demonstrates capturing a sequence of photos from the Frame camera and displaying them
 * on a webpage to create a live feed effect.
 * This example involves:
 * - Iteratively requesting photos from the Frame device using `TxCaptureSettings`.
 * - Receiving the JPEG image data via `RxPhoto`.
 * - Displaying each newly captured photo in an HTML image element, replacing the previous one.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxPhoto receiver
    const rxPhoto = new RxPhoto();
    const photoQueue = await rxPhoto.attach(frame);

    // create the element to display the photo
    const img = document.createElement('img');
    const imageDiv = document.getElementById('image1');
    if (imageDiv) {
      // Clear any existing content in the div
      while (imageDiv.firstChild) {
        imageDiv.removeChild(imageDiv.firstChild);
      }
      imageDiv.appendChild(img);
    }

    // loop 20 times - take a photo and display it in the div
    for (let i = 0; i < 20; i++) {
      // Request the photo by sending a TxCaptureSettings message
      await frame.sendMessage(0x0d, new TxCaptureSettings({}).pack());

      // get the jpeg bytes as soon as they're ready
      const jpegBytes = await photoQueue.get();
      console.log("Photo received, length:", jpegBytes.length);

      // display the image on the web page
      // overwriting the previous image
      img.src = URL.createObjectURL(new Blob([jpegBytes], { type: 'image/jpeg' }));
    }

    // stop the photo listener and clean up its resources
    rxPhoto.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/live_camera_feed_frame_app.lua
```lua
local data = require('data.min')
local camera = require('camera.min')

-- Phone to Frame msg codes
CAPTURE_SETTINGS_MSG = 0x0d

-- register the message parser so it's automatically called when matching data comes in
data.parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

function show_flash()
    frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
    frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	clear_display()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
				local items_ready = data.process_raw_items()

				if items_ready > 0 then

					if (data.app_data[CAPTURE_SETTINGS_MSG] ~= nil) then
						-- visual indicator of capture and send
						show_flash()
						rc, err = pcall(camera.capture_and_send, data.app_data[CAPTURE_SETTINGS_MSG])
						clear_display()

						if rc == false then
							print(err)
						end

						data.app_data[CAPTURE_SETTINGS_MSG] = nil
					end

				end

				if camera.is_auto_exp then
					camera.run_auto_exposure()
				end

				frame.sleep(0.1)
			end
		)
		-- Catch the break signal here and clean up the display
		if rc == false then
			-- send the error back on the stdout stream
			print(err)
			frame.display.text(" ", 1, 1)
			frame.display.show()
			frame.sleep(0.04)
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## manual exposure
// JavaScript file: manual-exposure.js
```javascript
import { BrilliantMsg, StdLua, TxCaptureSettings, TxManualExpSettings, RxPhoto } from 'brilliant-msg';
import frameApp from './lua/manual_exposure_frame_app.lua?raw';

/**
 * Demonstrates taking a photo using the Frame camera with specific manual exposure settings.
 * This example involves:
 * - Sending `TxManualExpSettings` to the Frame device to configure parameters like shutter speed and gain.
 * - Sending `TxCaptureSettings` to request the photo capture.
 * - Using `RxPhoto` to receive the JPEG image data from the Frame.
 * - Displaying the captured photo within an HTML image element on the webpage.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin, StdLua.CodeMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxPhoto receiver
    const rxPhoto = new RxPhoto();
    const photoQueue = await rxPhoto.attach(frame);

    // take the default manual exposure settings
    // and send them to Frame before taking the photo
    await frame.sendMessage(0x0c, new TxManualExpSettings({}).pack());

    // NOTE: it takes up to 200ms for manual camera settings to take effect!
    console.log("Waiting 200ms for manual exposure settings to take effect...");
    await new Promise(resolve => setTimeout(resolve, 200));

    // Request the photo by sending a TxCaptureSettings message
    await frame.sendMessage(0x0d, new TxCaptureSettings({}).pack());

    // get the jpeg bytes as soon as they're ready
    const jpegBytes = await photoQueue.get();
    console.log("Photo received, length:", jpegBytes.length);

    // display the image on the web page
    const img = document.createElement('img');
    img.src = URL.createObjectURL(new Blob([jpegBytes], { type: 'image/jpeg' }));
    const imageDiv = document.getElementById('image1');
    if (imageDiv) {
      // Clear any existing content in the div
      while (imageDiv.firstChild) {
        imageDiv.removeChild(imageDiv.firstChild);
      }
      imageDiv.appendChild(img);
    }

    // stop the photo listener and clean up its resources
    rxPhoto.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/manual_exposure_frame_app.lua
```lua
local data = require('data.min')
local camera = require('camera.min')
local code = require('code.min')

-- Phone to Frame msg codes
CAPTURE_SETTINGS_MSG = 0x0d
MANUALEXP_SETTINGS_MSG = 0x0c

-- register the message parser so it's automatically called when matching data comes in
data.parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings
data.parsers[MANUALEXP_SETTINGS_MSG] = camera.parse_manual_exp_settings

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

function show_flash()
    frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
    frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	clear_display()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
				local items_ready = data.process_raw_items()

				if items_ready > 0 then

					if (data.app_data[CAPTURE_SETTINGS_MSG] ~= nil) then
						-- visual indicator of capture and send
						show_flash()
						rc, err = pcall(camera.capture_and_send, data.app_data[CAPTURE_SETTINGS_MSG])
						clear_display()

						if rc == false then
							print(err)
						end

						data.app_data[CAPTURE_SETTINGS_MSG] = nil
					end

					if (data.app_data[MANUALEXP_SETTINGS_MSG] ~= nil) then
						camera.set_manual_exp_settings(data.app_data[MANUALEXP_SETTINGS_MSG])
						data.app_data[MANUALEXP_SETTINGS_MSG] = nil
					end

				end

				frame.sleep(0.1)
			end
		)
		-- Catch the break signal here and clean up the display
		if rc == false then
			-- send the error back on the stdout stream
			print(err)
			frame.display.text(" ", 1, 1)
			frame.display.show()
			frame.sleep(0.04)
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## metering data
// JavaScript file: metering-data.js
```javascript
import { BrilliantMsg, StdLua, TxCode, RxMeteringData } from 'brilliant-msg';
import frameApp from './lua/metering_data_frame_app.lua?raw';

/**
 * Demonstrates requesting and displaying a sequence of light metering updates from Frame's camera.
 * This example involves:
 * - Sending `TxCode` messages to the Frame device to trigger light metering updates.
 * - Using `RxMeteringData` to receive the metering data, which includes spot and matrix RGB values.
 * - Displaying the received metering data (spot R,G,B and matrix R,G,B) on the webpage.
 * - Printing the raw metering data objects to the console.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin, StdLua.CodeMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxMeteringData receiver
    const rxMeteringData = new RxMeteringData();
    const meteringDataQueue = await rxMeteringData.attach(frame);

    // find the element to display the metering data
    const meteringDataDiv = document.getElementById('text1');
    if (meteringDataDiv) {
      // Clear any existing content in the div
      while (meteringDataDiv.firstChild) {
        meteringDataDiv.removeChild(meteringDataDiv.firstChild);
      }
    }

    // loop 60 times - await for the metering data to be received then print it to the console
    for (let i = 0; i < 60; i++) {
      await frame.sendMessage(0x12, new TxCode({ value: 1 }).pack());
      const data = await meteringDataQueue.get();
      console.log("Metering Data:", data);

      // Update the display element with the metering data
      meteringDataDiv.innerHTML = `
        Spot: R=${data.spot_r}, G=${data.spot_g}, B=${data.spot_b}<br>
        Matrix: R=${data.matrix_r}, G=${data.matrix_g}, B=${data.matrix_b}
      `;
    }

    // stop the listener and clean up its resources
    rxMeteringData.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/metering_data_frame_app.lua
```lua
local data = require('data.min')
local camera = require('camera.min')
local code = require('code.min')

-- Phone to Frame msg codes
METERING_QUERY_MSG = 0x12

-- register the message parser so it's automatically called when matching data comes in
data.parsers[METERING_QUERY_MSG] = code.parse_code

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	clear_display()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
				local items_ready = data.process_raw_items()

				if items_ready > 0 then

					if (data.app_data[METERING_QUERY_MSG] ~= nil) then
						camera.send_metering_data()
						data.app_data[METERING_QUERY_MSG] = nil
					end

				end

				frame.sleep(0.1)
			end
		)
		-- Catch the break signal here and clean up the display
		if rc == false then
			-- send the error back on the stdout stream
			print(err)
			frame.display.text(" ", 1, 1)
			frame.display.show()
			frame.sleep(0.04)
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## multi tap
// JavaScript file: multi-tap.js
```javascript
import { BrilliantMsg, StdLua, TxCode, RxTap } from 'brilliant-msg';
import frameApp from './lua/multi_tap_frame_app.lua?raw';

/**
 * Demonstrates detecting and counting multi-tap events from a Frame device.
 * This example involves:
 * - Sending `TxCode` messages to the Frame device to subscribe to and later unsubscribe from tap events.
 * - Using `RxTap` to receive and process tap events, which counts consecutive taps within a defined threshold.
 * - Logging the detected tap counts to the console (e.g., "2-tap received", "3-tap received").
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CodeMin, StdLua.TapMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxTap receiver
    var rxTap = new RxTap({});
    var tapQueue = await rxTap.attach(frame);

    // Subscribe for tap events
    await frame.sendMessage(0x10, new TxCode({ value: 1 }).pack());

    // iterate 10 times
    for (let i = 0; i < 10; i++) {
      // wait for a multi-tap event
      var tapCount = await tapQueue.get();
      console.log(`${tapCount}-tap received`);
    }

    // unsubscribe from tap events
    await frame.sendMessage(0x10, new TxCode({ value: 0 }).pack());

    // stop the tap listener and clean up its resources
    rxTap.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/multi_tap_frame_app.lua
```lua
local data = require('data.min')
local code = require('code.min')
local tap = require('tap.min')

-- Phone to Frame msg codes
TAP_SUBS_MSG = 0x10

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TAP_SUBS_MSG] = code.parse_code

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

                    if (data.app_data[TAP_SUBS_MSG] ~= nil) then

                        if data.app_data[TAP_SUBS_MSG].value == 1 then
                            -- start subscription to tap events
                            frame.imu.tap_callback(tap.send_tap)
							frame.display.text('Listening for taps', 1, 1)
							frame.display.show()
                        else
                            -- cancel subscription to tap events
                            frame.imu.tap_callback(nil)
							frame.display.text('Not listening for taps', 1, 1)
							frame.display.show()
                        end

                        data.app_data[TAP_SUBS_MSG] = nil
                    end

				end

				frame.sleep(0.01)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## plain text
// JavaScript file: plain-text.js
```javascript
import { BrilliantMsg, StdLua, TxPlainText } from 'brilliant-msg';
import frameApp from './lua/plain_text_frame_app.lua?raw';

/**
 * Demonstrates sending a sequence of plain text messages to a Frame device for display.
 * This example involves:
 * - Iteratively creating `TxPlainText` messages with varying text content and palette offsets (for different colors).
 * - Sending these messages to the Frame device, where a corresponding Lua application is expected to handle
 *   their display on the screen.
 * - Includes a delay between messages to allow each text to be visible.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame that handle data accumulation and text display
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.PlainTextMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // Send the text for display on Frame
    // Note that the frameside app is expecting a message of type TxPlainText on msgCode 0x0a
    const displayStrings = ["white", "gray", "red", "pink", "dark\nbrown", "brown", "orange", "yellow", "dark\ngreen", "green", "light\ngreen", "night\nblue", "sea\nblue", "sky\nblue", "cloud\nblue"];
    for (let i = 0; i < displayStrings.length; i++) {
      await frame.sendMessage(0x0a, new TxPlainText({ text: displayStrings[i], x: 50, y: 50, paletteOffset: i+1 }).pack());
      await new Promise(resolve => setTimeout(resolve, 1000)); // 1 second delay
    }
    // clear the display
    await frame.sendMessage(0x0a, new TxPlainText({ text: " " }).pack());

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/plain_text_frame_app.lua
```lua
local data = require('data.min')
local plain_text = require('plain_text.min')

-- Phone to Frame msg codes
TEXT_MSG = 0x0a

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_MSG] = plain_text.parse_plain_text

-- draw the specified text on the display
function print_text(text)
    local i = 0
    for line in text.string:gmatch('([^\n]*)\n?') do
        if line ~= "" then
            frame.display.text(line, text.x, i * 60 + text.y, {color=text.color})
            i = i + 1
        end
    end
end

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if data.app_data[TEXT_MSG] ~= nil and data.app_data[TEXT_MSG].string ~= nil then
						local text = data.app_data[TEXT_MSG]
						print_text(text)
						frame.display.show()

						-- clear the object and run the garbage collector right away
						data.app_data[TEXT_MSG] = nil
						collectgarbage('collect')
					end

				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## prog sprite jpg
// JavaScript file: prog-sprite-jpg.js
```javascript
import { BrilliantMsg, StdLua, TxSprite, TxImageSpriteBlock } from 'brilliant-msg';
import frameApp from './lua/prog_sprite_jpg_frame_app.lua?raw';

/**
 * Creates or updates an <img> element within a specified div to display a JPEG image.
 * @param {Uint8Array} imageBytes - The byte array of the JPEG image.
 * @param {string} mimeType - The mime type of the image bytes, e.g. 'image/jpeg'.
 * @param {string} divId - The ID of the div element to display the image in.
 */
function displayImage(imageBytes, mimeType, divId) {
  const img = document.createElement('img');
  img.src = URL.createObjectURL(new Blob([imageBytes], { type: mimeType }));
  const imageDiv = document.getElementById(divId);
  if (imageDiv) {
    imageDiv.innerHTML = ''; // Clear any existing content
    imageDiv.appendChild(img);
  }
}

/**
 * Demonstrates fetching a JPG image, converting it to a sprite format,
 * and sending it to a Frame device for progressive display.
 * This example involves:
 * - Fetching a JPG image from a local path.
 * - Displaying the original JPG image on the webpage.
 * - Converting the JPG image data into a `TxSprite` object using `TxSprite.fromImageBytes`,
 *   which includes resizing and color quantization.
 * - Displaying the generated `TxSprite` (as a PNG) on the webpage for comparison.
 * - Creating a `TxImageSpriteBlock` from the `TxSprite`, configured for progressive rendering.
 *   This process splits the sprite into smaller, transmittable lines.
 * - Sending the `TxImageSpriteBlock` (header first, then each sprite line) to the Frame device,
 *   allowing the image to be rendered progressively on its screen.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame that handle data accumulation and text display
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.SpriteMin, StdLua.ImageSpriteBlockMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // Quantize the image and send the image to Frame in chunks
    // read in the image bytes from "images/koala.jpg" and send it to the Frame
    const response = await fetch(new URL('./images/koala.jpg', import.meta.url));
    const imageBytes = new Uint8Array(await response.arrayBuffer());

    // display the source image on the web page
    displayImage(imageBytes, 'image/jpeg', 'image1');

    const sprite = await TxSprite.fromImageBytes(imageBytes);

    // display the sprite on the web page
    displayImage(sprite.toPngBytes(), 'image/png', 'image2');

    const isb = new TxImageSpriteBlock({ image: sprite, spriteLineHeight: 20 });
    // send the Image Sprite Block header
    await frame.sendMessage(0x20, isb.pack());

    // then send all the slices
    for (const spr of isb.spriteLines) {
      await frame.sendMessage(0x20, spr.pack());
    }

    // sleep for 20 seconds to allow the user to see the image
    await new Promise(resolve => setTimeout(resolve, 20000));

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/prog_sprite_jpg_frame_app.lua
```lua
local data = require('data.min')
local image_sprite_block = require('image_sprite_block.min')

-- Phone to Frame msg codes
IMAGE_SPRITE_BLOCK_MSG = 0x20

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[IMAGE_SPRITE_BLOCK_MSG] = image_sprite_block.parse_image_sprite_block


-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if (data.app_data[IMAGE_SPRITE_BLOCK_MSG] ~= nil) then
						-- show the image sprite block
						local isb = data.app_data[IMAGE_SPRITE_BLOCK_MSG]

						-- it can be that we haven't got any sprites yet, so only proceed if we have a sprite
						if isb.current_sprite_index > 0 then
							-- either we have all the sprites, or we want to do progressive/incremental rendering
							if isb.progressive_render or (isb.active_sprites == isb.total_sprites) then

								for index = 1, isb.active_sprites do
										local spr = isb.sprites[index]
										local y_offset = isb.sprite_line_height * (index - 1)

										-- set the palette the first time, all the sprites should have the same palette
										if index == 1 then
												image_sprite_block.set_palette(spr.num_colors, spr.palette_data)
										end

										frame.display.bitmap(1, y_offset + 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
								end

								frame.display.show()
							end
						end
					end

				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## sprite indexed png
// JavaScript file: sprite-indexed-png.js
```javascript
import { BrilliantMsg, StdLua, TxSprite } from 'brilliant-msg';
import frameApp from './lua/sprite_indexed_png_frame_app.lua?raw';

/**
 * Demonstrates fetching and displaying various indexed PNG images on a Frame device.
 * This example involves:
 * - Fetching a sequence of indexed PNG images (specifically 1-bit, 2-bit, and 4-bit) from local paths.
 * - Converting each fetched PNG image directly into a `TxSprite` object using `TxSprite.fromIndexedPngBytes`.
 *   This method preserves the original indexed color data without further quantization or resizing.
 * - Sending each `TxSprite` to the Frame device, where a corresponding Lua application is expected
 *   to handle its display on the screen.
 * - Pausing between sending each sprite to allow time for viewing on the Frame device.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame that handle data accumulation and text display
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.SpriteMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // send the 1-bit image to Frame
    // Note that the frameside app is expecting a message of type TxSprite on msgCode 0x20
    let response = await fetch(new URL('./images/logo_1bit.png', import.meta.url));
    let imageBytes = new Uint8Array(await response.arrayBuffer());
    let sprite = await TxSprite.fromIndexedPngBytes(imageBytes);
    await frame.sendMessage(0x20, sprite.pack());

    // sleep for 20 seconds to allow the user to see the image
    await new Promise(resolve => setTimeout(resolve, 20000));

    // send the 2-bit image to Frame
    response = await fetch(new URL('./images/street_2bit.png', import.meta.url));
    imageBytes = new Uint8Array(await response.arrayBuffer());
    sprite = await TxSprite.fromIndexedPngBytes(imageBytes);
    await frame.sendMessage(0x20, sprite.pack());

    // sleep for 20 more seconds to allow the user to see the image
    await new Promise(resolve => setTimeout(resolve, 20000));

    // send the 4-bit image to Frame
    response = await fetch(new URL('./images/hotdog_4bit.png', import.meta.url));
    imageBytes = new Uint8Array(await response.arrayBuffer());
    sprite = await TxSprite.fromIndexedPngBytes(imageBytes);
    await frame.sendMessage(0x20, sprite.pack());

    // sleep for 20 seconds to allow the user to see the image
    await new Promise(resolve => setTimeout(resolve, 20000));

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/sprite_indexed_png_frame_app.lua
```lua
local data = require('data.min')
local sprite = require('sprite.min')

-- Phone to Frame msg codes
USER_SPRITE_MSG = 0x20

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[USER_SPRITE_MSG] = sprite.parse_sprite

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if data.app_data[USER_SPRITE_MSG] ~= nil then
						local spr = data.app_data[USER_SPRITE_MSG]

						-- set the palette in case it's different to the standard palette
						sprite.set_palette(spr.num_colors, spr.palette_data)

						-- show the sprite
						frame.display.bitmap(1, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
						frame.display.show()

						-- clear the object and run the garbage collector right away
						data.app_data[USER_SPRITE_MSG] = nil
						collectgarbage('collect')
					end

				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## sprite jpg
// JavaScript file: sprite-jpg.js
```javascript
import { BrilliantMsg, StdLua, TxSprite } from 'brilliant-msg';
import frameApp from './lua/sprite_jpg_frame_app.lua?raw';

/**
 * Creates or updates an <img> element within a specified div to display a JPEG image.
 * @param {Uint8Array} imageBytes - The byte array of the JPEG image.
 * @param {string} mimeType - The mime type of the image bytes, e.g. 'image/jpeg'.
 * @param {string} divId - The ID of the div element to display the image in.
 */
function displayImage(imageBytes, mimeType, divId) {
  const img = document.createElement('img');
  img.src = URL.createObjectURL(new Blob([imageBytes], { type: mimeType }));
  const imageDiv = document.getElementById(divId);
  if (imageDiv) {
    imageDiv.innerHTML = ''; // Clear any existing content
    imageDiv.appendChild(img);
  }
}

/**
 * Demonstrates fetching a JPG image, converting it to a `TxSprite`, and sending it to a Frame device.
 * This example involves:
 * - Fetching a JPG image from a local path.
 * - Displaying the original JPG image on the webpage.
 * - Converting the JPG image data into a `TxSprite` object using `TxSprite.fromImageBytes`.
 *   This process includes resizing the image and quantizing its colors to a limited palette.
 * - Sending the entire packed `TxSprite` (header, palette, and pixel data) to the Frame device
 *   in a single message.
 * - Displaying the generated `TxSprite` (as a PNG) on the webpage for comparison with the original.
 * - The Frame device is expected to display the received sprite.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame that handle data accumulation and text display
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.SpriteMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // Quantize the image and send the image to Frame in chunks
    // read in the image bytes from "images/koala.jpg" and send it to the Frame
    const response = await fetch(new URL('./images/koala.jpg', import.meta.url));
    const imageBytes = new Uint8Array(await response.arrayBuffer());

    // display the source image on the web page
    displayImage(imageBytes, 'image/jpeg', 'image1');

    const sprite = await TxSprite.fromImageBytes(imageBytes);
    await frame.sendMessage(0x20, sprite.pack());

    // display the sprite on the web page
    displayImage(sprite.toPngBytes(), 'image/png', 'image2');

    // sleep for 20 seconds to allow the user to see the image
    await new Promise(resolve => setTimeout(resolve, 20000));

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/sprite_jpg_frame_app.lua
```lua
local data = require('data.min')
local sprite = require('sprite.min')

-- Phone to Frame msg codes
USER_SPRITE_MSG = 0x20

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[USER_SPRITE_MSG] = sprite.parse_sprite

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if data.app_data[USER_SPRITE_MSG] ~= nil then
						local spr = data.app_data[USER_SPRITE_MSG]

						-- set the palette in case it's different to the standard palette
						sprite.set_palette(spr.num_colors, spr.palette_data)

						-- show the sprite
						frame.display.bitmap(1, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
						frame.display.show()

						-- clear the object and run the garbage collector right away
						data.app_data[USER_SPRITE_MSG] = nil
						collectgarbage('collect')
					end

				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## sprite move
// JavaScript file: sprite-move.js
```javascript
import { BrilliantMsg, StdLua, TxSprite, TxSpriteCoords, TxCode } from 'brilliant-msg';
import frameApp from './lua/sprite_move_frame_app.lua?raw';

/**
 * Demonstrates sending a sprite to a Frame device and then moving it to random positions.
 * This example involves:
 * - Fetching an indexed PNG image and converting it to a `TxSprite` using `TxSprite.fromIndexedPngBytes`.
 * - Sending this initial `TxSprite` to the Frame device.
 * - Iteratively:
 *   - Generating random X and Y coordinates.
 *   - Sending these coordinates to the Frame device using a `TxSpriteCoords` message.
 *   - Sending a `TxCode` message to trigger the Frame device to redraw the sprite at the new coordinates.
 * - A short pause is included in each iteration to make the movement visible.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame that handle data accumulation and text display
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.SpriteMin, StdLua.CodeMin, StdLua.SpriteCoordsMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // send the 1-bit image to Frame in chunks
    // Note that the frameside app is expecting a message of type TxSprite on msgCode 0x20
    let response = await fetch(new URL('./images/rings_1bit.png', import.meta.url));
    let imageBytes = new Uint8Array(await response.arrayBuffer());
    let sprite = await TxSprite.fromIndexedPngBytes(imageBytes);
    await frame.sendMessage(0x20, sprite.pack());

    // send the sprite coordinates to Frame 20 times with random positions on msgCode 0x40
    // then send a message of type TxCode on msgCode 0x50 to draw the sprite
    for (let i = 0; i < 20; i++) {
      const x = Math.floor(Math.random() * 441) + 1;
      const y = Math.floor(Math.random() * 201) + 1;
      const coords = new TxSpriteCoords({ code: 0x20, x: x, y: y, offset: 0 });
      await frame.sendMessage(0x40, coords.pack());

      // draw the sprite
      await frame.sendMessage(0x50, new TxCode({}).pack());

      // sleep for 1s to allow the user to see the image
      await new Promise(resolve => setTimeout(resolve, 1000));
    }

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/sprite_move_frame_app.lua
```lua
local data = require('data.min')
local sprite = require('sprite.min')
local code = require('code.min')
local sprite_coords = require('sprite_coords.min')

-- Phone to Frame msg codes
SPRITE_0_MSG = 0x20
SPRITE_COORDS_MSG = 0x40
CODE_DRAW_MSG = 0x50

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[SPRITE_0_MSG] = sprite.parse_sprite
data.parsers[SPRITE_COORDS_MSG] = sprite_coords.parse_sprite_coords
data.parsers[CODE_DRAW_MSG] = code.parse_code

-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					-- sprite resource saved for later drawing
					-- also updates Frame's palette to match the sprite
					if data.app_data[SPRITE_0_MSG] ~= nil then
						local spr = data.app_data[SPRITE_0_MSG]

						-- set Frame's palette to match the sprite in case it's different to the standard palette
						sprite.set_palette(spr.num_colors, spr.palette_data)

						collectgarbage('collect')
					end

					-- place a sprite on the display (backbuffer)
					if data.app_data[SPRITE_COORDS_MSG] ~= nil then
						local coords = data.app_data[SPRITE_COORDS_MSG]
						local spr = data.app_data[coords.code]

						if spr ~= nil then
							frame.display.bitmap(coords.x, coords.y, spr.width, spr.num_colors, coords.offset, spr.pixel_data)
						else
							print('Sprite not found: ' .. tostring(coords.code))
						end

						data.app_data[SPRITE_COORDS_MSG] = nil
					end


					-- flip the buffers, show what we've drawn
					if data.app_data[CODE_DRAW_MSG] ~= nil then
						data.app_data[CODE_DRAW_MSG] = nil

						frame.display.show()
					end

				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


## text sprite block
// JavaScript file: text-sprite-block.js
```javascript
import { BrilliantMsg, StdLua, TxTextSpriteBlock } from 'brilliant-msg';
import frameApp from './lua/text_sprite_block_frame_app.lua?raw';

/**
 * Uses TxTextSpriteBlock to send rows of rasterized text as sprite images to the Frame display.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame that handle data accumulation and text display
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.TextSpriteBlockMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    const tsb = new TxTextSpriteBlock({width: 600,
                                fontSize: 40,
                                maxDisplayRows: 7,
                                text: "Hello, friend!\nこんにちは、友人！\n朋友你好！\nПривет, друг!\n안녕, 친구!\nשלום, חבר!\nمرحبا يا صديق",
                                fontFamily: "Monospace",
                               });
    // send the Image Sprite Block header
    await frame.sendMessage(0x20, tsb.pack());

    // then send all the slices
    for (const spr of tsb.sprites) {
      await frame.sendMessage(0x20, spr.pack());
    }

    // sleep for 20 seconds to allow the user to see the text
    await new Promise(resolve => setTimeout(resolve, 20000));

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};

```


// Corresponding Lua file: lua/text_sprite_block_frame_app.lua
```lua
local data = require('data.min')
local text_sprite_block = require('text_sprite_block.min')

-- Phone to Frame msg codes
TEXT_SPRITE_BLOCK_MSG = 0x20

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_SPRITE_BLOCK_MSG] = text_sprite_block.parse_text_sprite_block


-- Main app loop
function app_loop()
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if (data.app_data[TEXT_SPRITE_BLOCK_MSG] ~= nil) then
						-- show the text sprite block
						local tsb = data.app_data[TEXT_SPRITE_BLOCK_MSG]

						-- it can be that we haven't got any sprites yet, so only proceed if we have a sprite
						if tsb.first_sprite_index > 0 then
							-- either we have all the sprites, or we want to do progressive/incremental rendering
							if tsb.progressive_render or (tsb.active_sprites == tsb.total_sprites) then

								for index, spr in ipairs(tsb.sprites) do
									frame.display.bitmap(1, tsb.offsets[index].y + 1, spr.width, 2^spr.bpp, 0+index, spr.pixel_data)
								end

								frame.display.show()
							end
						end
					end

				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			frame.display.text(' ', 1, 1)
			frame.display.show()
			break
		end
	end
end

-- run the main app loop
app_loop()
```


