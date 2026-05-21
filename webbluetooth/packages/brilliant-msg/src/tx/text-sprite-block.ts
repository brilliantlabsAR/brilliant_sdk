import { TxSprite } from './sprite';

/**
 * Interface for TxTextSpriteBlock constructor options.
 */
export interface TxTextSpriteBlockOptions {
    /** Width constraint for text layout */
    width: number;
    /** Font size in pixels */
    fontSize: number;
    /** Line height in pixels (fixed height for each sprite) */
    lineHeight: number;
    /** Maximum number of lines to display */
    maxDisplayLines: number;
    /** Optional font family name. Defaults to 'sans-serif'. */
    fontFamily?: string;
}

/**
 * A block of text rendered as sprites, for use in a browser environment.
 */
export class TxTextSpriteBlock {
    /** The width constraint for the text layout, in pixels. */
    public width: number;
    /** The font size used for rendering the text, in pixels. */
    public fontSize: number;
    /** The fixed line height for each sprite, in pixels. */
    public lineHeight: number;
    /** The maximum number of lines of text to be displayed. */
    public maxDisplayLines: number;
    /** The font family used for rendering the text. */
    public fontFamily: string;

    /** An array of {@link TxSprite} instances, each representing a line of rendered text. */
    public sprites: TxSprite[] = [];

    /**
     * @param options Configuration options for the text sprite block.
     */
    constructor(options: TxTextSpriteBlockOptions) {
        this.width = options.width;
        this.fontSize = options.fontSize;
        this.lineHeight = options.lineHeight;
        this.maxDisplayLines = options.maxDisplayLines;
        this.fontFamily = options.fontFamily || 'sans-serif';
    }

    /**
     * Creates sprites from the rendered text using the browser's Canvas API.
     * Returns an array of TxSprite instances, one per line of text.
     * Each sprite has exactly lineHeight pixels in height and width pixels in width,
     * except blank lines which are 1×lineHeight.
     * @param text The text to render. Lines are split on '\n'.
     * @returns Array of TxSprite instances.
     */
    public createTextSprites(text: string): TxSprite[] {
        if (this.width <= 0 || this.lineHeight <= 0) {
            return [];
        }

        const inputTextLines = text.split('\n');
        const sprites: TxSprite[] = [];

        for (const lineText of inputTextLines) {
            if (lineText.trim() === '') {
                // Blank line: create a 1×lineHeight all-zeros sprite
                const blankSprite = new TxSprite({
                    width: 1,
                    height: this.lineHeight,
                    numColors: 2,
                    paletteData: new Uint8Array([0, 0, 0, 255, 255, 255]),
                    pixelData: new Uint8Array(this.lineHeight),
                    compress: false
                });
                sprites.push(blankSprite);
                continue;
            }

            // Create a canvas exactly width × lineHeight for this line
            const canvas = document.createElement('canvas');
            canvas.width = this.width;
            canvas.height = this.lineHeight;

            const ctx = canvas.getContext('2d', { willReadFrequently: true });
            if (!ctx) {
                console.error("TxTextSpriteBlock: Could not get 2D rendering context.");
                continue;
            }

            // Black background
            ctx.fillStyle = 'black';
            ctx.fillRect(0, 0, canvas.width, canvas.height);

            // White text
            ctx.fillStyle = 'white';
            ctx.font = `${this.fontSize}px ${this.fontFamily}`;
            ctx.textBaseline = 'alphabetic';

            // Place baseline at 80% of lineHeight from top
            const baselineY = Math.round(this.lineHeight * 0.8);
            ctx.fillText(lineText, 0, baselineY);

            // Read back the full lineWidth × lineHeight region
            const imageData = ctx.getImageData(0, 0, this.width, this.lineHeight);
            const { data } = imageData;
            const spritePixelData = new Uint8Array(this.width * this.lineHeight);

            for (let i = 0, j = 0; i < data.length; i += 4, j++) {
                spritePixelData[j] = (data[i] > 127) ? 1 : 0;
            }

            const lineSprite = new TxSprite({
                width: this.width,
                height: this.lineHeight,
                numColors: 2,
                paletteData: new Uint8Array([0, 0, 0, 255, 255, 255]),
                pixelData: spritePixelData,
                compress: false
            });
            sprites.push(lineSprite);
        }

        return sprites;
    }

    /**
     * Packs the text block header into a 6-byte binary format.
     * Format: 0xFF (1 byte) | width (uint16 BE) | lineHeight (uint16 BE) | maxDisplayLines (uint8)
     * @returns Uint8Array Binary representation of the text block header.
     */
    public pack(): Uint8Array {
        const buf = new Uint8Array(6);
        const view = new DataView(buf.buffer);
        view.setUint8(0, 0xFF);
        view.setUint16(1, this.width, false);
        view.setUint16(3, this.lineHeight, false);
        view.setUint8(5, this.maxDisplayLines & 0xFF);
        return buf;
    }
}
