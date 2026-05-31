import type { ITerminal } from './ITerminal';
/**
 * Options for {@link PrintUtilities.(printMessageInBox:1)}.
 *
 * @public
 */
export interface IPrintMessageInBoxOptions {
    /**
     * The width of the box in characters. Defaults to half of the console width.
     */
    boxWidth?: number;
    /**
     * A function to apply styling to the box border characters.
     *
     * @example
     * ```typescript
     * import { Colorize } from '@rushstack/terminal';
     * PrintUtilities.printMessageInBox('Hello!', terminal, { borderColor: Colorize.cyan })
     * ```
     */
    borderColor?: (text: string) => string;
    /**
     * A function to apply styling to the message text inside the box.
     *
     * @example
     * ```typescript
     * import { Colorize } from '@rushstack/terminal';
     * PrintUtilities.printMessageInBox('Hello!', terminal, { messageColor: Colorize.bold })
     * ```
     */
    messageColor?: (text: string) => string;
}
/**
 * A sensible fallback column width for consoles.
 *
 * @public
 */
export declare const DEFAULT_CONSOLE_WIDTH: number;
/**
 * A collection of utilities for printing messages to the console.
 *
 * @public
 */
export declare class PrintUtilities {
    /**
     * Returns the width of the console, measured in columns
     */
    static getConsoleWidth(): number | undefined;
    /**
     * Applies word wrapping.
     *
     * @param text - The text to wrap
     * @param maxLineLength - The maximum length of a line, defaults to the console width
     * @param indent - The number of spaces to indent the wrapped lines, defaults to 0
     */
    static wrapWords(text: string, maxLineLength?: number, indent?: number): string;
    /**
     * Applies word wrapping.
     *
     * @param text - The text to wrap
     * @param maxLineLength - The maximum length of a line, defaults to the console width
     * @param linePrefix - The string to prefix each line with, defaults to ''
     */
    static wrapWords(text: string, maxLineLength?: number, linePrefix?: string): string;
    /**
     * Applies word wrapping.
     *
     * @param text - The text to wrap
     * @param maxLineLength - The maximum length of a line, defaults to the console width
     * @param indentOrLinePrefix - The number of spaces to indent the wrapped lines or the string to prefix
     * each line with, defaults to no prefix
     */
    static wrapWords(text: string, maxLineLength?: number, indentOrLinePrefix?: number | string): string;
    /**
     * Applies word wrapping and returns an array of lines.
     *
     * @param text - The text to wrap
     * @param maxLineLength - The maximum length of a line, defaults to the console width
     * @param indent - The number of spaces to indent the wrapped lines, defaults to 0
     */
    static wrapWordsToLines(text: string, maxLineLength?: number, indent?: number): string[];
    /**
     * Applies word wrapping and returns an array of lines.
     *
     * @param text - The text to wrap
     * @param maxLineLength - The maximum length of a line, defaults to the console width
     * @param linePrefix - The string to prefix each line with, defaults to ''
     */
    static wrapWordsToLines(text: string, maxLineLength?: number, linePrefix?: string): string[];
    /**
     * Applies word wrapping and returns an array of lines.
     *
     * @param text - The text to wrap
     * @param maxLineLength - The maximum length of a line, defaults to the console width
     * @param indentOrLinePrefix - The number of spaces to indent the wrapped lines or the string to prefix
     * each line with, defaults to no prefix
     */
    static wrapWordsToLines(text: string, maxLineLength?: number, indentOrLinePrefix?: number | string): string[];
    /**
     * Displays a message in the console wrapped in a box UI.
     *
     * @param message - The message to display.
     * @param terminal - The terminal to write the message to.
     * @param options - Controls the box width and optional styling for the border and message text.
     * {@label WITH_OPTIONS}
     */
    static printMessageInBox(message: string, terminal: ITerminal, options?: IPrintMessageInBoxOptions): void;
    /**
     * @deprecated Use the {@link PrintUtilities.(printMessageInBox:1)} overload instead.
     * Pass `boxWidth` via the {@link IPrintMessageInBoxOptions.boxWidth} property.
     */
    static printMessageInBox(message: string, terminal: ITerminal, boxWidth?: number): void;
}
//# sourceMappingURL=PrintUtilities.d.ts.map