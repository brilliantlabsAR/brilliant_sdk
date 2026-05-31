import { BrilliantMsg } from '../brilliant-msg';
import { AsyncQueue } from '../async-queue';

/**
 * Buffer class to provide smoothed moving average of samples.
 */
class SensorBuffer {
    private maxSize: number;
    private _buffer: Array<[number, number, number]>;

    constructor(maxSize: number) {
        this.maxSize = maxSize;
        this._buffer = [];
    }

    public add(value: [number, number, number]): void {
        this._buffer.push(value);
        if (this._buffer.length > this.maxSize) {
            this._buffer.shift(); // equivalent to pop(0)
        }
    }

    public get average(): [number, number, number] {
        if (!this._buffer.length) {
            return [0, 0, 0];
        }

        let sumX = 0;
        let sumY = 0;
        let sumZ = 0;

        for (const [x, y, z] of this._buffer) {
            sumX += x;
            sumY += y;
            sumZ += z;
        }

        const length = this._buffer.length;

        return [
            sumX / length,
            sumY / length,
            sumZ / length
        ];
    }
}

/**
 * Interface for raw IMU data.
 */
export interface IMURawData {
    /** Raw compass data as a tuple: `[x, y, z]`. */
    compass: [number, number, number];
    /** Raw accelerometer data as a tuple: `[x, y, z]`. */
    accel: [number, number, number];
}

/**
 * Class for processed IMU data.
 * Contains smoothed compass and accelerometer data, and optionally the raw data.
 * Also provides calculated pitch and roll values.
 */
export class IMUData {
    /** Smoothed compass data as a tuple: `[x, y, z]`. */
    public compass: [number, number, number];
    /** Smoothed accelerometer data as a tuple: `[x, y, z]`. */
    public accel: [number, number, number];
    /** Optional raw IMU data. */
    public raw?: IMURawData;

    /**
     * Constructs an instance of IMUData.
     * @param compass Smoothed compass data `[x, y, z]`.
     * @param accel Smoothed accelerometer data `[x, y, z]`.
     * @param raw Optional raw IMU data.
     */
    constructor(compass: [number, number, number], accel: [number, number, number], raw?: IMURawData) {
        this.compass = compass;
        this.accel = accel;
        this.raw = raw;
    }

    /** Calculated pitch in degrees. */
    public get pitch(): number {
        return Math.atan2(this.accel[1], this.accel[2]) * 180.0 / Math.PI;
    }

    /** Calculated roll in degrees. */
    public get roll(): number {
        return Math.atan2(this.accel[0], this.accel[2]) * 180.0 / Math.PI;
    }
}

/**
 * Options for RxIMU constructor.
 */
export interface RxIMUOptions {
    /** Optional msgCode to identify IMU data packets. Defaults to 0x0A. */
    msgCode?: number;
    /** Optional number of samples to average for smoothing. Defaults to 1 (no smoothing). */
    smoothingSamples?: number;
}

/**
 * RxIMU class handles IMU data processing.
 * It processes magnetometer and accelerometer data, providing smoothed values.
 */
export class RxIMU {
    private msgCode: number;
    private smoothingSamples: number;

    /** Asynchronous queue for received IMUData objects. Null if not attached. */
    public queue: AsyncQueue<IMUData | null> | null;
    private compassBuffer: SensorBuffer;
    private accelBuffer: SensorBuffer;

    /**
     * Constructs an instance of the RxIMU class.
     * @param options Configuration options for the IMU handler.
     */
    constructor(options: RxIMUOptions = {}) {
        this.msgCode = options.msgCode ?? 0x0A; //
        this.smoothingSamples = options.smoothingSamples ?? 1; //

        this.queue = null;
        this.compassBuffer = new SensorBuffer(this.smoothingSamples); //
        this.accelBuffer = new SensorBuffer(this.smoothingSamples); //
    }

    /**
     * Process incoming IMU data packets.
     * @param data Uint8Array containing IMU data with msgCode byte prefix.
     */
    public handleData(data: Uint8Array): void { //
        if (!this.queue) {
            console.warn("RxIMU: Received data but queue not initialized - call attach() first"); //
            return;
        }

        // Data is expected to be: [msgCode, padding, f32, f32, f32, f32, f32, f32]
        // 6 32-bit little-endian floats starting at byte offset 2
        if (data.length < 26) {
            console.warn("RxIMU: Data packet too short for IMU float data.");
            return;
        }
        const view = new DataView(data.buffer, data.byteOffset);
        const cX = view.getFloat32(2, true);
        const cY = view.getFloat32(6, true);
        const cZ = view.getFloat32(10, true);
        const aX = view.getFloat32(14, true);
        const aY = view.getFloat32(18, true);
        const aZ = view.getFloat32(22, true);

        const rawCompass: [number, number, number] = [cX, cY, cZ];
        const rawAccel: [number, number, number] = [aX, aY, aZ];

        this.compassBuffer.add(rawCompass); //
        this.accelBuffer.add(rawAccel); //

        const imuData = new IMUData(
            this.compassBuffer.average, //
            this.accelBuffer.average, //
            {
                compass: rawCompass,
                accel: rawAccel
            }
        );

        this.queue.put(imuData); //
    }

    /**
     * Attach the IMU handler to the Frame data response.
     * @param frame The BrilliantMsg instance.
     * @returns A promise that resolves to an AsyncQueue that will receive IMUData objects.
     */
    public async attach(frame: BrilliantMsg): Promise<AsyncQueue<IMUData | null>> {
        this.queue = new AsyncQueue<IMUData | null>(); //

        // Subscribe for notifications
        frame.registerDataResponseHandler(
            this,
            [this.msgCode],
            this.handleData.bind(this)
        );

        return this.queue;
    }

    /**
     * Detach the IMU handler from the Frame data response and clean up resources.
     * @param frame The BrilliantMsg instance.
     */
    public detach(frame: BrilliantMsg): void {
        frame.unregisterDataResponseHandler(this);
        if (this.queue) {
            this.queue.clear();
        }
        this.queue = null;
    }
}