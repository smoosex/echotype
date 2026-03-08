import SwiftUI

struct PermissionStatusRow: View {
    let appLanguage: AppLanguage
    let title: String
    let state: PermissionState
    let requestAction: () -> Void
    let openSettingsAction: () -> Void
    var prominentTitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(titleFont)
                Spacer()
                Text(permissionStateTitle(state))
                    .font(stateFont)
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

    private var titleFont: Font {
        prominentTitle ? .subheadline.weight(.semibold) : .body
    }

    private var stateFont: Font {
        prominentTitle ? .caption.weight(.semibold) : .caption
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
