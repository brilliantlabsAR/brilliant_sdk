import { TxSprite } from './sprite';
import UPNG from '@pdf-lib/upng';

/**
 * Abstract interface for defining the geometry of a text layout area.
 * This allows for different shapes like rectangles and circles.
 */
export interface TextLayout {
    /** The width of the layout in pixels. */
    width: number;
    /** The height of the layout in pixels. */
    height: number;
    /** The font size in pixels. */
    fontSize: number;
    /** Optional font family name. */
    fontFamily?: string;
    /** Text alignment within each line. */
    textAlign: CanvasTextAlign;
    /** The starting Y coordinate for laying out text. */
    readonly startY: number;
    /**
     * Gets the layout parameters (width and x-offset) for a line at a specific Y position.
     * Returns null if the line is outside the displayable area.
     */
    getLineLayout(lineY: number, lineHeight: number): { width: number; xOffset: number } | null;
}

/**
 * A standard rectangular text layout.
 */
export class RectangularTextLayout implements TextLayout {
    public width: number;
    public height: number;
    public fontSize: number;
    public fontFamily?: string;
    public textAlign: CanvasTextAlign;

    /**
     * Constructs a RectangularTextLayout.
     * @param options Configuration options.
     */
    constructor(options: {
        width: number;
        height: number;
        fontSize: number;
        fontFamily?: string;
        textAlign?: CanvasTextAlign;
    }) {
        this.width = options.width;
        this.height = options.height;
        this.fontSize = options.fontSize;
        this.fontFamily = options.fontFamily;
        this.textAlign = options.textAlign ?? 'left';
    }

    /** The starting Y coordinate for text layout (always 0 for rectangular). */
    get startY(): number {
        return 0;
    }

    /**
     * Returns the full width at xOffset 0 if the line fits vertically, null otherwise.
     */
    getLineLayout(lineY: number, lineHeight: number): { width: number; xOffset: number } | null {
        if (lineY < 0 || lineY + lineHeight > this.height) {
            return null;
        }
        return { width: this.width, xOffset: 0 };
    }
}

/**
 * A circular text layout, ideal for the Halo device.
 * Text is constrained within a circle inscribed in the defined width/height.
 */
export class CircularTextLayout implements TextLayout {
    public width: number;
    public height: number;
    public fontSize: number;
    public fontFamily?: string;
    public textAlign: CanvasTextAlign;
    public circleMargin: number;
    public readonly radius: number;
    public readonly centerX: number;
    public readonly centerY: number;

    /**
     * Constructs a CircularTextLayout.
     * @param options Configuration options.
     */
    constructor(options: {
        width: number;
        height: number;
        fontSize: number;
        circleMargin?: number;
        fontFamily?: string;
        textAlign?: CanvasTextAlign;
    }) {
        this.width = options.width;
        this.height = options.height;
        this.fontSize = options.fontSize;
        this.circleMargin = options.circleMargin ?? 15;
        this.fontFamily = options.fontFamily;
        this.textAlign = options.textAlign ?? 'center';

        this.radius = Math.min(this.width, this.height) / 2 - this.circleMargin;
        this.centerX = this.width / 2;
        this.centerY = this.height / 2;
    }

    /** The starting Y coordinate for text layout (top of the inscribed circle). */
    get startY(): number {
        return this.centerY - this.radius;
    }

    /**
     * Returns the chord width and x-offset for a line at the given Y position within the circle.
     * Returns null if the line is outside the circle or too narrow to render text.
     */
    getLineLayout(lineY: number, lineHeight: number): { width: number; xOffset: number } | null {
        // Calculate the vertical distance from the center to the middle of the line.
        const distFromCenter = (lineY + lineHeight / 2) - this.centerY;

        if (Math.abs(distFromCenter) > this.radius) {
            return null; // Line is completely outside the circle.
        }

        // Use the Pythagorean theorem to calculate the half-width of the chord at this y-position.
        const halfWidth = Math.sqrt(this.radius * this.radius - distFromCenter * distFromCenter);
        const lineWidth = Math.floor(halfWidth * 2);
        const xOffset = Math.floor(this.centerX - halfWidth);

        // Avoid rendering text on very narrow lines near the top/bottom of the circle.
        if (lineWidth < this.fontSize) return null;

        return { width: lineWidth, xOffset };
    }
}

/**
 * Options for TxTextPage constructor.
 */
export interface TxTextPageOptions {
    /** The layout to use for text rendering. */
    layout: TextLayout;
    /** The text to render. */
    text: string;
}

/** Internal data class for a measured line of text. */
interface LineData {
    text: string;
    width: number;
    xOffset: number;
    yOffset: number;
    lineHeight: number;
}

/**
 * Represents a single, measured page of text that is ready to be rasterized into sprites.
 */
export class PageData {
    private _lines: LineData[];
    private _layout: TextLayout;
    private _sprites: TxSprite[] = [];
    private _isRasterizing = false;

    /** @internal */
    constructor(lines: LineData[], layout: TextLayout) {
        this._lines = lines;
        this._layout = layout;
    }

    /** Returns true if the page contains no lines. */
    get isEmpty(): boolean {
        return this._lines.length === 0;
    }

    /** Returns true if the page has been rasterized into sprites. */
    get isRasterized(): boolean {
        return this._sprites.length > 0;
    }

    /** The rasterized sprites, one per line. Only valid after rasterize() has been called. */
    get rasterizedSprites(): TxSprite[] {
        return this._sprites;
    }

    /** The text for each measured line. */
    get lineTexts(): string[] {
        return this._lines.map(l => l.text);
    }

    /**
     * Rasterizes the measured lines into TxSprite objects (one per line) using
     * 1-bit monochrome rendering via the Canvas 2D API.
     */
    async rasterize(): Promise<void> {
        if (this.isRasterized || this._isRasterizing) return;

        this._isRasterizing = true;
        try {
            const fontSpec = `${this._layout.fontSize}px ${this._layout.fontFamily ?? 'sans-serif'}`;

            for (const lineData of this._lines) {
                if (!lineData.text || lineData.lineHeight <= 0 || lineData.width <= 0) {
                    continue;
                }

                const canvas = document.createElement('canvas');
                canvas.width = lineData.width;
                canvas.height = lineData.lineHeight;

                const ctx = canvas.getContext('2d', { willReadFrequently: true });
                if (!ctx) {
                    console.error("TxTextPage: Could not get 2D rendering context.");
                    continue;
                }

                // Black background
                ctx.fillStyle = 'black';
                ctx.fillRect(0, 0, canvas.width, canvas.height);

                // White text
                ctx.fillStyle = 'white';
                ctx.font = fontSpec;
                ctx.textAlign = this._layout.textAlign;
                ctx.textBaseline = 'alphabetic';

                // Baseline at ~80% of lineHeight
                const baselineY = Math.round(lineData.lineHeight * 0.8);

                // Horizontal anchor for textAlign
                let textX: number;
                switch (this._layout.textAlign) {
                    case 'center':
                        textX = lineData.width / 2;
                        break;
                    case 'right':
                    case 'end':
                        textX = lineData.width;
                        break;
                    default:
                        textX = 0;
                }

                ctx.fillText(lineData.text, textX, baselineY);

                const imageData = ctx.getImageData(0, 0, lineData.width, lineData.lineHeight);
                const { data } = imageData;
                const spritePixelData = new Uint8Array(lineData.width * lineData.lineHeight);

                for (let i = 0, j = 0; i < data.length; i += 4, j++) {
                    spritePixelData[j] = data[i] >= 128 ? 1 : 0;
                }

                const sprite = new TxSprite({
                    width: lineData.width,
                    height: lineData.lineHeight,
                    numColors: 2,
                    paletteData: new Uint8Array([0, 0, 0, 255, 255, 255]),
                    pixelData: spritePixelData,
                    compress: false,
                });

                this._sprites.push(sprite);
            }
        } finally {
            this._isRasterizing = false;
        }
    }

    /**
     * Composes all rasterized sprites into a single layout.width × layout.height canvas
     * and returns a PNG as a Uint8Array.
     * Calls rasterize() first if not already done.
     */
    async toPngBytes(): Promise<Uint8Array> {
        if (!this.isRasterized) {
            await this.rasterize();
        }

        const layout = this._layout;
        const totalPixels = layout.width * layout.height;
        const rgba = new Uint8Array(totalPixels * 4);
        // Transparent background
        for (let i = 0; i < totalPixels; i++) {
            rgba[i * 4 + 3] = 0; // alpha = 0
        }

        for (let i = 0; i < this._sprites.length; i++) {
            const sprite = this._sprites[i];
            const line = this._lines[i];
            const palette = sprite.paletteData;

            for (let py = 0; py < sprite.height; py++) {
                for (let px = 0; px < sprite.width; px++) {
                    const srcIdx = py * sprite.width + px;
                    const palIdx = sprite.pixelData[srcIdx];
                    const dstX = line.xOffset + px;
                    const dstY = line.yOffset + py;

                    if (dstX < 0 || dstX >= layout.width || dstY < 0 || dstY >= layout.height) {
                        continue;
                    }

                    const dstIdx = (dstY * layout.width + dstX) * 4;
                    rgba[dstIdx]     = palette[palIdx * 3];
                    rgba[dstIdx + 1] = palette[palIdx * 3 + 1];
                    rgba[dstIdx + 2] = palette[palIdx * 3 + 2];
                    rgba[dstIdx + 3] = 255;
                }
            }
        }

        const pngBuffer = UPNG.encode([rgba.buffer], layout.width, layout.height, 0);
        return new Uint8Array(pngBuffer);
    }

    /**
     * Packs the page layout data for transmission to the device.
     * Must be called after rasterize().
     * Format:
     *   0xFF (1 byte)
     *   layout.width  (2 bytes, big-endian)
     *   layout.height (2 bytes, big-endian)
     *   numSprites    (1 byte)
     *   [xOffset_h, xOffset_l, yOffset_h, yOffset_l] * numSprites
     */
    pack(): Uint8Array {
        if (!this.isRasterized) {
            throw new Error('PageData must be rasterized before packing.');
        }

        const numSprites = this._sprites.length;
        const buf = new Uint8Array(6 + numSprites * 4);
        buf[0] = 0xFF;
        buf[1] = this._layout.width >> 8;
        buf[2] = this._layout.width & 0xFF;
        buf[3] = this._layout.height >> 8;
        buf[4] = this._layout.height & 0xFF;
        buf[5] = numSprites & 0xFF;

        for (let i = 0; i < numSprites; i++) {
            const line = this._lines[i];
            buf[6 + i * 4]     = line.xOffset >> 8;
            buf[6 + i * 4 + 1] = line.xOffset & 0xFF;
            buf[6 + i * 4 + 2] = line.yOffset >> 8;
            buf[6 + i * 4 + 3] = line.yOffset & 0xFF;
        }

        return buf;
    }
}

/**
 * Manages the process of laying out and rasterizing text into pages.
 * It works with any TextLayout to support different display shapes.
 */
export class TxTextPage {
    /** The layout used for text rendering. */
    public readonly layout: TextLayout;
    /** The full original text. */
    public readonly text: string;

    private _remainingText: string;

    /**
     * Constructs an instance of TxTextPage.
     * @param options Configuration options.
     */
    constructor(options: TxTextPageOptions) {
        this.layout = options.layout;
        this.text = options.text;
        this._remainingText = options.text.trim();
    }

    /** The portion of the text that has not yet been processed into a page. */
    get remainingText(): string {
        return this._remainingText;
    }

    /** Returns true if there is more text to be laid out. */
    get hasMoreText(): boolean {
        return this._remainingText.length > 0;
    }

    /**
     * Measures the next page of text using the Canvas 2D API and returns a PageData
     * without rasterizing any sprites.
     * Returns null if there is no remaining text or if no text fits on the page.
     */
    async measureNextPage(): Promise<PageData | null> {
        if (!this._remainingText) return null;

        const layout = this.layout;
        const estimatedLineHeight = layout.fontSize * 1.4;
        const fontSpec = `${layout.fontSize}px ${layout.fontFamily ?? 'sans-serif'}`;

        // Create a temporary canvas just for measurement.
        const canvas = document.createElement('canvas');
        canvas.width = layout.width;
        canvas.height = layout.height;
        const ctx = canvas.getContext('2d');
        if (!ctx) {
            console.error("TxTextPage: Could not get 2D rendering context for measurement.");
            return null;
        }
        ctx.font = fontSpec;

        const lines: LineData[] = [];
        let textToLayout = this._remainingText;
        let currentY = layout.startY;

        while (textToLayout.length > 0 && currentY < layout.height) {
            const lineLayout = layout.getLineLayout(currentY, estimatedLineHeight);

            if (lineLayout === null) {
                // Outside the drawable area — page is done.
                break;
            }

            const { width: availableWidth, xOffset } = lineLayout;

            // Word-wrap: fill the current line greedily at word boundaries.
            const words = textToLayout.split(/\s+/).filter(w => w.length > 0);
            if (words.length === 0) {
                // Only whitespace left — consume it and stop.
                textToLayout = '';
                break;
            }

            let lineFit = '';
            let wordIdx = 0;

            // Build the longest word-wrapped line that fits within availableWidth.
            for (; wordIdx < words.length; wordIdx++) {
                const candidate = lineFit.length === 0
                    ? words[wordIdx]
                    : lineFit + ' ' + words[wordIdx];

                const measured = ctx.measureText(candidate).width;
                if (measured > availableWidth) {
                    if (lineFit.length === 0) {
                        // Single word is too wide — include it anyway to prevent an infinite loop.
                        lineFit = words[wordIdx];
                        wordIdx++;
                    }
                    break;
                }
                lineFit = candidate;
                // Check whether there is actually more text after this word
                // that we may be able to include on the next line.
            }

            if (lineFit.length > 0) {
                lines.push({
                    text: lineFit,
                    width: availableWidth,
                    xOffset,
                    yOffset: Math.round(currentY),
                    lineHeight: Math.round(estimatedLineHeight),
                });
            }

            currentY += estimatedLineHeight;

            // Consume the words placed on this line from textToLayout.
            // Rebuild remaining text from words not yet placed.
            // wordIdx now points to the first word NOT placed on this line.
            const remainingWords = words.slice(wordIdx);
            // Also need to account for any leading whitespace in the original textToLayout
            // by searching for the end of the placed words in the original string.
            if (remainingWords.length > 0) {
                // Find the start of the first remaining word in the original text.
                const firstRemainingWord = remainingWords[0];
                // Build a search string from placed words to locate the split point.
                // Use the placed words to compute the consumed prefix length.
                const placedWords = words.slice(0, wordIdx);
                const placedText = placedWords.join(' ');
                // Find end of placedText in textToLayout (it may have different whitespace).
                const placedIdx = textToLayout.indexOf(firstRemainingWord, placedText.length > 0
                    ? textToLayout.indexOf(placedWords[placedWords.length - 1]) + placedWords[placedWords.length - 1].length
                    : 0
                );
                if (placedIdx !== -1) {
                    textToLayout = textToLayout.substring(placedIdx);
                } else {
                    textToLayout = remainingWords.join(' ');
                }
            } else {
                textToLayout = '';
            }
        }

        if (lines.length === 0 && this._remainingText.length > 0) {
            // No text fit — consume remaining to avoid an infinite loop.
            this._remainingText = textToLayout;
            return null;
        }

        this._remainingText = textToLayout;
        return new PageData(lines, layout);
    }

    /**
     * Measures and rasterizes the next page in one call.
     * Returns null if there is no remaining text or nothing fit on the page.
     */
    async rasterizeNextPage(): Promise<PageData | null> {
        const page = await this.measureNextPage();
        if (page) {
            await page.rasterize();
        }
        return page;
    }
}
