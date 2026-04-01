# Design: Native Addon Rewrite

**Date:** 2026-04-01
**Status:** Approved
**Goal:** Replace the external Swift Helper app with an in-process N-API addon so that macOS TCC attributes permissions to VS Code itself, not a separate helper binary.

## Problems Addressed

1. **Helper gets permissions, not VS Code.** The current `PermissionHelper.app` is a separate bundle. TCC grants permissions to it, not to Visual Studio Code. This defeats the extension's purpose.
2. **Dead enums in TypeScript.** `Accessibility`, `ScreenRecording`, `Bluetooth` are defined in `extension.ts` but not implemented in the Swift helper.
3. **Missing Reminders support.** Calendars are supported but Reminders are not.
4. **Build requires Xcode CLI Tools.** No pre-built binaries are shipped — every user needs `swiftc`.
5. **No tests.**

## Architecture

### In-Process Native Addon

The ObjC++ addon (`.node` file) is loaded via `require()` into VS Code's Extension Host process (`Code Helper (Plugin)`). When it calls macOS permission APIs, the OS attributes the request to the VS Code application bundle. macOS shows TCC dialogs like: *"Visual Studio Code wants to access your photos"*.

### Project Structure

```
vscode-macos-permissions/
├── src/
│   ├── extension.ts          # VS Code extension entry point
│   └── permissions.ts        # Permission types & interfaces
├── native/
│   ├── binding.gyp           # node-gyp build configuration
│   └── permissions.mm        # ObjC++ N-API addon
├── prebuilds/                # Pre-built binaries for Marketplace
│   ├── darwin-arm64/
│   └── darwin-x64/
├── test/
│   ├── extension.test.ts     # Extension unit tests
│   └── native.test.ts        # Addon loading & status check tests
├── package.json
└── tsconfig.json
```

### Addon API

The native addon exports two functions:

```typescript
checkPermission(type: string): string
// Synchronous. Returns: "granted" | "denied" | "not_determined" | "restricted"

requestPermission(type: string): Promise<string>
// Asynchronous. Triggers TCC dialog, resolves with final status.
```

## Supported Permissions

| Key | macOS API | Framework | Notes |
|-----|-----------|-----------|-------|
| `microphone` | `AVCaptureDevice.requestAccess(for: .audio)` | AVFoundation | |
| `camera` | `AVCaptureDevice.requestAccess(for: .video)` | AVFoundation | |
| `speech_recognition` | `SFSpeechRecognizer.requestAuthorization()` | Speech | macOS 10.15+ |
| `location` | `CLLocationManager.requestAlwaysAuthorization()` | CoreLocation | |
| `contacts` | `CNContactStore.requestAccess(for:)` | Contacts | |
| `calendars` | `EKEventStore.requestFullAccessToEvents()` | EventKit | macOS 14+ API with fallback |
| `reminders` | `EKEventStore.requestFullAccessToReminders()` | EventKit | **New** |
| `photos` | `PHPhotoLibrary.requestAuthorization(for:)` | Photos | |
| `bluetooth` | `CBCentralManager` init triggers TCC, check via `CBManager.authorization` | CoreBluetooth | **New in native**. macOS 10.15+ |

### Not Supported Programmatically

- **Accessibility** — requires manual toggle in System Settings
- **Screen Recording** — requires manual toggle in System Settings

The extension provides deep-link commands to open the correct System Settings pane for these.

## Extension UX

### Commands

| Command | Description |
|---------|-------------|
| `macOS Permissions: Request All` | Quick Pick with multi-select |
| `macOS Permissions: Show Status` | Status overview with icons |
| `macOS Permissions: Open Privacy Settings` | Deep-link to System Settings |
| Individual permission commands | Available in Command Palette |

### Status Bar

Right-aligned shield icon: `$(shield) All OK` or `$(shield) 2 denied`. Click opens status overview.

### Startup Check

Optional setting `macosPermissions.checkOnStartup`. Shows notification with "Request" / "Open Settings" if denied permissions are detected.

## Build & Distribution

### Local Development

```bash
npm install        # node-gyp builds the native addon
npm run compile    # TypeScript compilation
```

Requires Xcode Command Line Tools for local builds.

### Marketplace Distribution

- `prebuildify` creates universal binaries (arm64 + x86_64) at publish time
- The `.vsix` includes prebuilds — users do NOT need Xcode
- `node-gyp-build` resolves the correct prebuild at runtime
- Fallback: if no prebuild matches, node-gyp builds locally

### Test Strategy

- **Unit tests (TypeScript):** Command registration, status bar logic, JSON parsing, permission type mapping
- **Integration test:** Addon loads correctly, `checkPermission()` returns a valid status string
- **No automated test for `requestPermission()`** — requires user interaction for TCC dialog
- CI runs on macOS runners only (platform-specific extension)

## What Gets Removed

- `native/PermissionHelper.swift` — replaced by `native/permissions.mm`
- `native/PermissionHelper.app` — no longer needed (in-process)
- `native/build.sh` — replaced by `binding.gyp`
- `macos-permissions-0.1.0.vsix` — will be rebuilt
- Symlink `native/PermissionHelper` — removed

## System Settings Deep-Links

For permissions that can't be requested programmatically, and as fallback for denied permissions:

| Permission | URL |
|------------|-----|
| Microphone | `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone` |
| Camera | `x-apple.systempreferences:com.apple.preference.security?Privacy_Camera` |
| Speech Recognition | `x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition` |
| Location | `x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices` |
| Contacts | `x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts` |
| Calendars | `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars` |
| Reminders | `x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders` |
| Photos | `x-apple.systempreferences:com.apple.preference.security?Privacy_Photos` |
| Bluetooth | `x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth` |
| Accessibility | `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` |
| Screen Recording | `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` |
