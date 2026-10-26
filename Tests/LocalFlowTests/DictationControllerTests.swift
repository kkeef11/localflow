import XCTest
@testable import LocalFlow

/// Never touches real audio hardware: `start()` is a no-op and `stop()` returns a fixed,
/// empty sample buffer. `FakeTranscriber` ignores the samples entirely, so the actual
/// contents don't matter for these tests.
private final class FakeRecorder: AudioRecording, @unchecked Sendable {
    var onLevel: (@Sendable (Float) -> Void)?
    var startError: Error?
    private(set) var started = false
    func start() throws {
        if let startError { throw startError }
        started = true
    }
    func stop() -> [Float] { [] }
    /// Test helper: simulate the audio thread delivering a level.
    func emit(_ level: Float) { onLevel?(level) }
}

/// Records the lifecycle calls the controller makes so tests can assert ordering.
@MainActor
private final class SpyIndicator: RecordingIndicating {
    enum Event: Equatable { case show(IndicatorMode); case level(Float); case processing; case hide }
    private(set) var events: [Event] = []
    func show(mode: IndicatorMode) { events.append(.show(mode)) }
    func updateLevel(_ level: Float) { events.append(.level(level)) }
    func beginProcessing() { events.append(.processing) }
    func hide() { events.append(.hide) }
}

/// Trivially equatable (no associated values); declared in-test to avoid touching production code.
extension IndicatorMode: Equatable {}

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
        while state.status != "Idle" && !state.status.hasPrefix("Error") && !state.status.hasPrefix("Grant") {
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
        injector: FakeInjector,
        indicator: RecordingIndicating = NoopIndicator(),
        recorder: FakeRecorder = FakeRecorder(),
        axTrusted: @escaping @Sendable () -> Bool = { true },
        micAuthorized: @escaping @Sendable () -> Bool = { true }
    ) -> DictationController {
        DictationController(
            recorder: recorder,
            transcriber: FakeTranscriber(transcript: transcript),
            cleanup: cleanup,
            injector: injector,
            state: state,
            contextProvider: ContextProvider(modes: [:]),
            router: CommandRouter(registry: ActionRegistry()),
            llm: FakeLLM(),
            indicator: indicator,
            axTrusted: axTrusted,
            micAuthorized: micAuthorized
        )
    }

    func test_missing_accessibility_blocks_paste_with_actionable_status() async throws {
        let state = AppState()
        let injector = FakeInjector()
        let controller = makeController(transcript: "raw text", cleanup: nil,
                                        state: state, injector: injector,
                                        axTrusted: { false })

        controller.dictationHotkey(pressed: true)
        controller.dictationHotkey(pressed: false)
        try await waitForCompletion(state)

        XCTAssertNil(injector.injectedText, "must not attempt a paste that macOS will silently drop")
        XCTAssertEqual(state.status, "Grant Accessibility (paste blocked)")
        XCTAssertEqual(state.history.first, "raw text", "transcript must be preserved in history for manual copy")
    }

    func test_missing_microphone_permission_blocks_recording() async throws {
        let state = AppState(); let injector = FakeInjector(); let spy = SpyIndicator()
        let recorder = FakeRecorder()
        let controller = makeController(transcript: "Thank you.", cleanup: nil, state: state,
                                        injector: injector, indicator: spy, recorder: recorder,
                                        micAuthorized: { false })
        controller.dictationHotkey(pressed: true)
        controller.dictationHotkey(pressed: false)
        XCTAssertFalse(recorder.started, "must not record silence that Whisper would hallucinate over")
        XCTAssertEqual(state.status, "Grant Microphone access")
        XCTAssertTrue(spy.events.isEmpty)
        XCTAssertNil(injector.injectedText)
    }

    func test_missing_speech_model_blocks_recording() async throws {
        let state = AppState(); let injector = FakeInjector()
        state.setup.speechModel = .notDownloaded
        let recorder = FakeRecorder()
        let controller = makeController(transcript: "raw", cleanup: nil, state: state,
                                        injector: injector, recorder: recorder)
        controller.dictationHotkey(pressed: true)
        controller.dictationHotkey(pressed: false)
        XCTAssertFalse(recorder.started)
        XCTAssertEqual(state.status, "Speech model not ready — open Setup")
        XCTAssertNil(injector.injectedText)
    }

    func test_recorder_start_failure_reports_error_and_resets() async throws {
        let state = AppState(); let injector = FakeInjector(); let spy = SpyIndicator()
        let recorder = FakeRecorder()
        recorder.startError = FakeLLMError.simulatedFailure
        let controller = makeController(transcript: "raw", cleanup: nil, state: state,
                                        injector: injector, indicator: spy, recorder: recorder)
        controller.dictationHotkey(pressed: true)
        XCTAssertTrue(state.status.hasPrefix("Error: microphone unavailable"))
        XCTAssertEqual(spy.events.last, .hide)
        controller.dictationHotkey(pressed: false) // release after a failed start is a no-op
        XCTAssertTrue(state.status.hasPrefix("Error: microphone unavailable"))
        XCTAssertNil(injector.injectedText)
    }

    func test_dictation_shows_processing_then_hides() async throws {
        let state = AppState(); let injector = FakeInjector(); let spy = SpyIndicator()
        let cleanup = CleanupService(llm: FakeLLM(response: "cleaned"), dictionary: [])
        let controller = makeController(transcript: "raw", cleanup: cleanup,
                                        state: state, injector: injector, indicator: spy)
        controller.dictationHotkey(pressed: true)
        controller.dictationHotkey(pressed: false)
        try await waitForCompletion(state)
        XCTAssertEqual(spy.events.first, .show(.dictation))
        XCTAssertTrue(spy.events.contains(.processing))
        XCTAssertEqual(spy.events.last, .hide)
    }

    func test_command_shows_command_mode_and_hides() async throws {
        let state = AppState(); let injector = FakeInjector(); let spy = SpyIndicator()
        let controller = makeController(transcript: "open ZzNonexistentApp12345",
                                        cleanup: nil, state: state, injector: injector, indicator: spy)
        controller.commandHotkey(pressed: true)
        controller.commandHotkey(pressed: false)
        try await waitForCompletion(state)
        XCTAssertEqual(spy.events.first, .show(.command))
        XCTAssertEqual(spy.events.last, .hide)
    }

    func test_level_updates_forwarded_while_listening() async throws {
        let state = AppState(); let injector = FakeInjector(); let spy = SpyIndicator()
        let recorder = FakeRecorder()
        let controller = makeController(transcript: "raw", cleanup: nil,
                                        state: state, injector: injector,
                                        indicator: spy, recorder: recorder)
        controller.dictationHotkey(pressed: true)
        recorder.emit(0.5)  // simulate a mic buffer
        // The controller hops levels to the main actor via a Task; yield until it lands.
        for _ in 0..<50 where !spy.events.contains(.level(0.5)) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(spy.events.contains(.level(0.5)))
        controller.dictationHotkey(pressed: false)
        try await waitForCompletion(state)
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
        XCTAssertNotNil(state.notice, "a skipped cleanup must be visible, not silent")
    }
}
