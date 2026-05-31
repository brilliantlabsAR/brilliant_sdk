"use strict";
// Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
// See LICENSE in the project root for license information.
Object.defineProperty(exports, "__esModule", { value: true });
exports.isRecord = isRecord;
/**
 * Returns `true` if `value` is a non-null, non-array plain object (i.e. assignable to
 * `Record<string, unknown>`), narrowing the type accordingly.
 *
 * @public
 */
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
//# sourceMappingURL=isRecord.js.map