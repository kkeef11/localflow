protocol LLMGenerating: Sendable {
    func generate(system: String, prompt: String) async throws -> String
}
