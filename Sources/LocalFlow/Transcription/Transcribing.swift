protocol Transcribing: Sendable {
    func transcribe(samples: [Float]) async throws -> String
}
