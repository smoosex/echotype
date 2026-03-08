import SwiftUI

struct WelcomeGuideView: View {
    let appLanguage: AppLanguage
    let microphonePermission: PermissionState
    let accessibilityPermission: PermissionState
    let onRequestMicrophone: () -> Void
    let onRequestAccessibility: () -> Void
    let onRefreshPermissions: () -> Void
    let onOpenMicrophoneSettings: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    let onDontShowAgainChanged: (Bool) -> Void
    let onStartUsing: (Bool) -> Void
    let onDismiss: (Bool) -> Void

    @State private var dontShowAgain: Bool

    init(
        appLanguage: AppLanguage,
        microphonePermission: PermissionState,
        accessibilityPermission: PermissionState,
        initiallyDontShowAgain: Bool,
        onRequestMicrophone: @escaping () -> Void,
        onRequestAccessibility: @escaping () -> Void,
        onRefreshPermissions: @escaping () -> Void,
        onOpenMicrophoneSettings: @escaping () -> Void,
        onOpenAccessibilitySettings: @escaping () -> Void,
        onDontShowAgainChanged: @escaping (Bool) -> Void,
        onStartUsing: @escaping (Bool) -> Void,
        onDismiss: @escaping (Bool) -> Void
    ) {
        self.appLanguage = appLanguage
        self.microphonePermission = microphonePermission
        self.accessibilityPermission = accessibilityPermission
        self.onRequestMicrophone = onRequestMicrophone
        self.onRequestAccessibility = onRequestAccessibility
        self.onRefreshPermissions = onRefreshPermissions
        self.onOpenMicrophoneSettings = onOpenMicrophoneSettings
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        self.onDontShowAgainChanged = onDontShowAgainChanged
        self.onStartUsing = onStartUsing
        self.onDismiss = onDismiss
        _dontShowAgain = State(initialValue: initiallyDontShowAgain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(L10nKey.welcomeTitle, language: appLanguage))
                    .font(.title2.bold())
                Text(L10n.text(L10nKey.welcomeSubtitle, language: appLanguage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GroupBox(L10n.text(L10nKey.welcomePermissions, language: appLanguage)) {
                VStack(alignment: .leading, spacing: 12) {
                    PermissionStatusRow(
                        appLanguage: appLanguage,
                        title: L10n.text(L10nKey.permissionMicrophone, language: appLanguage),
                        state: microphonePermission,
                        requestAction: onRequestMicrophone,
                        openSettingsAction: onOpenMicrophoneSettings,
                        prominentTitle: true
                    )

                    Divider()

                    PermissionStatusRow(
                        appLanguage: appLanguage,
                        title: L10n.text(L10nKey.permissionAccessibility, language: appLanguage),
                        state: accessibilityPermission,
                        requestAction: onRequestAccessibility,
                        openSettingsAction: onOpenAccessibilitySettings,
                        prominentTitle: true
                    )

                    HStack(spacing: 8) {
                        Spacer()
                        Button(L10n.text(L10nKey.welcomeRefreshStatus, language: appLanguage), action: onRefreshPermissions)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)
            }

            GroupBox(L10n.text(L10nKey.welcomeHowItWorks, language: appLanguage)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text(L10nKey.welcomeStep1, language: appLanguage))
                    Text(L10n.text(L10nKey.welcomeStep2, language: appLanguage))
                    Text(L10n.text(L10nKey.welcomeStep3, language: appLanguage))
                    Text(L10n.text(L10nKey.welcomeStep4, language: appLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .padding(.horizontal, 8)
            }

            Toggle(L10n.text(L10nKey.welcomeDontShowAgain, language: appLanguage), isOn: $dontShowAgain)
                .onChange(of: dontShowAgain) { _, newValue in
                    onDontShowAgainChanged(newValue)
                }

            HStack(spacing: 8) {
                Spacer()
                Button(L10n.text(L10nKey.welcomeClose, language: appLanguage)) {
                    onDismiss(dontShowAgain)
                }
                .buttonStyle(.bordered)

                Button(L10n.text(L10nKey.welcomeStartUsing, language: appLanguage)) {
                    onStartUsing(dontShowAgain)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 580, alignment: .topLeading)
        .onAppear(perform: onRefreshPermissions)
    }
}
