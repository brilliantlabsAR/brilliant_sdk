import { BrilliantMsg } from '../brilliant-msg';
import { AsyncQueue } from '../async-queue';

/**
 * Configuration options for the RxTap class.
 */
export interface RxTapOptions {
    /**
     * Optional msgCode byte used to identify tap event packets received from the Frame device.
     * Defaults to 0x09.
     */
    msgCode?: number;
    /**
     * Optional time window in seconds within which multiple taps are counted as a single event.
     * Defaults to 0.3 seconds.
     */
    threshold?: number;
}

/**
 * RxTap class handles tap events from the device.
 * It counts the number of taps within a specified threshold time.
 * It uses a queue to manage tap events and provides methods to attach and detach from a BrilliantMsg instance.
 * It also debounces taps that occur too close together (40ms).
 * The tap count is reset if no taps are detected within the threshold time.
 */
export class RxTap {
    private msgCode: number;
    private threshold: number; // in milliseconds
    /** Asynchronous queue for tap count events. Each event is a number representing the count of taps. Null if not attached. */
    public queue: AsyncQueue<number> | null;
    private lastTapTime: number;
    private tapCount: number;
    private thresholdTimeoutId: NodeJS.Timeout | null;

    /**
     * Constructs an instance of the RxTap class.
     * @param options Configuration options for the tap handler.
     *                Includes `msgCode` (default: 0x09) and `threshold` in seconds (default: 0.3).
     */
    constructor(options: RxTapOptions = {}) {
        this.msgCode = options.msgCode ?? 0x09;
        this.threshold = (options.threshold ?? 0.3) * 1000; // Convert seconds to milliseconds
        this.queue = null;
        this.lastTapTime = 0;
        this.tapCount = 0;
        this.thresholdTimeoutId = null;
    }

    private async resetThresholdTimer(): Promise<void> {
        if (this.thresholdTimeoutId) {
            clearTimeout(this.thresholdTimeoutId);
            this.thresholdTimeoutId = null;
        }

        this.thresholdTimeoutId = setTimeout(() => {
            this.thresholdTimeout();
        }, this.threshold);
    }

    private thresholdTimeout(): void {
        if (this.queue && this.tapCount > 0) {
            this.queue.put(this.tapCount);
            this.tapCount = 0;
        }
        this.thresholdTimeoutId = null; // Clear the timeout ID after execution
    }

    /**
     * Handles incoming tap event data packets.
     * This method is typically called by a `BrilliantMsg` instance when a tap event is received.
     * It debounces rapid taps and counts taps within a defined threshold.
     * The accumulated tap count is placed onto the `queue` when the threshold timer expires.
     * @param data A Uint8Array containing the tap event data: the msgCode byte,
     *             optionally followed by a kind byte (1=single, 2=double,
     *             3=triple) on Halo firmware 0.8.8+.
     */
    public handleData(data: Uint8Array): void {
        if (!this.queue) {
            console.warn("RxTap: Received data but queue not initialized - call attach() first");
            return;
        }

        // Halo (firmware 0.8.8+) detects multi-taps natively: one message per
        // gesture carrying the kind, so no timing aggregation is needed.
        if (data.length >= 2 && data[1] >= 1 && data[1] <= 3) {
            this.queue.put(data[1]);
            return;
        }

        // Frame sends a bare flag byte per tap: aggregate by timing.
        const currentTime = Date.now(); // Use milliseconds for timing

        // Debounce taps that occur too close together (40ms)
        if (currentTime - this.lastTapTime < 40) { // 40ms
            this.lastTapTime = currentTime;
            return;
        }

        this.lastTapTime = currentTime;
        this.tapCount += 1;

        // Reset the threshold timer
        this.resetThresholdTimer();
    }

    /**
     * Attaches this RxTap instance to a BrilliantMsg object to receive tap event data.
     * It initializes the tap event queue and registers a handler for incoming data.
     * @param frame The BrilliantMsg instance to attach to.
     * @returns A Promise that resolves to the `AsyncQueue` where tap counts (number) will be placed.
     */
    public async attach(frame: BrilliantMsg): Promise<AsyncQueue<number>> {
        this.queue = new AsyncQueue<number>();
        this.lastTapTime = 0;
        this.tapCount = 0;

        // Ensure the handler is bound to `this` context of the RxTap instance
        frame.registerDataResponseHandler(this, [this.msgCode], this.handleData.bind(this));

        return this.queue;
    }

    /**
     * Detaches this RxTap instance from a BrilliantMsg object.
     * It unregisters the data handler, clears any active timers, and clears the event queue.
     * @param frame The BrilliantMsg instance to detach from.
     */
    public detach(frame: BrilliantMsg): void {
        frame.unregisterDataResponseHandler(this);
        if (this.thresholdTimeoutId) {
            clearTimeout(this.thresholdTimeoutId);
            this.thresholdTimeoutId = null;
        }
        if (this.queue) {
            this.queue.clear(); // Clear any pending items in the queue
        }
        this.queue = null;
        this.tapCount = 0;
    }
}