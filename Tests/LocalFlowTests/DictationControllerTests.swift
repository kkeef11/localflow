import XCTest
@testable import LocalFlow

/// Never touches real audio hardware: `start()` is a no-op and `stop()` returns a fixed,
/// empty sample buffer. `FakeTranscriber` ignores the samples entirely, so the actual
/// contents don't matter for these tests.
private struct FakeRecorder: AudioRecording {
    func start() throws {}
    func stop() -> [Float] { [] }
}

private final class FakeTranscriber: Transcribing {
    let transcript: String
    init(transcript: String) { self.transcript = transcript }
    func transcribe(samples: [Float]) async throws -> String { transcript }
}

private enum FakeLLMError: Error { case simulatedFailure }

/// `final class` with only `let` stored properties of `Sendable` types, mirroring the
/// pattern `OllamaClient` documents for satisfying `LLMGenerating: Sendable`.
private final class FakeLLM: LLMGenerating {
    private let shouldFail: Bool
    private let response: String
    init(shouldFail: Bool = false, response: String = "") {
        self.shouldFail = shouldFail
        self.response = response
    }
    func generate(system: String, prompt: String) async throws -> String {
        if shouldFail { throw FakeLLMError.simulatedFailure }
        return response
    }
}

@MainActor
private final class FakeInjector: TextInjecting {
    var injectedText: String?
    func inject(_ text: String) { injectedText = text }
    func readSelection() -> String? { nil }
    func replaceSelection(with text: String) {}
}

@MainActor
final class DictationControllerTests: XCTestCase {
    /// `finishRecording()` sets status synchronously to a non-"Idle" value, then completes
    /// the rest of the pipeline in a spawned `Task`. Polls (bounded) until that task lands
    /// on a terminal status ("Idle" or "Error: ...") instead of asserting on a fixed delay.
    private func waitForCompletion(_ state: AppState, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while state.status != "Idle" && !state.status.hasPrefix("Error") {
            if Date() > deadline {
                XCTFail("Timed out waiting for DictationController to finish; status=\(state.status)")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func makeController(
        transcript: String,
        cleanup: CleanupService?,
        state: AppState,
        injector: FakeInjector
    ) -> DictationController {
        DictationController(
            recorder: FakeRecorder(),
            transcriber: FakeTranscriber(transcript: transcript),
            cleanup: cleanup,
            injector: injector,
            state: state,
            contextProvider: ContextProvider(modes: [:]),
            router: CommandRouter(registry: ActionRegistry()),
            llm: FakeLLM()
        )
    }

    func test_commandMode_routesToAction_andDoesNotInject() async throws {
        let state = AppState()
        let injector = FakeInjector()
        // "open <nonexistent app>" matches ActionRegistry's whitelist (so CommandRouter
        // routes it as an action, not a rewrite) but resolves to no application on disk,
        // so AppAction.run is a safe no-op — nothing gets launched or typed.
        let controller = makeController(
            transcript: "open ZzNonexistentApp12345",
            cleanup: nil,
            state: state,
            injector: injector
        )

        controller.commandHotkey(pressed: true)
        controller.commandHotkey(pressed: false)
        try await waitForCompletion(state)

        XCTAssertEqual(state.status, "Idle")
        XCTAssertNil(injector.injectedText, "command mode must not inject text")
        XCTAssertTrue(state.history.isEmpty, "command mode must not record dictation history")
    }

    func test_dictationMode_injectsCleanedText() async throws {
        let state = AppState()
        let injector = FakeInjector()
        let cleanup = CleanupService(llm: FakeLLM(response: "cleaned text"), dictionary: [])
        let controller = makeController(
            transcript: "raw text",
            cleanup: cleanup,
            state: state,
            injector: injector
        )

        controller.dictationHotkey(pressed: true)
        controller.dictationHotkey(pressed: false)
        try await waitForCompletion(state)

        XCTAssertEqual(injector.injectedText, "cleaned text")
        XCTAssertEqual(state.history.first, "cleaned text")
    }

    func test_cleanupFailure_fallsBackToRawText() async throws {
        let state = AppState()
        let injector = FakeInjector()
        let cleanup = CleanupService(llm: FakeLLM(shouldFail: true), dictionary: [])
        let controller = makeController(
            transcript: "raw text",
            cleanup: cleanup,
            state: state,
            injector: injector
        )

        controller.dictationHotkey(pressed: true)
        controller.dictationHotkey(pressed: false)
        try await waitForCompletion(state)

        XCTAssertEqual(injector.injectedText, "raw text")
    }
}
