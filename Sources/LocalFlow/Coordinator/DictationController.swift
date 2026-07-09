import Foundation

/// Coordinates the Phase-1 MVP dictation flow: hold the dictation hotkey to record,
/// release to transcribe and paste the raw transcript at the cursor.
///
/// Deviation from the Task 1.5 brief: `CleanupService` (Ollama-based cleanup, Phase 2)
/// does not exist yet, so this type has no `cleanup` property in this task. Task 2.3
/// will add `cleanup: CleanupService?` and the "Cleaning…" status step back in; until
/// then this controller always does the raw-paste-only path from the brief's `else`
/// branch.
@MainActor
final class DictationController {
    private let recorder: AudioRecorder
    private let transcriber: Transcribing
    private let injector: TextInjecting
    private let state: AppState
    private let settings: SettingsStore
    private var recording = false

    init(recorder: AudioRecorder, transcriber: Transcribing,
         injector: TextInjecting, state: AppState, settings: SettingsStore) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.injector = injector
        self.state = state
        self.settings = settings
    }

    func dictationHotkey(pressed: Bool) {
        if pressed { beginRecording() } else { finishRecording() }
    }

    private func beginRecording() {
        guard !recording else { return }
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
                let text = try await transcriber.transcribe(samples: samples)
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
