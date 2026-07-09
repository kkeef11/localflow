import Foundation

/// Coordinates the Phase-1/2 dictation flow: hold the dictation hotkey to record,
/// release to transcribe, optionally clean up via the local LLM, and paste the
/// result at the cursor.
///
/// `cleanup` is optional: when `nil` (or when cleanup throws), the controller
/// falls back to the raw transcript, so the app degrades gracefully if Ollama
/// isn't running or a `CleanupService` isn't wired up.
@MainActor
final class DictationController {
    private let recorder: AudioRecorder
    private let transcriber: Transcribing
    private let cleanup: CleanupService?
    private let injector: TextInjecting
    private let state: AppState
    private let settings: SettingsStore
    private let contextProvider: ContextProvider
    private let router: CommandRouter
    private let llm: LLMGenerating
    private var recording = false
    private var capturedTone = "neutral"
    private enum Mode { case dictation, command }
    private var mode: Mode = .dictation

    init(recorder: AudioRecorder, transcriber: Transcribing, cleanup: CleanupService? = nil,
         injector: TextInjecting, state: AppState, settings: SettingsStore,
         contextProvider: ContextProvider, router: CommandRouter, llm: LLMGenerating) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleanup = cleanup
        self.injector = injector
        self.state = state
        self.settings = settings
        self.contextProvider = contextProvider
        self.router = router
        self.llm = llm
    }

    func dictationHotkey(pressed: Bool) {
        if pressed { mode = .dictation; beginRecording() } else { finishRecording() }
    }

    /// Mirrors `dictationHotkey(pressed:)` but tags the capture as `.command` so
    /// `finishRecording()` routes the transcript through `CommandRouter` instead of the
    /// cleanup/inject dictation path. If both hotkeys are held, the most recently pressed
    /// one wins `mode` (no interlocking/queueing) — an edge case not worth engineering
    /// around for a solo-user, hold-and-release control scheme.
    func commandHotkey(pressed: Bool) {
        if pressed { mode = .command; beginRecording() } else { finishRecording() }
    }

    private func beginRecording() {
        guard !recording else { return }
        capturedTone = contextProvider.toneLabel(forBundleID: ContextProvider.frontmostBundleID())
        recording = true
        state.status = "Listening…"
        try? recorder.start()
    }

    private func finishRecording() {
        guard recording else { return }
        recording = false
        state.status = "Transcribing…"
        let samples = recorder.stop()
        Task { @MainActor in
            do {
                let raw = try await transcriber.transcribe(samples: samples)
                if mode == .command {
                    state.status = "Command…"
                    await router.execute(router.decide(raw), llm: llm, injector: injector)
                    state.status = "Idle"
                    return
                }
                var text = raw
                if let cleanup {
                    state.status = "Cleaning…"
                    text = (try? await cleanup.clean(raw: text, toneLabel: capturedTone)) ?? text
                }
                guard !text.isEmpty else { state.status = "Idle"; return }
                injector.inject(text)
                state.record(text)
                state.status = "Idle"
            } catch {
                state.status = "Error: \(error.localizedDescription)"
            }
        }
    }
}
