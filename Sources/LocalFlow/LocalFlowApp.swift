import SwiftUI

@main
struct LocalFlowApp: App {
    @StateObject private var state = AppState()
    private let hotkeys = HotkeyManager()
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let settings = SettingsStore()
    private let transcriber: Transcribing

    init() {
        transcriber = WhisperKitTranscriber(model: settings.settings.sttModel,
                                            promptTerms: settings.settings.dictionary)
    }

    var body: some Scene {
        MenuBarExtra("LocalFlow", systemImage: "mic.fill") {
            MenuBarView(state: state, onDictionarySave: saveDictionary)
                .onAppear {
                    wire()
                    state.dictionaryText = settings.settings.dictionary.joined(separator: ", ")
                }
        }
        .menuBarExtraStyle(.window)
    }

    /// Parses the comma-separated dictionary field and persists it to `SettingsStore`.
    /// Both the STT prompt bias (captured at `WhisperKitTranscriber` construction, above)
    /// and cleanup's dictionary (captured at `wire()` time, below) read this store once at
    /// startup — an edit here takes effect on next launch, not live. That's an acceptable
    /// v1 tradeoff and is called out in the menu copy.
    @MainActor private func saveDictionary(_ text: String) {
        settings.settings.dictionary = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// `.onAppear` can fire more than once for a `MenuBarExtra`'s content view (e.g. each
    /// time the menu is opened), but hotkey wiring must happen exactly once. The brief's
    /// `struct Once { static var done = false }` guarded against that with static mutable
    /// state, which Swift 6 strict concurrency flags as unsafe (global mutable state isn't
    /// provably isolated). `wired` is a plain stored property on this `@MainActor`-isolated
    /// method's enclosing type instead, which the compiler can confirm is only ever touched
    /// from the main actor.
    @MainActor private static var wired = false

    @MainActor private func wire() {
        guard !Self.wired else { return }
        Self.wired = true
        let llm = OllamaClient(model: settings.settings.llmModel)
        let cleanup = CleanupService(llm: llm, dictionary: settings.settings.dictionary)
        let contextProvider = ContextProvider(modes: settings.settings.contextModes)
        let router = CommandRouter(registry: ActionRegistry())
        let controller = DictationController(recorder: recorder, transcriber: transcriber, cleanup: cleanup,
                                             injector: injector, state: state, settings: settings,
                                             contextProvider: contextProvider, router: router, llm: llm)
        hotkeys.onDictation = { pressed in Task { @MainActor in controller.dictationHotkey(pressed: pressed) } }
        hotkeys.onCommand = { pressed in Task { @MainActor in controller.commandHotkey(pressed: pressed) } }
        hotkeys.start()

        // Best-effort readiness probe: surfaces a warning status if Accessibility isn't
        // granted (hotkeys/injection won't work) or Ollama isn't reachable (cleanup will be
        // skipped). Neither check blocks dictation — it still works via WhisperKit alone.
        Task { @MainActor in
            if !HealthCheck.accessibilityGranted() {
                state.status = "Grant Accessibility & Input Monitoring"
            } else if !(await HealthCheck.ollamaReachable()) {
                state.status = "Ollama not running (ollama serve)"
            }
        }
    }
}
