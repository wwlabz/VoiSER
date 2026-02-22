import Foundation

public enum WhisperModelInstallError: LocalizedError {
    case manifestUnavailable
    case modelFilesMissing

    public var errorDescription: String? {
        switch self {
        case .manifestUnavailable:
            "Не удалось получить манифест модели Whisper."
        case .modelFilesMissing:
            "В манифесте отсутствуют файлы выбранной модели Whisper."
        }
    }
}

public actor WhisperModelInstaller {
    private struct HubModelManifest: Decodable {
        struct Sibling: Decodable {
            let rfilename: String
        }

        let siblings: [Sibling]
    }

    private struct DownloadEntry {
        let sourceURL: URL
        let destinationURL: URL
    }

    private let fileManager: FileManager
    private let session: URLSession

    public init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    func modelRootURL() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("VoiSER", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    func modelDirectoryURL(for option: WhisperModelOption) throws -> URL {
        try modelRootURL().appendingPathComponent(option.folderName, isDirectory: true)
    }

    func hasRuntimeModel(for option: WhisperModelOption) -> Bool {
        guard let directory = try? modelDirectoryURL(for: option) else {
            return false
        }
        guard fileManager.fileExists(atPath: directory.path) else {
            return false
        }
        return fileManager.fileExists(atPath: directory.appendingPathComponent("tokenizer.json").path)
    }

    func prepareModelIfNeeded(
        option: WhisperModelOption,
        progress: (@Sendable (_ fraction: Double, _ message: String) -> Void)?
    ) async throws -> URL {
        let directory = try modelDirectoryURL(for: option)
        if hasRuntimeModel(for: option) {
            progress?(1, "Модель готова")
            return directory
        }

        progress?(0.02, "Подготовка установки Whisper…")
        let downloadPlan = try await makeDownloadPlan(for: option)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if downloadPlan.isEmpty {
            throw WhisperModelInstallError.modelFilesMissing
        }

        var completed = 0
        let total = downloadPlan.count
        for entry in downloadPlan {
            if fileManager.fileExists(atPath: entry.destinationURL.path) {
                completed += 1
                progress?(Double(completed) / Double(total), "Проверка файлов Whisper…")
                continue
            }

            try await download(entry: entry)
            completed += 1
            let fraction = Double(completed) / Double(total)
            progress?(fraction, "Загрузка Whisper \(Int(fraction * 100))%")
        }

        progress?(1, "Модель Whisper установлена")
        return directory
    }

    private func makeDownloadPlan(for option: WhisperModelOption) async throws -> [DownloadEntry] {
        let modelRepo = "argmaxinc/whisperkit-coreml"
        let modelPrefix = "\(option.folderName)/"
        let manifestURL = URL(string: "https://huggingface.co/api/models/\(modelRepo)")!
        let (manifestData, response) = try await session.data(from: manifestURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw WhisperModelInstallError.manifestUnavailable
        }

        let manifest = try JSONDecoder().decode(HubModelManifest.self, from: manifestData)
        let modelFiles = manifest.siblings
            .map(\.rfilename)
            .filter { $0.hasPrefix(modelPrefix) }

        guard !modelFiles.isEmpty else {
            throw WhisperModelInstallError.modelFilesMissing
        }

        let modelRoot = try modelRootURL()
        var entries: [DownloadEntry] = modelFiles.map { relativePath in
            let source = URL(string: "https://huggingface.co/\(modelRepo)/resolve/main/\(relativePath)?download=true")!
            let destination = modelRoot.appendingPathComponent(relativePath)
            return DownloadEntry(
                sourceURL: source,
                destinationURL: destination
            )
        }

        let tokenizerRepo = await resolveTokenizerRepo(for: option)
        let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json", "config.json"]
        let modelDir = try modelDirectoryURL(for: option)
        for filename in tokenizerFiles {
            let source = URL(string: "https://huggingface.co/\(tokenizerRepo)/resolve/main/\(filename)?download=true")!
            let destination = modelDir.appendingPathComponent(filename)
            entries.append(DownloadEntry(
                sourceURL: source,
                destinationURL: destination
            ))
        }

        return entries
    }

    private func resolveTokenizerRepo(for option: WhisperModelOption) async -> String {
        let preferred = "openai/whisper-\(option.rawValue)"
        let fallback = "openai/whisper-base"
        guard let probeURL = URL(string: "https://huggingface.co/api/models/\(preferred)") else {
            return fallback
        }

        do {
            let (_, response) = try await session.data(from: probeURL)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                return preferred
            }
        } catch {
            return fallback
        }

        return fallback
    }

    private func download(entry: DownloadEntry) async throws {
        try fileManager.createDirectory(
            at: entry.destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let tempURL = entry.destinationURL.appendingPathExtension("part")
        if fileManager.fileExists(atPath: tempURL.path) {
            try? fileManager.removeItem(at: tempURL)
        }

        let (downloadedURL, response) = try await session.download(from: entry.sourceURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        if fileManager.fileExists(atPath: tempURL.path) {
            try? fileManager.removeItem(at: tempURL)
        }

        try fileManager.moveItem(at: downloadedURL, to: tempURL)
        if fileManager.fileExists(atPath: entry.destinationURL.path) {
            try? fileManager.removeItem(at: entry.destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: entry.destinationURL)
    }
}
