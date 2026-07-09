import WhisperKit

// WhisperKit (as of 0.18.0) predates Swift 6 strict concurrency and isn't
// marked Sendable. We only ever touch `pipe` from within this actor's
// isolation domain (sequential access enforced by the actor), so this is safe.
extension WhisperKit: @unchecked Sendable {}

actor WhisperKitTranscriber: Transcribing {
    private let model: String
    private var pipe: WhisperKit?

    init(model: String) { self.model = model }

    func transcribe(samples: [Float]) async throws -> String {
        if pipe == nil {
            pipe = try await WhisperKit(WhisperKitConfig(model: model))
        }
        let results = try await pipe!.transcribe(audioArray: samples)
        return results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
