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
                    permissionRow(
                        title: L10n.text(L10nKey.permissionMicrophone, language: appLanguage),
                        state: microphonePermission,
                        requestAction: onRequestMicrophone,
                        openSettingsAction: onOpenMicrophoneSettings
                    )

                    Divider()

                    permissionRow(
                        title: L10n.text(L10nKey.permissionAccessibility, language: appLanguage),
                        state: accessibilityPermission,
                        requestAction: onRequestAccessibility,
                        openSettingsAction: onOpenAccessibilitySettings
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
                .onChange(of: dontShowAgain) { onDontShowAgainChanged($0) }

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

    private func permissionRow(
        title: String,
        state: PermissionState,
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(permissionStateTitle(state))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(permissionStateColor(state))
            }

            HStack(spacing: 8) {
                Button(L10n.text(L10nKey.permissionRequest, language: appLanguage), action: requestAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(L10n.text(L10nKey.permissionOpenSettings, language: appLanguage), action: openSettingsAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func permissionStateTitle(_ state: PermissionState) -> String {
        switch state {
        case .authorized:
            return L10n.text(L10nKey.permissionAuthorized, language: appLanguage)
        case .denied:
            return L10n.text(L10nKey.permissionDenied, language: appLanguage)
        case .restricted:
            return L10n.text(L10nKey.permissionRestricted, language: appLanguage)
        case .notDetermined:
            return L10n.text(L10nKey.permissionNotDetermined, language: appLanguage)
        }
    }

    private func permissionStateColor(_ state: PermissionState) -> Color {
        switch state {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        }
    }
}
