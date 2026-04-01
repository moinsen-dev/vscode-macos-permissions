# Native Addon Rewrite — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use moinsenpowers:subagent-driven-development (recommended) or moinsenpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the external Swift PermissionHelper.app with an in-process ObjC++ N-API addon so macOS TCC attributes permissions to VS Code, not a separate helper.

**Architecture:** Native ObjC++ addon loaded via `require()` into VS Code's Extension Host process. Exports `checkPermission(type)` (sync) and `requestPermission(type)` (async/Promise). TypeScript layer wraps the addon with type-safe interfaces and VS Code command bindings.

**Tech Stack:** TypeScript (extension), ObjC++ (N-API addon), node-gyp (build), prebuildify + node-gyp-build (distribution), Mocha + @vscode/test-electron (tests)

**Working directory:** `/Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions`

---

### Task 1: Clean up old native helper

**Files:**
- Delete: `native/PermissionHelper.swift`
- Delete: `native/PermissionHelper.app/` (entire directory)
- Delete: `native/build.sh`
- Delete: `native/PermissionHelper` (symlink)
- Delete: `macos-permissions-0.1.0.vsix`

- [ ] **Step 1: Remove old native files**

```bash
cd /Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions
rm -f native/PermissionHelper.swift
rm -rf native/PermissionHelper.app
rm -f native/build.sh
rm -f native/PermissionHelper
rm -f macos-permissions-0.1.0.vsix
```

- [ ] **Step 2: Verify native dir is empty**

```bash
ls native/
```

Expected: empty directory (or directory not found)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove old PermissionHelper.app and build artifacts"
```

---

### Task 2: Set up node-gyp build infrastructure

**Files:**
- Create: `native/binding.gyp`
- Create: `native/permissions.mm` (minimal stub)
- Modify: `package.json`
- Modify: `.vscodeignore`

- [ ] **Step 1: Create binding.gyp**

Create `native/binding.gyp`:

```json
{
  "targets": [
    {
      "target_name": "permissions",
      "sources": ["permissions.mm"],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")"
      ],
      "defines": ["NAPI_DISABLE_CPP_EXCEPTIONS"],
      "cflags!": ["-fno-exceptions"],
      "cflags_cc!": ["-fno-exceptions"],
      "conditions": [
        [
          "OS=='mac'",
          {
            "xcode_settings": {
              "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
              "CLANG_CXX_LANGUAGE_STANDARD": "c++17",
              "MACOSX_DEPLOYMENT_TARGET": "10.15",
              "OTHER_CFLAGS": ["-fobjc-arc"],
              "OTHER_LDFLAGS": [
                "-framework", "AVFoundation",
                "-framework", "Speech",
                "-framework", "CoreLocation",
                "-framework", "Contacts",
                "-framework", "EventKit",
                "-framework", "Photos",
                "-framework", "CoreBluetooth"
              ]
            }
          }
        ]
      ]
    }
  ]
}
```

- [ ] **Step 2: Create minimal permissions.mm stub**

Create `native/permissions.mm`:

```objc
#include <napi.h>

Napi::String CheckPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    return Napi::String::New(env, "not_determined");
}

Napi::Promise RequestPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    auto deferred = Napi::Promise::Deferred::New(env);
    deferred.Resolve(Napi::String::New(env, "not_determined"));
    return deferred.Promise();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("checkPermission", Napi::Function::New(env, CheckPermission));
    exports.Set("requestPermission", Napi::Function::New(env, RequestPermission));
    return exports;
}

NODE_API_MODULE(permissions, Init)
```

- [ ] **Step 3: Update package.json**

Add to `devDependencies`:

```json
"node-addon-api": "^7.0.0",
"node-gyp": "^10.0.0",
"node-gyp-build": "^4.8.0",
"prebuildify": "^6.0.0"
```

Add to `dependencies`:

```json
"node-gyp-build": "^4.8.0"
```

Add to `scripts`:

```json
"build-native": "cd native && node-gyp rebuild",
"prebuildify": "prebuildify --napi --strip",
"install": "node-gyp-build || echo 'Native build skipped (no compiler)'",
"test": "npm run compile && node out/test/runTests.js"
```

Change `vscode:prepublish` to:

```json
"vscode:prepublish": "npm run compile && npm run prebuildify"
```

- [ ] **Step 4: Update .vscodeignore**

Replace contents of `.vscodeignore`:

```
.vscode/**
.vscode-test/**
src/**
native/**
!prebuilds/**
.gitignore
**/tsconfig.json
**/.eslintrc.json
**/*.map
**/*.ts
!out/**/*.js
node_modules/**
docs/**
test/**
```

- [ ] **Step 5: Install dependencies and verify build**

```bash
cd /Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions
npm install
cd native && npx node-gyp rebuild
```

Expected: Build succeeds, `native/build/Release/permissions.node` exists.

- [ ] **Step 6: Verify addon loads**

```bash
node -e "const p = require('./native/build/Release/permissions.node'); console.log(p.checkPermission('photos'))"
```

Expected: Prints `not_determined`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add node-gyp build infrastructure with N-API stub"
```

---

### Task 3: Implement native permission checks (sync)

**Files:**
- Modify: `native/permissions.mm`

- [ ] **Step 1: Implement all check functions**

Replace `native/permissions.mm` with the full check implementation:

```objc
#include <napi.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <CoreLocation/CoreLocation.h>
#import <Contacts/Contacts.h>
#import <EventKit/EventKit.h>
#import <Photos/Photos.h>
#import <CoreBluetooth/CoreBluetooth.h>

// MARK: - Permission status strings

static const char* STATUS_GRANTED = "granted";
static const char* STATUS_DENIED = "denied";
static const char* STATUS_NOT_DETERMINED = "not_determined";
static const char* STATUS_RESTRICTED = "restricted";
static const char* STATUS_UNKNOWN = "unknown";

// MARK: - Check functions

static const char* checkMicrophone() {
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
        case AVAuthorizationStatusAuthorized: return STATUS_GRANTED;
        case AVAuthorizationStatusDenied: return STATUS_DENIED;
        case AVAuthorizationStatusNotDetermined: return STATUS_NOT_DETERMINED;
        case AVAuthorizationStatusRestricted: return STATUS_RESTRICTED;
        default: return STATUS_UNKNOWN;
    }
}

static const char* checkCamera() {
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
        case AVAuthorizationStatusAuthorized: return STATUS_GRANTED;
        case AVAuthorizationStatusDenied: return STATUS_DENIED;
        case AVAuthorizationStatusNotDetermined: return STATUS_NOT_DETERMINED;
        case AVAuthorizationStatusRestricted: return STATUS_RESTRICTED;
        default: return STATUS_UNKNOWN;
    }
}

static const char* checkSpeechRecognition() {
    if (@available(macOS 10.15, *)) {
        switch ([SFSpeechRecognizer authorizationStatus]) {
            case SFSpeechRecognizerAuthorizationStatusAuthorized: return STATUS_GRANTED;
            case SFSpeechRecognizerAuthorizationStatusDenied: return STATUS_DENIED;
            case SFSpeechRecognizerAuthorizationStatusNotDetermined: return STATUS_NOT_DETERMINED;
            case SFSpeechRecognizerAuthorizationStatusRestricted: return STATUS_RESTRICTED;
            default: return STATUS_UNKNOWN;
        }
    }
    return STATUS_UNKNOWN;
}

static const char* checkLocation() {
    CLLocationManager* manager = [[CLLocationManager alloc] init];
    CLAuthorizationStatus status;
    if (@available(macOS 11.0, *)) {
        status = manager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }
    switch (status) {
        case kCLAuthorizationStatusAuthorizedAlways: return STATUS_GRANTED;
        case kCLAuthorizationStatusDenied: return STATUS_DENIED;
        case kCLAuthorizationStatusNotDetermined: return STATUS_NOT_DETERMINED;
        case kCLAuthorizationStatusRestricted: return STATUS_RESTRICTED;
        default: return STATUS_UNKNOWN;
    }
}

static const char* checkContacts() {
    switch ([CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts]) {
        case CNAuthorizationStatusAuthorized: return STATUS_GRANTED;
        case CNAuthorizationStatusDenied: return STATUS_DENIED;
        case CNAuthorizationStatusNotDetermined: return STATUS_NOT_DETERMINED;
        case CNAuthorizationStatusRestricted: return STATUS_RESTRICTED;
        default: return STATUS_UNKNOWN;
    }
}

static const char* checkCalendars() {
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
    switch (status) {
        case EKAuthorizationStatusAuthorized: return STATUS_GRANTED;
        case EKAuthorizationStatusFullAccess: return STATUS_GRANTED;
        case EKAuthorizationStatusWriteOnly: return STATUS_GRANTED;
        case EKAuthorizationStatusDenied: return STATUS_DENIED;
        case EKAuthorizationStatusNotDetermined: return STATUS_NOT_DETERMINED;
        case EKAuthorizationStatusRestricted: return STATUS_RESTRICTED;
        default: return STATUS_UNKNOWN;
    }
}

static const char* checkReminders() {
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder];
    switch (status) {
        case EKAuthorizationStatusAuthorized: return STATUS_GRANTED;
        case EKAuthorizationStatusFullAccess: return STATUS_GRANTED;
        case EKAuthorizationStatusDenied: return STATUS_DENIED;
        case EKAuthorizationStatusNotDetermined: return STATUS_NOT_DETERMINED;
        case EKAuthorizationStatusRestricted: return STATUS_RESTRICTED;
        default: return STATUS_UNKNOWN;
    }
}

static const char* checkPhotos() {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    switch (status) {
        case PHAuthorizationStatusAuthorized: return STATUS_GRANTED;
        case PHAuthorizationStatusLimited: return STATUS_GRANTED;
        case PHAuthorizationStatusDenied: return STATUS_DENIED;
        case PHAuthorizationStatusNotDetermined: return STATUS_NOT_DETERMINED;
        case PHAuthorizationStatusRestricted: return STATUS_RESTRICTED;
        default: return STATUS_UNKNOWN;
    }
}

static const char* checkBluetooth() {
    if (@available(macOS 10.15, *)) {
        switch (CBManager.authorization) {
            case CBManagerAuthorizationAllowedAlways: return STATUS_GRANTED;
            case CBManagerAuthorizationDenied: return STATUS_DENIED;
            case CBManagerAuthorizationNotDetermined: return STATUS_NOT_DETERMINED;
            case CBManagerAuthorizationRestricted: return STATUS_RESTRICTED;
            default: return STATUS_UNKNOWN;
        }
    }
    return STATUS_UNKNOWN;
}

// MARK: - Check dispatcher

static const char* checkPermissionByType(const std::string& type) {
    if (type == "microphone") return checkMicrophone();
    if (type == "camera") return checkCamera();
    if (type == "speech_recognition") return checkSpeechRecognition();
    if (type == "location") return checkLocation();
    if (type == "contacts") return checkContacts();
    if (type == "calendars") return checkCalendars();
    if (type == "reminders") return checkReminders();
    if (type == "photos") return checkPhotos();
    if (type == "bluetooth") return checkBluetooth();
    return STATUS_UNKNOWN;
}

// MARK: - N-API exports

Napi::String CheckPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "Permission type string expected").ThrowAsJavaScriptException();
        return Napi::String::New(env, STATUS_UNKNOWN);
    }

    std::string type = info[0].As<Napi::String>().Utf8Value();
    return Napi::String::New(env, checkPermissionByType(type));
}

// Placeholder — request implementation in Task 4
Napi::Promise RequestPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    auto deferred = Napi::Promise::Deferred::New(env);
    deferred.Resolve(Napi::String::New(env, STATUS_NOT_DETERMINED));
    return deferred.Promise();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("checkPermission", Napi::Function::New(env, CheckPermission));
    exports.Set("requestPermission", Napi::Function::New(env, RequestPermission));
    return exports;
}

NODE_API_MODULE(permissions, Init)
```

- [ ] **Step 2: Rebuild and verify**

```bash
cd /Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions/native
npx node-gyp rebuild
node -e "const p = require('./build/Release/permissions.node'); console.log('photos:', p.checkPermission('photos')); console.log('microphone:', p.checkPermission('microphone')); console.log('invalid:', p.checkPermission('bogus'))"
```

Expected: Each prints a valid status string (`granted`, `denied`, `not_determined`, etc.). `bogus` prints `unknown`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: implement sync permission checks for all 9 permission types"
```

---

### Task 4: Implement native permission requests (async)

**Files:**
- Modify: `native/permissions.mm` — replace `RequestPermission` placeholder

- [ ] **Step 1: Add ThreadSafeFunction-based async request implementation**

Replace the `RequestPermission` placeholder and everything below it (keep everything above including `checkPermissionByType`) in `native/permissions.mm`:

```objc
// MARK: - Request helpers

class PermissionWorker : public Napi::AsyncWorker {
public:
    PermissionWorker(Napi::Env env, Napi::Promise::Deferred deferred, const std::string& type)
        : Napi::AsyncWorker(env), deferred_(deferred), type_(type), result_(STATUS_UNKNOWN) {}

    void Execute() override {
        // Actual permission request must happen on the main thread.
        // We use dispatch_semaphore to block until the async macOS callback fires.
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        dispatch_async(dispatch_get_main_queue(), ^{
            requestOnMainThread(type_, ^(const char* status) {
                result_ = status;
                dispatch_semaphore_signal(sem);
            });
        });

        // 30s timeout
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    }

    void OnOK() override {
        deferred_.Resolve(Napi::String::New(Env(), result_));
    }

    void OnError(const Napi::Error& error) override {
        deferred_.Reject(error.Value());
    }

private:
    Napi::Promise::Deferred deferred_;
    std::string type_;
    const char* result_;

    typedef void (^CompletionBlock)(const char*);

    static void requestOnMainThread(const std::string& type, CompletionBlock completion) {
        if (type == "microphone") {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
                completion(granted ? STATUS_GRANTED : STATUS_DENIED);
            }];
        } else if (type == "camera") {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                completion(granted ? STATUS_GRANTED : STATUS_DENIED);
            }];
        } else if (type == "speech_recognition") {
            if (@available(macOS 10.15, *)) {
                [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
                    switch (status) {
                        case SFSpeechRecognizerAuthorizationStatusAuthorized: completion(STATUS_GRANTED); break;
                        case SFSpeechRecognizerAuthorizationStatusDenied: completion(STATUS_DENIED); break;
                        default: completion(STATUS_NOT_DETERMINED); break;
                    }
                }];
            } else {
                completion(STATUS_UNKNOWN);
            }
        } else if (type == "contacts") {
            [[CNContactStore new] requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError* _) {
                completion(granted ? STATUS_GRANTED : STATUS_DENIED);
            }];
        } else if (type == "calendars") {
            EKEventStore* store = [EKEventStore new];
            if (@available(macOS 14.0, *)) {
                [store requestFullAccessToEventsWithCompletion:^(BOOL granted, NSError* _) {
                    completion(granted ? STATUS_GRANTED : STATUS_DENIED);
                }];
            } else {
                [store requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError* _) {
                    completion(granted ? STATUS_GRANTED : STATUS_DENIED);
                }];
            }
        } else if (type == "reminders") {
            EKEventStore* store = [EKEventStore new];
            if (@available(macOS 14.0, *)) {
                [store requestFullAccessToRemindersWithCompletion:^(BOOL granted, NSError* _) {
                    completion(granted ? STATUS_GRANTED : STATUS_DENIED);
                }];
            } else {
                [store requestAccessToEntityType:EKEntityTypeReminder completion:^(BOOL granted, NSError* _) {
                    completion(granted ? STATUS_GRANTED : STATUS_DENIED);
                }];
            }
        } else if (type == "photos") {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
                switch (status) {
                    case PHAuthorizationStatusAuthorized:
                    case PHAuthorizationStatusLimited:
                        completion(STATUS_GRANTED); break;
                    case PHAuthorizationStatusDenied:
                        completion(STATUS_DENIED); break;
                    default:
                        completion(STATUS_NOT_DETERMINED); break;
                }
            }];
        } else if (type == "bluetooth") {
            // Initializing CBCentralManager triggers the TCC dialog
            CBCentralManager* __unused manager = [[CBCentralManager alloc] initWithDelegate:nil queue:nil];
            // Give macOS a moment to process, then check status
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (@available(macOS 10.15, *)) {
                    switch (CBManager.authorization) {
                        case CBManagerAuthorizationAllowedAlways: completion(STATUS_GRANTED); break;
                        case CBManagerAuthorizationDenied: completion(STATUS_DENIED); break;
                        default: completion(STATUS_NOT_DETERMINED); break;
                    }
                } else {
                    completion(STATUS_UNKNOWN);
                }
            });
        } else if (type == "location") {
            // Location requires a delegate; for the initial request we trigger and then poll
            CLLocationManager* locManager = [CLLocationManager new];
            [locManager requestAlwaysAuthorization];
            // Poll after a delay — the dialog is synchronous from the user's perspective
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                completion(checkLocation());
            });
        } else {
            completion(STATUS_UNKNOWN);
        }
    }
};

// MARK: - N-API exports

Napi::String CheckPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "Permission type string expected").ThrowAsJavaScriptException();
        return Napi::String::New(env, STATUS_UNKNOWN);
    }

    std::string type = info[0].As<Napi::String>().Utf8Value();
    return Napi::String::New(env, checkPermissionByType(type));
}

Napi::Promise RequestPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "Permission type string expected").ThrowAsJavaScriptException();
        auto deferred = Napi::Promise::Deferred::New(env);
        deferred.Reject(Napi::String::New(env, "Invalid argument"));
        return deferred.Promise();
    }

    std::string type = info[0].As<Napi::String>().Utf8Value();

    // If already determined, return immediately
    const char* current = checkPermissionByType(type);
    if (strcmp(current, STATUS_NOT_DETERMINED) != 0) {
        auto deferred = Napi::Promise::Deferred::New(env);
        deferred.Resolve(Napi::String::New(env, current));
        return deferred.Promise();
    }

    auto deferred = Napi::Promise::Deferred::New(env);
    auto* worker = new PermissionWorker(env, deferred, type);
    worker->Queue();
    return deferred.Promise();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("checkPermission", Napi::Function::New(env, CheckPermission));
    exports.Set("requestPermission", Napi::Function::New(env, RequestPermission));
    return exports;
}

NODE_API_MODULE(permissions, Init)
```

- [ ] **Step 2: Rebuild**

```bash
cd /Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions/native
npx node-gyp rebuild
```

Expected: Compiles without errors.

- [ ] **Step 3: Smoke test request (manual)**

```bash
node -e "const p = require('./native/build/Release/permissions.node'); p.requestPermission('microphone').then(s => console.log('microphone:', s))"
```

Expected: If not determined → macOS dialog appears. If already determined → prints current status immediately.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: implement async permission requests for all 9 types via N-API"
```

---

### Task 5: Rewrite TypeScript extension layer

**Files:**
- Create: `src/permissions.ts`
- Rewrite: `src/extension.ts`

- [ ] **Step 1: Create src/permissions.ts**

```typescript
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

// Not requestable programmatically — manual only
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
        // Try prebuild first (Marketplace installs)
        const gypBuild = require('node-gyp-build');
        addon = gypBuild(extensionPath) as NativeAddon;
    } catch {
        // Fallback: local dev build
        addon = require(path.join(extensionPath, 'native', 'build', 'Release', 'permissions.node')) as NativeAddon;
    }

    return addon;
}

export function checkPermission(extensionPath: string, type: PermissionType): PermissionStatus {
    const native = loadAddon(extensionPath);
    const result = native.checkPermission(type);
    return result as PermissionStatus;
}

export async function requestPermission(extensionPath: string, type: PermissionType): Promise<PermissionStatus> {
    const native = loadAddon(extensionPath);
    const result = await native.requestPermission(type);
    return result as PermissionStatus;
}

export function checkAll(extensionPath: string): Record<PermissionType, PermissionStatus> {
    const results = {} as Record<PermissionType, PermissionStatus>;
    for (const type of Object.values(PermissionType)) {
        results[type] = checkPermission(extensionPath, type);
    }
    return results;
}
```

- [ ] **Step 2: Rewrite src/extension.ts**

```typescript
import * as vscode from 'vscode';
import { execSync } from 'child_process';
import {
    PermissionType,
    ManualPermissionType,
    PermissionStatus,
    PERMISSION_LABELS,
    SETTINGS_URLS,
    checkPermission,
    requestPermission,
    checkAll,
    loadAddon,
} from './permissions';

let statusBarItem: vscode.StatusBarItem;
let outputChannel: vscode.OutputChannel;

export function activate(context: vscode.ExtensionContext) {
    if (process.platform !== 'darwin') {
        vscode.window.showInformationMessage('macOS Permissions extension only works on macOS');
        return;
    }

    // Verify addon loads
    try {
        loadAddon(context.extensionPath);
    } catch (err) {
        vscode.window.showErrorMessage(`macOS Permissions: Failed to load native addon — ${err}`);
        return;
    }

    outputChannel = vscode.window.createOutputChannel('macOS Permissions');

    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.command = 'macosPermissions.showStatus';
    context.subscriptions.push(statusBarItem);

    // Register commands
    const commands: [string, () => void | Promise<void>][] = [
        ['macosPermissions.requestAll', () => handleRequestAll(context)],
        ['macosPermissions.showStatus', () => handleShowStatus(context)],
        ['macosPermissions.openSystemPreferences', () => openSettings()],
    ];

    // Individual permission commands
    for (const type of Object.values(PermissionType)) {
        const label = PERMISSION_LABELS[type];
        commands.push([
            `macosPermissions.request${toPascal(type)}`,
            () => handleRequestSingle(context, type),
        ]);
    }

    for (const [id, handler] of commands) {
        context.subscriptions.push(vscode.commands.registerCommand(id, handler));
    }

    // Status bar
    const config = vscode.workspace.getConfiguration('macosPermissions');
    if (config.get('showStatusBarItem')) {
        updateStatusBar(context);
        statusBarItem.show();
    }

    // Startup check
    if (config.get('checkOnStartup')) {
        const results = checkAll(context.extensionPath);
        const denied = Object.entries(results).filter(([_, s]) => s === 'denied');
        if (denied.length > 0) {
            vscode.window.showWarningMessage(
                `macOS permissions denied: ${denied.map(([p]) => PERMISSION_LABELS[p as PermissionType]).join(', ')}`,
                'Request', 'Open Settings',
            ).then(choice => {
                if (choice === 'Request') { handleRequestAll(context); }
                else if (choice === 'Open Settings') { openSettings(); }
            });
        }
    }

    outputChannel.appendLine('macOS Permissions extension activated (native addon)');
}

export function deactivate() {
    outputChannel?.dispose();
}

// MARK: - Command handlers

async function handleRequestSingle(context: vscode.ExtensionContext, type: PermissionType) {
    const label = PERMISSION_LABELS[type];
    outputChannel.appendLine(`Requesting: ${label}`);

    const status = await requestPermission(context.extensionPath, type);
    outputChannel.appendLine(`${label}: ${status}`);

    if (status === 'granted') {
        vscode.window.showInformationMessage(`${label} permission granted!`);
    } else if (status === 'denied') {
        const choice = await vscode.window.showWarningMessage(
            `${label} was denied. Grant it in System Settings.`,
            'Open Settings',
        );
        if (choice === 'Open Settings') { openSettingsFor(type); }
    }

    updateStatusBar(context);
}

async function handleRequestAll(context: vscode.ExtensionContext) {
    const items = Object.values(PermissionType).map(type => ({
        label: PERMISSION_LABELS[type],
        description: type,
        picked: true,
    }));

    const selected = await vscode.window.showQuickPick(items, {
        canPickMany: true,
        placeHolder: 'Select permissions to request',
        title: 'macOS Permissions',
    });

    if (!selected || selected.length === 0) { return; }

    outputChannel.show();
    outputChannel.appendLine('--- Requesting Permissions ---');

    let granted = 0;
    let denied = 0;

    await vscode.window.withProgress({
        location: vscode.ProgressLocation.Notification,
        title: 'Requesting macOS Permissions',
        cancellable: false,
    }, async (progress) => {
        for (let i = 0; i < selected.length; i++) {
            const type = selected[i].description as PermissionType;
            const label = PERMISSION_LABELS[type];
            progress.report({ message: `${label} (${i + 1}/${selected.length})`, increment: 100 / selected.length });

            const status = await requestPermission(context.extensionPath, type);
            outputChannel.appendLine(`${label}: ${status}`);
            if (status === 'granted') { granted++; } else { denied++; }
        }
    });

    if (denied > 0) {
        const choice = await vscode.window.showWarningMessage(
            `${denied} permission(s) denied. Grant them in System Settings.`,
            'Open Settings', 'OK',
        );
        if (choice === 'Open Settings') { openSettings(); }
    } else {
        vscode.window.showInformationMessage('All requested permissions granted!');
    }

    updateStatusBar(context);
}

async function handleShowStatus(context: vscode.ExtensionContext) {
    const results = checkAll(context.extensionPath);

    const items: vscode.QuickPickItem[] = Object.entries(results).map(([type, status]) => {
        const icon = status === 'granted' ? '$(check)' :
                     status === 'denied' ? '$(x)' :
                     status === 'not_determined' ? '$(question)' : '$(warning)';
        return {
            label: `${icon} ${PERMISSION_LABELS[type as PermissionType]}`,
            description: status,
        };
    });

    const choice = await vscode.window.showQuickPick(items, {
        placeHolder: 'Select a permission for actions',
        title: 'macOS Permission Status',
    });

    if (!choice) { return; }

    const type = Object.values(PermissionType).find(
        t => PERMISSION_LABELS[t] === choice.label.replace(/^\$\([^)]+\)\s*/, ''),
    );
    if (!type) { return; }

    const action = await vscode.window.showQuickPick(
        ['Request Permission', 'Open System Settings', 'Cancel'],
        { placeHolder: `Action for ${PERMISSION_LABELS[type]}` },
    );

    if (action === 'Request Permission') { await handleRequestSingle(context, type); }
    else if (action === 'Open System Settings') { openSettingsFor(type); }
}

function updateStatusBar(context: vscode.ExtensionContext) {
    try {
        const results = checkAll(context.extensionPath);
        const total = Object.keys(results).length;
        const grantedCount = Object.values(results).filter(s => s === 'granted').length;
        const deniedCount = Object.values(results).filter(s => s === 'denied').length;

        if (deniedCount > 0) {
            statusBarItem.text = `$(shield) ${deniedCount} denied`;
            statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
            statusBarItem.tooltip = `${deniedCount} macOS permission(s) denied`;
        } else if (grantedCount === total) {
            statusBarItem.text = '$(shield) All OK';
            statusBarItem.backgroundColor = undefined;
            statusBarItem.tooltip = 'All macOS permissions granted';
        } else {
            statusBarItem.text = `$(shield) ${grantedCount}/${total}`;
            statusBarItem.backgroundColor = undefined;
            statusBarItem.tooltip = `${grantedCount} of ${total} macOS permissions granted`;
        }
    } catch {
        statusBarItem.text = '$(shield) ?';
        statusBarItem.tooltip = 'Click to check macOS permissions';
    }
}

// MARK: - Helpers

function openSettings() {
    execSync('open "x-apple.systempreferences:com.apple.preference.security?Privacy"');
}

function openSettingsFor(type: string) {
    const pane = SETTINGS_URLS[type] || 'Privacy';
    execSync(`open "x-apple.systempreferences:com.apple.preference.security?${pane}"`);
}

function toPascal(s: string): string {
    return s.split('_').map(w => w[0].toUpperCase() + w.slice(1)).join('');
}
```

- [ ] **Step 3: Compile TypeScript**

```bash
cd /Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions
npx tsc -p .
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: rewrite extension with in-process native addon and typed permission layer"
```

---

### Task 6: Update package.json commands & configuration

**Files:**
- Modify: `package.json` — commands, menus, configuration

- [ ] **Step 1: Update contributes section in package.json**

Replace the entire `contributes` block with updated commands covering all 9 permission types plus reminders, bluetooth, and removing the dead accessibility/screen recording request commands:

```json
"contributes": {
    "commands": [
        { "command": "macosPermissions.requestAll", "title": "Request All macOS Permissions", "category": "macOS Permissions" },
        { "command": "macosPermissions.showStatus", "title": "Show Permission Status", "category": "macOS Permissions" },
        { "command": "macosPermissions.requestMicrophone", "title": "Request Microphone Permission", "category": "macOS Permissions" },
        { "command": "macosPermissions.requestCamera", "title": "Request Camera Permission", "category": "macOS Permissions" },
        { "command": "macosPermissions.requestSpeechRecognition", "title": "Request Speech Recognition Permission", "category": "macOS Permissions" },
        { "command": "macosPermissions.requestLocation", "title": "Request Location Permission", "category": "macOS Permissions" },
        { "command": "macosPermissions.requestContacts", "title": "Request Contacts Permission", "category": "macOS Permissions" },
        { "command": "macosPermissions.requestCalendars", "title": "Request Calendars Permission", "category": "macOS Permissions" },
        { "command": "macosPermissions.requestReminders", "title": "Request Reminders Permission", "category": "macOS Permissions" },
        { "command": "macosPermissions.requestPhotos", "title": "Request Photos Permission", "category": "macOS Permissions" },
        { "command": "macosPermissions.requestBluetooth", "title": "Request Bluetooth Permission", "category": "macOS Permissions" },
        { "command": "macosPermissions.openSystemPreferences", "title": "Open Privacy & Security Settings", "category": "macOS Permissions" }
    ],
    "menus": {
        "commandPalette": [
            { "command": "macosPermissions.requestAll", "when": "isMac" },
            { "command": "macosPermissions.showStatus", "when": "isMac" },
            { "command": "macosPermissions.requestMicrophone", "when": "isMac" },
            { "command": "macosPermissions.requestCamera", "when": "isMac" },
            { "command": "macosPermissions.requestSpeechRecognition", "when": "isMac" },
            { "command": "macosPermissions.requestLocation", "when": "isMac" },
            { "command": "macosPermissions.requestContacts", "when": "isMac" },
            { "command": "macosPermissions.requestCalendars", "when": "isMac" },
            { "command": "macosPermissions.requestReminders", "when": "isMac" },
            { "command": "macosPermissions.requestPhotos", "when": "isMac" },
            { "command": "macosPermissions.requestBluetooth", "when": "isMac" },
            { "command": "macosPermissions.openSystemPreferences", "when": "isMac" }
        ]
    },
    "configuration": {
        "title": "macOS Permissions",
        "properties": {
            "macosPermissions.showStatusBarItem": {
                "type": "boolean",
                "default": true,
                "description": "Show permission status in the status bar"
            },
            "macosPermissions.checkOnStartup": {
                "type": "boolean",
                "default": false,
                "description": "Check permission status when VS Code starts"
            }
        }
    }
}
```

- [ ] **Step 2: Verify package.json is valid JSON**

```bash
cd /Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions
node -e "JSON.parse(require('fs').readFileSync('package.json', 'utf8')); console.log('Valid JSON')"
```

Expected: `Valid JSON`

- [ ] **Step 3: Commit**

```bash
git add package.json
git commit -m "feat: update commands for all 9 permissions, remove dead accessibility/screen recording commands"
```

---

### Task 7: Add prebuildify support for Marketplace distribution

**Files:**
- Modify: `package.json` — add prebuildify scripts
- Modify: `.vscodeignore` — include prebuilds

- [ ] **Step 1: Generate prebuilds for current architecture**

```bash
cd /Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions
npx prebuildify --napi --strip
ls prebuilds/
```

Expected: `darwin-arm64/` directory with `permissions.node` inside.

Note: For Marketplace, we'd also build on x86_64 CI. For now, arm64 is sufficient for local testing.

- [ ] **Step 2: Test loading via node-gyp-build**

```bash
node -e "const build = require('node-gyp-build'); const addon = build('.'); console.log(addon.checkPermission('photos'))"
```

Expected: Prints a valid status string. `node-gyp-build` finds the prebuild automatically.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add prebuildify support for Marketplace distribution"
```

---

### Task 8: Write tests

**Files:**
- Create: `test/native.test.ts`
- Create: `test/permissions.test.ts`
- Create: `test/runTests.ts`
- Modify: `tsconfig.json` — include test dir

- [ ] **Step 1: Update tsconfig.json**

Change `include` to also cover tests:

```json
"include": ["src/**/*", "test/**/*"]
```

- [ ] **Step 2: Add test dependencies to package.json**

Add to `devDependencies`:

```json
"mocha": "^10.2.0",
"@types/mocha": "^10.0.0",
"@vscode/test-electron": "^2.3.0"
```

- [ ] **Step 3: Create test/runTests.ts**

```typescript
import * as path from 'path';

async function main() {
    const { runTests } = require('@vscode/test-electron');
    const extensionDevelopmentPath = path.resolve(__dirname, '../../');
    const extensionTestsPath = path.resolve(__dirname, './');

    await runTests({
        extensionDevelopmentPath,
        extensionTestsPath,
        launchArgs: ['--disable-extensions'],
    });
}

main().catch(err => {
    console.error('Failed to run tests:', err);
    process.exit(1);
});
```

- [ ] **Step 4: Create test/native.test.ts**

```typescript
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

    const validStatuses = ['granted', 'denied', 'not_determined', 'restricted', 'unknown'];
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

    test('requestPermission with invalid type rejects or returns unknown', async () => {
        try {
            const result = await addon.requestPermission('nonexistent');
            assert.strictEqual(result, 'unknown');
        } catch {
            // Rejection is also acceptable
        }
    });
});
```

- [ ] **Step 5: Create test/permissions.test.ts**

```typescript
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
```

- [ ] **Step 6: Run tests**

```bash
cd /Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions
npx tsc -p .
npx mocha out/test/native.test.js out/test/permissions.test.js --timeout 10000
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test: add native addon and permissions module tests"
```

---

### Task 9: Update README and build VSIX

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README.md**

Update the README to reflect the new architecture. Key changes:
- Add Reminders and Bluetooth to the supported permissions table
- Remove references to the Swift helper
- Update installation instructions (prebuild = no Xcode needed)
- Add note about Accessibility and Screen Recording being manual-only
- Update "How It Works" section to describe in-process N-API addon

- [ ] **Step 2: Build VSIX**

```bash
cd /Users/udi/work/moinsen/ideas/fred/tools/vscode-macos-permissions
npx vsce package
```

Expected: Creates `macos-permissions-0.2.0.vsix` (bump version in package.json to `0.2.0` first).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "docs: update README for native addon architecture, bump to 0.2.0"
```

---

Plan complete und gespeichert. Zwei Ausführungsoptionen:

**1. Subagent-Driven (diese Session)** — Ich dispatche pro Task einen frischen Subagent, review zwischen Tasks, schnelle Iteration

**2. Parallel Session (separate)** — Neue Session im Worktree mit executing-plans, Batch-Execution mit Checkpoints

Welcher Ansatz?