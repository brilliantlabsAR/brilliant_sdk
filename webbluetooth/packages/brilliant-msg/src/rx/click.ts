import { FrameMsg } from '../frame-msg';
import { AsyncQueue } from '../async-queue';

/**
 * Enum representing the types of tap/click detected by the Frame device.
 */
export enum ClickType {
    /** A single tap/click. */
    SINGLE = 1,
    /** A double tap/click. */
    DOUBLE = 2,
    /** A long press. */
    LONG = 3,
}

/**
 * Options for RxClick constructor.
 */
export interface RxClickOptions {
    /** Optional msgCode to identify click data packets. Defaults to 0x0B. */
    clickFlag?: number;
}

/**
 * RxClick handles incoming tap/click events from the Frame device.
 * It processes raw BLE data and enqueues typed ClickType values.
 */
export class RxClick {
    private clickFlag: number;

    /** Asynchronous queue for received ClickType values. Null if not attached. */
    public queue: AsyncQueue<ClickType | null> | null;

    /**
     * Constructs an instance of the RxClick class.
     * @param options Configuration options for the click handler.
     */
    constructor(options: RxClickOptions = {}) {
        this.clickFlag = options.clickFlag ?? 0x0B;
        this.queue = null;
    }

    /**
     * Process incoming click data packets.
     * @param data Uint8Array containing click data: [clickFlag, clickType].
     */
    public handleData(data: Uint8Array): void {
        if (!this.queue) {
            console.warn("RxClick: Received data but queue not initialized - call attach() first");
            return;
        }

        if (data.length < 2) {
            console.warn("RxClick: Data packet too short for click data.");
            return;
        }

        const clickType = data[1];
        switch (clickType) {
            case 1:
                this.queue.put(ClickType.SINGLE);
                break;
            case 2:
                this.queue.put(ClickType.DOUBLE);
                break;
            case 3:
                this.queue.put(ClickType.LONG);
                break;
            default:
                console.warn(`RxClick: Unknown click type ${clickType}`);
        }
    }

    /**
     * Attach the click handler to the Frame data response.
     * @param frame The FrameMsg instance.
     * @returns A promise that resolves to an AsyncQueue that will receive ClickType values.
     */
    public async attach(frame: FrameMsg): Promise<AsyncQueue<ClickType | null>> {
        this.queue = new AsyncQueue<ClickType | null>();

        frame.registerDataResponseHandler(
            this,
            [this.clickFlag],
            this.handleData.bind(this)
        );

        return this.queue;
    }

    /**
     * Detach the click handler from the Frame data response and clean up resources.
     * @param frame The FrameMsg instance.
     */
    public detach(frame: FrameMsg): void {
        frame.unregisterDataResponseHandler(this);
        if (this.queue) {
            this.queue.clear();
        }
        this.queue = null;
    }
}
