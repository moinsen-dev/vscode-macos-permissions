import * as vscode from 'vscode';
import { execSync } from 'child_process';
import {
    PermissionType,
    PermissionStatus,
    PERMISSION_LABELS,
    SETTINGS_URLS,
    loadAddon,
    requestPermission,
    checkAll,
} from './permissions';

let statusBarItem: vscode.StatusBarItem;
let outputChannel: vscode.OutputChannel;

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

/** Convert snake_case to PascalCase: speech_recognition -> SpeechRecognition */
function toPascal(s: string): string {
    return s.replace(/(^|_)([a-z])/g, (_, __, c: string) => c.toUpperCase());
}

function statusIcon(s: PermissionStatus): string {
    switch (s) {
        case 'granted': return '$(check)';
        case 'denied': return '$(x)';
        case 'not_determined': return '$(question)';
        case 'restricted': return '$(lock)';
        default: return '$(warning)';
    }
}

function openSettingsForPermission(type: string): void {
    const pane = SETTINGS_URLS[type] ?? 'Privacy';
    execSync(`open "x-apple.systempreferences:com.apple.preference.security?${pane}"`);
}

/* ------------------------------------------------------------------ */
/*  Status bar                                                         */
/* ------------------------------------------------------------------ */

function updateStatusBar(extPath: string): void {
    try {
        const results = checkAll(extPath);
        const denied = Object.values(results).filter(s => s === 'denied').length;

        if (denied > 0) {
            statusBarItem.text = `$(shield) ${denied} denied`;
            statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
            statusBarItem.tooltip = `${denied} macOS permission(s) denied - Click to view`;
        } else {
            statusBarItem.text = '$(shield) All OK';
            statusBarItem.backgroundColor = undefined;
            statusBarItem.tooltip = 'All macOS permissions granted';
        }
    } catch {
        statusBarItem.text = '$(shield) ?';
        statusBarItem.tooltip = 'Click to check macOS permissions';
    }
}

/* ------------------------------------------------------------------ */
/*  Commands                                                           */
/* ------------------------------------------------------------------ */

async function cmdRequestSingle(extPath: string, type: PermissionType): Promise<void> {
    const label = PERMISSION_LABELS[type];
    outputChannel.appendLine(`Requesting ${label}...`);

    try {
        const status = await requestPermission(extPath, type);
        outputChannel.appendLine(`${label}: ${status}`);

        if (status === 'granted') {
            vscode.window.showInformationMessage(`${label} permission granted!`);
        } else if (status === 'denied') {
            const choice = await vscode.window.showWarningMessage(
                `${label} permission was denied. You can grant it in System Settings.`,
                'Open Settings'
            );
            if (choice === 'Open Settings') {
                openSettingsForPermission(type);
            }
        }
        updateStatusBar(extPath);
    } catch (err) {
        outputChannel.appendLine(`Error requesting ${label}: ${err}`);
        vscode.window.showErrorMessage(`Failed to request ${label}: ${err}`);
    }
}

async function cmdRequestAll(extPath: string): Promise<void> {
    const currentStatuses = checkAll(extPath);

    const items = Object.values(PermissionType).map(type => ({
        label: PERMISSION_LABELS[type],
        description: currentStatuses[type],
        picked: currentStatuses[type] !== 'granted',
        type,
    }));

    const selected = await vscode.window.showQuickPick(items, {
        canPickMany: true,
        placeHolder: 'Select permissions to request',
        title: 'macOS Permissions',
    });

    if (!selected || selected.length === 0) { return; }

    outputChannel.show();
    outputChannel.appendLine('='.repeat(50));
    outputChannel.appendLine('Requesting macOS Permissions');
    outputChannel.appendLine('='.repeat(50));

    const results: { label: string; status: PermissionStatus }[] = [];

    await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: 'Requesting macOS Permissions', cancellable: false },
        async (progress) => {
            for (let i = 0; i < selected.length; i++) {
                const { type, label } = selected[i];
                progress.report({ message: `${label} (${i + 1}/${selected.length})`, increment: 100 / selected.length });

                try {
                    const status = await requestPermission(extPath, type);
                    outputChannel.appendLine(`${label}: ${status}`);
                    results.push({ label, status });
                } catch (err) {
                    outputChannel.appendLine(`${label}: error - ${err}`);
                    results.push({ label, status: 'unknown' });
                }
            }
        }
    );

    const granted = results.filter(r => r.status === 'granted').length;
    const denied = results.filter(r => r.status === 'denied').length;

    outputChannel.appendLine(`\nSummary: ${granted} granted, ${denied} denied, ${results.length - granted - denied} other`);

    if (denied > 0) {
        const choice = await vscode.window.showWarningMessage(
            `${denied} permission(s) were denied. Grant them in System Settings for full functionality.`,
            'Open Settings', 'OK'
        );
        if (choice === 'Open Settings') {
            openSettingsForPermission('');
        }
    } else if (granted === selected.length) {
        vscode.window.showInformationMessage('All requested permissions have been granted!');
    }

    updateStatusBar(extPath);
}

async function cmdShowStatus(extPath: string): Promise<void> {
    const results = checkAll(extPath);

    const items: (vscode.QuickPickItem & { permType: PermissionType })[] = Object.values(PermissionType).map(type => ({
        label: `${statusIcon(results[type])} ${PERMISSION_LABELS[type]}`,
        description: results[type],
        permType: type,
    }));

    const choice = await vscode.window.showQuickPick(items, {
        placeHolder: 'Permission status (select to request or open settings)',
        title: 'macOS Permission Status',
    });

    if (!choice) { return; }

    const action = await vscode.window.showQuickPick(
        ['Request Permission', 'Open System Settings', 'Cancel'],
        { placeHolder: `Action for ${PERMISSION_LABELS[choice.permType]}` }
    );

    if (action === 'Request Permission') {
        await cmdRequestSingle(extPath, choice.permType);
    } else if (action === 'Open System Settings') {
        openSettingsForPermission(choice.permType);
    }
}

function cmdOpenSystemPreferences(): void {
    execSync('open "x-apple.systempreferences:com.apple.preference.security?Privacy"');
}

/* ------------------------------------------------------------------ */
/*  Activation / Deactivation                                          */
/* ------------------------------------------------------------------ */

export function activate(context: vscode.ExtensionContext): void {
    if (process.platform !== 'darwin') {
        vscode.window.showInformationMessage('macOS Permissions extension only works on macOS.');
        return;
    }

    const extPath = context.extensionPath;

    // Eagerly load the native addon so failures surface immediately
    try {
        loadAddon(extPath);
    } catch (err) {
        vscode.window.showErrorMessage(`Failed to load native permissions addon: ${err}`);
        return;
    }

    outputChannel = vscode.window.createOutputChannel('macOS Permissions');

    // Status bar
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.command = 'macosPermissions.showStatus';
    context.subscriptions.push(statusBarItem);

    const config = vscode.workspace.getConfiguration('macosPermissions');

    if (config.get<boolean>('showStatusBarItem', true)) {
        updateStatusBar(extPath);
        statusBarItem.show();
    }

    // Register top-level commands
    context.subscriptions.push(
        vscode.commands.registerCommand('macosPermissions.requestAll', () => cmdRequestAll(extPath)),
        vscode.commands.registerCommand('macosPermissions.showStatus', () => cmdShowStatus(extPath)),
        vscode.commands.registerCommand('macosPermissions.openSystemPreferences', cmdOpenSystemPreferences),
    );

    // Register per-permission commands dynamically
    for (const type of Object.values(PermissionType)) {
        const cmdId = `macosPermissions.request${toPascal(type)}`;
        context.subscriptions.push(
            vscode.commands.registerCommand(cmdId, () => cmdRequestSingle(extPath, type))
        );
    }

    // Optional startup check
    if (config.get<boolean>('checkOnStartup', false)) {
        const results = checkAll(extPath);
        const denied = Object.entries(results).filter(([, s]) => s === 'denied');
        if (denied.length > 0) {
            const names = denied.map(([p]) => PERMISSION_LABELS[p as PermissionType] ?? p).join(', ');
            vscode.window.showWarningMessage(
                `Some macOS permissions are denied: ${names}`,
                'Request Permissions', 'Open Settings'
            ).then(choice => {
                if (choice === 'Request Permissions') { cmdRequestAll(extPath); }
                else if (choice === 'Open Settings') { cmdOpenSystemPreferences(); }
            });
        }
    }

    outputChannel.appendLine('macOS Permissions extension activated (native addon)');
}

export function deactivate(): void {
    outputChannel?.dispose();
}
