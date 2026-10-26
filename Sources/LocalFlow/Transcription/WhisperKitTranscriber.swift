import Foundation
import WhisperKit

// WhisperKit (as of 0.18.0) predates Swift 6 strict concurrency and isn't
// marked Sendable. We only ever touch `pipe` from within this actor's
// isolation domain (sequential access enforced by the actor), so this is safe.
extension WhisperKit: @unchecked Sendable {}

enum TranscriberError: Error, LocalizedError {
    case modelNotDownloaded

    var errorDescription: String? {
        "Speech model not downloaded yet — open the LocalFlow menu → Setup to download it."
    }
}

/// Owns the WhisperKit pipeline and its model files.
///
/// Model files live in `~/Library/Application Support/LocalFlow/Models` rather than
/// WhisperKit's default `~/Documents/huggingface`: Documents is privacy-protected, so the
/// default would trigger a "LocalFlow wants to access your Documents folder" prompt.
///
/// Offline operation: WhisperKit's own download path asks the Hugging Face API for the file
/// list on every launch (no offline fallback in 0.18.0). So after the first successful load
/// we write a marker recording the model folder, and later launches load straight from disk
/// with `download: false` — no network at all.
actor WhisperKitTranscriber: Transcribing {
    private let model: String
    private let promptTerms: [String]
    private let modelsDirectory: URL
    private let onState: @Sendable (SpeechModelState) -> Void
    private var pipe: WhisperKit?
    private var loading: Task<WhisperKit, Error>?

    static var defaultModelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalFlow/Models", isDirectory: true)
    }

    init(model: String, promptTerms: [String] = [],
         modelsDirectory: URL = WhisperKitTranscriber.defaultModelsDirectory,
         onState: @escaping @Sendable (SpeechModelState) -> Void = { _ in }) {
        self.model = model
        self.promptTerms = promptTerms
        self.modelsDirectory = modelsDirectory
        self.onState = onState
    }

    /// Loads the model if it's already on disk; otherwise reports `.notDownloaded` and does
    /// nothing, so a multi-gigabyte download never starts without the user asking.
    func loadIfDownloaded() async {
        guard pipe == nil, loading == nil else { return }
        guard Self.completedModelFolder(model: model, in: modelsDirectory) != nil else {
            onState(.notDownloaded)
            return
        }
        _ = try? await prepare(allowDownload: false)
    }

    /// Downloads (if needed and allowed) and loads the model. Concurrent callers share one
    /// load. Interrupted downloads resume: the Hub client keeps partial `.incomplete` files.
    func prepare(allowDownload: Bool) async throws -> WhisperKit {
        if let pipe { return pipe }
        if let loading { return try await loading.value }
        let cached = Self.completedModelFolder(model: model, in: modelsDirectory)
        guard cached != nil || allowDownload else { throw TranscriberError.modelNotDownloaded }

        let task = Task { [model, modelsDirectory, onState] in
            try await Self.load(model: model, cachedFolder: cached, base: modelsDirectory, onState: onState)
        }
        loading = task
        defer { loading = nil }
        do {
            let loaded = try await task.value
            pipe = loaded
            return loaded
        } catch {
            onState(.failed(error.localizedDescription))
            throw error
        }
    }

    /// Forgets the completed-download marker so the next `prepare` re-verifies the files
    /// against the server (re-downloading anything missing or changed). Used by "Retry".
    func resetAfterFailure() {
        guard pipe == nil else { return }
        try? FileManager.default.removeItem(at: Self.markerURL(model: model, in: modelsDirectory))
    }

    func transcribe(samples: [Float]) async throws -> String {
        let pipe = try await prepare(allowDownload: false)
        var options = DecodingOptions()
        if !promptTerms.isEmpty {
            // WhisperKit 0.18.0's `DecodingOptions` has no `promptText`; prompt biasing
            // is token-based (`promptTokens: [Int]?`), decoded via the pipeline's
            // `WhisperTokenizer`. The tokenizer is only populated once models are
            // loaded, so make sure they are.
            if pipe.modelState != .loaded {
                try await pipe.loadModels()
            }
            let promptText = "Vocabulary: " + promptTerms.joined(separator: ", ")
            options.promptTokens = pipe.tokenizer?.encode(text: promptText)
            options.usePrefillPrompt = true
        }
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Model files

    private static func load(model: String, cachedFolder: URL?, base: URL,
                             onState: @escaping @Sendable (SpeechModelState) -> Void) async throws -> WhisperKit {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let folder: URL
        if let cachedFolder {
            folder = cachedFolder
        } else {
            onState(.downloading(fraction: 0))
            let throttle = ProgressThrottle()
            folder = try await WhisperKit.download(variant: model, downloadBase: base) { progress in
                if throttle.shouldReport(progress.fractionCompleted) {
                    onState(.downloading(fraction: progress.fractionCompleted))
                }
            }
        }
        onState(.loading)
        // download: false + an explicit folder = no network. The tokenizer is fetched once
        // (on the first load) into `base` and found there afterwards.
        let config = WhisperKitConfig(model: model, downloadBase: base, modelFolder: folder.path,
                                      tokenizerFolder: base, verbose: false, load: true, download: false)
        let kit = try await WhisperKit(config)
        try? folder.path.write(to: markerURL(model: model, in: base), atomically: true, encoding: .utf8)
        onState(.ready)
        return kit
    }

    private static func markerURL(model: String, in base: URL) -> URL {
        base.appendingPathComponent("\(model).ready")
    }

    /// The model folder recorded by a previous successful load, if it still exists.
    static func completedModelFolder(model: String, in base: URL) -> URL? {
        guard let path = try? String(contentsOf: markerURL(model: model, in: base), encoding: .utf8),
              !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// Download progress arrives many times per second from a background thread; only forward
/// whole-percent changes so the UI isn't flooded with main-actor hops.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPercent = -1

    func shouldReport(_ fraction: Double) -> Bool {
        let percent = Int(fraction * 100)
        lock.lock(); defer { lock.unlock() }
        guard percent != lastPercent else { return false }
        lastPercent = percent
        return true
    }
}
