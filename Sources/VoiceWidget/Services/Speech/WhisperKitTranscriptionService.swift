import Foundation
import os
@preconcurrency import WhisperKit

public enum WhisperTranscriptionError: LocalizedError, Equatable {
    case modelUnavailable
    case emptyTranscription

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Модель Whisper недоступна. Проверьте интернет-соединение и повторите установку в окне Whisper Flow или в Settings -> Обслуживание."
        case .emptyTranscription:
            "Распознанный текст пустой. Попробуйте записать более длинную фразу."
        }
    }
}

public actor WhisperKitTranscriptionService: SpeechTranscriptionService {
    private let logger = Logger(subsystem: "io.voicewidget.app", category: "Whisper")
    private let installer: WhisperModelInstaller
    private var whisperKit: WhisperKit?
    private var preferredModel: WhisperModelOption

    public init(
        preferredModel: WhisperModelOption = .small,
        installer: WhisperModelInstaller = WhisperModelInstaller()
    ) {
        self.preferredModel = preferredModel
        self.installer = installer
    }

    public func setPreferredModel(_ model: WhisperModelOption) async {
        guard preferredModel != model else {
            return
        }

        preferredModel = model
        whisperKit = nil
    }

    public func transcribe(audioFileURL: URL) async throws -> TranscriptionResult {
        let startedAt = Date()
        let kit = try await loadIfNeeded()
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: nil,
            usePrefillPrompt: true,
            detectLanguage: true,
            withoutTimestamps: true,
            wordTimestamps: false
        )

        let results = try await kit.transcribe(audioPath: audioFileURL.path, decodeOptions: options)
        guard let first = results.first else {
            throw WhisperTranscriptionError.emptyTranscription
        }

        let text = normalizedTranscriptionText(first.text)
        guard !text.isEmpty else {
            throw WhisperTranscriptionError.emptyTranscription
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        return TranscriptionResult(
            text: text,
            detectedLanguage: first.language,
            durationMs: durationMs
        )
    }

    public func recoverModelIfPossible() async throws {
        whisperKit = nil
        _ = try await loadIfNeeded()
    }

    public func prepareModelIfNeeded(
        progress: (@Sendable (_ fraction: Double, _ message: String) -> Void)?
    ) async throws {
        _ = try await installer.prepareModelIfNeeded(option: preferredModel, progress: progress)
    }

    public func isModelPrepared() async -> Bool {
        if await installer.hasRuntimeModel(for: preferredModel) {
            return true
        }
        return resolveBundledModel() != nil
    }

    private func loadIfNeeded() async throws -> WhisperKit {
        if let whisperKit {
            return whisperKit
        }

        guard let selectedModel = try await resolveModelLocationEnsuringInstalled() else {
            throw WhisperTranscriptionError.modelUnavailable
        }

        let config = WhisperKitConfig(
            model: selectedModel.modelName,
            modelFolder: selectedModel.url.path,
            tokenizerFolder: selectedModel.url,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )

        let loaded = try await WhisperKit(config)
        logger.log("Whisper model loaded: \(selectedModel.modelName, privacy: .public) (\(selectedModel.url.lastPathComponent, privacy: .public))")
        whisperKit = loaded
        return loaded
    }

    private func resolveBundledModel() -> (modelName: String, url: URL)? {
        for variant in modelPriority(for: preferredModel) {
            if let url = Bundle.module.url(forResource: variant.folderName, withExtension: nil, subdirectory: "Models") {
                return (variant.rawValue, url)
            }
        }

        return nil
    }

    private func resolveRuntimeModel() async -> (modelName: String, url: URL)? {
        for variant in modelPriority(for: preferredModel) {
            if await installer.hasRuntimeModel(for: variant),
               let url = try? await installer.modelDirectoryURL(for: variant) {
                return (variant.rawValue, url)
            }
        }
        return nil
    }

    private func resolveModelLocationEnsuringInstalled() async throws -> (modelName: String, url: URL)? {
        if let runtime = await resolveRuntimeModel() {
            return runtime
        }

        _ = try? await installer.prepareModelIfNeeded(option: preferredModel, progress: nil)
        if let runtime = await resolveRuntimeModel() {
            return runtime
        }

        return resolveBundledModel()
    }

    private func modelPriority(for preferred: WhisperModelOption) -> [WhisperModelOption] {
        switch preferred {
        case .small:
            [.small, .tiny, .base]
        case .tiny:
            [.tiny, .small, .base]
        case .base:
            [.base, .small, .tiny]
        }
    }

    private func normalizedTranscriptionText(_ raw: String) -> String {
        let compact = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if compact.isEmpty {
            return ""
        }

        if compact.uppercased() == "[BLANK_AUDIO]" {
            return ""
        }

        let hasLettersOrNumbers = compact.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0)
        }
        return hasLettersOrNumbers ? compact : ""
    }
}
