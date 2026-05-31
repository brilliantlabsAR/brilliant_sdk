import { BrilliantBle, BrilliantDeviceType } from 'brilliant-ble';

// --- Standard Lua Library Imports ---
import stdDataMinLua from './lua/data.min.lua?raw';
import stdAudioMinLua from './lua/audio.min.lua?raw';
import stdCameraMinLua from './lua/camera.min.lua?raw';
import stdCodeMinLua from './lua/code.min.lua?raw';
import stdIMUMinLua from './lua/imu.min.lua?raw';
import stdImageSpriteBlockMinLua from './lua/image_sprite_block.min.lua?raw';
import stdPlainTextMinLua from './lua/plain_text.min.lua?raw';
import stdSpriteMinLua from './lua/sprite.min.lua?raw';
import stdSpriteCoordsMinLua from './lua/sprite_coords.min.lua?raw';
import stdTapMinLua from './lua/tap.min.lua?raw';
import stdTextSpriteBlockMinLua from './lua/text_sprite_block.min.lua?raw';

/**
 * Enum representing the available standard Lua libraries that can be uploaded.
 */
export enum StdLua {
    DataMin = "stdDataMin",
    AudioMin = "stdAudioMin",
    CameraMin = "stdCameraMin",
    CodeMin = "stdCodeMin",
    IMUMin = "stdIMUMin",
    ImageSpriteBlockMin = "stdImageSpriteBlockMin",
    PlainTextMin = "stdPlainTextMin",
    SpriteMin = "stdSpriteMin",
    SpriteCoordsMin = "stdSpriteCoordsMin",
    TapMin = "stdTapMin",
    TextSpriteBlockMin = "stdTextSpriteBlockMin",
}

// Internal mapping from the enum to the actual Lua content and target filename
interface StdLibDetails {
    content: string;
    targetFileName: string;
}

const standardLuaLibrarySources: Record<StdLua, StdLibDetails> = {
    [StdLua.DataMin]: { content: stdDataMinLua, targetFileName: 'data.min.lua' },
    [StdLua.AudioMin]: { content: stdAudioMinLua, targetFileName: 'audio.min.lua' },
    [StdLua.CameraMin]: { content: stdCameraMinLua, targetFileName: 'camera.min.lua' },
    [StdLua.CodeMin]: { content: stdCodeMinLua, targetFileName: 'code.min.lua' },
    [StdLua.IMUMin]: { content: stdIMUMinLua, targetFileName: 'imu.min.lua' },
    [StdLua.ImageSpriteBlockMin]: { content: stdImageSpriteBlockMinLua, targetFileName: 'image_sprite_block.min.lua' },
    [StdLua.PlainTextMin]: { content: stdPlainTextMinLua, targetFileName: 'plain_text.min.lua' },
    [StdLua.SpriteMin]: { content: stdSpriteMinLua, targetFileName: 'sprite.min.lua' },
    [StdLua.SpriteCoordsMin]: { content: stdSpriteCoordsMinLua, targetFileName: 'sprite_coords.min.lua' },
    [StdLua.TapMin]: { content: stdTapMinLua, targetFileName: 'tap.min.lua' },
    [StdLua.TextSpriteBlockMin]: { content: stdTextSpriteBlockMinLua, targetFileName: 'text_sprite_block.min.lua' },
};


// Define a type for the data response handler function BrilliantMsg's subscribers will use
// Now expects Uint8Array
type BrilliantMsgDataHandler = (data: Uint8Array) => void;

// Define a type for subscribers to data responses within BrilliantMsg
interface DataResponseSubscriber {
    subscriber: any;
    handler: BrilliantMsgDataHandler;
}

/**
 * BrilliantMsg class handles communication with the Frame device.
 * It wraps the BrilliantBle class and provides higher-level methods for uploading standard Lua libraries
 * and Frame applications.
 * It also manages the registration and unregistration of data response handlers for different Rx message types.
 * Subscribers can register their own handlers for specific message codes.
 */
export class BrilliantMsg {
    /** The underlying {@link BrilliantBle} instance used for Bluetooth Low Energy communication. */
    public ble: BrilliantBle;
    private dataResponseHandlers: Map<number, Array<DataResponseSubscriber>>;

    /**
     * Constructs an instance of the BrilliantMsg class.
     * Initializes a new BrilliantBle instance and sets up internal data response handling.
     */
    constructor() {
        this.ble = new BrilliantBle();
        this.dataResponseHandlers = new Map<number, Array<DataResponseSubscriber>>();

        // Set BrilliantBle's data response handler to BrilliantMsg's internal multiplexer.
        // This now expects a Uint8Array from BrilliantBle.
        this.ble.setDataResponseHandler(this._handleDataResponse.bind(this));
    }

    /**
     * Connects to the Frame device and optionally runs the initialization sequence.
     * Note: Print and Disconnect handlers should be set directly on the BrilliantBle instance
     * (e.g., `frameMsg.ble.setPrintResponseHandler(...)`, `frameMsg.ble.setDisconnectHandler(...)`)
     * or via `frameMsg.attachPrintResponseHandler(...)` before or after calling connect.
     * @param initialize If true, runs the break/reset/break sequence after connecting. Defaults to true.
     * @param connectOptions Options including name and namePrefix for device filtering.
     * @returns The device ID or name if connection was successful.
     * @throws Any exceptions from the underlying BrilliantBle connection or initialization.
     */
    public async connect(
        initialize: boolean = true,
        connectOptions: {
            name?: string;
            namePrefix?: string;
        } = {}
    ): Promise<string | undefined> {
        try {
            const bleConnectOptions = {
                name: connectOptions.name,
                namePrefix: connectOptions.namePrefix,
            };

            const connectionResult = await this.ble.connect(bleConnectOptions);

            if (initialize) {
                await this.ble.sendBreakSignal();
                await this.ble.sendResetSignal();
                await this.ble.sendBreakSignal();
            }
            return connectionResult;
        } catch (e) {
            if (this.ble.isConnected()) {
                await this.ble.disconnect();
            }
            throw e;
        }
    }

    /**
     * Disconnects from the Frame device if currently connected.
     * @returns A Promise that resolves when disconnection is complete.
     */
    public async disconnect(): Promise<void> {
        if (this.ble.isConnected()) {
            await this.ble.disconnect();
        }
    }

    /**
     * Checks if the Frame device is currently connected.
     * @returns True if connected, false otherwise.
     */
    public isConnected(): boolean {
        return this.ble.isConnected();
    }

    /**
     * Displays a short string of text on the Frame's display.
     * The text is sanitized to escape single quotes and remove newlines.
     * @param text The text to display. Defaults to an empty string.
     * @returns A Promise that resolves with the print response from the device if `awaitPrint` is true (default), otherwise void.
     */
    public async printShortText(text: string = ''): Promise<string | void> {
        const sanitizedText = text.replace(/'/g, "\\'").replace(/\n/g, "");
        const luaCommand = this.ble.type === BrilliantDeviceType.FRAME
            ? `frame.display.text('${sanitizedText}',1,1);frame.display.show();print(0)`
            : `frame.display.clear();frame.display.text('${sanitizedText}',50,50);print(0)`;
        return this.ble.sendLua(luaCommand, { awaitPrint: true });
    }

    /**
     * Uploads specified standard Lua libraries to the Frame device.
     * @param libs An array of {@link StdLua} enum values indicating which libraries to upload.
     * @returns A Promise that resolves when all specified libraries have been uploaded.
     */
    public async uploadStdLuaLibs(libs: StdLua[]): Promise<void> {
        for (const libKey of libs) {
            const libDetails = standardLuaLibrarySources[libKey];
            if (libDetails) {
                await this.ble.uploadFileFromString(libDetails.content, libDetails.targetFileName);
            } else {
                console.warn(`Standard Lua library key "${libKey}" not found. Skipping.`);
            }
        }
    }

    /**
     * Uploads a Frame application (Lua script) to the device.
     * @param fileContent The content of the Lua application file as a string.
     * @param frameFileName The target filename on the Frame device. Defaults to 'frame_app.lua'.
     * @returns A Promise that resolves when the file has been uploaded.
     */
    public async uploadFrameApp(fileContent: string, frameFileName: string = 'frame_app.lua'): Promise<void> {
        await this.ble.uploadFile(fileContent, frameFileName);
    }

    /**
     * Starts a Frame application on the device by requiring its module name.
     * @param frameAppName The name of the Frame application module (without .lua extension). Defaults to 'frame_app'.
     * @param awaitPrint Whether to wait for a print response from the device. Defaults to true.
     * @returns A Promise that resolves with the print response if `awaitPrint` is true, otherwise void.
     */
    public async startFrameApp(frameAppName: string = 'frame_app', awaitPrint: boolean = true): Promise<string | void> {
        return this.ble.sendLua(`require('${frameAppName}')`, { awaitPrint: awaitPrint });
    }

    /**
     * Stops the currently running Frame application by sending a break signal.
     * Optionally, it can also reset the device.
     * @param reset If true, sends a reset signal after the break signal. Defaults to true.
     * @returns A Promise that resolves when the signals have been sent.
     */
    public async stopFrameApp(reset: boolean = true): Promise<void> {
        await this.ble.sendBreakSignal();
        if (reset) {
            await this.ble.sendResetSignal();
        }
    }

    /**
     * Attaches a handler for print responses from the Frame device.
     * This handler will be called with any text data printed by Lua scripts on the device.
     * @param handler A function to handle the print response string. Defaults to `console.log`.
     */
    public attachPrintResponseHandler(handler: (data: string) => void | Promise<void> = console.log): void {
        this.ble.setPrintResponseHandler(handler);
    }

    /**
     * Detaches the currently set print response handler.
     * After calling this, print responses from the device will no longer be processed by a custom handler.
     */
    public detachPrintResponseHandler(): void {
        this.ble.setPrintResponseHandler(undefined);
    }

    /**
     * Sends a message (msg_code and payload) to the Frame device.
     * @param msgCode The message code (an integer identifying the message type).
     * @param payload The Uint8Array payload for the message.
     * @param showMe If true, prints the message being sent to the console. Defaults to false.
     * @returns A Promise that resolves when the message has been sent.
     */
    public async sendMessage(msgCode: number, payload: Uint8Array, showMe: boolean = false): Promise<void> {
        await this.ble.sendMessage(msgCode, payload, showMe);
    }

    /**
     * Registers a handler for a subscriber interested in specific message codes from Frame.
     * @param subscriber The subscriber object/identifier.
     * @param msgCodes Array of message codes the subscriber is interested in.
     * @param handler The function to call with the incoming data (Uint8Array).
     */
    public registerDataResponseHandler(subscriber: any, msgCodes: number[], handler: BrilliantMsgDataHandler): void {
        for (const code of msgCodes) {
            if (!this.dataResponseHandlers.has(code)) {
                this.dataResponseHandlers.set(code, []);
            }
            const handlersForCode = this.dataResponseHandlers.get(code)!;
            const existing = handlersForCode.find(
                s => s.subscriber === subscriber && s.handler === handler
            );
            if (!existing) {
                handlersForCode.push({ subscriber, handler });
            }
        }
    }

    /**
     * Unregisters all data response handlers associated with a specific subscriber.
     * @param subscriber The subscriber object/identifier whose handlers should be removed.
     */
    public unregisterDataResponseHandler(subscriber: any): void {
        this.dataResponseHandlers.forEach((handlers, code) => {
            const filteredHandlers = handlers.filter(subHandler => subHandler.subscriber !== subscriber);
            if (filteredHandlers.length === 0) {
                this.dataResponseHandlers.delete(code);
            } else {
                this.dataResponseHandlers.set(code, filteredHandlers);
            }
        });
    }

    /**
     * Internal method to handle incoming data responses from BrilliantBle (as Uint8Array)
     * and dispatch to appropriate BrilliantMsg subscribers.
     * @param data The incoming data response as a Uint8Array.
     */
    private _handleDataResponse(data: Uint8Array): void { // Changed DataView to Uint8Array
        if (data && data.byteLength > 0) {
            const msgCode = data[0]; // Accessing first byte of Uint8Array
            if (this.dataResponseHandlers.has(msgCode)) {
                this.dataResponseHandlers.get(msgCode)!.forEach(subHandler => {
                    try {
                        // Pass the Uint8Array directly. If the handler needs a specific view
                        // (e.g. for multi-byte numbers), it can create it.
                        subHandler.handler(data);
                    } catch (error) {
                        console.error("Error in BrilliantMsg data response handler for msgCode", msgCode, ":", error);
                    }
                });
            }
        }
    }

    // --- Direct proxy methods to BrilliantBle for convenience ---

    /**
     * Sends a Lua command string to the Frame device.
     * This is a proxy to `BrilliantBle.sendLua()`.
     * @param str The Lua command string to send.
     * @param options Configuration options for sending the Lua command.
     * @returns A Promise that resolves with the print response if `awaitPrint` is true, otherwise void.
     */
    public async sendLua(
        str: string,
        options: {
            showMe?: boolean;
            awaitPrint?: boolean;
            timeout?: number;
        } = {}
    ): Promise<string | void> {
        return this.ble.sendLua(str, options);
    }

    /**
     * Sends raw data to the device.
     * @param data The Uint8Array payload to send.
     * @param options Configuration options.
     * @returns A Promise that resolves with the Uint8Array data response if awaitData is true, or void.
     */
     public async sendData(
        data: Uint8Array,
        options: {
            showMe?: boolean;
            awaitData?: boolean;
            timeout?: number;
        } = {}
    ): Promise<Uint8Array | void> { // Updated return type
        return this.ble.sendData(data, options);
    }

    /**
     * Sends a reset signal to the Frame device.
     * This is a proxy to `BrilliantBle.sendResetSignal()`.
     * @param showMe If true, prints a message to the console indicating the signal was sent. Defaults to false.
     * @returns A Promise that resolves when the signal has been sent.
     */
    public async sendResetSignal(showMe: boolean = false): Promise<void> {
        return this.ble.sendResetSignal(showMe);
    }

    /**
     * Sends a break signal (Ctrl+C) to the Frame device.
     * This is a proxy to `BrilliantBle.sendBreakSignal()`.
     * @param showMe If true, prints a message to the console indicating the signal was sent. Defaults to false.
     * @returns A Promise that resolves when the signal has been sent.
     */
    public async sendBreakSignal(showMe: boolean = false): Promise<void> {
        return this.ble.sendBreakSignal(showMe);
    }

    /**
     * Gets the maximum payload size for sending data to the Frame device.
     * This is a proxy to `BrilliantBle.getMaxPayload()`.
     * @param isLua True if the payload is for a Lua command, false for other data types.
     * @returns The maximum payload size in bytes.
     */
    public getMaxPayload(isLua: boolean): number {
        if (!this.ble) {
            console.warn("BrilliantBle instance not initialized or not connected for getMaxPayload.");
            return 60; // Default fallback
        }
        return this.ble.getMaxPayload(isLua);
    }
}
