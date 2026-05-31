import type { ITerminal } from './ITerminal';
/**
 * The set of characters used to draw table borders.
 *
 * Visual reference (default Unicode box-drawing characters):
 * ```
 * ┌─────────┬─────────┐  ← topLeft, top (fill), topCenter, topRight
 * │ header  │ header  │  ← left, verticalCenter, right
 * ├─────────┼─────────┤  ← leftCenter, horizontalCenter (fill), centerCenter, rightCenter
 * │ data    │ data    │  ← left, verticalCenter, right
 * └─────────┴─────────┘  ← bottomLeft, bottom (fill), bottomCenter, bottomRight
 * ```
 *
 * @public
 */
export interface ITerminalTableChars {
    /** Fill character for the top border row. Default: `─` */
    top: string;
    /** Junction where a column divider meets the top border. Default: `┬` */
    topCenter: string;
    /** Top-left corner. Default: `┌` */
    topLeft: string;
    /** Top-right corner. Default: `┐` */
    topRight: string;
    /** Fill character for the bottom border row. Default: `─` */
    bottom: string;
    /** Junction where a column divider meets the bottom border. Default: `┴` */
    bottomCenter: string;
    /** Bottom-left corner. Default: `└` */
    bottomLeft: string;
    /** Bottom-right corner. Default: `┘` */
    bottomRight: string;
    /** Left border character for data rows. Default: `│` */
    left: string;
    /** Left end of the header/body separator row. Default: `├` */
    leftCenter: string;
    /** Fill character for the header/body separator row. Default: `─` */
    horizontalCenter: string;
    /** Junction where a column divider crosses the header/body separator. Default: `┼` */
    centerCenter: string;
    /** Right border character for data rows. Default: `│` */
    right: string;
    /** Right end of the header/body separator row. Default: `┤` */
    rightCenter: string;
    /** Column separator character within data rows. Default: `│` */
    verticalCenter: string;
}
/**
 * Options for {@link TerminalTable}.
 *
 * @public
 */
export interface ITerminalTableOptions {
    /**
     * Column header labels.
     */
    head?: string[];
    /**
     * Fixed column widths in characters, including one character of padding on each side.
     * Columns not listed default to auto-sizing based on content.
     */
    colWidths?: number[];
    /**
     * If `true`, all border and separator lines are suppressed. Columns are visually
     * separated only by the built-in one-character left-padding of each cell.
     * This is a convenient shorthand for setting every entry in `chars` to `''`.
     */
    borderless?: boolean;
    /**
     * Overrides for individual border characters.
     * Pass an empty string for any character to suppress that part of the border.
     * Applied after `borderless`, so individual characters can be restored even in
     * borderless mode.
     */
    borderCharacters?: Partial<ITerminalTableChars>;
    /**
     * A function to apply styling to all border and grid line characters.
     *
     * @example
     * ```typescript
     * import { Colorize } from '@rushstack/terminal';
     * new TerminalTable({ borderColor: Colorize.gray })
     * ```
     */
    borderColor?: (text: string) => string;
    /**
     * A function to apply styling to the text within header row cells.
     *
     * @example
     * ```typescript
     * import { Colorize } from '@rushstack/terminal';
     * new TerminalTable({ headingColor: Colorize.bold })
     * ```
     */
    headingColor?: (text: string) => string;
}
/**
 * Renders text data as a fixed-column table suitable for terminal output.
 *
 * @example
 * ```typescript
 * const table = new TerminalTable({ head: ['Name', 'Version'] });
 * table.push(['@rushstack/terminal', '1.0.0']);
 * table.push(['@rushstack/heft', '2.0.0']);
 * console.log(table.toString());
 * ```
 *
 * @public
 */
export declare class TerminalTable {
    private readonly _head;
    private readonly _specifiedColWidths;
    private readonly _borderCharacters;
    private readonly _borderColor;
    private readonly _headingColor;
    private readonly _rows;
    constructor(options?: ITerminalTableOptions);
    /**
     * Appends one or more rows to the table.
     */
    push(...rows: string[][]): void;
    getLines(): string[];
    /**
     * Renders the table to a string.
     */
    toString(): string;
    /**
     * Writes the rendered table to the provided terminal, one line at a time.
     */
    printToTerminal(terminal: ITerminal): void;
}
//# sourceMappingURL=TerminalTable.d.ts.map