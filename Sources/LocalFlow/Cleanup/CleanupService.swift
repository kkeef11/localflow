import Foundation

/// Runs a raw transcript through the local LLM to strip filler words, fix
/// punctuation/formatting, and apply the user's custom dictionary before the
/// cleaned text reaches the injector.
///
/// `final class` with only `let` stored properties of `Sendable` types
/// (`LLMGenerating` is itself `Sendable`; `[String]` is `Sendable`). Unlike
/// `OllamaClient` — which gets an implicit Sendable pass because it conforms
/// to the `Sendable`-inheriting `LLMGenerating` protocol — `CleanupService`
/// conforms to no protocol, so Swift 6's strict concurrency checker won't
/// infer Sendable for it on its own; calling `clean(raw:)` from a `@MainActor`
/// context across an `await` otherwise fails with "sending risks causing data
/// races". Declaring the conformance explicitly is enough, since every stored
/// property is already an immutable, Sendable value.
final class CleanupService: Sendable {
    private let llm: LLMGenerating
    private let dictionary: [String]

    init(llm: LLMGenerating, dictionary: [String]) {
        self.llm = llm
        self.dictionary = dictionary
    }

    /// Cleans `raw` via the LLM using the cleanup system prompt. Empty or
    /// whitespace-only input is returned unchanged without calling the LLM,
    /// so callers get graceful degradation (and avoid a pointless network
    /// round-trip) for empty transcripts.
    func clean(raw: String, toneLabel: String = "neutral") async throws -> String {
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return raw }
        let system = PromptBuilder.cleanupSystemPrompt(toneLabel: toneLabel, dictionary: dictionary)
        return try await llm.generate(system: system, prompt: raw)
    }
}
