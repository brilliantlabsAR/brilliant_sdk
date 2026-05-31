import { BrilliantMsg } from '../brilliant-msg';
import { AsyncQueue } from '../async-queue';

/**
 * Interface for the structured metering data.
 */
export interface MeteringData {
    /** Spot metering red channel value. */
    spot_r: number;
    /** Spot metering green channel value. */
    spot_g: number;
    /** Spot metering blue channel value. */
    spot_b: number;
    /** Matrix metering red channel value. */
    matrix_r: number;
    /** Matrix metering green channel value. */
    matrix_g: number;
    /** Matrix metering blue channel value. */
    matrix_b: number;
}

/**
 * Options for RxMeteringData constructor.
 */
export interface RxMeteringDataOptions {
    /** Optional message code to identify metering data packets. Defaults to 0x12. */
    msgCode?: number;
}

/**
 * RxMeteringData class handles processing of metering data packets.
 */
export class RxMeteringData {
    private msgCode: number;
    /** Asynchronous queue for received MeteringData objects. Null if not attached. */
    public queue: AsyncQueue<MeteringData | null> | null;

    /**
     * Constructs an instance of the RxMeteringData class.
     * @param options Configuration options for the metering data handler.
     */
    constructor(options: RxMeteringDataOptions = {}) {
        this.msgCode = options.msgCode ?? 0x12; // Default msg_code from Python
        this.queue = null;
    }

    /**
     * Process incoming metering data packets.
     * @param data Uint8Array containing metering data with a msgCode byte prefix,
     * followed by 6 unsigned bytes (spot r,g,b, matrix r,g,b).
     */
    public handleData(data: Uint8Array): void {
        if (!this.queue) {
            console.warn("RxMeteringData: Received data but queue not initialized - call attach() first");
            return;
        }

        // Python: struct.unpack("<BBBBBB", data[1:7])
        // This means 6 unsigned bytes starting from index 1 of the data array.
        // data[0] is the msgCode, data[1] through data[6] are the values.
        if (data.length < 7) { // Needs 1 byte for msgCode + 6 bytes for data
            console.warn("RxMeteringData: Data packet too short for metering data.");
            return;
        }

        const result: MeteringData = {
            spot_r: data[1],    // unpacked[0]
            spot_g: data[2],    // unpacked[1]
            spot_b: data[3],    // unpacked[2]
            matrix_r: data[4],  // unpacked[3]
            matrix_g: data[5],  // unpacked[4]
            matrix_b: data[6],  // unpacked[5]
        };

        this.queue.put(result);
    }

    /**
     * Attach the receive handler to the Frame data response.
     * @param frame The BrilliantMsg instance.
     * @returns A promise that resolves to an AsyncQueue that will receive MeteringData objects.
     */
    public async attach(frame: BrilliantMsg): Promise<AsyncQueue<MeteringData | null>> {
        this.queue = new AsyncQueue<MeteringData | null>();

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
            this.queue.clear(); // Clear any pending items
        }
        this.queue = null;
    }
}