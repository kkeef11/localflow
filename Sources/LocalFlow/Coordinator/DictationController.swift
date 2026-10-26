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
    private var recorder: AudioRecording
    private let transcriber: Transcribing
    private let cleanup: CleanupService?
    private let injector: TextInjecting
    private let state: AppState
    private let contextProvider: ContextProvider
    private let router: CommandRouter
    private let llm: LLMGenerating
    private let indicator: RecordingIndicating
    /// Whether synthetic keystrokes will actually be delivered. macOS silently DROPS
    /// posted events from apps without Accessibility trust — no error, no prompt — so
    /// pasting without checking this looks like success while nothing lands (the
    /// failure mode that cost a debugging session on 2026-07-09). Injectable for tests.
    private let axTrusted: @Sendable () -> Bool
    /// Whether the microphone is usable. Without permission macOS hands the app silent
    /// buffers rather than an error, and Whisper "transcribes" silence into phrases like
    /// "Thank you." — which would then be pasted. Injectable for tests.
    private let micAuthorized: @Sendable () -> Bool
    private var recording = false
    private var capturedTone = "neutral"
    private enum Mode { case dictation, command }
    private var mode: Mode = .dictation

    init(recorder: AudioRecording, transcriber: Transcribing, cleanup: CleanupService? = nil,
         injector: TextInjecting, state: AppState,
         contextProvider: ContextProvider, router: CommandRouter, llm: LLMGenerating,
         indicator: RecordingIndicating = NoopIndicator(),
         axTrusted: @escaping @Sendable () -> Bool = { HealthCheck.accessibilityGranted() },
         micAuthorized: @escaping @Sendable () -> Bool = { HealthCheck.microphonePermission() == .granted }) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleanup = cleanup
        self.injector = injector
        self.state = state
        self.contextProvider = contextProvider
        self.router = router
        self.llm = llm
        self.indicator = indicator
        self.axTrusted = axTrusted
        self.micAuthorized = micAuthorized
    }

    func dictationHotkey(pressed: Bool) {
        if pressed { mode = .dictation; beginRecording() } else { finishRecording() }
    }

    /// Mirrors `dictationHotkey(pressed:)` but tags the capture as `.command` so
    /// `finishRecording()` routes the transcript through `CommandRouter` instead of the
    /// cleanup/inject dictation path. Mode is shared mutable state read AFTER transcription
    /// completes (post-await), not captured at hotkey release. If another recording starts
    /// while a prior transcription is still in flight, the prior session's transcript is
    /// routed per the NEWEST mode (and cleanup uses the newest capturedTone) — "last press
    /// wins", per design. Accepted trade-off: no interlocking; overlapping sessions are rare
    /// in push-to-talk use.
    func commandHotkey(pressed: Bool) {
        if pressed { mode = .command; beginRecording() } else { finishRecording() }
    }

    private func beginRecording() {
        guard !recording else { return }
        guard micAuthorized() else {
            state.status = "Grant Microphone access"
            return
        }
        switch state.setup.speechModel {
        case .notDownloaded, .failed:
            // Recording now would only end in an error after the user finished speaking.
            state.status = "Speech model not ready — open Setup"
            return
        default:
            break
        }
        capturedTone = contextProvider.toneLabel(forBundleID: ContextProvider.frontmostBundleID())
        recording = true
        state.status = "Listening…"
        indicator.show(mode: mode == .command ? .command : .dictation)
        let indicator = self.indicator
        recorder.onLevel = { level in Task { @MainActor in indicator.updateLevel(level) } }
        do {
            try recorder.start()
        } catch {
            recording = false
            recorder.onLevel = nil
            indicator.hide()
            state.status = "Error: microphone unavailable (\(error.localizedDescription))"
        }
    }

    private func finishRecording() {
        guard recording else { return }
        recording = false
        state.status = "Transcribing…"
        let samples = recorder.stop()
        recorder.onLevel = nil
        indicator.beginProcessing()
        Task { @MainActor in
            defer { indicator.hide() }
            do {
                let raw = try await transcriber.transcribe(samples: samples)
                if mode == .command {
                    state.status = "Command…"
                    await router.execute(router.decide(raw), llm: llm, injector: injector)
                    returnToIdle()
                    return
                }
                var text = raw
                if let cleanup {
                    state.status = "Cleaning…"
                    do {
                        text = try await cleanup.clean(raw: text, toneLabel: capturedTone)
                        state.notice = nil
                    } catch {
                        // Degrade to the raw transcript, but say so instead of failing silently.
                        state.notice = "Cleanup skipped (\(error.localizedDescription)); pasted the raw transcript."
                    }
                }
                guard !text.isEmpty else { returnToIdle(); return }
                guard axTrusted() else {
                    // Keep the transcript in history so it can be copied manually.
                    state.record(text)
                    state.status = "Grant Accessibility (paste blocked)"
                    return
                }
                injector.inject(text)
                state.record(text)
                returnToIdle()
            } catch {
                state.status = "Error: \(error.localizedDescription)"
            }
        }
    }

    /// Back to "Idle" — or to an outstanding setup warning (e.g. Ollama down), so finishing
    /// a dictation doesn't hide it.
    private func returnToIdle() {
        state.status = "Idle"
        state.applySetupStatus()
    }
}
