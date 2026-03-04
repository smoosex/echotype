import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
struct SettingsView: View {
    @ObservedObject var stateStore: AppStateStore
    @ObservedObject var configurationStore: WhisperConfigurationStore
    @ObservedObject var preferencesStore: AppPreferencesStore
    @ObservedObject var qwenCLIService: QwenCLIService
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
    @State private var selectedUnifiedModelID: String = ""
    @State private var isWhisperInstallHintPresented = false
    @State private var isQwenInstallHintPresented = false
    @State private var hotkeyRecorderMessage: String?
    @State private var hotkeyRecorderError: String?
    @State private var hotkeyEnabledState: Bool
    private var uiLanguage: AppLanguage { preferencesStore.appLanguage }

    init(
        stateStore: AppStateStore,
        configurationStore: WhisperConfigurationStore,
        preferencesStore: AppPreferencesStore,
        qwenCLIService: QwenCLIService,
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
        _qwenCLIService = ObservedObject(wrappedValue: qwenCLIService)
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
                permissionRow(
                    title: L10n.text(L10nKey.permissionMicrophone, language: uiLanguage),
                    state: microphonePermission,
                    requestAction: onRequestMicrophone,
                    openSettingsAction: onOpenMicrophoneSettings
                )

                permissionRow(
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
        .onChange(of: hotkeyEnabledState) { newValue in
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
        .onChange(of: hotkeyEnabled) { newValue in
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
            Section(L10n.text(L10nKey.settingsSectionRuntime, language: uiLanguage)) {
                HStack(alignment: .center, spacing: 12) {
                    Text(L10n.text(L10nKey.settingsEngine, language: uiLanguage))
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 64, alignment: .leading)

                    HStack(spacing: 8) {
                        Picker(L10n.text(L10nKey.settingsEngine, language: uiLanguage), selection: $configurationStore.backend) {
                            ForEach(STTBackend.allCases) { backend in
                                Text(backend.title(in: uiLanguage)).tag(backend)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("settings.engine.\(uiLanguage.rawValue)")

                        Text(currentRuntimeStatusTitle)
                            .foregroundStyle(currentRuntimeStatusColor)
                        if !selectedEngineRuntimeInstalled {
                            Button(L10n.text(L10nKey.settingsInstall, language: uiLanguage)) {
                                handleRuntimeInstallAction()
                            }
                            .buttonStyle(.bordered)
                        }
                        Button(L10n.text(L10nKey.settingsDetect, language: uiLanguage)) {
                            handleRuntimeDetectAction()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }

            Section(L10n.text(L10nKey.settingsSectionLanguageHint, language: uiLanguage)) {
                Picker(L10n.text(L10nKey.settingsSectionLanguageHint, language: uiLanguage), selection: unifiedLanguageHintBinding) {
                    ForEach(WhisperTranscriptionLanguage.allCases) { hint in
                        Text(hint.title(in: uiLanguage)).tag(hint)
                    }
                }
                .pickerStyle(.menu)
                .id("settings.language_hint.\(uiLanguage.rawValue)")
            }

            Section(L10n.text(L10nKey.settingsSectionModel, language: uiLanguage)) {
                HStack(spacing: 8) {
                    Picker(L10n.text(L10nKey.settingsModel, language: uiLanguage), selection: $selectedUnifiedModelID) {
                        ForEach(currentEngineModelOptions) { option in
                            Text(modelOptionTitle(for: option)).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: selectedUnifiedModelID) { newID in
                        applyUnifiedModelSelection(newID)
                    }

                    Button(selectedModelInstalled
                        ? L10n.text(L10nKey.settingsDelete, language: uiLanguage)
                        : L10n.text(L10nKey.settingsInstall, language: uiLanguage)
                    ) {
                        handleSelectedModelAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(modelActionDisabled)
                }

                if let runtimeHint = selectedModelRuntimeHint {
                    Text(runtimeHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if configurationStore.isInstallingModel || configurationStore.isModelInstallPaused {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if let progress = configurationStore.modelInstallProgressFraction {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                            } else {
                                ProgressView()
                                    .progressViewStyle(.linear)
                            }
                            Button {
                                if configurationStore.isModelInstallPaused {
                                    configurationStore.startInstallSelectedModel()
                                } else {
                                    configurationStore.pauseModelInstallation()
                                }
                            } label: {
                                Image(systemName: configurationStore.isModelInstallPaused ? "play.circle.fill" : "pause.circle.fill")
                            }
                            .buttonStyle(.plain)
                            Button {
                                configurationStore.cancelModelInstallation()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        Text(configurationStore.modelInstallStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(configurationStore.modelInstallSizeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if qwenCLIService.isInstallingModel {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView()
                            .progressViewStyle(.linear)
                        Text(qwenCLIService.modelInstallStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let modelInstallError = configurationStore.modelInstallError {
                    Text(modelInstallError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let qwenModelInstallError = qwenCLIService.modelInstallError {
                    Label(qwenModelInstallError, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            qwenCLIService.refreshEnvironment()
            syncUnifiedModelSelectionFromConfiguration()
        }
        .onChange(of: configurationStore.backend) { _ in
            syncUnifiedModelSelectionFromConfiguration()
        }
        .onChange(of: configurationStore.selectedModelFileName) { _ in
            guard configurationStore.backend == .whisperCpp else { return }
            syncUnifiedModelSelectionFromConfiguration()
        }
        .onChange(of: configurationStore.qwenModelName) { _ in
            guard configurationStore.backend == .qwen3ASRServer else { return }
            syncUnifiedModelSelectionFromConfiguration()
        }
        .alert(L10n.text(L10nKey.settingsAlertInstallWhisperTitle, language: uiLanguage), isPresented: $isWhisperInstallHintPresented) {
            Button(L10n.text(L10nKey.commonOk, language: uiLanguage), role: .cancel) { }
        } message: {
            Text(L10n.text(L10nKey.settingsAlertInstallWhisperMessage, language: uiLanguage))
        }
        .alert(L10n.text(L10nKey.settingsAlertInstallQwenTitle, language: uiLanguage), isPresented: $isQwenInstallHintPresented) {
            Button(L10n.text(L10nKey.commonOk, language: uiLanguage), role: .cancel) { }
        } message: {
            Text(L10n.text(L10nKey.settingsAlertInstallQwenMessage, language: uiLanguage))
        }
    }

    private var unifiedModelOptions: [UnifiedModelOption] {
        let whisperOptions = WhisperModelSize.allCases.map { size in
            UnifiedModelOption.whisper(WhisperModelCatalog.descriptor(size: size, language: .chinese))
        }
        let qwenOptions = QwenASRModelPreset.allCases.map { UnifiedModelOption.qwen($0) }
        return whisperOptions + qwenOptions
    }

    private var currentEngineModelOptions: [UnifiedModelOption] {
        switch configurationStore.backend {
        case .whisperCpp:
            return unifiedModelOptions.filter {
                if case .whisper = $0 { return true }
                return false
            }
        case .qwen3ASRServer:
            return unifiedModelOptions.filter {
                if case .qwen = $0 { return true }
                return false
            }
        }
    }

    private var selectedEngineRuntimeInstalled: Bool {
        switch configurationStore.backend {
        case .whisperCpp:
            return configurationStore.isWhisperRuntimeInstalled
        case .qwen3ASRServer:
            return qwenCLIService.isRuntimeInstalled
        }
    }

    private var currentRuntimeStatusTitle: String {
        selectedEngineRuntimeInstalled
            ? L10n.text(L10nKey.settingsInstalled, language: uiLanguage)
            : L10n.text(L10nKey.settingsNotInstalled, language: uiLanguage)
    }

    private var currentRuntimeStatusColor: Color {
        selectedEngineRuntimeInstalled ? .green : .orange
    }

    private var selectedUnifiedModel: UnifiedModelOption? {
        currentEngineModelOptions.first(where: { $0.id == selectedUnifiedModelID })
    }

    private var selectedModelInstalled: Bool {
        guard let selectedUnifiedModel else { return false }
        switch selectedUnifiedModel {
        case let .whisper(descriptor):
            return configurationStore.installedModels.contains { $0.fileName == descriptor.fileName }
        case let .qwen(preset):
            return qwenCLIService.isModelInstalled(modelIdentifier: preset.rawValue)
        }
    }

    private var selectedModelRuntimeInstalled: Bool {
        guard let selectedUnifiedModel else { return false }
        switch selectedUnifiedModel {
        case .whisper:
            return configurationStore.isWhisperRuntimeInstalled
        case .qwen:
            return qwenCLIService.isRuntimeInstalled
        }
    }

    private var selectedModelRuntimeHint: String? {
        guard let selectedUnifiedModel, !selectedModelRuntimeInstalled else { return nil }
        switch selectedUnifiedModel {
        case .whisper:
            return L10n.text(L10nKey.settingsRuntimeHintWhisper, language: uiLanguage)
        case .qwen:
            return L10n.text(L10nKey.settingsRuntimeHintQwen, language: uiLanguage)
        }
    }

    private var modelActionDisabled: Bool {
        guard let selectedUnifiedModel else { return true }
        if !selectedModelRuntimeInstalled {
            return true
        }
        switch selectedUnifiedModel {
        case .whisper:
            return configurationStore.isInstallingModel
        case .qwen:
            return qwenCLIService.isInstallingModel
        }
    }

    private var unifiedLanguageHintBinding: Binding<WhisperTranscriptionLanguage> {
        Binding(
            get: {
                switch configurationStore.backend {
                case .whisperCpp:
                    return WhisperTranscriptionLanguage
                        .fromTranscriptionLanguageCode(configurationStore.language) ?? .auto
                case .qwen3ASRServer:
                    switch QwenLanguageHint.fromPersistedCode(configurationStore.qwenLanguageHint) ?? .auto {
                    case .auto:
                        return .auto
                    case .chinese:
                        return .chinese
                    case .english:
                        return .english
                    }
                }
            },
            set: { newHint in
                configurationStore.language = newHint.transcriptionLanguageCode
                switch newHint {
                case .auto:
                    configurationStore.qwenLanguageHint = QwenLanguageHint.auto.persistedCode
                case .chinese:
                    configurationStore.qwenLanguageHint = QwenLanguageHint.chinese.persistedCode
                case .english:
                    configurationStore.qwenLanguageHint = QwenLanguageHint.english.persistedCode
                }
            }
        )
    }

    private func modelOptionTitle(for option: UnifiedModelOption) -> String {
        let installed: Bool
        switch option {
        case let .whisper(descriptor):
            installed = configurationStore.installedModels.contains { $0.fileName == descriptor.fileName }
        case let .qwen(preset):
            installed = qwenCLIService.isModelInstalled(modelIdentifier: preset.rawValue)
        }
        let status = installed
            ? L10n.text(L10nKey.settingsInstalled, language: uiLanguage)
            : L10n.text(L10nKey.settingsNotInstalled, language: uiLanguage)
        return L10n.text(L10nKey.settingsModelOptionFormat, language: uiLanguage, option.title, status)
    }

    private func handleRuntimeInstallAction() {
        switch configurationStore.backend {
        case .whisperCpp:
            isWhisperInstallHintPresented = true
        case .qwen3ASRServer:
            isQwenInstallHintPresented = true
        }
    }

    private func handleRuntimeDetectAction() {
        switch configurationStore.backend {
        case .whisperCpp:
            configurationStore.autoDetectExecutable()
        case .qwen3ASRServer:
            configurationStore.autoDetectQwenExecutable()
            qwenCLIService.refreshEnvironment()
            if configurationStore.qwenCLIPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let detected = qwenCLIService.qwenCLIPath {
                configurationStore.qwenCLIPath = detected
            }
        }
    }

    private func syncUnifiedModelSelectionFromConfiguration() {
        switch configurationStore.backend {
        case .whisperCpp:
            let candidateFile = configurationStore.selectedModelFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let option = currentEngineModelOptions.first(where: { option in
                if case let .whisper(descriptor) = option {
                    return descriptor.fileName == candidateFile
                }
                return false
            }) {
                selectedUnifiedModelID = option.id
                return
            }
            selectedUnifiedModelID = configurationStore.selectedModelDescriptor.fileName.unifiedWhisperID
        case .qwen3ASRServer:
            if let preset = QwenASRModelPreset(rawValue: configurationStore.qwenModelName) {
                selectedUnifiedModelID = preset.unifiedQwenID
                qwenCLIService.selectedPreset = preset
                return
            }
            selectedUnifiedModelID = QwenASRModelPreset.model0_6B.unifiedQwenID
            qwenCLIService.selectedPreset = .model0_6B
        }
    }

    private func applyUnifiedModelSelection(_ modelID: String) {
        guard let option = currentEngineModelOptions.first(where: { $0.id == modelID }) else { return }
        switch option {
        case let .whisper(descriptor):
            configurationStore.backend = .whisperCpp
            configurationStore.selectedModelSize = descriptor.size
            configurationStore.selectedModelLanguage = descriptor.language
            configurationStore.selectedModelFileName = descriptor.fileName
            if configurationStore.modelDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let defaultPath = try? WhisperModelInstallerService.modelsDirectoryPath() {
                configurationStore.modelDirectoryPath = defaultPath
            }
        case let .qwen(preset):
            configurationStore.backend = .qwen3ASRServer
            configurationStore.qwenModelName = preset.rawValue
            qwenCLIService.selectedPreset = preset
        }
    }

    private func handleSelectedModelAction() {
        guard let selectedUnifiedModel else { return }
        if selectedModelInstalled {
            switch selectedUnifiedModel {
            case let .whisper(descriptor):
                configurationStore.selectedModelFileName = descriptor.fileName
                configurationStore.deleteSelectedModel()
            case let .qwen(preset):
                qwenCLIService.selectedPreset = preset
                configurationStore.qwenModelName = preset.rawValue
                qwenCLIService.uninstallSelectedModel()
            }
            return
        }

        switch selectedUnifiedModel {
        case let .whisper(descriptor):
            configurationStore.selectedModelSize = descriptor.size
            configurationStore.selectedModelLanguage = descriptor.language
            configurationStore.selectedModelFileName = descriptor.fileName
            configurationStore.backend = .whisperCpp
            configurationStore.startInstallSelectedModel()
        case let .qwen(preset):
            qwenCLIService.selectedPreset = preset
            configurationStore.qwenModelName = preset.rawValue
            configurationStore.backend = .qwen3ASRServer
            Task {
                await qwenCLIService.installSelectedModel()
                configurationStore.qwenModelName = qwenCLIService.selectedPreset.rawValue
            }
        }
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
                Spacer()
                Text(permissionStateTitle(state))
                    .font(.caption)
                    .foregroundStyle(permissionStateColor(state))
            }

            HStack(spacing: 8) {
                Button(L10n.text(L10nKey.permissionRequest, language: uiLanguage), action: requestAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(L10n.text(L10nKey.permissionOpenSettings, language: uiLanguage), action: openSettingsAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func permissionStateTitle(_ state: PermissionState) -> String {
        switch state {
        case .authorized:
            return L10n.text(L10nKey.permissionAuthorized, language: uiLanguage)
        case .denied:
            return L10n.text(L10nKey.permissionDenied, language: uiLanguage)
        case .restricted:
            return L10n.text(L10nKey.permissionRestricted, language: uiLanguage)
        case .notDetermined:
            return L10n.text(L10nKey.permissionNotDetermined, language: uiLanguage)
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

private enum UnifiedModelOption: Identifiable {
    case whisper(WhisperModelDescriptor)
    case qwen(QwenASRModelPreset)

    var id: String {
        switch self {
        case let .whisper(descriptor):
            return descriptor.fileName.unifiedWhisperID
        case let .qwen(preset):
            return preset.unifiedQwenID
        }
    }

    var title: String {
        switch self {
        case let .whisper(descriptor):
            return "Whisper \(descriptor.displayName)"
        case let .qwen(preset):
            return "Qwen3-ASR (\(preset.approximateSizeText))"
        }
    }
}

private extension String {
    var unifiedWhisperID: String {
        "whisper::\(self)"
    }
}

private extension QwenASRModelPreset {
    var unifiedQwenID: String {
        "qwen::\(rawValue)"
    }
}
