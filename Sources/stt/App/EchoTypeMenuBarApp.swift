import SwiftUI
import AppKit

@main
@MainActor
struct EchoTypeMenuBarApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        let model = configuredAppModel

        MenuBarExtra("EchoType", systemImage: appModel.stateStore.state.symbolName) {
            MenuBarContentView(
                appLanguage: model.currentLanguage,
                hotkeyHint: model.hotkeyHint,
                onRefreshPermissions: model.refreshPermissions,
                onboardingCompleted: model.onboardingCompleted,
                onOpenWelcomeGuide: model.openWelcomeGuide,
                onOpenSettings: openSettingsWindow,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
        .menuBarExtraStyle(.menu)

        Window(L10n.text(L10nKey.menuSettings, language: model.currentLanguage), id: "settings") {
            SettingsView(
                stateStore: model.stateStore,
                configurationStore: model.sttConfigurationStore,
                preferencesStore: model.preferencesStore,
                microphonePermission: model.microphonePermission,
                accessibilityPermission: model.accessibilityPermission,
                hotkeyHint: model.hotkeyHint,
                hotkeyGlyphHint: model.hotkeyGlyphHint,
                hotkeyEnabled: model.hotkeyEnabled,
                hotkeyError: model.hotkeyError,
                hotkeyWarning: model.hotkeyWarning,
                onUpdateHotkey: model.updateHotkey,
                onSetHotkeyEnabled: model.setHotkeyEnabled,
                onRestoreDefaultHotkey: model.restoreDefaultHotkey,
                onRequestMicrophone: model.requestMicrophonePermission,
                onRequestAccessibility: model.requestAccessibilityPermission,
                onRefreshPermissions: model.refreshPermissions,
                onOpenMicrophoneSettings: model.openMicrophoneSettings,
                onOpenAccessibilitySettings: model.openAccessibilitySettings
            )
        }
        .defaultSize(width: 520, height: 520)
    }

    private var configuredAppModel: AppModel {
        appModel.setOpenSettingsWindowHandler { openSettingsWindow() }
        return appModel
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}
