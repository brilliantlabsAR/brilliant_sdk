// Unit tests for bleWriteSize. No device or test framework required:
// run with `npm test` (node --test) after `npm run build`.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { bleWriteSize } from '../dist/brilliant-ble.es.js';

test('write size fills whole link-layer packets', () => {
    assert.equal(bleWriteSize(512), 495);
    assert.equal(bleWriteSize(495), 495);
    assert.equal(bleWriteSize(494), 244);
    assert.equal(bleWriteSize(244), 244);
});

test('write size is unchanged when not even one packet fits', () => {
    assert.equal(bleWriteSize(243), 243);
    assert.equal(bleWriteSize(60), 60);
    assert.equal(bleWriteSize(20), 20);
});
