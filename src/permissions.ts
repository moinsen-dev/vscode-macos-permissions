import * as path from 'path';

export enum PermissionType {
    Microphone = 'microphone',
    Camera = 'camera',
    SpeechRecognition = 'speech_recognition',
    Location = 'location',
    Contacts = 'contacts',
    Calendars = 'calendars',
    Reminders = 'reminders',
    Photos = 'photos',
    Bluetooth = 'bluetooth',
}

export enum ManualPermissionType {
    Accessibility = 'accessibility',
    ScreenRecording = 'screen_recording',
}

export type PermissionStatus = 'granted' | 'denied' | 'not_determined' | 'restricted' | 'unknown';

export const PERMISSION_LABELS: Record<PermissionType, string> = {
    [PermissionType.Microphone]: 'Microphone',
    [PermissionType.Camera]: 'Camera',
    [PermissionType.SpeechRecognition]: 'Speech Recognition',
    [PermissionType.Location]: 'Location',
    [PermissionType.Contacts]: 'Contacts',
    [PermissionType.Calendars]: 'Calendars',
    [PermissionType.Reminders]: 'Reminders',
    [PermissionType.Photos]: 'Photos',
    [PermissionType.Bluetooth]: 'Bluetooth',
};

export const SETTINGS_URLS: Record<string, string> = {
    [PermissionType.Microphone]: 'Privacy_Microphone',
    [PermissionType.Camera]: 'Privacy_Camera',
    [PermissionType.SpeechRecognition]: 'Privacy_SpeechRecognition',
    [PermissionType.Location]: 'Privacy_LocationServices',
    [PermissionType.Contacts]: 'Privacy_Contacts',
    [PermissionType.Calendars]: 'Privacy_Calendars',
    [PermissionType.Reminders]: 'Privacy_Reminders',
    [PermissionType.Photos]: 'Privacy_Photos',
    [PermissionType.Bluetooth]: 'Privacy_Bluetooth',
    [ManualPermissionType.Accessibility]: 'Privacy_Accessibility',
    [ManualPermissionType.ScreenRecording]: 'Privacy_ScreenCapture',
};

export interface NativeAddon {
    checkPermission(type: string): string;
    requestPermission(type: string): Promise<string>;
}

let addon: NativeAddon | null = null;

export function loadAddon(extensionPath: string): NativeAddon {
    if (addon) { return addon; }
    try {
        const gypBuild = require('node-gyp-build');
        addon = gypBuild(extensionPath) as NativeAddon;
    } catch {
        addon = require(path.join(extensionPath, 'native', 'build', 'Release', 'permissions.node')) as NativeAddon;
    }
    return addon;
}

export function checkPermission(extensionPath: string, type: PermissionType): PermissionStatus {
    const native = loadAddon(extensionPath);
    return native.checkPermission(type) as PermissionStatus;
}

export async function requestPermission(extensionPath: string, type: PermissionType): Promise<PermissionStatus> {
    const native = loadAddon(extensionPath);
    return await native.requestPermission(type) as PermissionStatus;
}

export function checkAll(extensionPath: string): Record<PermissionType, PermissionStatus> {
    const results = {} as Record<PermissionType, PermissionStatus>;
    for (const type of Object.values(PermissionType)) {
        results[type] = checkPermission(extensionPath, type);
    }
    return results;
}
