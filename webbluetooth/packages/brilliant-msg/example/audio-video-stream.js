import { FrameMsg, StdLua, TxCode, TxCaptureSettings, RxAudio, RxPhoto, RxAudioSampleRate } from 'frame-msg';
import { BrilliantDeviceType } from 'frame-ble';
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
        const resolution = frame.ble.type === BrilliantDeviceType.FRAME ? 512 : 640;
        const captureSettings = new TxCaptureSettings({resolution: resolution});
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
    const frame = new FrameMsg();
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

        const upright = frame.ble.type === BrilliantDeviceType.FRAME; // rotate images from Frame 90 degrees counterclockwise, not Halo
        rxPhoto = new RxPhoto({ upright: upright });
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
