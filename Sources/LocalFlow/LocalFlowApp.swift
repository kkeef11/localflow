import SwiftUI

@main
struct LocalFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("LocalFlow", systemImage: "mic.fill") {
            MenuBarView(state: delegate.state, onDictionarySave: delegate.saveDictionary)
                .onAppear { delegate.refreshHealth() } // re-check every time the menu opens
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the app's long-lived objects and wires the pipeline in
/// `applicationDidFinishLaunching` — i.e. at LAUNCH. The previous design wired in the
/// menu content's `.onAppear`, which for a `MenuBarExtra` only fires when the menu is
/// first opened — leaving hotkeys dead until the user happened to click the icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state = AppState()
    private let hotkeys = HotkeyManager()
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let settings = SettingsStore()
    /// Retained here: the hotkey closures capture it, but an explicit owner is clearer.
    private var controller: DictationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let transcriber = WhisperKitTranscriber(model: settings.settings.sttModel,
                                                promptTerms: settings.settings.dictionary)
        let llm = OllamaClient(model: settings.settings.llmModel)
        let cleanup = CleanupService(llm: llm, dictionary: settings.settings.dictionary)
        let contextProvider = ContextProvider(modes: settings.settings.contextModes)
        let router = CommandRouter(registry: ActionRegistry())
        let indicator = RecordingIndicatorController()
        let controller = DictationController(recorder: recorder, transcriber: transcriber, cleanup: cleanup,
                                             injector: injector, state: state,
                                             contextProvider: contextProvider, router: router, llm: llm,
                                             indicator: indicator)
        self.controller = controller
        hotkeys.onDictation = { pressed in Task { @MainActor in controller.dictationHotkey(pressed: pressed) } }
        hotkeys.onCommand = { pressed in Task { @MainActor in controller.commandHotkey(pressed: pressed) } }
        hotkeys.start()
        state.dictionaryText = settings.settings.dictionary.joined(separator: ", ")

        refreshHealth()
    }

    /// Best-effort readiness probe: surfaces a warning status if Accessibility isn't
    /// granted (injection won't land) or Ollama isn't reachable (cleanup will be skipped).
    /// Runs at launch and again on every menu open, so the status reflects the CURRENT
    /// permission state — not a stale launch-time snapshot. Only overwrites Idle/warning
    /// statuses; never stomps an in-flight "Listening…"/"Transcribing…"/"Cleaning…".
    func refreshHealth() {
        Task { @MainActor in
            let overwritable = state.status == "Idle"
                || state.status.hasPrefix("Grant")
                || state.status.hasPrefix("Ollama")
            guard overwritable else { return }
            if !HealthCheck.accessibilityGranted() {
                state.status = "Grant Accessibility & Input Monitoring"
            } else if !(await HealthCheck.ollamaReachable()) {
                state.status = "Ollama not running (ollama serve)"
            } else {
                state.status = "Idle"
            }
        }
    }

    /// Parses the comma-separated dictionary field and persists it to `SettingsStore`.
    /// Both the STT prompt bias and cleanup's dictionary read this store once at
    /// startup — an edit here takes effect on next launch, not live. That's an
    /// acceptable v1 tradeoff and is called out in the menu copy.
    func saveDictionary(_ text: String) {
        settings.settings.dictionary = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
