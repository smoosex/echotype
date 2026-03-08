import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
struct SettingsView: View {
    @ObservedObject var stateStore: AppStateStore
    @ObservedObject var configurationStore: STTConfigurationStore
    @ObservedObject var preferencesStore: AppPreferencesStore
    let microphonePermission: PermissionState
    let accessibilityPermission: PermissionState
    let hotkeyHint: String
    let hotkeyGlyphHint: String
    let hotkeyKeyCode: UInt32
    let hotkeyModifiers: UInt32
    let hotkeyEnabled: Bool
    let hotkeyError: String?
    let hotkeyWarning: String?
    let onUpdateHotkey: (UInt32, UInt32) -> String?
    let onSetHotkeyEnabled: (Bool) -> String?
    let onRestoreDefaultHotkey: () -> String?
    let onRequestMicrophone: () -> Void
    let onRequestAccessibility: () -> Void
    let onRefreshPermissions: () -> Void
    let onOpenMicrophoneSettings: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    @State private var hotkeyRecorderMessage: String?
    @State private var hotkeyRecorderError: String?
    @State private var hotkeyEnabledState: Bool
    @State private var deleteConfirmationModel: STTModelOption?
    private var uiLanguage: AppLanguage { preferencesStore.appLanguage }

    init(
        stateStore: AppStateStore,
        configurationStore: STTConfigurationStore,
        preferencesStore: AppPreferencesStore,
        microphonePermission: PermissionState,
        accessibilityPermission: PermissionState,
        hotkeyHint: String,
        hotkeyGlyphHint: String,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        hotkeyEnabled: Bool,
        hotkeyError: String?,
        hotkeyWarning: String?,
        onUpdateHotkey: @escaping (UInt32, UInt32) -> String?,
        onSetHotkeyEnabled: @escaping (Bool) -> String?,
        onRestoreDefaultHotkey: @escaping () -> String?,
        onRequestMicrophone: @escaping () -> Void,
        onRequestAccessibility: @escaping () -> Void,
        onRefreshPermissions: @escaping () -> Void,
        onOpenMicrophoneSettings: @escaping () -> Void,
        onOpenAccessibilitySettings: @escaping () -> Void
    ) {
        _stateStore = ObservedObject(wrappedValue: stateStore)
        _configurationStore = ObservedObject(wrappedValue: configurationStore)
        _preferencesStore = ObservedObject(wrappedValue: preferencesStore)
        self.microphonePermission = microphonePermission
        self.accessibilityPermission = accessibilityPermission
        self.hotkeyHint = hotkeyHint
        self.hotkeyGlyphHint = hotkeyGlyphHint
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.hotkeyEnabled = hotkeyEnabled
        self.hotkeyError = hotkeyError
        self.hotkeyWarning = hotkeyWarning
        self.onUpdateHotkey = onUpdateHotkey
        self.onSetHotkeyEnabled = onSetHotkeyEnabled
        self.onRestoreDefaultHotkey = onRestoreDefaultHotkey
        self.onRequestMicrophone = onRequestMicrophone
        self.onRequestAccessibility = onRequestAccessibility
        self.onRefreshPermissions = onRefreshPermissions
        self.onOpenMicrophoneSettings = onOpenMicrophoneSettings
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        _hotkeyEnabledState = State(initialValue: hotkeyEnabled)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label(
                        L10n.text(L10nKey.settingsTabGeneral, language: uiLanguage),
                        systemImage: "gearshape"
                    )
                }

            modelTab
                .tabItem {
                    Label(
                        L10n.text(L10nKey.settingsTabEngine, language: uiLanguage),
                        systemImage: "waveform"
                    )
                }
        }
        .padding()
        .frame(width: 550, height: 450)
    }

    private var generalTab: some View {
        Form {
            Section(L10n.text(L10nKey.settingsSectionLanguage, language: uiLanguage)) {
                Picker(
                    L10n.text(L10nKey.settingsLanguage, language: uiLanguage),
                    selection: $preferencesStore.appLanguage
                ) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.localizedOptionTitle(in: uiLanguage)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .id("settings.language.\(uiLanguage.rawValue)")
            }

            Section(L10n.text(L10nKey.settingsSectionStatus, language: uiLanguage)) {
                LabeledContent(
                    L10n.text(L10nKey.settingsCurrentState, language: uiLanguage),
                    value: stateStore.state.title(in: uiLanguage)
                )
                LabeledContent(
                    L10n.text(L10nKey.settingsHotkey, language: uiLanguage),
                    value: hotkeyHint
                )
            }

            Section(L10n.text(L10nKey.settingsSectionHotkey, language: uiLanguage)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(L10n.text(L10nKey.settingsGlobalShortcut, language: uiLanguage))
                            .font(.subheadline.weight(.semibold))
                        hotkeyStatusBadge
                        hotkeyGlyphBadge
                        Spacer()
                        Toggle(
                            L10n.text(L10nKey.settingsEnableGlobalHotkey, language: uiLanguage),
                            isOn: $hotkeyEnabledState
                        )
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    HStack(alignment: .center, spacing: 8) {
                        KeyboardShortcuts.Recorder(for: .toggleRecording) { shortcut in
                            handleHotkeyRecorderChange(shortcut)
                        }
                        .frame(width: 220, alignment: .leading)
                        Spacer(minLength: 0)

                        Button {
                            if let error = onRestoreDefaultHotkey() {
                                hotkeyRecorderError = error
                                hotkeyRecorderMessage = nil
                            } else {
                                hotkeyRecorderError = nil
                                hotkeyRecorderMessage = L10n.text(
                                    L10nKey.settingsHotkeyRestoredDefault,
                                    language: uiLanguage
                                )
                            }
                        } label: {
                            Label(
                                L10n.text(L10nKey.settingsDefault, language: uiLanguage),
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text(L10n.text(L10nKey.settingsHotkeyHelp, language: uiLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let error = hotkeyRecorderError ?? hotkeyError {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let warning = hotkeyWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let message = hotkeyRecorderMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L10n.text(L10nKey.settingsSectionBehavior, language: uiLanguage)) {
                Picker(
                    L10n.text(L10nKey.settingsInjectionMode, language: uiLanguage),
                    selection: $preferencesStore.injectionMode
                ) {
                    ForEach(TextInjectionMode.allCases) { mode in
                        Text(mode.title(in: uiLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .id("settings.injection_mode.\(uiLanguage.rawValue)")
            }

            Section(L10n.text(L10nKey.settingsSectionPermissions, language: uiLanguage)) {
                PermissionStatusRow(
                    appLanguage: uiLanguage,
                    title: L10n.text(L10nKey.permissionMicrophone, language: uiLanguage),
                    state: microphonePermission,
                    requestAction: onRequestMicrophone,
                    openSettingsAction: onOpenMicrophoneSettings
                )

                PermissionStatusRow(
                    appLanguage: uiLanguage,
                    title: L10n.text(L10nKey.permissionAccessibility, language: uiLanguage),
                    state: accessibilityPermission,
                    requestAction: onRequestAccessibility,
                    openSettingsAction: onOpenAccessibilitySettings
                )

                HStack {
                    Spacer()
                    Button(L10n.text(L10nKey.settingsRefreshStatus, language: uiLanguage), action: onRefreshPermissions)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Text(L10n.text(L10nKey.settingsPermissionsHelp, language: uiLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text(L10nKey.settingsSectionPrivacy, language: uiLanguage)) {
                Toggle(L10n.text(L10nKey.settingsKeepTempAudio, language: uiLanguage), isOn: $preferencesStore.keepAudioFiles)
                Text(L10n.text(L10nKey.settingsKeepTempAudioHelp, language: uiLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: hotkeyEnabledState) { _, newValue in
            guard newValue != hotkeyEnabled else { return }
            if let error = onSetHotkeyEnabled(newValue) {
                hotkeyRecorderError = error
                hotkeyRecorderMessage = nil
                hotkeyEnabledState = hotkeyEnabled
            } else {
                hotkeyRecorderError = nil
                hotkeyRecorderMessage = newValue
                    ? L10n.text(L10nKey.settingsGlobalHotkeyEnabled, language: uiLanguage)
                    : L10n.text(L10nKey.settingsGlobalHotkeyDisabled, language: uiLanguage)
            }
        }
        .onChange(of: hotkeyEnabled) { _, newValue in
            guard hotkeyEnabledState != newValue else { return }
            hotkeyEnabledState = newValue
        }
        .onAppear(perform: onRefreshPermissions)
    }

    private var hotkeyStatusBadge: some View {
        Text(
            hotkeyEnabledState
                ? L10n.text(L10nKey.settingsEnabled, language: uiLanguage)
                : L10n.text(L10nKey.settingsDisabled, language: uiLanguage)
        )
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(hotkeyEnabledState ? .green : .secondary)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        hotkeyEnabledState
                            ? Color.green.opacity(0.14)
                            : Color.secondary.opacity(0.15)
                    )
            )
    }

    private var hotkeyGlyphBadge: some View {
        Text(hotkeyGlyphHint)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.primary)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }

    private func handleHotkeyRecorderChange(_ shortcut: KeyboardShortcuts.Shortcut?) {
        guard let shortcut else {
            if let error = onRestoreDefaultHotkey() {
                hotkeyRecorderError = error
                hotkeyRecorderMessage = nil
            } else {
                hotkeyRecorderError = nil
                hotkeyRecorderMessage = L10n.text(
                    L10nKey.settingsHotkeyClearedReverted,
                    language: uiLanguage
                )
            }
            return
        }

        let keyCode = UInt32(shortcut.carbonKeyCode)
        let modifiers = UInt32(shortcut.carbonModifiers)
        if let error = onUpdateHotkey(keyCode, modifiers) {
            hotkeyRecorderError = error
            hotkeyRecorderMessage = nil
            return
        }

        if !hotkeyEnabledState {
            hotkeyEnabledState = true
        }

        hotkeyRecorderError = nil
        hotkeyRecorderMessage = L10n.text(
            L10nKey.settingsHotkeyUpdatedFormat,
            language: uiLanguage,
            HotkeyDisplayFormatter.hint(forKeyCode: keyCode, modifiers: modifiers)
        )
    }

    private var modelTab: some View {
        Form {
            Section(L10n.text(L10nKey.settingsSectionStatus, language: uiLanguage)) {
                LabeledContent(
                    L10n.text(L10nKey.settingsModel, language: uiLanguage),
                    value: configurationStore.selectedModel.title
                )
                LabeledContent(
                    L10n.text(L10nKey.settingsCurrentState, language: uiLanguage),
                    value: configurationStore.readinessText
                )
            }

            Section(L10n.text(L10nKey.settingsSectionLanguageHint, language: uiLanguage)) {
                Picker(L10n.text(L10nKey.settingsSectionLanguageHint, language: uiLanguage), selection: languageHintBinding) {
                    ForEach(STTLanguageHint.allCases) { hint in
                        Text(hint.title(in: uiLanguage)).tag(hint)
                    }
                }
                .pickerStyle(.menu)
                .id("settings.language_hint.\(uiLanguage.rawValue)")
            }

            Section(L10n.text(L10nKey.settingsSectionModel, language: uiLanguage)) {
                VStack(spacing: 12) {
                    ForEach(STTModelOption.allCases) { model in
                        modelCard(for: model)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert(
            L10n.text(
                L10nKey.settingsDeleteModelTitleFormat,
                language: uiLanguage,
                deleteConfirmationModel?.title ?? ""
            ),
            isPresented: deleteAlertPresented,
            presenting: deleteConfirmationModel
        ) { model in
            Button(L10n.text(L10nKey.settingsDelete, language: uiLanguage), role: .destructive) {
                configurationStore.deleteModel(model)
                deleteConfirmationModel = nil
            }
            Button(L10n.text(L10nKey.commonCancel, language: uiLanguage), role: .cancel) {
                deleteConfirmationModel = nil
            }
        } message: { _ in
            Text(L10n.text(L10nKey.settingsDeleteModelMessageFormat, language: uiLanguage))
        }
    }

    private var languageHintBinding: Binding<STTLanguageHint> {
        Binding(
            get: {
                configurationStore.languageHint
            },
            set: { newHint in
                configurationStore.languageHintCode = newHint.transcriptionLanguageCode
            }
        )
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: {
                deleteConfirmationModel != nil
            },
            set: { newValue in
                if !newValue {
                    deleteConfirmationModel = nil
                }
            }
        )
    }

    @ViewBuilder
    private func modelCard(for model: STTModelOption) -> some View {
        let installState = configurationStore.installState(for: model)

        ModelDownloadCard(
            title: model.title,
            sizeText: model.downloadSizeText,
            isSelected: configurationStore.selectedModelID == model.rawValue,
            installState: installState,
            onSelect: {
                configurationStore.selectedModelID = model.rawValue
            },
            onInstall: {
                configurationStore.installModel(model)
            }
        )
        .contextMenu {
            if installState.isInstalled && !installState.isBusy {
                Button(L10n.text(L10nKey.settingsShowInFinder, language: uiLanguage)) {
                    configurationStore.revealModelInFinder(model)
                }

                Button(L10n.text(L10nKey.settingsDelete, language: uiLanguage), role: .destructive) {
                    deleteConfirmationModel = model
                }
            }
        }
    }
}

private struct ModelDownloadCard: View {
    let title: String
    let sizeText: String
    let isSelected: Bool
    let installState: ModelInstallRowState
    let onSelect: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onSelect) {
                    HStack(spacing: 12) {
                        ModelRadioIndicator(isSelected: isSelected)

                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(sizeText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                trailingControl
            }

            if let error = installState.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if installState.isBusy {
            ModelInstallProgressRing(
                progress: installState.progressFraction,
                tint: installState.activity == .deleting ? .secondary : .accentColor
            )
            .frame(width: 18, height: 18)
        } else if installState.isInstalled {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 18, height: 18)
        } else {
            Button(action: onInstall) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color(nsColor: .controlBackgroundColor)
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                isSelected
                    ? Color.accentColor.opacity(0.45)
                    : Color(nsColor: .separatorColor).opacity(0.5),
                lineWidth: 1
            )
    }
}

private struct ModelRadioIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.6),
                    lineWidth: 2
                )

            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .padding(4)
            }
        }
        .frame(width: 16, height: 16)
    }
}

private struct ModelInstallProgressRing: View {
    let progress: Double?
    let tint: Color

    @State private var rotationDegrees: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 2.5)

            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.06, min(progress, 1)))
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0.1, to: 0.72)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotationDegrees - 90))
                    .onAppear {
                        rotationDegrees = 0
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                            rotationDegrees = 360
                        }
                    }
            }
        }
    }
}
