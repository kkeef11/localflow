import Foundation

/// The result of interpreting a transcript: either a whitelisted app action (with its
/// argument, if any), a free-form rewrite instruction to hand to the LLM, or nothing at all.
enum CommandDecision: Equatable {
    case action(id: String, argument: String?)
    case rewrite(instruction: String)
    case none
}

/// Decides what a transcript means (an app action vs. free-form text to rewrite) and,
/// separately, carries out that decision.
struct CommandRouter {
    let registry: ActionRegistry

    /// Interprets a transcript. Whitelisted phrases (see `ActionRegistry`) win; anything else
    /// is treated as an instruction to rewrite the current selection. Blank input is `.none`.
    func decide(_ transcript: String) -> CommandDecision {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .none }
        if let m = registry.match(t) {
            return .action(id: m.action.id, argument: m.argument)
        }
        return .rewrite(instruction: t)
    }

    /// Carries out a `CommandDecision`.
    ///
    /// For `.action`, this re-derives the `AppAction` from `registry` by reconstructing a
    /// phrase from `id`/`argument` and re-matching it, rather than storing the action's `run`
    /// closure directly on `CommandDecision`. That's deliberate: `CommandDecision` is
    /// `Equatable` (required so callers, including Task 4.3, can pattern-match and assert on
    /// it in tests), and `AppAction.run` is a `@MainActor` closure, which is neither
    /// `Equatable` nor safely storable in a `Sendable`/value-comparable enum case. Re-matching
    /// keeps the decision type simple and comparable at the cost of a cheap, deterministic
    /// re-lookup against the same fixed whitelist `decide` already consulted. If re-matching
    /// fails (it shouldn't, since `id`/`argument` came from a prior successful match against
    /// the same registry), this is a no-op rather than a crash.
    @MainActor
    func execute(_ decision: CommandDecision, llm: LLMGenerating, injector: TextInjecting) async {
        switch decision {
        case .none:
            return
        case .action(let id, let argument):
            let phrase = id == "open" ? "open \(argument ?? "")" : id
            guard let m = registry.match(phrase) else { return }
            m.action.run(argument)
        case .rewrite(let instruction):
            guard let selection = injector.readSelection(), !selection.isEmpty else { return }
            let system = "You rewrite text per an instruction. Output ONLY the rewritten text, no preamble."
            let prompt = "Instruction: \(instruction)\n\nText:\n\(selection)"
            if let rewritten = try? await llm.generate(system: system, prompt: prompt) {
                injector.replaceSelection(with: rewritten)
            }
        }
    }
}
