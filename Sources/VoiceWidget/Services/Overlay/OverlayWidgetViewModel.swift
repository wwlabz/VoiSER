import Combine
import Foundation

@MainActor
public final class OverlayWidgetViewModel: ObservableObject {
    private let smoothingAlpha: Float = 0.18

    @Published public var state: CaptureState = .idle
    @Published public var message: String?
    @Published public var canRetryModel = false
    @Published public var selectedModel: WhisperModelOption = .small
    @Published public var hotkeyPreset: HotkeyPreset = .optionSpace
    @Published public var widgetStyle: WidgetStyleOption = .micOrb
    @Published public var inputLevelRaw: Float = 0
    @Published public var inputLevelSmoothed: Float = 0

    public init() {}

    public func pushInputLevel(_ rawLevel: Float) {
        let clamped = max(0, min(1, rawLevel))
        inputLevelRaw = clamped
        inputLevelSmoothed = (inputLevelSmoothed * (1 - smoothingAlpha)) + (clamped * smoothingAlpha)
        inputLevelSmoothed = max(0, min(1, inputLevelSmoothed))
    }

    public func resetInputLevels() {
        inputLevelRaw = 0
        inputLevelSmoothed = 0
    }
}
