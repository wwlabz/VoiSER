import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation
import SwiftUI

@MainActor
public final class VoiceWidgetCoordinator: ObservableObject {
    @Published public private(set) var state: CaptureState = .idle
    @Published public private(set) var lastError: String?
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var widgetEnabled: Bool
    @Published public private(set) var preferredModel: WhisperModelOption
    @Published public private(set) var hotkeyPreset: HotkeyPreset
    @Published public private(set) var exclusiveSingleKeyCode: Int
    @Published public private(set) var exclusiveSingleKeyEnabled: Bool
    @Published public private(set) var exclusiveSingleKeyBlocksSystemDelivery: Bool
    @Published public private(set) var widgetStyle: WidgetStyleOption
    @Published public private(set) var textOutputMode: TextOutputMode
    @Published public private(set) var widgetPresentationMode: WidgetPresentationMode
    @Published public private(set) var modelPreparationProgress: Double = 0
    @Published public private(set) var modelPreparationMessage: String?
    @Published public private(set) var isModelReady = false
    @Published public private(set) var isModelInstallationInProgress = false

    private let audioRecordingService: AudioRecordingService
    private let speechTranscriptionService: SpeechTranscriptionService
    private let globalHotkeyService: GlobalHotkeyService
    private let overlayWidgetController: OverlayWidgetController
    private let textOutputService: TextOutputService
    private let microphonePermissionManager: MicrophonePermissionProviding
    private let launchAtLoginManager: LaunchAtLoginManaging
    private let settingsStore: AppSettingsStore
    private let alertPresenter: AlertPresenting

    private var didBootstrap = false
    private var isToggleInFlight = false
    private var prewarmTask: Task<Void, Never>?
    private var hasSuccessfulTranscription = false
    private var settingsWindowController: NSWindowController?
    private var whisperFlowWindowController: NSWindowController?
    private var activationObserver: NSObjectProtocol?
    private var lastExternalBundleIdentifier: String?
    private var captureTargetBundleIdentifier: String?

    public init(
        audioRecordingService: AudioRecordingService,
        speechTranscriptionService: SpeechTranscriptionService,
        globalHotkeyService: GlobalHotkeyService,
        overlayWidgetController: OverlayWidgetController,
        textOutputService: TextOutputService,
        microphonePermissionManager: MicrophonePermissionProviding,
        launchAtLoginManager: LaunchAtLoginManaging,
        settingsStore: AppSettingsStore,
        alertPresenter: AlertPresenting
    ) {
        self.audioRecordingService = audioRecordingService
        self.speechTranscriptionService = speechTranscriptionService
        self.globalHotkeyService = globalHotkeyService
        self.overlayWidgetController = overlayWidgetController
        self.textOutputService = textOutputService
        self.microphonePermissionManager = microphonePermissionManager
        self.launchAtLoginManager = launchAtLoginManager
        self.settingsStore = settingsStore
        self.alertPresenter = alertPresenter

        launchAtLoginEnabled = settingsStore.launchAtLoginEnabled
        widgetEnabled = settingsStore.widgetEnabled
        preferredModel = settingsStore.preferredModel
        hotkeyPreset = settingsStore.hotkeyPreset
        exclusiveSingleKeyCode = settingsStore.exclusiveSingleKeyCode ?? 49
        exclusiveSingleKeyEnabled = settingsStore.exclusiveSingleKeyEnabled
        exclusiveSingleKeyBlocksSystemDelivery = settingsStore.exclusiveSingleKeyBlocksSystemDelivery
        widgetStyle = settingsStore.widgetStyle
        textOutputMode = settingsStore.textOutputMode
        widgetPresentationMode = settingsStore.widgetPresentationMode

        audioRecordingService.setLevelUpdateHandler { [weak self] level in
            self?.overlayWidgetController.setInputLevel(level)
        }
        beginTrackingFrontmostApplication()
    }

    public func bootstrap() {
        guard !didBootstrap else {
            return
        }

        didBootstrap = true
        overlayWidgetController.setToggleHandler { [weak self] in
            self?.toggleCapture()
        }
        overlayWidgetController.setRetryModelHandler { [weak self] in
            self?.retryModelLoad()
        }
        overlayWidgetController.setOpenSettingsHandler { [weak self] in
            self?.openSettingsWindow()
        }
        overlayWidgetController.setResetPositionHandler { [weak self] in
            self?.resetWidgetPosition()
        }
        overlayWidgetController.setModelSelectionHandler { [weak self] model in
            self?.setPreferredModel(model)
        }
        overlayWidgetController.setHotkeySelectionHandler { [weak self] preset in
            self?.setHotkeyPreset(preset)
        }
        overlayWidgetController.setWidgetStyleSelectionHandler { [weak self] style in
            self?.setWidgetStyle(style)
        }
        overlayWidgetController.show()
        applyWidgetVisibilityForCurrentState()
        overlayWidgetController.update(state: state)
        overlayWidgetController.setSelectedModel(preferredModel)
        overlayWidgetController.setSelectedHotkeyPreset(hotkeyPreset)
        overlayWidgetController.setSelectedWidgetStyle(widgetStyle)

        globalHotkeyService.registerDefaultIfNeeded()
        globalHotkeyService.applyPreset(hotkeyPreset)
        globalHotkeyService.onToggleRecording { [weak self] in
            self?.toggleCapture()
        }
        applyExclusiveSingleKeyConfiguration()
        Task {
            await speechTranscriptionService.setPreferredModel(preferredModel)
        }
        if !settingsStore.didRunInitialSetup {
            setLaunchAtLoginEnabled(true)
            beginInitialSetupFlow()
        } else {
            setLaunchAtLoginEnabled(settingsStore.launchAtLoginEnabled)
            scheduleBackgroundModelPrewarm()
        }
    }

    public var menuBarSymbol: String {
        switch state {
        case .idle:
            "mic"
        case .installingModel:
            "arrow.down.circle"
        case .recording:
            "record.circle"
        case .transcribing:
            "waveform"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    public var shouldShowMenuBarLiveWidget: Bool {
        widgetPresentationMode != .overlayOnly
    }

    public var isPrimaryActionDisabled: Bool {
        switch state {
        case .installingModel, .transcribing:
            return true
        case .idle, .recording, .failed:
            return false
        }
    }

    public var canStartModelDownload: Bool {
        !isModelReady && !isModelInstallationInProgress
    }

    public var primaryActionTitle: String {
        switch state {
        case .installingModel:
            "Подготовка Whisper…"
        case .recording:
            "Остановить запись"
        case .transcribing:
            "Обработка…"
        case .idle, .failed:
            "Начать запись"
        }
    }

    public func toggleCapture() {
        Task { [weak self] in
            await self?.toggleCaptureNow()
        }
    }

    public func toggleCaptureNow() async {
        guard !isToggleInFlight else {
            return
        }

        isToggleInFlight = true
        defer { isToggleInFlight = false }

        switch state {
        case .idle, .failed:
            await startCapture()
        case .installingModel:
            break
        case .recording:
            await stopAndTranscribe()
        case .transcribing:
            break
        }
    }

    public func retryModelLoad() {
        Task { [weak self] in
            guard let self else {
                return
            }

            self.overlayWidgetController.setMessage("Переинициализирую модель…")
            do {
                try await self.speechTranscriptionService.recoverModelIfPossible()
                self.setState(.idle)
                self.lastError = nil
                self.overlayWidgetController.setMessage("Модель готова")
                self.clearOverlayMessageAfterDelay()
            } catch {
                self.fail(with: error.localizedDescription)
            }
        }
    }

    public func setWidgetEnabled(_ enabled: Bool) {
        widgetEnabled = enabled
        settingsStore.widgetEnabled = enabled
        applyWidgetVisibilityForCurrentState()
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginEnabled = enabled

        do {
            try launchAtLoginManager.setEnabled(enabled)
            settingsStore.launchAtLoginEnabled = enabled
        } catch {
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            fail(with: "Не удалось обновить автозапуск: \(error.localizedDescription)")
        }
    }

    public func resetWidgetPosition() {
        overlayWidgetController.resetPosition()
        overlayWidgetController.persistPosition()
    }

    public func setPreferredModel(_ model: WhisperModelOption) {
        guard preferredModel != model else {
            return
        }

        preferredModel = model
        settingsStore.preferredModel = model
        overlayWidgetController.setSelectedModel(model)
        overlayWidgetController.setMessage("Модель: \(model.title)")
        clearOverlayMessageAfterDelay()

        Task {
            await speechTranscriptionService.setPreferredModel(model)
        }
        scheduleBackgroundModelPrewarm()
    }

    public func setHotkeyPreset(_ preset: HotkeyPreset) {
        guard hotkeyPreset != preset else {
            return
        }

        hotkeyPreset = preset
        settingsStore.hotkeyPreset = preset
        overlayWidgetController.setSelectedHotkeyPreset(preset)
        globalHotkeyService.applyPreset(preset)
        applyExclusiveSingleKeyConfiguration()
        overlayWidgetController.setMessage("Хоткей: \(preset.title)")
        clearOverlayMessageAfterDelay()
    }

    public func setExclusiveSingleKeyEnabled(_ enabled: Bool) {
        guard exclusiveSingleKeyEnabled != enabled else {
            return
        }
        exclusiveSingleKeyEnabled = enabled
        settingsStore.exclusiveSingleKeyEnabled = enabled
        applyExclusiveSingleKeyConfiguration()
    }

    public func setExclusiveSingleKeyCode(_ keyCode: Int) {
        guard exclusiveSingleKeyCode != keyCode else {
            return
        }
        exclusiveSingleKeyCode = keyCode
        settingsStore.exclusiveSingleKeyCode = keyCode
        applyExclusiveSingleKeyConfiguration()
    }

    public func setExclusiveSingleKeyBlocksSystemDelivery(_ shouldBlock: Bool) {
        guard exclusiveSingleKeyBlocksSystemDelivery != shouldBlock else {
            return
        }
        exclusiveSingleKeyBlocksSystemDelivery = shouldBlock
        settingsStore.exclusiveSingleKeyBlocksSystemDelivery = shouldBlock
        applyExclusiveSingleKeyConfiguration()
    }

    public func setWidgetStyle(_ style: WidgetStyleOption) {
        guard widgetStyle != style else {
            return
        }

        widgetStyle = style
        settingsStore.widgetStyle = style
        overlayWidgetController.setSelectedWidgetStyle(style)
        overlayWidgetController.setMessage("Виджет: \(style.title)")
        clearOverlayMessageAfterDelay()
        applyWidgetVisibilityForCurrentState()
    }

    public func setTextOutputMode(_ mode: TextOutputMode) {
        guard textOutputMode != mode else {
            return
        }

        textOutputMode = mode
        settingsStore.textOutputMode = mode
    }

    public func setWidgetPresentationMode(_ mode: WidgetPresentationMode) {
        guard widgetPresentationMode != mode else {
            return
        }
        widgetPresentationMode = mode
        settingsStore.widgetPresentationMode = mode
        applyWidgetVisibilityForCurrentState()
        overlayWidgetController.setMessage("Режим: \(mode.title)")
        clearOverlayMessageAfterDelay()
    }

    public func openSettingsWindow() {
        let app = NSApplication.shared
        app.activate(ignoringOtherApps: true)

        // Open directly to avoid failures of app-level Settings selectors from context menus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.presentSettingsWindow()
        }
    }

    public func runPermissionsOnboarding() {
        Task { @MainActor [weak self] in
            await self?.runPermissionsOnboardingFlow()
        }
    }

    public func prepareModelNow() {
        Task { [weak self] in
            guard let self else {
                return
            }
            let prepared = await self.ensureModelPreparedIfNeeded(
                showOverlayState: true,
                userInitiatedDownload: true
            )
            if prepared {
                self.completeInitialSetupAfterModelReady()
            }
        }
    }

    public static func makeDefault() -> VoiceWidgetCoordinator {
        let settings = AppSettingsStore()
        return VoiceWidgetCoordinator(
            audioRecordingService: AVAudioEngineRecordingService(),
            speechTranscriptionService: WhisperKitTranscriptionService(),
            globalHotkeyService: KeyboardHotkeyService(),
            overlayWidgetController: OverlayWindowController(settingsStore: settings),
            textOutputService: SystemTextOutputService(),
            microphonePermissionManager: MicrophonePermissionManager(),
            launchAtLoginManager: LaunchAtLoginManager(),
            settingsStore: settings,
            alertPresenter: SystemAlertPresenter()
        )
    }

    private func startCapture() async {
        guard await ensureModelPreparedIfNeeded(showOverlayState: true, userInitiatedDownload: false) else {
            return
        }

        guard await ensureMicrophoneAccess() else {
            return
        }

        do {
            captureTargetBundleIdentifier = resolveCaptureTargetBundleIdentifier()
            try await audioRecordingService.start()
            setState(.recording)
            overlayWidgetController.setInputLevel(0)
            overlayWidgetController.setMessage(nil)
            lastError = nil
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    private func stopAndTranscribe() async {
        do {
            let audioURL = try await audioRecordingService.stop()
            defer {
                try? FileManager.default.removeItem(at: audioURL)
            }
            setState(.transcribing)

            let result = try await transcribeWithFirstRunRetry(audioURL: audioURL)
            let preferredTargetBundle = resolvePreferredOutputTargetBundleIdentifier()
            let outputResult = try textOutputService.deliver(
                text: result.text,
                mode: textOutputMode,
                preferredTargetBundleIdentifier: preferredTargetBundle
            )
            overlayWidgetController.setMessage(outputMessage(for: outputResult))
            if let diagnostic = outputDiagnostic(for: outputResult) {
                lastError = diagnostic
            } else {
                lastError = nil
            }
            clearOverlayMessageAfterDelay()
            setState(.idle)
            overlayWidgetController.setInputLevel(0)
            captureTargetBundleIdentifier = nil
        } catch let error as WhisperTranscriptionError where error == .emptyTranscription {
            handleNoSpeechDetected()
        } catch {
            fail(with: error.localizedDescription)
            captureTargetBundleIdentifier = nil
        }
    }

    private func setState(_ state: CaptureState) {
        self.state = state
        if case let .installingModel(progress, message) = state {
            modelPreparationProgress = progress
            modelPreparationMessage = message
        } else if case .idle = state {
            modelPreparationProgress = 0
            modelPreparationMessage = nil
        }
        overlayWidgetController.update(state: state)
        applyWidgetVisibilityForCurrentState()
    }

    private func fail(with message: String) {
        lastError = message
        setState(.failed(message))
        overlayWidgetController.setInputLevel(0)
        overlayWidgetController.setMessage(message)
    }

    private func clearOverlayMessageAfterDelay() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            self?.overlayWidgetController.setMessage(nil)
        }
    }

    private func handleNoSpeechDetected() {
        lastError = nil
        setState(.idle)
        overlayWidgetController.setInputLevel(0)
        overlayWidgetController.setMessage("Тишина или слишком короткая запись")
        clearOverlayMessageAfterDelay()
    }

    private func outputMessage(for outcome: TextDeliveryOutcome) -> String {
        switch outcome {
        case .insertedIntoActiveField:
            return "Вставлено"
        case .pasteCommandDispatched:
            return "Команда вставки отправлена"
        case let .copiedToClipboard(reason):
            switch reason {
            case .explicitClipboardMode:
                return "Скопировано"
            case .accessibilityUnavailable:
                return "Скопировано (нужен доступ Accessibility)"
            case .noFocusedInputField:
                return "Скопировано (не найдено поле ввода)"
            case .pasteEventFailed:
                return "Скопировано (вставка не сработала)"
            }
        }
    }

    private func outputDiagnostic(for outcome: TextDeliveryOutcome) -> String? {
        switch outcome {
        case .insertedIntoActiveField, .copiedToClipboard(reason: .explicitClipboardMode):
            return nil
        case .pasteCommandDispatched:
            return nil
        case .copiedToClipboard(reason: .accessibilityUnavailable):
            return "Вставка недоступна: нет доступа Accessibility для VoiSER."
        case .copiedToClipboard(reason: .noFocusedInputField):
            return "Вставка недоступна: курсор не в текстовом поле активного приложения."
        case .copiedToClipboard(reason: .pasteEventFailed):
            return "Вставка недоступна: macOS не приняла Cmd+V событие для активного окна."
        }
    }

    private func resolveCaptureTargetBundleIdentifier() -> String? {
        if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           frontmost != Bundle.main.bundleIdentifier {
            return frontmost
        }
        return lastExternalBundleIdentifier
    }

    private func resolvePreferredOutputTargetBundleIdentifier() -> String? {
        if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           frontmost != Bundle.main.bundleIdentifier {
            return frontmost
        }
        return captureTargetBundleIdentifier ?? lastExternalBundleIdentifier
    }

    private func presentSettingsWindow() {
        if settingsWindowController == nil {
            let settingsRoot = SettingsView(coordinator: self)
            let hostingView = NSHostingView(rootView: settingsRoot)
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 540, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Настройки VoiSER"
            window.setFrameAutosaveName("VoiSERSettingsWindow")
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func transcribeWithFirstRunRetry(audioURL: URL) async throws -> TranscriptionResult {
        do {
            let result = try await speechTranscriptionService.transcribe(audioFileURL: audioURL)
            hasSuccessfulTranscription = true
            return result
        } catch let error as WhisperTranscriptionError {
            let isRecoverableFirstRunError = !hasSuccessfulTranscription && (error == .emptyTranscription || error == .modelUnavailable)
            guard isRecoverableFirstRunError else {
                throw error
            }

            _ = await ensureModelPreparedIfNeeded(showOverlayState: true, userInitiatedDownload: true)
            try await speechTranscriptionService.recoverModelIfPossible()
            let retried = try await speechTranscriptionService.transcribe(audioFileURL: audioURL)
            hasSuccessfulTranscription = true
            return retried
        } catch {
            throw error
        }
    }

    private func scheduleBackgroundModelPrewarm() {
        prewarmTask?.cancel()
        let service = speechTranscriptionService
        prewarmTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled else {
                return
            }

            do {
                if await service.isModelPrepared() {
                    try await service.recoverModelIfPossible()
                }
            } catch {
                // Ignore warmup failures here; explicit failures are surfaced on real transcription.
            }
        }
    }

    private func beginTrackingFrontmostApplication() {
        if let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalBundleIdentifier = bundleIdentifier
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleIdentifier = app.bundleIdentifier,
                bundleIdentifier != Bundle.main.bundleIdentifier
            else {
                return
            }

            Task { @MainActor [weak self] in
                self?.lastExternalBundleIdentifier = bundleIdentifier
            }
        }
    }

    private func ensureMicrophoneAccess() async -> Bool {
        switch microphonePermissionManager.status {
        case .granted:
            return true
        case .notDetermined:
            let granted = await microphonePermissionManager.requestAccess()
            if granted {
                return true
            }
            alertPresenter.showMicrophoneAccessAlert { [microphonePermissionManager] in
                microphonePermissionManager.openSystemSettings()
            }
            fail(with: "Нет доступа к микрофону")
            return false
        case .denied:
            alertPresenter.showMicrophoneAccessAlert { [microphonePermissionManager] in
                microphonePermissionManager.openSystemSettings()
            }
            fail(with: "Нет доступа к микрофону")
            return false
        }
    }

    private func runPermissionsOnboardingFlow() async {
        let microphoneGranted = await ensureMicrophoneAccessForOnboarding()
        let accessibilityGranted = ensureAccessibilityAccessForOnboarding()
        let automationGranted = true

        if microphoneGranted && accessibilityGranted && automationGranted {
            lastError = nil
            overlayWidgetController.setMessage("Разрешения настроены")
            clearOverlayMessageAfterDelay()
            return
        }

        overlayWidgetController.setMessage("Проверьте разрешения в настройках")
        clearOverlayMessageAfterDelay()

        var missingItems: [String] = []
        if !microphoneGranted { missingItems.append("Microphone") }
        if !accessibilityGranted { missingItems.append("Accessibility") }
        lastError = "Не выданы разрешения: \(missingItems.joined(separator: ", "))."
    }

    private func ensureMicrophoneAccessForOnboarding() async -> Bool {
        switch microphonePermissionManager.status {
        case .granted:
            return true
        case .notDetermined:
            let granted = await microphonePermissionManager.requestAccess()
            if !granted {
                alertPresenter.showMicrophoneAccessAlert { [microphonePermissionManager] in
                    microphonePermissionManager.openSystemSettings()
                }
            }
            return granted
        case .denied:
            alertPresenter.showMicrophoneAccessAlert { [microphonePermissionManager] in
                microphonePermissionManager.openSystemSettings()
            }
            return false
        }
    }

    private func ensureAccessibilityAccessForOnboarding() -> Bool {
        if textOutputMode == .clipboard {
            return true
        }

        if AXIsProcessTrusted() {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Нужен доступ Accessibility для автовставки"
        alert.informativeText = "Откройте Privacy & Security -> Accessibility и включите VoiSER."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Пропустить")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openPrivacySettings(anchor: "Privacy_Accessibility")
        }
        return false
    }

    private func openPrivacySettings(anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
            return
        }
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallback)
        }
    }

    private func applyWidgetVisibilityForCurrentState() {
        if widgetPresentationMode == .menuBarOnly {
            overlayWidgetController.setVisible(false)
            return
        }

        guard widgetEnabled else {
            overlayWidgetController.setVisible(false)
            return
        }

        if widgetStyle == .notchTop {
            // Keep the top area clean: for notch style we do not show a second transient top widget.
            // Status is represented by a single persistent menu bar icon.
            overlayWidgetController.setVisible(false)
            return
        }

        overlayWidgetController.setVisible(true)
    }

    private func applyExclusiveSingleKeyConfiguration() {
        let keyCode = exclusiveSingleKeyEnabled ? exclusiveSingleKeyCode : nil
        let configured = globalHotkeyService.configureExclusiveSingleKey(
            keyCode: keyCode,
            isEnabled: exclusiveSingleKeyEnabled,
            blocksSystemDelivery: exclusiveSingleKeyBlocksSystemDelivery
        )

        if !configured {
            lastError = "Не удалось включить режим одной клавиши. Проверьте Input Monitoring для VoiSER и перезапустите приложение."
            overlayWidgetController.setMessage("Нужен Input Monitoring")
            clearOverlayMessageAfterDelay()
        } else if lastError?.contains("Input Monitoring") == true {
            lastError = nil
        }
    }

    public var exclusiveSingleKeyTitle: String {
        Self.keyTitle(for: exclusiveSingleKeyCode)
    }

    public static func keyTitle(for keyCode: Int) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 36: return "Return"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        default:
            return "KeyCode \(keyCode)"
        }
    }

    private func presentWhisperFlowWindowIfPossible() {
        guard NSApp != nil else {
            return
        }

        if whisperFlowWindowController == nil {
            let root = WhisperFlowView(coordinator: self)
            let hostingView = NSHostingView(rootView: root)
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 560, height: 340),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "VoiSER Setup"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = hostingView
            whisperFlowWindowController = NSWindowController(window: window)
        }

        whisperFlowWindowController?.showWindow(nil)
        whisperFlowWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func dismissWhisperFlowWindow() {
        whisperFlowWindowController?.close()
    }

    @discardableResult
    private func ensureModelPreparedIfNeeded(
        showOverlayState: Bool,
        userInitiatedDownload: Bool
    ) async -> Bool {
        let alreadyPrepared = await speechTranscriptionService.isModelPrepared()
        if alreadyPrepared {
            isModelReady = true
            modelPreparationProgress = 1
            settingsStore.didCompleteRuntimeModelSetup = true
            dismissWhisperFlowWindow()
            return true
        }

        if !userInitiatedDownload {
            presentWhisperFlowWindowIfPossible()
            setState(.installingModel(
                progress: 0,
                message: "Для начала работы скачайте модель Whisper"
            ))
            modelPreparationMessage = "Нажмите «Скачать модель»"
            modelPreparationProgress = 0
            overlayWidgetController.setMessage("Нужно скачать модель Whisper")
            return false
        }

        if showOverlayState {
            setState(.installingModel(progress: 0.01, message: "Подготовка Whisper…"))
        }
        isModelInstallationInProgress = true
        modelPreparationMessage = "Подготовка Whisper…"
        modelPreparationProgress = 0.01
        overlayWidgetController.setMessage("Подготовка Whisper…")
        lastError = nil

        do {
            try await speechTranscriptionService.prepareModelIfNeeded { [weak self] progress, message in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.modelPreparationProgress = progress
                    self.modelPreparationMessage = message
                    self.overlayWidgetController.setMessage(message)
                    if showOverlayState {
                        self.setState(.installingModel(progress: progress, message: message))
                    }
                }
            }
            try await speechTranscriptionService.recoverModelIfPossible()
            isModelReady = true
            isModelInstallationInProgress = false
            settingsStore.didCompleteRuntimeModelSetup = true
            overlayWidgetController.setMessage("Whisper готов")
            clearOverlayMessageAfterDelay()
            dismissWhisperFlowWindow()
            if case .installingModel = state {
                setState(.idle)
            }
            return true
        } catch {
            isModelInstallationInProgress = false
            fail(with: "Не удалось подготовить Whisper: \(error.localizedDescription)")
            return false
        }
    }

    private func beginInitialSetupFlow() {
        Task { [weak self] in
            guard let self else {
                return
            }
            let isPrepared = await self.speechTranscriptionService.isModelPrepared()
            if isPrepared {
                await MainActor.run {
                    self.completeInitialSetupAfterModelReady()
                }
                return
            }

            await MainActor.run {
                self.isModelReady = false
                self.modelPreparationProgress = 0
                self.modelPreparationMessage = "Для работы приложения нужна локальная модель Whisper."
                self.setState(.installingModel(progress: 0, message: "Требуется установка модели"))
                self.presentWhisperFlowWindowIfPossible()
            }
        }
    }

    private func completeInitialSetupAfterModelReady() {
        if !settingsStore.didRunInitialSetup {
            runPermissionsOnboarding()
            settingsStore.didRunInitialSetup = true
        }
        scheduleBackgroundModelPrewarm()
    }
}
