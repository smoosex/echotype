import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let appLanguage: AppLanguage
    let hotkeyHint: String
    let onRefreshPermissions: () -> Void
    let onboardingCompleted: Bool
    let onOpenWelcomeGuide: () -> Void
    let onOpenSettings: () -> Void
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
        .onAppear(perform: onRefreshPermissions)
    }
}
