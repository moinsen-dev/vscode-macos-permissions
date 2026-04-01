import * as assert from 'assert';
import { PermissionType, PERMISSION_LABELS, SETTINGS_URLS } from '../src/permissions';

suite('Permissions Module', () => {
    test('every PermissionType has a label', () => {
        for (const type of Object.values(PermissionType)) {
            assert.ok(PERMISSION_LABELS[type], `Missing label for ${type}`);
        }
    });

    test('every PermissionType has a settings URL', () => {
        for (const type of Object.values(PermissionType)) {
            assert.ok(SETTINGS_URLS[type], `Missing settings URL for ${type}`);
        }
    });

    test('PermissionType enum has 9 entries', () => {
        assert.strictEqual(Object.values(PermissionType).length, 9);
    });

    test('labels are human-readable (no underscores)', () => {
        for (const label of Object.values(PERMISSION_LABELS)) {
            assert.ok(!label.includes('_'), `Label "${label}" contains underscores`);
        }
    });
});
