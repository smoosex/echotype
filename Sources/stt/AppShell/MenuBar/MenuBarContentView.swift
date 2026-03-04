import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var stateStore: AppStateStore
    let appLanguage: AppLanguage
    let hotkeyHint: String
    let hotkeyError: String?
    let lastRecordingFile: String?
    let lastAudioValidation: String?
    let lastTranscription: String?
    let transcriptionHint: String
    let injectionStatus: String
    let microphonePermission: PermissionState
    let accessibilityPermission: PermissionState
    let onRequestMicrophone: () -> Void
    let onRequestAccessibility: () -> Void
    let onRefreshPermissions: () -> Void
    let onOpenMicrophoneSettings: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    let onboardingCompleted: Bool
    let onOpenWelcomeGuide: () -> Void
    let onOpenSettings: () -> Void
    let performanceSummary: String
    let metricsDirectoryPath: String
    let selfTestSummary: String
    let onRunSelfTest: () -> Void
    let onPaneOpen: () -> Void
    let onPaneClose: () -> Void
    let onPrimaryAction: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                L10n.text(
                    L10nKey.menuShortcutsFormat,
                    language: appLanguage,
                    hotkeyHint.isEmpty
                        ? L10n.text(L10nKey.menuNotSet, language: appLanguage)
                        : hotkeyHint
                ),
                systemImage: "keyboard"
            )
                .font(.body)
                .lineLimit(1)

            Button(action: onOpenWelcomeGuide) {
                Label(
                    onboardingCompleted
                        ? L10n.text(L10nKey.menuWelcomeGuide, language: appLanguage)
                        : L10n.text(L10nKey.menuWelcomeGuideNew, language: appLanguage),
                    systemImage: "sparkles"
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.body)

            Button(action: onOpenSettings) {
                Label(L10n.text(L10nKey.menuSettings, language: appLanguage), systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.body)

            Button(action: onQuit) {
                Label(L10n.text(L10nKey.menuQuit, language: appLanguage), systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.body)
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .onAppear {
            onPaneOpen()
            onRefreshPermissions()
        }
        .onDisappear(perform: onPaneClose)
    }
}
