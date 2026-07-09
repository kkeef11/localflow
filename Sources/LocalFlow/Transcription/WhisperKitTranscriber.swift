import WhisperKit

// WhisperKit (as of 0.18.0) predates Swift 6 strict concurrency and isn't
// marked Sendable. We only ever touch `pipe` from within this actor's
// isolation domain (sequential access enforced by the actor), so this is safe.
extension WhisperKit: @unchecked Sendable {}

actor WhisperKitTranscriber: Transcribing {
    private let model: String
    private let promptTerms: [String]
    private var pipe: WhisperKit?

    init(model: String, promptTerms: [String] = []) {
        self.model = model
        self.promptTerms = promptTerms
    }

    func transcribe(samples: [Float]) async throws -> String {
        if pipe == nil {
            pipe = try await WhisperKit(WhisperKitConfig(model: model))
        }
        var options = DecodingOptions()
        if !promptTerms.isEmpty {
            // WhisperKit 0.18.0's `DecodingOptions` has no `promptText`; prompt biasing
            // is token-based (`promptTokens: [Int]?`), decoded via the pipeline's
            // `WhisperTokenizer`. The tokenizer is only populated once models are
            // loaded, so load eagerly here rather than relying on the lazy load inside
            // `transcribe(audioArray:)`.
            if pipe!.modelState != .loaded {
                try await pipe!.loadModels()
            }
            let promptText = "Vocabulary: " + promptTerms.joined(separator: ", ")
            options.promptTokens = pipe!.tokenizer?.encode(text: promptText)
            options.usePrefillPrompt = true
        }
        let results = try await pipe!.transcribe(audioArray: samples, decodeOptions: options)
        return results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
