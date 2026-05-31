import { BrilliantMsg } from '../brilliant-msg';
import { AsyncQueue } from '../async-queue';

/**
 * Interface for the detailed brightness metrics (matrix or spot).
 */
export interface BrightnessDetails {
    /** Red channel brightness component. */
    r: number;
    /** Green channel brightness component. */
    g: number;
    /** Blue channel brightness component. */
    b: number;
    /** Average brightness across R, G, B channels. */
    average: number;
}

/**
 * Interface for the overall brightness data structure.
 */
export interface BrightnessData {
    /** Center-weighted average brightness of the scene. */
    center_weighted_average: number;
    /** Overall scene brightness. */
    scene: number;
    /** Detailed brightness metrics using matrix metering. */
    matrix: BrightnessDetails;
    /** Detailed brightness metrics using spot metering. */
    spot: BrightnessDetails;
}

/**
 * Interface for the structured auto exposure result data.
 */
export interface AutoExpResultData {
    /** The error value from the auto exposure algorithm. */
    error: number;
    /** The calculated shutter speed (exposure time). */
    shutter: number;
    /** The calculated analog gain. */
    analog_gain: number;
    /** The red channel gain. */
    red_gain: number;
    /** The green channel gain. */
    green_gain: number;
    /** The blue channel gain. */
    blue_gain: number;
    /** Detailed brightness data used for auto exposure. */
    brightness: BrightnessData;
}

/**
 * Options for RxAutoExpResult constructor.
 */
export interface RxAutoExpResultOptions {
    /** Optional message code to identify auto exposure result packets. Defaults to 0x11. */
    msgCode?: number;
}

/**
 * RxAutoExpResult class handles processing of auto exposure result data packets.
 */
export class RxAutoExpResult {
    private msgCode: number;
    /** Asynchronous queue for received auto exposure result data. Null if not attached. */
    public queue: AsyncQueue<AutoExpResultData | null> | null;

    /**
     * Initialize receive handler for processing auto exposure result data.
     * @param options Configuration options for the handler.
     * Includes `msgCode` (default: 0x11)
     */
    constructor(options: RxAutoExpResultOptions = {}) {
        this.msgCode = options.msgCode ?? 0x11; // Default msg_code from Python
        this.queue = null;
    }

    /**
     * Process incoming auto exposure result data packets.
     * @param data Uint8Array containing auto exposure result data with a msgCode byte prefix,
     * followed by 16 little-endian floats (64 bytes).
     */
    public handleData(data: Uint8Array): void {
        if (!this.queue) {
            console.warn("RxAutoExpResult: Received data but queue not initialized - call attach() first");
            return;
        }

        // Python: struct.unpack("<ffffff ff ffff ffff", data[1:65])
        // This means 16 little-endian floats, starting from index 1 of the data array.
        // data[0] is the msgCode. Data for floats is data[1] through data[64].
        // Total length required: 1 (msgCode) + 16 * 4 (floats) = 65 bytes.
        if (data.length < 65) {
            console.warn(`RxAutoExpResult: Data packet too short for auto exposure result data. Expected 65 bytes, got ${data.length}.`);
            return;
        }

        const dataView = new DataView(data.buffer, data.byteOffset, data.byteLength);
        const littleEndian = true;
        let offset = 1; // Start reading after the msgCode byte

        const unpacked: number[] = [];
        for (let i = 0; i < 16; i++) {
            unpacked.push(dataView.getFloat32(offset, littleEndian));
            offset += 4; // Each float is 4 bytes
        }

        const result: AutoExpResultData = {
            error: unpacked[0],
            shutter: unpacked[1],
            analog_gain: unpacked[2],
            red_gain: unpacked[3],
            green_gain: unpacked[4],
            blue_gain: unpacked[5],
            brightness: {
                center_weighted_average: unpacked[6],
                scene: unpacked[7],
                matrix: {
                    r: unpacked[8],
                    g: unpacked[9],
                    b: unpacked[10],
                    average: unpacked[11],
                },
                spot: {
                    r: unpacked[12],
                    g: unpacked[13],
                    b: unpacked[14],
                    average: unpacked[15],
                },
            },
        };

        this.queue.put(result);
    }

    /**
     * Attach the receive handler to the Frame data response.
     * @param frame The BrilliantMsg instance.
     * @returns A promise that resolves to an AsyncQueue that will receive AutoExpResultData objects.
     */
    public async attach(frame: BrilliantMsg): Promise<AsyncQueue<AutoExpResultData | null>> {
        this.queue = new AsyncQueue<AutoExpResultData | null>();

        // Subscribe for notifications
        frame.registerDataResponseHandler(
            this,
            [this.msgCode],
            this.handleData.bind(this)
        );

        return this.queue;
    }

    /**
     * Detach the receive handler from the Frame data response and clean up resources.
     * @param frame The BrilliantMsg instance.
     */
    public detach(frame: BrilliantMsg): void {
        frame.unregisterDataResponseHandler(this);
        if (this.queue) {
            this.queue.clear(); // Clear any pending items from AsyncQueue
        }
        this.queue = null;
    }
}