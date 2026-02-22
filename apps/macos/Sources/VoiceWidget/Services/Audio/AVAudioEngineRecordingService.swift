import AVFoundation
import Foundation

public enum AudioRecordingError: LocalizedError {
    case alreadyRecording
    case notRecording
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Запись уже запущена."
        case .notRecording:
            "Сейчас запись не запущена."
        case let .writeFailed(message):
            "Ошибка записи аудио: \(message)"
        }
    }
}

@MainActor
public final class AVAudioEngineRecordingService: AudioRecordingService {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var isRecording = false
    private var meterTimer: Timer?
    private var levelUpdateHandler: ((Float) -> Void)?

    public init() {}

    public func setLevelUpdateHandler(_ handler: @escaping (Float) -> Void) {
        levelUpdateHandler = handler
    }

    public func start() async throws {
        guard !isRecording else {
            throw AudioRecordingError.alreadyRecording
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicewidget-\(UUID().uuidString)")
            .appendingPathExtension("caf")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: tempURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw AudioRecordingError.writeFailed("Не удалось запустить запись с микрофона.")
        }

        self.recorder = recorder
        outputURL = tempURL
        isRecording = true
        startMetering()
        levelUpdateHandler?(0)
    }

    public func stop() async throws -> URL {
        guard isRecording, let outputURL, let recorder else {
            throw AudioRecordingError.notRecording
        }

        recorder.stop()
        stopMetering()
        self.recorder = nil

        try validateRecordedFile(at: outputURL)

        self.outputURL = nil
        isRecording = false
        levelUpdateHandler?(0)

        return outputURL
    }

    private func validateRecordedFile(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if fileSize < 256 {
            throw AudioRecordingError.writeFailed("Аудио не сохранилось. Проверьте доступ к микрофону и повторите.")
        }
    }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emitMeterLevel()
            }
        }
        RunLoop.main.add(meterTimer!, forMode: .common)
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func emitMeterLevel() {
        guard let recorder else {
            return
        }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (power + 60) / 60))
        levelUpdateHandler?(normalized)
    }
}
