import Foundation
import XCTest
@testable import VoiceWidget

@MainActor
final class VoiceWidgetCoordinatorTests: XCTestCase {
    func testToggleFromIdleStartsRecording() async {
        let fixtures = Fixtures(permissionStatus: .granted)
        let coordinator = fixtures.makeCoordinator()

        await coordinator.toggleCaptureNow()

        XCTAssertEqual(fixtures.audioService.startCallCount, 1)
        XCTAssertEqual(coordinator.state, .recording)
    }

    func testToggleFromRecordingStopsAndCopiesText() async {
        let fixtures = Fixtures(permissionStatus: .granted)
        let coordinator = fixtures.makeCoordinator()

        await coordinator.toggleCaptureNow()
        await coordinator.toggleCaptureNow()

        XCTAssertEqual(fixtures.audioService.stopCallCount, 1)
        XCTAssertEqual(fixtures.textOutputService.lastDeliveredText, "hello world")
        XCTAssertEqual(fixtures.textOutputService.lastMode, .clipboard)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testDeniedPermissionTransitionsToFailure() async {
        let fixtures = Fixtures(permissionStatus: .denied)
        let coordinator = fixtures.makeCoordinator()

        await coordinator.toggleCaptureNow()

        XCTAssertEqual(fixtures.audioService.startCallCount, 0)
        guard case .failed = coordinator.state else {
            XCTFail("Expected failed state")
            return
        }
    }

    func testHotkeyAndClickUseSameTogglePath() async {
        let fixtures = Fixtures(permissionStatus: .granted)
        let coordinator = fixtures.makeCoordinator()

        coordinator.bootstrap()
        fixtures.hotkeyService.trigger()

        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(fixtures.audioService.startCallCount, 1)
        XCTAssertEqual(coordinator.state, .recording)

        await coordinator.toggleCaptureNow()

        XCTAssertEqual(fixtures.audioService.stopCallCount, 1)
        XCTAssertEqual(fixtures.textOutputService.lastDeliveredText, "hello world")
        XCTAssertEqual(fixtures.textOutputService.lastMode, .clipboard)
    }

    func testSilentAudioKeepsCoordinatorInIdleState() async {
        let fixtures = Fixtures(
            permissionStatus: .granted,
            speechMode: .failure(WhisperTranscriptionError.emptyTranscription)
        )
        let coordinator = fixtures.makeCoordinator()

        await coordinator.toggleCaptureNow()
        await coordinator.toggleCaptureNow()

        XCTAssertEqual(fixtures.audioService.stopCallCount, 1)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(fixtures.textOutputService.lastDeliveredText)
        XCTAssertEqual(fixtures.overlayController.lastMessage, "Тишина или слишком короткая запись")
    }

    func testSetWidgetStyleUpdatesOverlayAndStore() {
        let fixtures = Fixtures(permissionStatus: .granted)
        let coordinator = fixtures.makeCoordinator()

        coordinator.setWidgetStyle(.voiceBar)

        XCTAssertEqual(coordinator.widgetStyle, .voiceBar)
        XCTAssertEqual(fixtures.overlayController.selectedWidgetStyle, .voiceBar)
        XCTAssertEqual(fixtures.settingsStore.widgetStyle, .voiceBar)
    }

    func testNotchStyleKeepsOverlayHiddenEvenWhenRecording() async {
        let fixtures = Fixtures(permissionStatus: .granted)
        let coordinator = fixtures.makeCoordinator()

        coordinator.setWidgetStyle(.notchTop)
        XCTAssertFalse(fixtures.overlayController.lastVisibleValue ?? true)

        await coordinator.toggleCaptureNow()
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(fixtures.overlayController.lastVisibleValue, false)
    }

    func testFirstCaptureRequiresExplicitModelDownloadWhenMissing() async {
        let fixtures = Fixtures(permissionStatus: .granted, modelPrepared: false)
        let coordinator = fixtures.makeCoordinator()

        await coordinator.toggleCaptureNow()

        let prepareCalls = await fixtures.speechService.prepareCallCount()
        XCTAssertEqual(prepareCalls, 0)
        XCTAssertEqual(fixtures.audioService.startCallCount, 0)
        guard case .installingModel = coordinator.state else {
            XCTFail("Expected installing state before explicit download")
            return
        }

        coordinator.prepareModelNow()
        try? await Task.sleep(for: .milliseconds(60))
        await coordinator.toggleCaptureNow()

        let prepareCallsAfterDownload = await fixtures.speechService.prepareCallCount()
        XCTAssertEqual(prepareCallsAfterDownload, 1)
        XCTAssertEqual(fixtures.audioService.startCallCount, 1)
        XCTAssertEqual(coordinator.state, .recording)
    }
}

@MainActor
private struct Fixtures {
    let audioService = MockAudioRecordingService()
    let speechService: MockSpeechTranscriptionService
    let hotkeyService = MockHotkeyService()
    let overlayController = MockOverlayWidgetController()
    let textOutputService = MockTextOutputService()
    let permissionManager: MockMicrophonePermissionManager
    let launchManager = MockLaunchAtLoginManager()
    let settingsStore: AppSettingsStore

    init(
        permissionStatus: MicrophonePermissionStatus,
        modelPrepared: Bool = true,
        speechMode: MockSpeechTranscriptionService.Mode = .success(
            TranscriptionResult(text: "hello world", detectedLanguage: "en", durationMs: 100)
        )
    ) {
        speechService = MockSpeechTranscriptionService(mode: speechMode, modelPrepared: modelPrepared)
        permissionManager = MockMicrophonePermissionManager(status: permissionStatus)

        let suiteName = "VoiceWidgetCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settingsStore = AppSettingsStore(defaults: defaults)
        settingsStore.didRunInitialSetup = true
    }

    func makeCoordinator() -> VoiceWidgetCoordinator {
        VoiceWidgetCoordinator(
            audioRecordingService: audioService,
            speechTranscriptionService: speechService,
            globalHotkeyService: hotkeyService,
            overlayWidgetController: overlayController,
            textOutputService: textOutputService,
            microphonePermissionManager: permissionManager,
            launchAtLoginManager: launchManager,
            settingsStore: settingsStore,
            alertPresenter: NoopAlertPresenter()
        )
    }
}

@MainActor
private final class MockAudioRecordingService: AudioRecordingService {
    var startCallCount = 0
    var stopCallCount = 0

    func setLevelUpdateHandler(_ handler: @escaping (Float) -> Void) {}

    func start() async throws {
        startCallCount += 1
    }

    func stop() async throws -> URL {
        stopCallCount += 1
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString)")
            .appendingPathExtension("caf")
    }
}

private actor MockSpeechTranscriptionService: SpeechTranscriptionService {
    enum Mode {
        case success(TranscriptionResult)
        case failure(Error)
    }

    private let mode: Mode
    private var modelPrepared: Bool
    private var prepareInvocationCount = 0

    init(mode: Mode, modelPrepared: Bool) {
        self.mode = mode
        self.modelPrepared = modelPrepared
    }

    func transcribe(audioFileURL: URL) async throws -> TranscriptionResult {
        switch mode {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }

    func recoverModelIfPossible() async throws {}

    func setPreferredModel(_ model: WhisperModelOption) async {}

    func prepareModelIfNeeded(
        progress: (@Sendable (_ fraction: Double, _ message: String) -> Void)?
    ) async throws {
        prepareInvocationCount += 1
        modelPrepared = true
        progress?(1, "ready")
    }

    func isModelPrepared() async -> Bool {
        modelPrepared
    }

    func prepareCallCount() async -> Int {
        prepareInvocationCount
    }
}

@MainActor
private final class MockHotkeyService: GlobalHotkeyService {
    private var handler: (() -> Void)?

    func registerDefaultIfNeeded() {}
    func applyPreset(_ preset: HotkeyPreset) {}
    func configureExclusiveSingleKey(
        keyCode: Int?,
        isEnabled: Bool,
        blocksSystemDelivery: Bool
    ) -> Bool {
        true
    }

    func onToggleRecording(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func trigger() {
        handler?()
    }
}

@MainActor
private final class MockOverlayWidgetController: OverlayWidgetController {
    private(set) var lastMessage: String?
    private(set) var selectedWidgetStyle: WidgetStyleOption = .micOrb
    private(set) var lastVisibleValue: Bool?

    func show() {}
    func setVisible(_ isVisible: Bool) {
        lastVisibleValue = isVisible
    }
    func update(state: CaptureState) {}
    func setMessage(_ message: String?) {
        lastMessage = message
    }
    func persistPosition() {}
    func resetPosition() {}
    func setToggleHandler(_ handler: @escaping () -> Void) {}
    func setRetryModelHandler(_ handler: @escaping () -> Void) {}
    func setOpenSettingsHandler(_ handler: @escaping () -> Void) {}
    func setResetPositionHandler(_ handler: @escaping () -> Void) {}
    func setModelSelectionHandler(_ handler: @escaping (WhisperModelOption) -> Void) {}
    func setHotkeySelectionHandler(_ handler: @escaping (HotkeyPreset) -> Void) {}
    func setWidgetStyleSelectionHandler(_ handler: @escaping (WidgetStyleOption) -> Void) {}
    func setSelectedModel(_ model: WhisperModelOption) {}
    func setSelectedHotkeyPreset(_ preset: HotkeyPreset) {}
    func setSelectedWidgetStyle(_ style: WidgetStyleOption) {
        selectedWidgetStyle = style
    }
    func setInputLevel(_ level: Float) {}
}

private final class MockTextOutputService: TextOutputService {
    private(set) var lastDeliveredText: String?
    private(set) var lastMode: TextOutputMode?
    private(set) var lastTargetBundleIdentifier: String?
    var nextOutcome: TextDeliveryOutcome = .copiedToClipboard(reason: .explicitClipboardMode)

    func deliver(
        text: String,
        mode: TextOutputMode,
        preferredTargetBundleIdentifier: String?
    ) throws -> TextDeliveryOutcome {
        lastDeliveredText = text
        lastMode = mode
        lastTargetBundleIdentifier = preferredTargetBundleIdentifier
        return nextOutcome
    }
}

@MainActor
private final class MockMicrophonePermissionManager: MicrophonePermissionProviding {
    var status: MicrophonePermissionStatus

    init(status: MicrophonePermissionStatus) {
        self.status = status
    }

    func requestAccess() async -> Bool {
        status == .granted
    }

    func openSystemSettings() {}
}

@MainActor
private struct MockLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled = true

    func setEnabled(_ enabled: Bool) throws {}
}

@MainActor
private struct NoopAlertPresenter: AlertPresenting {
    func showMicrophoneAccessAlert(openSettings: @escaping () -> Void) {}
}
