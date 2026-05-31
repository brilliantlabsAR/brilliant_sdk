// Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
// See LICENSE in the project root for license information.
import { AnsiEscape } from './AnsiEscape';
const BORDERLESS_CHARS = {
    top: '',
    topCenter: '',
    topLeft: '',
    topRight: '',
    bottom: '',
    bottomCenter: '',
    bottomLeft: '',
    bottomRight: '',
    left: '',
    leftCenter: '',
    horizontalCenter: '',
    centerCenter: '',
    right: '',
    rightCenter: '',
    verticalCenter: ''
};
const DEFAULT_CHARS = {
    top: '─',
    topCenter: '┬',
    topLeft: '┌',
    topRight: '┐',
    bottom: '─',
    bottomCenter: '┴',
    bottomLeft: '└',
    bottomRight: '┘',
    left: '│',
    leftCenter: '├',
    horizontalCenter: '─',
    centerCenter: '┼',
    right: '│',
    rightCenter: '┤',
    verticalCenter: '│'
};
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
export class TerminalTable {
    constructor(options = {}) {
        const { head, colWidths, borderless, borderCharacters, borderColor, headingColor } = options;
        this._head = head !== null && head !== void 0 ? head : [];
        this._specifiedColWidths = colWidths !== null && colWidths !== void 0 ? colWidths : [];
        this._borderCharacters = {
            ...(borderless ? BORDERLESS_CHARS : DEFAULT_CHARS),
            ...borderCharacters
        };
        this._borderColor = borderColor;
        this._headingColor = headingColor;
        this._rows = [];
    }
    /**
     * Appends one or more rows to the table.
     */
    push(...rows) {
        for (const row of rows) {
            this._rows.push(row);
        }
    }
    getLines() {
        const { _head: head, _rows: rows, _specifiedColWidths: specifiedColWidths, _borderColor: borderColor, _headingColor: headingColor, _borderCharacters: { top: topSeparator, topCenter: topCenterSeparator, topLeft: topLeftSeparator, topRight: topRightSeparator, bottom: bottomSeparator, bottomCenter: bottomCenterSeparator, bottomLeft: bottomLeftSeparator, bottomRight: bottomRightSeparator, left: leftSeparator, leftCenter: leftCenterSeparator, horizontalCenter: horizontalCenterSeparator, centerCenter: centerCenterSeparator, right: rightSeparator, rightCenter: rightCenterSeparator, verticalCenter: verticalCenterSeparator } } = this;
        const allRows = [head, ...rows];
        const columnCount = Math.max(0, ...allRows.map((r) => r.length));
        if (columnCount === 0) {
            return [];
        }
        // Resolve final column widths: use specified width if provided, otherwise auto-size from content.
        const columnWidths = [];
        for (let columnIndex = 0; columnIndex < columnCount; columnIndex++) {
            const specified = specifiedColWidths[columnIndex];
            if (specified !== undefined) {
                columnWidths.push(specified);
            }
            else {
                let maxContent = 0;
                for (const row of allRows) {
                    if (columnIndex < row.length) {
                        const width = AnsiEscape.removeCodes(row[columnIndex]).length;
                        if (width > maxContent) {
                            maxContent = width;
                        }
                    }
                }
                // +2 for one character of padding on each side
                columnWidths.push(maxContent + 2);
            }
        }
        // Builds a styled horizontal separator line; returns undefined if fillChar is empty (suppressed).
        const buildSepLine = (leftChar, fillChar, midChar, rightChar) => {
            if (fillChar.length === 0) {
                return undefined;
            }
            const line = leftChar + columnWidths.map((w) => fillChar.repeat(w)).join(midChar) + rightChar;
            return borderColor ? borderColor(line) : line;
        };
        // Pre-compute all separator lines (borderColor applied once per line, not per character).
        const topLine = buildSepLine(topLeftSeparator, topSeparator, topCenterSeparator, topRightSeparator);
        const centerLine = buildSepLine(leftCenterSeparator, horizontalCenterSeparator, centerCenterSeparator, rightCenterSeparator);
        const bottomLine = buildSepLine(bottomLeftSeparator, bottomSeparator, bottomCenterSeparator, bottomRightSeparator);
        // Pre-colorize vertical border chars used in data rows.
        const styledLeft = borderColor && leftSeparator ? borderColor(leftSeparator) : leftSeparator;
        const styledMid = borderColor && verticalCenterSeparator ? borderColor(verticalCenterSeparator) : verticalCenterSeparator;
        const styledRight = borderColor && rightSeparator ? borderColor(rightSeparator) : rightSeparator;
        // Renders a single data row. If contentColor is provided, it is applied to each cell's text.
        const renderRow = (row, contentColor) => {
            const cells = [];
            for (let col = 0; col < columnCount; col++) {
                const content = col < row.length ? row[col] : '';
                const visualWidth = AnsiEscape.removeCodes(content).length;
                // 1 char of left-padding; right-padding fills the remainder of the column width.
                const padRight = Math.max(columnWidths[col] - 1 - visualWidth, 0);
                const styledContent = content && contentColor ? contentColor(content) : content;
                cells.push(' ' + styledContent + ' '.repeat(padRight));
            }
            return styledLeft + cells.join(styledMid) + styledRight;
        };
        const lines = [];
        if (topLine !== undefined) {
            lines.push(topLine);
        }
        if (head.length > 0) {
            lines.push(renderRow(head, headingColor));
            if (centerLine !== undefined) {
                lines.push(centerLine);
            }
        }
        for (let i = 0; i < this._rows.length; i++) {
            lines.push(renderRow(this._rows[i]));
            if (i < this._rows.length - 1 && centerLine !== undefined) {
                lines.push(centerLine);
            }
        }
        if (bottomLine !== undefined) {
            lines.push(bottomLine);
        }
        return lines;
    }
    /**
     * Renders the table to a string.
     */
    toString() {
        const lines = this.getLines();
        return lines.join('\n');
    }
    /**
     * Writes the rendered table to the provided terminal, one line at a time.
     */
    printToTerminal(terminal) {
        for (const line of this.getLines()) {
            terminal.writeLine(line);
        }
    }
}
//# sourceMappingURL=TerminalTable.js.map