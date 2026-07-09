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
        transcriber = WhisperKitTranscriber(model: settings.settings.sttModel)
    }

    var body: some Scene {
        MenuBarExtra("LocalFlow", systemImage: "mic.fill") {
            MenuBarView(state: state)
                .onAppear { wire() }
        }
        .menuBarExtraStyle(.window)
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
        let controller = DictationController(recorder: recorder, transcriber: transcriber,
                                             injector: injector, state: state, settings: settings)
        hotkeys.onDictation = { pressed in Task { @MainActor in controller.dictationHotkey(pressed: pressed) } }
        hotkeys.start()
    }
}
