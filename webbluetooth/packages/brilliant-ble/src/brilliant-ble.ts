// Link-layer data PDUs carry at most 251 bytes, and the first PDU of an ATT
// write also carries the 4-byte L2CAP and 3-byte ATT headers
const LL_PDU_PAYLOAD = 251;
const ATT_WRITE_OVERHEAD = 7;

// Default size of Halo's data receive queue (frame.bluetooth.receive_buffer_size())
const HALO_RECEIVE_BUFFER_SIZE = 4096;

/**
 * Returns the largest ATT write value, at most maxWrite bytes, that exactly
 * fills whole link-layer packets (251k - 7 bytes: 244, 495, ...). A write
 * that overruns a packet boundary by a few bytes spends a whole extra packet
 * of airtime on them. Returns maxWrite when not even one packet fits.
 * @param maxWrite The maximum ATT write value length in bytes.
 * @returns The write size to use, in bytes.
 */
export function bleWriteSize(maxWrite: number): number {
    const packets = Math.floor((maxWrite + ATT_WRITE_OVERHEAD) / LL_PDU_PAYLOAD);
    if (packets === 0) {
        return maxWrite;
    }
    return packets * LL_PDU_PAYLOAD - ATT_WRITE_OVERHEAD;
}

export enum BrilliantDeviceType {
    FRAME = "Frame",
    HALO = "Halo",
    UNKNOWN = "Unknown",
}

/**
 * Class for managing a connection to and transferring data to and from
 * the Brilliant Labs Frame device over Bluetooth LE using WebBluetooth
 */
export class BrilliantBle {
    private device?: BluetoothDevice;
    private server?: BluetoothRemoteGATTServer;
    private txCharacteristic?: BluetoothRemoteGATTCharacteristic;
    private rxCharacteristic?: BluetoothRemoteGATTCharacteristic;
    private audioTxCharacteristic?: BluetoothRemoteGATTCharacteristic;
    private deviceType: BrilliantDeviceType = BrilliantDeviceType.UNKNOWN;

    private readonly SERVICE_UUID = "7a230001-5475-a6a4-654c-8431f6ad49c4";
    private readonly TX_CHARACTERISTIC_UUID = "7a230002-5475-a6a4-654c-8431f6ad49c4";
    private readonly RX_CHARACTERISTIC_UUID = "7a230003-5475-a6a4-654c-8431f6ad49c4";
    private readonly AUDIO_TX_CHARACTERISTIC_UUID = "7a230005-5475-a6a4-654c-8431f6ad49c4";

    private maxPayload = 60; // will be set after connection
    private awaitingPrintResponse = false;
    private awaitingDataResponse = false;
    private printTimeoutId?: NodeJS.Timeout;
    private printResponsePromise?: Promise<string>;
    private printResolve?: (value: string) => void;
    // Updated promise and resolve types for data responses
    private dataResponsePromise?: Promise<Uint8Array>;
    private dataResolve?: (value: Uint8Array) => void;
    private dataReject?: (reason: Error) => void;

    // Updated handler types
    private onDataResponse?: (data: Uint8Array) => void | Promise<void>;
    private onPrintResponse?: (data: string) => void | Promise<void>;
    private onDisconnectHandler?: () => void;

    // sendMessage() flow control on Halo: packets sent but not yet acknowledged,
    // and the waiters to wake on each ACK (true) or on disconnect (false)
    private acksOutstanding = 0;
    private ackFailed = false;
    private ackWaiters = new Set<(progressed: boolean) => void>();

    /**
     * Size in bytes of the device's data receive queue. On Halo, sendMessage()
     * keeps no more packets unacknowledged than fit in it, which is what keeps
     * a slow device-side handler from losing data. Set it to match a device
     * app that calls frame.bluetooth.receive_buffer_size(); larger values
     * allow faster sends. Defaults to Halo's 4096 bytes.
     */
    public receiveBufferSize = HALO_RECEIVE_BUFFER_SIZE;

    /**
     * Creates an instance of BrilliantBle.
     * The constructor is currently empty as most setup occurs during the connect method.
     */
    constructor() {}

    /**
     * Returns the type of the connected Brilliant device.
     */
    public get type(): BrilliantDeviceType {
        return this.deviceType;
    }

    /**
     * Sets or updates the handler for asynchronous data responses from the device.
     * @param handler The function to call when data (as Uint8Array) is received.
     * Pass undefined to remove the current handler.
     */
    public setDataResponseHandler(handler: ((data: Uint8Array) => void | Promise<void>) | undefined): void {
        this.onDataResponse = handler;
    }

    /**
     * Sets or updates the handler for asynchronous print (string) responses from the device.
     * @param handler The function to call when a print string is received.
     * Pass undefined to remove the current handler.
     */
    public setPrintResponseHandler(handler: ((data: string) => void | Promise<void>) | undefined): void {
        this.onPrintResponse = handler;
    }

    /**
     * Sets or updates the handler for disconnection events.
     * @param handler The function to call when the device disconnects.
     * Pass undefined to remove the current handler.
     */
    public setDisconnectHandler(handler: (() => void) | undefined): void {
        this.onDisconnectHandler = handler;
    }


    private handleDisconnect = () => {
        this.device = undefined;
        this.server = undefined;
        this.txCharacteristic = undefined;
        this.rxCharacteristic = undefined;
        this.audioTxCharacteristic = undefined;
        this.deviceType = BrilliantDeviceType.UNKNOWN;
        // Fail anything awaiting ACKs now, not at its timeout
        this.acksOutstanding = 0;
        this.ackFailed = false;
        this.wakeAckWaiters(false);
        // and a sendData() awaiting its response
        if (this.awaitingDataResponse && this.dataReject) {
            this.awaitingDataResponse = false;
            this.dataResolve = undefined;
            this.dataReject(new Error("Disconnected while awaiting a data response"));
        }
        this.dataReject = undefined;
        if (this.onDisconnectHandler) {
            this.onDisconnectHandler();
        }
    }

    private notificationHandler = (event: Event) => {
        const characteristic = event.target as BluetoothRemoteGATTCharacteristic;
        const value = characteristic.value; // This is a DataView
        if (!value || value.buffer.byteLength === 0) return;

        // The first byte of the raw characteristic value determines the type of message.
        // 0x01 indicates a data response. Other values (or no prefix) indicate a print response.
        // Note: Some devices might send print strings without a specific prefix byte if the data
        // is purely string data and not conforming to a more complex protocol on the same characteristic.
        // Here, we assume if it's not explicitly a data packet (0x01), it's a print string.

        if (value.byteLength > 0 && value.getUint8(0) === 1) { // Data response
            // Create a Uint8Array view of the data payload (from byte 1 to the end).
            // This avoids copying the underlying ArrayBuffer.
            const actualData = new Uint8Array(value.buffer, value.byteOffset + 1, value.byteLength - 1);

            if (this.acksOutstanding > 0 && value.byteLength === 4 &&
                value.getUint8(1) === 1 && value.getUint8(2) === 0) {
                // A sendMessage() ACK from data.lua (01 00 00, or 01 00 01 on
                // failure): count it rather than handing it to sendData()
                this.acksOutstanding--;
                if (value.getUint8(3) !== 0) {
                    this.ackFailed = true;
                }
                this.wakeAckWaiters(true);
            } else if (this.awaitingDataResponse && this.dataResolve) {
                this.awaitingDataResponse = false;
                this.dataResolve(actualData); // Resolve with Uint8Array
            }
            if (this.onDataResponse) {
                const result = this.onDataResponse(actualData); // Pass Uint8Array
                if (result instanceof Promise) {
                    result.catch(console.error);
                }
            }
        } else { // Print response (string)
            const decodedString = new TextDecoder().decode(value); // DataView is decodable
            if (this.awaitingPrintResponse && this.printResolve) {
                this.awaitingPrintResponse = false;
                this.printResolve(decodedString);
            }
            if (this.onPrintResponse) {
                const result = this.onPrintResponse(decodedString);
                if (result instanceof Promise) {
                    result.catch(console.error);
                }
            }
        }
    }

    /**
     * Attempts to establish a connection with the device and set up characteristics.
     * This method is intended to be called internally by `connect` and handles a single connection attempt.
     */
    private async _attemptConnection(): Promise<void> {
        if (!this.device || !this.device.gatt) {
            // this.device should be set by the connect() method before calling this.
            // this.device.gatt might be null if the device object exists but was never connected.
            throw new Error("Bluetooth device or GATT interface not available for connection attempt.");
        }

        // Reset characteristics and server from any previous failed attempt within a retry loop.
        this.txCharacteristic = undefined;
        this.rxCharacteristic = undefined;
        this.audioTxCharacteristic = undefined;
        this.deviceType = BrilliantDeviceType.UNKNOWN;
        this.server = undefined;

        try {
            console.log(`Attempting to connect to GATT server on device: ${this.device.name || this.device.id}...`);
            this.server = await this.device.gatt.connect();
            console.log("GATT server connected.");

            console.log("Getting primary service...");
            const service = await this.server.getPrimaryService(this.SERVICE_UUID);
            console.log("Primary service obtained.");

            console.log("Getting TX characteristic...");
            this.txCharacteristic = await service.getCharacteristic(this.TX_CHARACTERISTIC_UUID);
            console.log("TX characteristic obtained.");

            console.log("Getting RX characteristic...");
            this.rxCharacteristic = await service.getCharacteristic(this.RX_CHARACTERISTIC_UUID);
            console.log("RX characteristic obtained.");

            // Halo has an additional audio TX characteristic; Frame does not.
            try {
                this.audioTxCharacteristic = await service.getCharacteristic(this.AUDIO_TX_CHARACTERISTIC_UUID);
                this.deviceType = BrilliantDeviceType.HALO;
                console.log("Audio TX characteristic obtained — device is Halo.");
            } catch {
                this.deviceType = BrilliantDeviceType.FRAME;
                console.log("No audio TX characteristic — device is Frame.");
            }

            console.log("Starting notifications on RX characteristic...");
            await this.rxCharacteristic.startNotifications();
            this.rxCharacteristic.addEventListener('characteristicvaluechanged', this.notificationHandler);
            console.log("Notifications started.");

            await this.sendBreakSignal(false); // Initialize device state if necessary

            console.log("Fetching MTU size (max_length) from device...");
            const mtuString = await this.sendLua("print(frame.bluetooth.max_length())", {awaitPrint: true});
            if (mtuString === undefined || mtuString === null) {
                throw new Error("Failed to get MTU size from device: no response.");
            }
            const mtu = parseInt(mtuString);
            if (isNaN(mtu) || mtu <= 0) {
                throw new Error(`Invalid MTU size received: '${mtuString}'`);
            }
            this.maxPayload = mtu;
            console.log(`MTU size set to: ${this.maxPayload}`);

        } catch (error) {
            console.error("Error during connection attempt:", error);
            // Cleanup for this specific failed attempt
            if (this.rxCharacteristic) {
                try {
                    // Only try to stop notifications if gatt was connected and rxCharacteristic was obtained
                    if (this.device?.gatt?.connected) {
                        await this.rxCharacteristic.stopNotifications();
                    }
                } catch (stopNotificationError) {
                    // console.warn("Could not stop notifications during attempt cleanup:", stopNotificationError);
                }
                this.rxCharacteristic.removeEventListener('characteristicvaluechanged', this.notificationHandler);
                this.rxCharacteristic = undefined;
            }
            this.txCharacteristic = undefined;
            this.audioTxCharacteristic = undefined;
            this.deviceType = BrilliantDeviceType.UNKNOWN;
            if (this.device?.gatt?.connected) {
                this.device.gatt.disconnect(); // Disconnect from GATT for this attempt
            }
            this.server = undefined;
            throw error; // Rethrow to be handled by the calling loop in connect()
        }
    }

    /**
     * Connects to a Frame device.
     *
     * Prompts the user to select a Bluetooth device if one is not already known or connected.
     * Handles connection attempts, retries, and characteristic setup.
     *
     * @param options - Optional configuration for the connection process.
     * @param options.name - The exact name of the device to connect to.
     * @param options.namePrefix - The prefix of the device name to filter by.
     * @param options.numAttempts - The maximum number of connection attempts. Defaults to 5.
     * @param options.retryDelayMs - The delay in milliseconds between retry attempts. Defaults to 1000ms.
     * @returns A promise that resolves with the name or ID of the connected device, or undefined if connection fails.
     * @throws Error if Web Bluetooth is not available, if device selection is cancelled, or if connection fails after all attempts.
     */
    public async connect(
        options: {
            name?: string;
            namePrefix?: string;
            numAttempts?: number;
            retryDelayMs?: number;
        } = {}
    ): Promise<string | undefined> {
        const { name, namePrefix, numAttempts = 5, retryDelayMs = 1000 } = options; // Default values mentioned in JSDoc

        if (!navigator.bluetooth) {
            throw new Error("Web Bluetooth API not available.");
        }

        // Step 1: Request device from browser - This happens only if this.device is not already set.
        if (!this.device) {
            const baseFilter: BluetoothLEScanFilter = name
                ? { services: [this.SERVICE_UUID], name: name }
                : namePrefix
                    ? { services: [this.SERVICE_UUID], namePrefix: namePrefix }
                    : { services: [this.SERVICE_UUID] };

            const deviceOptions: RequestDeviceOptions = {
                filters: [baseFilter],
                optionalServices: [this.SERVICE_UUID],
            };
            try {
                console.log("Requesting Bluetooth device from user...");
                this.device = await navigator.bluetooth.requestDevice(deviceOptions);
                if (!this.device) {
                    // This case should ideally be caught by requestDevice throwing an error if user cancels.
                    throw new Error("No device selected by the user.");
                }
                console.log(`Device selected: ${this.device.name || this.device.id}`);
            } catch (error) {
                console.error("Bluetooth device request failed:", error);
                this.device = undefined; // Ensure device is reset
                throw error; // Rethrow error from requestDevice (e.g., user cancellation)
            }
        }

        // At this point, this.device should be set (either pre-existing or newly selected).
        if (!this.device) {
            // Fallback, should have been handled by logic above.
            throw new Error("Device not available after selection phase.");
        }

        // Store a reference to the device we are attempting to connect to for this sequence.
        // This is important because this.handleDisconnect might clear this.device.
        const currentDeviceToConnect = this.device;

        // Ensure the 'gattserverdisconnected' listener is correctly managed for the current device.
        // Remove first to prevent duplicates if connect is called multiple times on the same instance.
        currentDeviceToConnect.removeEventListener('gattserverdisconnected', this.handleDisconnect);
        currentDeviceToConnect.addEventListener('gattserverdisconnected', this.handleDisconnect);

        let lastError: any;

        for (let attempt = 1; attempt <= numAttempts; attempt++) {
            // If this.device became null due to an external disconnect event handled by handleDisconnect
            if (!this.device) {
                console.warn(`Device (id: ${currentDeviceToConnect.id}) was disconnected externally during connection attempts.`);
                lastError = lastError || new Error(`Device disconnected externally during connection attempt ${attempt}.`);
                break; // Exit retry loop as the device instance is no longer valid.
            }

            try {
                console.log(`Connection attempt ${attempt} of ${numAttempts} to device '${currentDeviceToConnect.name || currentDeviceToConnect.id}'...`);
                await this._attemptConnection(); // Uses this.device internally
                console.log(`Successfully connected to ${currentDeviceToConnect.name || currentDeviceToConnect.id} on attempt ${attempt}.`);
                return currentDeviceToConnect.name || currentDeviceToConnect.id || "Unknown Device";
            } catch (error) {
                lastError = error;
                console.error(`Attempt ${attempt} to connect to '${currentDeviceToConnect.name || currentDeviceToConnect.id}' failed:`, error);

                // Check if it's the specific retryable error
                const isRetryableError = error instanceof Error &&
                                         error.name === 'NetworkError' && // DOMException name
                                         (error.message.includes('Connection attempt failed.') ||
                                          error.message.includes('GATT operation failed for unknown reason.') ||
                                          error.message.includes('GATT Server is disconnected.') || // Potentially retryable if transient
                                          error.message.includes('Bluetooth device is already connected.') // Can happen, usually resolves
                                         );

                if (isRetryableError && attempt < numAttempts) {
                    console.log(`Retryable error encountered. Retrying in ${retryDelayMs / 1000}s...`);
                    await new Promise(resolve => setTimeout(resolve, retryDelayMs));
                    // _attemptConnection's catch block should have cleaned up resources for the next attempt
                    // (e.g., disconnected GATT if it was connected during the failed attempt).
                } else {
                    console.log("Non-retryable error or max attempts reached. Aborting connection process.");
                    break; // Exit loop to proceed to final cleanup and throw
                }
            }
        }

        // If loop finishes, all attempts failed or a non-retryable/external error occurred.
        console.error(`Failed to connect to device '${currentDeviceToConnect.name || currentDeviceToConnect.id}' after ${numAttempts} attempts or due to external disconnection.`);

        // Final cleanup:
        // Remove the specific listener from the device we were working with.
        currentDeviceToConnect.removeEventListener('gattserverdisconnected', this.handleDisconnect);

        // If gatt was connected on currentDeviceToConnect (e.g. _attemptConnection failed after gatt.connect but before full setup)
        // and _attemptConnection's cleanup didn't run or fully succeed, or if it was connected from a previous session.
        // Note: this.device.gatt.disconnect() in _attemptConnection's catch handles attempt-specific disconnects.
        // This is a final safeguard.
        if (currentDeviceToConnect.gatt?.connected) {
            currentDeviceToConnect.gatt.disconnect();
        }

        // Clear all class state properties as in the original catch block if connection ultimately fails.
        this.server = undefined;
        this.txCharacteristic = undefined;
        this.rxCharacteristic = undefined; // Listeners on rxCharacteristic are managed by _attemptConnection
        this.audioTxCharacteristic = undefined;
        this.deviceType = BrilliantDeviceType.UNKNOWN;

        // Crucially, clear this.device so a subsequent call to connect() re-prompts the user for a device.
        // This happens regardless of whether currentDeviceToConnect was the same as this.device at this point
        // (it should be, unless handleDisconnect cleared this.device).
        this.device = undefined;

        if (lastError) {
            throw lastError;
        } else {
            // This case should ideally not be reached if numAttempts >= 1, as lastError would be set.
            throw new Error(`Failed to connect to ${currentDeviceToConnect.name || currentDeviceToConnect.id} after ${numAttempts} attempts. No specific error recorded, or device disconnected externally.`);
        }
    }

    /**
     * Disconnects from the currently connected Frame device.
     * If no device is connected, this method does nothing.
     * It also triggers the `handleDisconnect` cleanup logic if not connected,
     * or relies on the 'gattserverdisconnected' event if connected.
     * @returns A promise that resolves once the disconnection process has been initiated, or immediately if already disconnected.
     */
    public async disconnect(): Promise<void> {
        const device = this.device;
        if (device && device.gatt?.connected) {
            // the link can drop during the wait, which clears this.device
            await this.settleAcks();
            device.gatt?.disconnect();
        } else {
            this.handleDisconnect(); // handleDisconnect is typically called by the 'gattserverdisconnected' event. Calling it here ensures immediate state cleanup if the event is delayed or not fired.
        }
    }

    /**
     * Checks if the Frame device is currently connected.
     * @returns True if the device is connected, false otherwise.
     */
    public isConnected(): boolean {
        return !!(this.device && this.device.gatt && this.device.gatt.connected);
    }

    /**
     * Gets the maximum payload size for a single BLE transmission.
     * This value is determined after device connection.
     * For Lua strings, the full `maxPayload` can be used.
     * For data packets (which include a 0x01 prefix byte), the effective payload is `maxPayload - 1`.
     * @param isLua If true, returns the max payload for Lua strings. Otherwise, for data packets.
     * @returns The maximum payload size in bytes.
     */
    public getMaxPayload(isLua: boolean): number {
        return isLua ? this.maxPayload : this.maxPayload - 1;
    }

    private async transmit(data: Uint8Array, showMe = false, awaitBtResponse = true) {
        if (!this.txCharacteristic) {
            throw new Error("Not connected or TX characteristic not available.");
        }
        if (data.byteLength > this.maxPayload) {
            throw new Error(`Payload length: ${data.byteLength} exceeds maximum BLE packet size: ${this.maxPayload}`);
        }
        if (showMe) {
            console.log("Transmitting (hex):", Array.from(data).map(b => b.toString(16).padStart(2, '0')).join(' '));
        }
        // TypeScript 5.9 narrowed BufferSource to ArrayBufferView<ArrayBuffer>,
        // while a bare Uint8Array is Uint8Array<ArrayBufferLike> and no longer
        // matches. Everything reaching here is ArrayBuffer-backed, so assert the
        // type rather than copying the buffer -- this is a per-packet hot path.
        const payload = data as BufferSource;
        if (awaitBtResponse) {
            await this.txCharacteristic.writeValueWithResponse(payload);
        } else {
            await this.txCharacteristic.writeValueWithoutResponse(payload);
        }
    }

    private wakeAckWaiters(progressed: boolean) {
        const waiters = [...this.ackWaiters];
        this.ackWaiters.clear();
        for (const wake of waiters) {
            wake(progressed);
        }
    }

    /**
     * Waits until at most maxOutstanding sendMessage() packets are
     * unacknowledged. Throws if the device reported a failed packet, stops
     * acknowledging for timeoutMs, or disconnects.
     */
    private async awaitAcks(maxOutstanding: number, timeoutMs = 5000): Promise<void> {
        // A failure ACK means data.lua's handler errored, after which no more
        // ACKs come: report it as soon as it arrives, not as a timeout, and
        // clear it so it can't fail a later, unrelated call
        const throwIfFailed = () => {
            if (this.ackFailed) {
                this.ackFailed = false;
                this.acksOutstanding = 0;
                throw new Error("Device failed to process a message (see its print output).");
            }
        };
        throwIfFailed();
        while (this.acksOutstanding > maxOutstanding) {
            const progressed = await new Promise<boolean | undefined>((resolve) => {
                const timeoutId = setTimeout(() => {
                    this.ackWaiters.delete(wake);
                    resolve(undefined);
                }, timeoutMs);
                const wake = (progressed: boolean) => {
                    clearTimeout(timeoutId);
                    resolve(progressed);
                };
                this.ackWaiters.add(wake);
            });
            throwIfFailed();
            if (progressed === undefined) {
                // Resetting the count means ACKs that still arrive late are
                // miscounted against later packets; acceptable, since this
                // only happens when the device app has stalled or been reset
                this.acksOutstanding = 0;
                throw new Error(`Device didn't acknowledge message data within ${timeoutMs}ms.`);
            }
            if (!progressed || !this.isConnected()) {
                throw new Error("Disconnected while awaiting message acknowledgements.");
            }
        }
        throwIfFailed();
    }

    /**
     * Waits until the device has acknowledged every packet sendMessage() has
     * sent, i.e. its data handler has taken them all in.
     *
     * On Halo, sendMessage() resolves once its last packet is written, so that
     * consecutive messages stream back to back. Every other call that talks to
     * the device waits for this first, so data is always processed before,
     * say, a break signal; call it directly to wait for that point.
     * Resolves immediately if nothing is outstanding (always the case on Frame).
     * @param timeoutMs Fail if no ACK arrives for this long. Defaults to 5000ms.
     * @throws Error if the device reported a failed packet, stopped acknowledging, or disconnected.
     */
    public async waitForAcks(timeoutMs = 5000): Promise<void> {
        await this.awaitAcks(0, timeoutMs);
    }

    // Before a control signal or disconnect: wait briefly, but a stuck device
    // app is exactly what break/reset/remove are for, so never fail on it
    private async settleAcks(): Promise<void> {
        try {
            await this.awaitAcks(0, 1000);
        } catch {
            // As after a timeout, late ACKs may then be miscounted, which is
            // acceptable straight after a break, reset or disconnect
            this.acksOutstanding = 0;
            this.ackFailed = false;
        }
    }

    /**
     * Sends a Lua command string to the Frame device.
     * @param str The Lua command string to send.
     * @param options Optional configuration for sending the Lua command.
     * @param options.showMe If true, logs the transmitted data (hex format) to the console. Defaults to false.
     * @param options.awaitPrint If true, waits for a print response from the device. Defaults to false.
     * @param options.timeout The timeout in milliseconds to wait for a print response if `awaitPrint` is true. Defaults to 5000ms.
     * @returns A promise that resolves with the print response string if `awaitPrint` is true, or void otherwise.
     * @throws Error if the Lua string payload is too large or if a timeout occurs while awaiting a print response,
     * or if earlier sendMessage() data is not acknowledged (see `waitForAcks()`).
     */
    public async sendLua(
        str: string,
        options: {
            showMe?: boolean;
            awaitPrint?: boolean;
            timeout?: number;
        } = {}
    ): Promise<string | void> {
        const { showMe = false, awaitPrint = false, timeout = 5000 } = options; // Default values documented
        const encodedString = new TextEncoder().encode(str);
        if (encodedString.byteLength > this.getMaxPayload(true)) {
             throw new Error(`Lua string payload (${encodedString.byteLength} bytes) is too large for max Lua payload (${this.getMaxPayload(true)} bytes).`);
        }

        await this.waitForAcks();

        if (awaitPrint) {
            if (this.printTimeoutId) clearTimeout(this.printTimeoutId);
            this.awaitingPrintResponse = true;
            this.printResponsePromise = new Promise<string>((resolve, reject) => {
                this.printResolve = resolve;
                this.printTimeoutId = setTimeout(() => {
                    if (this.awaitingPrintResponse) {
                        this.awaitingPrintResponse = false;
                        this.printResolve = undefined;
                        reject(new Error(`Device didn't respond with a print within ${timeout}ms.`));
                    }
                }, timeout);
            }).finally(() => {
                if (this.printTimeoutId) {
                    clearTimeout(this.printTimeoutId);
                    this.printTimeoutId = undefined;
                }
            });
        }

        await this.transmit(encodedString, showMe);
        if (awaitPrint) return this.printResponsePromise;
    }

    /**
     * Sends raw data to the device. The data is prefixed with a `0x01` byte to distinguish it from Lua commands.
     * @param data The raw application payload to send as a Uint8Array. This is the actual data without the prefix.
     * @param options Optional configuration for sending data.
     * @param options.showMe If true, logs the transmitted data (including prefix, hex format) to the console. Defaults to false.
     * @param options.awaitData If true, waits for a data response from the device. Defaults to false.
     * @param options.timeout The timeout in milliseconds to wait for a data response if `awaitData` is true. Defaults to 5000ms.
     * @param options.awaitBtResponse If true, uses write-with-response at the BLE level. Defaults to true.
     * @returns A promise that resolves with the Uint8Array data response if `awaitData` is true, or void otherwise.
     * @throws Error if not connected, if TX characteristic is not available, or if the data payload is too large,
     * or if earlier sendMessage() data is not acknowledged (see `waitForAcks()`).
     */
    public async sendData(
        data: Uint8Array, // This is the application payload
        options: {
            showMe?: boolean;
            awaitData?: boolean;
            timeout?: number;
            awaitBtResponse?: boolean;
        } = {}
    ): Promise<Uint8Array | void> { // Updated return type
        const { showMe = false, awaitData = false, timeout = 5000, awaitBtResponse = true } = options; // Default values documented

        if (!this.txCharacteristic) {
            throw new Error("Not connected or TX characteristic not available.");
        }
        if (data.byteLength > this.getMaxPayload(false)) {
            throw new Error(`Data payload (${data.byteLength} bytes) is too large for max data payload (${this.getMaxPayload(false)} bytes).`);
        }

        await this.waitForAcks();

        const prefix = new Uint8Array([1]); // 0x01 prefix for raw data
        const combinedData = new Uint8Array(prefix.length + data.byteLength);
        combinedData.set(prefix, 0);
        combinedData.set(data, prefix.length);

        let dataTimeoutId: NodeJS.Timeout | undefined;

        if (awaitData) {
            this.awaitingDataResponse = true;
            // Ensure the promise type matches the updated dataResolve type
            this.dataResponsePromise = new Promise<Uint8Array>((resolve, reject) => {
                this.dataResolve = resolve; // dataResolve expects Uint8Array
                this.dataReject = reject;
                dataTimeoutId = setTimeout(() => {
                    if (this.awaitingDataResponse) {
                        this.awaitingDataResponse = false;
                        this.dataResolve = undefined;
                        reject(new Error(`Device didn't respond with data within ${timeout}ms.`));
                    }
                }, timeout);
            }).finally(() => {
                if (dataTimeoutId) clearTimeout(dataTimeoutId);
            });
        }

        await this.transmit(combinedData, showMe, awaitBtResponse);
        if (awaitData) return this.dataResponsePromise; // Returns Promise<Uint8Array>
    }

    /**
     * Sends audio data to the Halo audio characteristic (UUID 7a230005).
     * Packets exceeding the MTU are silently dropped, matching device firmware behaviour.
     * @param data The audio payload (LC3 frames or PCM samples) to send.
     * @param awaitBtResponse If true, uses write-with-response at the BLE level. Defaults to false for throughput.
     */
    public async sendAudio(data: Uint8Array, awaitBtResponse = false): Promise<void> {
        if (!this.audioTxCharacteristic) {
            throw new Error("Audio TX characteristic not available. Is this a Halo device?");
        }
        const mtu = this.maxPayload;
        if (data.byteLength > mtu) {
            return;
        }
        // TypeScript 5.9 narrowed BufferSource to ArrayBufferView<ArrayBuffer>,
        // while a bare Uint8Array is Uint8Array<ArrayBufferLike> and no longer
        // matches. Everything reaching here is ArrayBuffer-backed, so assert the
        // type rather than copying the buffer -- this is a per-packet hot path.
        const payload = data as BufferSource;
        if (awaitBtResponse) {
            await this.audioTxCharacteristic.writeValueWithResponse(payload);
        } else {
            await this.audioTxCharacteristic.writeValueWithoutResponse(payload);
        }
    }

    /**
     * Discards any unsolicited print output currently arriving on the channel
     * (e.g. the 'interrupted'/reboot banner produced by a break or reset), so
     * the next `sendLua({ awaitPrint: true })` receives a clean response rather
     * than the stray banner.
     *
     * Bounded so it never hangs: returns after `quietMs` of silence, or
     * `maxTotalMs` at the latest. An idle device emits nothing, so the common
     * case costs a single quiet window. A break only prints 'interrupted' when
     * it actually interrupts a running chunk, and the banner can span more than
     * one notification, so we soak up everything until the channel goes quiet
     * rather than awaiting a single line.
     * @param quietMs Silence (ms) that marks the channel drained. Defaults to 250.
     * @param maxTotalMs Hard cap (ms) so it always returns. Defaults to 1500.
     */
    public async drainPrintChannel(quietMs = 250, maxTotalMs = 1500): Promise<void> {
        const start = Date.now();
        while (Date.now() - start < maxTotalMs) {
            const gotOne = await new Promise<boolean>((resolve) => {
                if (this.printTimeoutId) clearTimeout(this.printTimeoutId);
                this.awaitingPrintResponse = true;
                this.printResolve = () => resolve(true);
                this.printTimeoutId = setTimeout(() => {
                    if (this.awaitingPrintResponse) {
                        this.awaitingPrintResponse = false;
                        this.printResolve = undefined;
                        resolve(false);
                    }
                }, quietMs);
            });
            if (this.printTimeoutId) {
                clearTimeout(this.printTimeoutId);
                this.printTimeoutId = undefined;
            }
            if (!gotOne) break; // quiet window elapsed with no print
        }
        this.awaitingPrintResponse = false;
        this.printResolve = undefined;
    }

    /**
     * Sends a reset signal (0x04) to the Frame device.
     * This typically causes the device to restart its Lua environment.
     * @param showMe If true, logs the transmitted signal (hex format) to the console. Defaults to false.
     * @returns A promise that resolves after a short delay post-transmission.
     */
    public async sendResetSignal(showMe = false): Promise<void> {
        const signal = new Uint8Array([0x04]);
        await this.settleAcks();
        await this.transmit(signal, showMe);
        await new Promise(resolve => setTimeout(resolve, 200)); // Short delay
    }

    /**
     * Sends a remove signal (0x05) to the Halo device, which removes main.lua.
     * This is only applicable to Halo devices.
     * @param showMe If true, logs the transmitted signal (hex format) to the console. Defaults to false.
     * @returns A promise that resolves after a short delay post-transmission.
     */
    public async sendRemoveSignal(showMe = false): Promise<void> {
        const signal = new Uint8Array([0x05]);
        await this.settleAcks();
        await this.transmit(signal, showMe);
        await new Promise(resolve => setTimeout(resolve, 200)); // Short delay
    }

    /**
     * Sends a break signal (0x03) to the Frame device.
     * This typically interrupts any currently running Lua script on the device.
     * @param showMe If true, logs the transmitted signal (hex format) to the console. Defaults to false.
     * @returns A promise that resolves after a short delay post-transmission.
     */
    public async sendBreakSignal(showMe = false): Promise<void> {
        const signal = new Uint8Array([0x03]);
        await this.settleAcks();
        await this.transmit(signal, showMe);
        await new Promise(resolve => setTimeout(resolve, 200)); // Short delay
    }

    /**
     * Uploads content to a file on the Frame device by sending Lua commands.
     * The content is escaped and chunked to fit within payload limits.
     * @param content The string content to write to the file.
     * @param frameFilePath The path to the file on the Frame device. Defaults to "main.lua".
     * @returns A promise that resolves when the file upload is complete.
     * @throws Error if any step of the file upload process fails (e.g., opening file, writing chunk).
     */
    public async uploadFileFromString(content: string, frameFilePath = "main.lua"): Promise<void> {
        let escapedContent = content.replace(/\r/g, "")
                                  .replace(/\\/g, "\\\\")
                                  .replace(/\n/g, "\\n")
                                  .replace(/\t/g, "\\t")
                                  .replace(/'/g, "\\'")
                                  .replace(/"/g, '\\"');

        const luaCommandOverhead = `f:write("");print(1)`.length;
        const maxChunkSize = this.getMaxPayload(true) - luaCommandOverhead;

        if (maxChunkSize <= 0) {
            throw new Error("Max payload size too small for file upload operations.");
        }

        // Chunk by UTF-8 byte length (not string length) so that characters
        // that expand to multiple bytes can't push a packet over the MTU
        const chunks = chunkLuaString(new TextEncoder().encode(escapedContent), maxChunkSize);

        const openResponse = await this.sendLua(`f=frame.file.open('${frameFilePath}','w');print(1)`, {awaitPrint: true});
        if (openResponse !== "1") {
            throw new Error(`Failed to open file ${frameFilePath} on device. Response: ${openResponse}`);
        }

        for (const chunk of chunks) {
            const writeResponse = await this.sendLua(`f:write("${chunk}");print(1)`, {awaitPrint: true});
            if (writeResponse !== "1") {
                 await this.sendLua("f:close();print(nil)", {awaitPrint: true});
                throw new Error(`Failed to write chunk to ${frameFilePath}. Response: ${writeResponse}`);
            }
        }
        await this.sendLua("f:close();print(nil)", {awaitPrint: true});
    }

    /**
     * A convenience method that calls `uploadFileFromString`.
     * Uploads file content to a specified path on the Frame device.
     * @param fileContent The string content of the file to upload.
     * @param frameFilePath The path on the Frame device where the file will be saved. Defaults to "main.lua".
     * @returns A promise that resolves when the file upload is complete.
     */
    public async uploadFile(fileContent: string, frameFilePath = "main.lua"): Promise<void> {
        await this.uploadFileFromString(fileContent, frameFilePath);
    }

    /**
     * Sends a multi-packet message to the device.
     * This method handles chunking the payload and sending it in multiple BLE packets
     * according to a specific protocol (message code, total size header, then data chunks).
     *
     * On Frame, each packet is written and acknowledged by data.lua before the
     * next, and the promise resolves once the last packet is acknowledged.
     *
     * On Halo, packets are written without response, each filling whole
     * link-layer packets, with at most `receiveBufferSize / (packet size + 2)`
     * of them unacknowledged at a time. The promise resolves once the last
     * packet is written, so consecutive messages stream back to back; the
     * remaining ACKs are collected by the next call that talks to the device
     * (or by `waitForAcks()`). `awaitBtResponse` is ignored on Halo.
     *
     * The device app must acknowledge every packet with data.lua's ACK (data
     * payload 01 00 00), as data.lua's own handler does. On Halo, an app whose
     * receive callback doesn't makes a LATER call throw after its timeout (the
     * next sendLua or sendData, or a sendMessage once the window is full), not
     * this one; control signals just wait about a second and carry on.
     * @param msgCode A number (0-255) representing the message type or command.
     * @param payload The Uint8Array data to send as the message payload.
     * @param showMe If true, logs details of each transmitted packet to the console. Defaults to false.
     * @param awaitBtResponse Frame only: if true, uses write-with-response at the BLE level. Defaults to true.
     * @returns A promise that resolves when all parts of the message have been sent (and, on Frame, acknowledged).
     * @throws Error if msgCode is out of range, payload is too large, if max payload size is too small for the protocol,
     * or if the device fails, stops acknowledging or disconnects mid-message.
     */
    public async sendMessage(msgCode: number, payload: Uint8Array, showMe = false, awaitBtResponse = true): Promise<void> {
        const HEADER_SIZE = 2; // size_high(1), size_low(1)
        const MAX_TOTAL_PAYLOAD_SIZE = 65535;

        if (msgCode < 0 || msgCode > 255) {
            throw new Error(`Message code must be 0-255, got ${msgCode}`);
        }
        const totalPayloadSize = payload.byteLength;
        if (totalPayloadSize > MAX_TOTAL_PAYLOAD_SIZE) {
            throw new Error(`Payload size ${totalPayloadSize} exceeds maximum ${MAX_TOTAL_PAYLOAD_SIZE} bytes`);
        }

        // Packet size excludes the 0x01 data marker
        let maxDataPayloadForSend: number;
        let sendPacket: (packet: Uint8Array) => Promise<void>;

        if (this.deviceType === BrilliantDeviceType.HALO) {
            // Halo: writes without response, filling whole link-layer packets,
            // paced by a window over data.lua's per-packet ACKs. Halo queues
            // each packet (less its marker byte, plus a 2-byte length) until
            // the Lua handler takes it, and silently drops a write without
            // response that doesn't fit, so never have more packets
            // unacknowledged than the queue holds. Messages stream back to
            // back; the ACKs still outstanding are collected by the next call
            // that needs them (see waitForAcks()).
            //
            // writeValueWithoutResponse() is no flow control. The spec resolves
            // it once the Write Without Response procedure is done, and that
            // procedure has no reply, so it only means the platform took the
            // write. Chromium on macOS calls CoreBluetooth's writeValue and
            // resolves straight away, without checking
            // canSendWriteWithoutResponse, so a write made while CoreBluetooth's
            // queue is full can be silently dropped. On Android and Windows,
            // Chromium resolves when the OS stack completes the write
            // (onCharacteristicWrite / WriteValueWithResultAndOptionAsync),
            // which those stacks pace. The window below bounds the data in
            // flight either way, and a lost packet stops the ACKs, so it shows
            // up as a timeout rather than passing unnoticed.
            const writeSize = bleWriteSize(this.maxPayload);
            maxDataPayloadForSend = writeSize - 1;
            const window = Math.max(1, Math.floor(this.receiveBufferSize / (maxDataPayloadForSend + 2)));

            sendPacket = async (packet: Uint8Array) => {
                await this.awaitAcks(window - 1);
                const combinedData = new Uint8Array(1 + packet.byteLength);
                combinedData[0] = 1; // 0x01 prefix for raw data
                combinedData.set(packet, 1);
                // Count it before writing: its ACK can arrive during the write
                this.acksOutstanding++;
                try {
                    await this.transmit(combinedData, showMe, false);
                } catch (error) {
                    // Never sent, so never acknowledged
                    this.acksOutstanding = Math.max(0, this.acksOutstanding - 1);
                    throw error;
                }
            };
        } else {
            // Frame: one packet at a time, each acknowledged by data.lua
            // before the next
            maxDataPayloadForSend = this.getMaxPayload(false);

            sendPacket = async (packet: Uint8Array) => {
                await this.sendData(packet, {showMe: showMe, awaitData: true, awaitBtResponse: awaitBtResponse});
            };
        }

        const maxFirstChunkDataSize = maxDataPayloadForSend - 1 - HEADER_SIZE;
        const maxSubsequentChunkDataSize = maxDataPayloadForSend - 1;

        if (maxFirstChunkDataSize <=0 || maxSubsequentChunkDataSize <=0) {
            throw new Error("Max payload size too small for message sending protocol.");
        }

        let sentBytes = 0;
        const firstChunkActualDataSize = Math.min(maxFirstChunkDataSize, totalPayloadSize);
        const firstPacketDataForSendData = new Uint8Array(1 + HEADER_SIZE + firstChunkActualDataSize);
        firstPacketDataForSendData[0] = msgCode;
        firstPacketDataForSendData[1] = totalPayloadSize >> 8;
        firstPacketDataForSendData[2] = totalPayloadSize & 0xFF;
        firstPacketDataForSendData.set(payload.subarray(0, firstChunkActualDataSize), 1 + HEADER_SIZE);

        await sendPacket(firstPacketDataForSendData);
        sentBytes += firstChunkActualDataSize;

        while (sentBytes < totalPayloadSize) {
            const remaining = totalPayloadSize - sentBytes;
            const currentChunkActualDataSize = Math.min(maxSubsequentChunkDataSize, remaining);
            const subsequentPacketDataForSendData = new Uint8Array(1 + currentChunkActualDataSize);
            subsequentPacketDataForSendData[0] = msgCode;
            subsequentPacketDataForSendData.set(payload.subarray(sentBytes, sentBytes + currentChunkActualDataSize), 1);

            await sendPacket(subsequentPacketDataForSendData);
            sentBytes += currentChunkActualDataSize;
        }
    }
}

/**
 * Splits payload (the UTF-8 bytes of an escaped Lua string literal) into
 * chunks of at most maxChunkBytes bytes, without splitting a multi-byte
 * UTF-8 sequence or a Lua escape sequence across two chunks.
 * @param payload The UTF-8 encoded bytes of the escaped Lua string.
 * @param maxChunkBytes The maximum size of each chunk in bytes.
 * @returns The chunks, decoded back to strings.
 */
export function chunkLuaString(payload: Uint8Array, maxChunkBytes: number): string[] {
    if (maxChunkBytes <= 0) {
        throw new Error("maxChunkBytes must be positive.");
    }

    const decoder = new TextDecoder();
    const chunks: string[] = [];
    let index = 0;

    while (index < payload.length) {
        let end = index + maxChunkBytes;

        if (end >= payload.length) {
            end = payload.length;
        } else {
            // Don't split a multi-byte UTF-8 sequence: back up while the byte
            // at the split point is a continuation byte (0b10xxxxxx)
            while (end > index && (payload[end] & 0xC0) === 0x80) {
                end--;
            }

            // Don't split an escape sequence: an odd number of trailing
            // backslashes means the last one starts an escape whose second
            // character would land in the next chunk
            let trailingBackslashes = 0;
            while (end - 1 - trailingBackslashes >= index && payload[end - 1 - trailingBackslashes] === 0x5C) {
                trailingBackslashes++;
            }
            if (trailingBackslashes % 2 === 1) {
                end--;
            }

            if (end === index) {
                throw new Error("maxChunkBytes is too small to hold the next character of the payload.");
            }
        }

        chunks.push(decoder.decode(payload.subarray(index, end)));
        index = end;
    }

    return chunks;
}
