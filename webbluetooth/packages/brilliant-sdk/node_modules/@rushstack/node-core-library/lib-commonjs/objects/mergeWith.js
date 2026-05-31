"use strict";
// Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
// See LICENSE in the project root for license information.
Object.defineProperty(exports, "__esModule", { value: true });
exports.mergeWith = mergeWith;
const isRecord_1 = require("./isRecord");
/**
 * Recursively merges own enumerable string-keyed properties of `source` into `target`, invoking
 * `customizer` for each property. Mutates and returns `target`.
 *
 * @remarks
 * For each property in `source`, `customizer` is called with `(targetValue, sourceValue, key)`.
 * If the customizer returns a value other than `undefined`, that value is assigned directly.
 * Otherwise the default behavior applies: plain objects are merged recursively; all other values
 * (arrays, primitives, `null`) overwrite the corresponding target property.
 *
 * @public
 */
function mergeWith(target, source, customizer) {
    const targetRecord = target;
    const sourceRecord = source;
    for (const [key, srcValue] of Object.entries(sourceRecord)) {
        const objValue = targetRecord[key];
        const customized = customizer === null || customizer === void 0 ? void 0 : customizer(objValue, srcValue, key);
        if (customized !== undefined) {
            targetRecord[key] = customized;
        }
        else if ((0, isRecord_1.isRecord)(srcValue) && (0, isRecord_1.isRecord)(objValue)) {
            mergeWith(objValue, srcValue, customizer);
        }
        else {
            targetRecord[key] = srcValue;
        }
    }
    return target;
}
//# sourceMappingURL=mergeWith.js.map