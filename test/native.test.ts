import * as assert from 'assert';
import * as path from 'path';

suite('Native Addon', () => {
    const addonPath = path.resolve(__dirname, '../../native/build/Release/permissions.node');
    let addon: { checkPermission: (t: string) => string; requestPermission: (t: string) => Promise<string> };

    suiteSetup(() => {
        addon = require(addonPath);
    });

    test('addon exports checkPermission function', () => {
        assert.strictEqual(typeof addon.checkPermission, 'function');
    });

    test('addon exports requestPermission function', () => {
        assert.strictEqual(typeof addon.requestPermission, 'function');
    });

    const validStatuses = ['granted', 'denied', 'not_determined', 'restricted', 'limited', 'unknown'];
    const permissionTypes = [
        'microphone', 'camera', 'speech_recognition', 'location',
        'contacts', 'calendars', 'reminders', 'photos', 'bluetooth',
    ];

    for (const type of permissionTypes) {
        test(`checkPermission("${type}") returns a valid status`, () => {
            const result = addon.checkPermission(type);
            assert.ok(validStatuses.includes(result), `Got "${result}" for ${type}`);
        });
    }

    test('checkPermission with invalid type returns "unknown"', () => {
        assert.strictEqual(addon.checkPermission('nonexistent'), 'unknown');
    });

    test('requestPermission returns a Promise', () => {
        const result = addon.requestPermission('microphone');
        assert.ok(result instanceof Promise);
    });
});
