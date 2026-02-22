import Foundation

public enum CaptureState: Equatable, Sendable {
    case idle
    case installingModel(progress: Double, message: String)
    case recording
    case transcribing
    case failed(String)
}

public struct TranscriptionResult: Equatable, Sendable {
    public let text: String
    public let detectedLanguage: String?
    public let durationMs: Int

    public init(text: String, detectedLanguage: String?, durationMs: Int) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.durationMs = durationMs
    }
}

@MainActor
public protocol AudioRecordingService {
    func start() async throws
    func stop() async throws -> URL
    func setLevelUpdateHandler(_ handler: @escaping (Float) -> Void)
}

public protocol SpeechTranscriptionService: Sendable {
    func transcribe(audioFileURL: URL) async throws -> TranscriptionResult
    func recoverModelIfPossible() async throws
    func setPreferredModel(_ model: WhisperModelOption) async
    func prepareModelIfNeeded(
        progress: (@Sendable (_ fraction: Double, _ message: String) -> Void)?
    ) async throws
    func isModelPrepared() async -> Bool
}

public extension SpeechTranscriptionService {
    func recoverModelIfPossible() async throws {}
    func setPreferredModel(_ model: WhisperModelOption) async {}
    func prepareModelIfNeeded(
        progress: (@Sendable (_ fraction: Double, _ message: String) -> Void)?
    ) async throws {}
    func isModelPrepared() async -> Bool { true }
}

@MainActor
public protocol GlobalHotkeyService: AnyObject {
    func registerDefaultIfNeeded()
    func applyPreset(_ preset: HotkeyPreset)
    @discardableResult
    func configureExclusiveSingleKey(
        keyCode: Int?,
        isEnabled: Bool,
        blocksSystemDelivery: Bool
    ) -> Bool
    func onToggleRecording(_ handler: @escaping () -> Void)
}

@MainActor
public protocol OverlayWidgetController: AnyObject {
    func show()
    func setVisible(_ isVisible: Bool)
    func update(state: CaptureState)
    func setMessage(_ message: String?)
    func persistPosition()
    func resetPosition()
    func setToggleHandler(_ handler: @escaping () -> Void)
    func setRetryModelHandler(_ handler: @escaping () -> Void)
    func setOpenSettingsHandler(_ handler: @escaping () -> Void)
    func setResetPositionHandler(_ handler: @escaping () -> Void)
    func setModelSelectionHandler(_ handler: @escaping (WhisperModelOption) -> Void)
    func setHotkeySelectionHandler(_ handler: @escaping (HotkeyPreset) -> Void)
    func setWidgetStyleSelectionHandler(_ handler: @escaping (WidgetStyleOption) -> Void)
    func setSelectedModel(_ model: WhisperModelOption)
    func setSelectedHotkeyPreset(_ preset: HotkeyPreset)
    func setSelectedWidgetStyle(_ style: WidgetStyleOption)
    func setInputLevel(_ level: Float)
}

public protocol TextOutputService {
    func deliver(
        text: String,
        mode: TextOutputMode,
        preferredTargetBundleIdentifier: String?
    ) throws -> TextDeliveryOutcome
}

public enum TextDeliveryOutcome: Equatable {
    case copiedToClipboard(reason: TextOutputFallbackReason)
    case insertedIntoActiveField
    case pasteCommandDispatched
}

public enum TextOutputFallbackReason: Equatable {
    case explicitClipboardMode
    case accessibilityUnavailable
    case noFocusedInputField
    case pasteEventFailed
}

public enum MicrophonePermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

@MainActor
public protocol MicrophonePermissionProviding {
    var status: MicrophonePermissionStatus { get }
    func requestAccess() async -> Bool
    func openSystemSettings()
}

@MainActor
public protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
public protocol AlertPresenting {
    func showMicrophoneAccessAlert(openSettings: @escaping () -> Void)
}
