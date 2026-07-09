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
    private var recording = false
    private var capturedTone = "neutral"

    init(recorder: AudioRecorder, transcriber: Transcribing, cleanup: CleanupService? = nil,
         injector: TextInjecting, state: AppState, settings: SettingsStore,
         contextProvider: ContextProvider) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleanup = cleanup
        self.injector = injector
        self.state = state
        self.settings = settings
        self.contextProvider = contextProvider
    }

    func dictationHotkey(pressed: Bool) {
        if pressed { beginRecording() } else { finishRecording() }
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
                var text = try await transcriber.transcribe(samples: samples)
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
