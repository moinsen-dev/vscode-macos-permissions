# macOS Permissions for VS Code

A VS Code extension that requests macOS permissions (microphone, camera, photos, speech recognition, etc.) **from within VS Code's process**, so that apps launched from VS Code inherit these permissions.

## The Problem

When you launch a Flutter or native macOS app from VS Code that requires permissions like microphone, photos, or speech recognition, macOS may deny access because:

1. The app is launched as a child process of VS Code
2. macOS TCC (Transparency, Consent, and Control) checks permissions against the parent process
3. VS Code hasn't requested these permissions, so they're not granted

## The Solution

This extension uses a **native N-API addon** that runs directly inside VS Code's Extension Host process. When it calls macOS permission APIs, the OS attributes the request to VS Code itself — not a separate helper app. Once granted, any app launched from VS Code inherits these permissions.

## Supported Permissions

| Permission | Description | Requestable |
|------------|-------------|-------------|
| Microphone | Audio recording, voice input | Yes |
| Camera | Video capture, QR scanning | Yes |
| Speech Recognition | Voice-to-text, dictation | Yes |
| Location | GPS, location services | Yes |
| Contacts | Address book access | Yes |
| Calendars | Calendar events | Yes |
| Reminders | Reminders access | Yes |
| Photos | Photo library access | Yes |
| Bluetooth | Bluetooth devices | Yes |
| Accessibility | Automation features | Manual only |
| Screen Recording | Screen capture | Manual only |

Accessibility and Screen Recording cannot be requested programmatically — the extension provides deep-links to the correct System Settings pane.

## Installation

### From VSIX

```bash
code --install-extension macos-permissions-0.2.0.vsix
```

### From Marketplace

Search for "macOS Permissions" in the VS Code extension marketplace.

### From Source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
cd vscode-macos-permissions
npm install
npm run build-native
npm run compile
```

## Usage

1. Open Command Palette (`Cmd+Shift+P`)
2. Type "macOS Permissions"
3. Select "Request All macOS Permissions"
4. Grant permissions in the system dialogs that appear

## Commands

| Command | Description |
|---------|-------------|
| `macOS Permissions: Request All macOS Permissions` | Request all permissions at once (multi-select) |
| `macOS Permissions: Show Permission Status` | View current permission status |
| `macOS Permissions: Request [Permission]` | Request a specific permission |
| `macOS Permissions: Open Privacy & Security Settings` | Open System Settings |

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `macosPermissions.showStatusBarItem` | `true` | Show permission status in status bar |
| `macosPermissions.checkOnStartup` | `false` | Check permissions when VS Code starts |

## How It Works

The extension includes a **native N-API addon** (ObjC++) that:

1. Is loaded directly into VS Code's Extension Host process via `require()`
2. Calls macOS permission APIs (AVFoundation, Photos, CoreLocation, etc.)
3. Because it runs in-process, macOS attributes the permission to **Visual Studio Code** — not a separate helper app
4. Returns permission status as strings ("granted", "denied", "not_determined", etc.)

Pre-built binaries are included for both Apple Silicon (arm64) and Intel (x86_64), so you don't need Xcode to install from the Marketplace.

## Troubleshooting

### Permission still denied after granting

1. Restart VS Code completely (Cmd+Q, then reopen)
2. Check System Settings > Privacy & Security > [Permission]
3. Ensure "Visual Studio Code" or "Code Helper (Plugin)" is listed and enabled

### Extension shows "Failed to load native addon"

```bash
# Rebuild the native addon
cd ~/.vscode/extensions/moinsen.macos-permissions-*/
npm run build-native
```

Requires Xcode Command Line Tools: `xcode-select --install`

### Accessibility / Screen Recording

These permissions cannot be requested programmatically. Use the "Open Privacy & Security Settings" command and toggle them manually.

## License

MIT
