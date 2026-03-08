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
                HStack(spacing: 8) {
                    Picker(L10n.text(L10nKey.settingsModel, language: uiLanguage), selection: $configurationStore.selectedModelID) {
                        ForEach(STTModelOption.allCases) { option in
                            Text(modelOptionTitle(for: option)).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(selectedModelInstalled
                        ? L10n.text(L10nKey.settingsDelete, language: uiLanguage)
                        : L10n.text(L10nKey.settingsInstall, language: uiLanguage)
                    ) {
                        handleSelectedModelAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(modelActionDisabled)
                }

                Text(configurationStore.selectedModel.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if configurationStore.isInstallingModel {
                    VStack(alignment: .leading, spacing: 4) {
                        if let progress = configurationStore.modelInstallProgressFraction {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                        } else {
                            ProgressView()
                                .progressViewStyle(.linear)
                        }
                        Text(configurationStore.modelInstallStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let transferText = configurationStore.modelInstallTransferText {
                            Text(transferText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let modelInstallError = configurationStore.modelInstallError {
                    Text(modelInstallError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var selectedModelInstalled: Bool {
        configurationStore.isModelInstalled(configurationStore.selectedModel)
    }

    private var modelActionDisabled: Bool {
        configurationStore.isInstallingModel
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

    private func modelOptionTitle(for option: STTModelOption) -> String {
        let installed: Bool
        installed = configurationStore.isModelInstalled(option)
        let status = installed
            ? L10n.text(L10nKey.settingsInstalled, language: uiLanguage)
            : L10n.text(L10nKey.settingsNotInstalled, language: uiLanguage)
        return L10n.text(L10nKey.settingsModelOptionFormat, language: uiLanguage, option.title, status)
    }

    private func handleSelectedModelAction() {
        if selectedModelInstalled {
            Task {
                await configurationStore.deleteSelectedModel()
            }
            return
        }

        Task {
            await configurationStore.installSelectedModel()
        }
    }
}
