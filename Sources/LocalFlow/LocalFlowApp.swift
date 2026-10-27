import AVFoundation
import SwiftUI

@main
struct LocalFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("LocalFlow", systemImage: "mic.fill") {
            MenuBarView(state: delegate.state, onDictionarySave: delegate.saveDictionary,
                        onShowSetup: delegate.showSetup)
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    let state = AppState()
    private let hotkeys = HotkeyManager()
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let settings = SettingsStore()
    /// Retained here: the hotkey closures capture it, but an explicit owner is clearer.
    private var controller: DictationController?
    private var transcriber: WhisperKitTranscriber?
    private var llm: OllamaClient?
    private var setupWindow: NSWindow?
    /// Re-checks permissions every couple of seconds while the setup window is open, so
    /// rows tick green as soon as the user flips a switch in System Settings.
    private var recheckTimer: Timer?
    /// Health refreshes overlap (timer, menu open, Check Again) and the Ollama probe can take
    /// up to 1.5 s, so only the most recently started refresh may publish its result.
    private var healthGeneration = 0
    /// The models loaded at launch. Changing the preset takes effect on relaunch.
    private var runningModels = ModelDefaults.full

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = self.state
        let models = settings.settings.models()
        runningModels = models
        let sttModel = models.stt
        let transcriber = WhisperKitTranscriber(model: sttModel, promptTerms: settings.settings.dictionary,
                                                onState: { model in
            Task { @MainActor in
                state.setup.speechModel = model
                state.applySetupStatus()
            }
        })
        let llm = OllamaClient(model: models.llm)
        let cleanup = CleanupService(llm: llm, dictionary: settings.settings.dictionary)
        let contextProvider = ContextProvider(modes: settings.settings.contextModes)
        let router = CommandRouter(registry: ActionRegistry())
        let indicator = RecordingIndicatorController()
        let controller = DictationController(recorder: recorder, transcriber: transcriber, cleanup: cleanup,
                                             injector: injector, state: state,
                                             contextProvider: contextProvider, router: router, llm: llm,
                                             indicator: indicator,
                                             onSetupNeeded: { [weak self] in self?.showSetup() })
        self.controller = controller
        self.transcriber = transcriber
        self.llm = llm
        hotkeys.onDictation = { pressed in Task { @MainActor in controller.dictationHotkey(pressed: pressed) } }
        hotkeys.onCommand = { pressed in Task { @MainActor in controller.commandHotkey(pressed: pressed) } }
        state.dictionaryText = settings.settings.dictionary.joined(separator: ", ")
        state.setup.ollamaModel = models.llm
        state.modelChoice.preset = settings.settings.modelPreset
        if settings.settings.hasCustomModels {
            state.modelChoice.custom = "\(models.stt) + \(models.llm)"
        }
        state.setup.sttModel = sttModel

        // Speech model: load it now if a previous download completed (fully offline);
        // otherwise wait for the user to start the download from the setup window.
        if WhisperKitTranscriber.completedModelFolder(
            model: sttModel, in: WhisperKitTranscriber.defaultModelsDirectory) == nil {
            state.setup.speechModel = .notDownloaded
        }
        Task { await transcriber.loadIfDownloaded() }

        // The microphone prompt is one-time by design; ask up front rather than mid-dictation.
        if HealthCheck.microphonePermission() == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in self?.refreshHealth() }
            }
        }

        Task {
            await refreshHealthNow() // also creates the hotkey event tap
            if state.setup.requiredItemsMissing { showSetup() }
        }
    }

    /// Best-effort readiness probe: updates the setup checklist and surfaces the most
    /// important missing item in the status line. Runs at launch, on every menu open, and
    /// periodically while the setup window is open, so it reflects the CURRENT permission
    /// state — not a stale launch-time snapshot. Never stomps an in-flight
    /// "Listening…"/"Transcribing…"/"Cleaning…" (see `AppState.applySetupStatus`).
    func refreshHealth() {
        Task { await refreshHealthNow() }
    }

    private func refreshHealthNow() async {
        state.setup.microphone = HealthCheck.microphonePermission()
        state.setup.accessibility = HealthCheck.accessibilityGranted()
        // Tap creation alone proves nothing (it succeeds without Input Monitoring and then
        // receives no keys), so ask macOS about the permission too. When it flips to granted,
        // recreate the tap: one made before the grant can stay deaf.
        let listenGranted = HealthCheck.inputMonitoringGranted()
        if listenGranted && !state.setup.hotkeysActive {
            hotkeys.restart()
        }
        state.setup.hotkeysActive = hotkeys.start() && listenGranted
        healthGeneration += 1
        let generation = healthGeneration
        let ollama = await HealthCheck.ollamaStatus(model: runningModels.llm)
        guard generation == healthGeneration else { return } // a newer refresh owns the result
        state.setup.ollama = ollama
        state.applySetupStatus()
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

    /// Saves a model-size choice. Choosing a preset replaces custom models from settings.json.
    /// The models are loaded at launch, so a change asks for a relaunch; after it, Setup shows
    /// Download for any model not on disk yet.
    func chooseModelPreset(_ preset: ModelPreset) {
        settings.settings.modelPreset = preset
        settings.settings.sttModel = nil
        settings.settings.llmModel = nil
        state.modelChoice.preset = preset
        state.modelChoice.custom = nil
        state.modelChoice.relaunchNeeded = settings.settings.models() != runningModels
    }

    // MARK: - Setup window

    func showSetup() {
        if setupWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SetupView(state: state, actions: setupActions())))
            window.title = "LocalFlow Setup"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            setupWindow = window
        }
        NSApp.activate() // menu-bar-only app: bring the window in front of other apps
        setupWindow?.makeKeyAndOrderFront(nil)
        recheckTimer?.invalidate()
        recheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshHealth() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        recheckTimer?.invalidate()
        recheckTimer = nil
    }

    private func setupActions() -> SetupActions {
        SetupActions(
            request: { permission in permission.request() },
            relaunch: { [weak self] in
                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
                    let message = error?.localizedDescription
                    Task { @MainActor in
                        // Only quit once the new instance is actually launching.
                        if let message {
                            self?.state.notice = "Couldn't relaunch (\(message)). Quit and reopen LocalFlow."
                        } else {
                            NSApp.terminate(nil)
                        }
                    }
                }
            },
            downloadSpeechModel: { [weak self] in
                guard let transcriber = self?.transcriber else { return }
                Task { await transcriber.retry() }
            },
            redownloadSpeechModel: { [weak self] in
                guard let transcriber = self?.transcriber else { return }
                Task { await transcriber.redownload() }
            },
            openOllamaDownloadPage: {
                NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
            },
            startOllama: { [weak self] in
                if let app = HealthCheck.ollamaAppURL() {
                    NSWorkspace.shared.openApplication(at: app, configuration: .init())
                } else {
                    // Homebrew/CLI install: starting a background service is the user's call.
                    self?.state.notice = "Start Ollama in Terminal: brew services start ollama (or ollama serve)"
                }
            },
            pullOllamaModel: { [weak self] in self?.pullOllamaModel() },
            recheck: { [weak self] in self?.refreshHealth() },
            chooseModelPreset: { [weak self] preset in self?.chooseModelPreset(preset) }
        )
    }

    private func pullOllamaModel() {
        guard state.setup.ollamaPull == nil, let llm else { return }
        let state = self.state
        state.setup.ollamaPull = 0
        Task {
            do {
                try await llm.pull { fraction in
                    Task { @MainActor in
                        // Ignore progress that arrives after the pull already finished.
                        if let fraction, state.setup.ollamaPull != nil { state.setup.ollamaPull = fraction }
                    }
                }
                state.notice = nil
            } catch {
                state.notice = "Model download failed: \(error.localizedDescription)"
            }
            state.setup.ollamaPull = nil
            await refreshHealthNow()
        }
    }
}
