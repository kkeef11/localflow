import SwiftUI

/// What the setup checklist's buttons do. Supplied by `AppDelegate`, which owns the objects
/// involved; every action is user-initiated (nothing here runs on its own).
struct SetupActions {
    var request: (Permission) -> Void = { _ in }
    var relaunch: () -> Void = {}
    var downloadSpeechModel: () -> Void = {}
    var openOllamaDownloadPage: () -> Void = {}
    var startOllama: () -> Void = {}
    var pullOllamaModel: () -> Void = {}
    var recheck: () -> Void = {}
}

/// First-run checklist: one row per dependency, each explaining why it's needed and offering
/// the single next step. Shown in its own window at launch when something required is
/// missing, and reachable any time from the menu's "Setup…" button.
struct SetupView: View {
    @ObservedObject var state: AppState
    var actions: SetupActions

    var body: some View {
        let setup = state.setup
        VStack(alignment: .leading, spacing: 14) {
            Text("LocalFlow Setup").font(.title2.bold())
            Text("Everything runs on this Mac. These steps are needed once.")
                .foregroundStyle(.secondary)

            row(done: setup.microphone == .granted, title: "Microphone",
                why: "To hear your dictation. Audio never leaves this Mac.") {
                Button(setup.microphone == .notDetermined ? "Allow…" : "Open Settings") {
                    actions.request(.microphone)
                }
            }
            row(done: setup.accessibility, title: "Accessibility",
                why: "To paste text at your cursor and read selected text for rewrites.") {
                Button("Open Settings") { actions.request(.accessibility) }
            }
            row(done: setup.hotkeysActive, title: "Input Monitoring",
                why: "To notice when you hold Right Option / Right Shift. If it's already on, relaunch LocalFlow.") {
                HStack {
                    Button("Open Settings") { actions.request(.inputMonitoring) }
                    Button("Relaunch") { actions.relaunch() }
                }
            }
            speechRow(setup.speechModel)
            ollamaRow(setup)

            HStack {
                Spacer()
                Button("Check Again") { actions.recheck() }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder
    private func speechRow(_ model: SpeechModelState) -> some View {
        let why = "Whisper large-v3 turns speech into text on-device. One-time ~3 GB download; works offline afterwards."
        switch model {
        case .ready, .unknown:
            row(done: true, title: "Speech model", why: why) { EmptyView() }
        case .notDownloaded:
            row(done: false, title: "Speech model", why: why) {
                Button("Download (~3 GB)") { actions.downloadSpeechModel() }
            }
        case .downloading(let fraction):
            row(done: false, title: "Speech model", why: "Downloading… you can keep using your Mac. If interrupted, it resumes next time.") {
                ProgressView(value: fraction).frame(width: 120)
            }
        case .loading:
            row(done: false, title: "Speech model",
                why: "Preparing the model for this Mac. The first time can take several minutes; later launches are quick.") {
                ProgressView().controlSize(.small)
            }
        case .failed(let message):
            row(done: false, title: "Speech model", why: "Couldn't load: \(message)") {
                Button("Retry") { actions.downloadSpeechModel() }
            }
        }
    }

    @ViewBuilder
    private func ollamaRow(_ setup: SetupStatus) -> some View {
        let title = "Ollama (optional)"
        switch setup.ollama {
        case .ready, .unknown:
            row(done: true, title: title, why: "Cleans up punctuation and filler words with \(setup.ollamaModel).") { EmptyView() }
        case .notInstalled:
            row(done: false, title: title,
                why: "Cleans up punctuation and filler words. Without it, LocalFlow pastes the raw transcript.") {
                Button("Get Ollama") { actions.openOllamaDownloadPage() }
            }
        case .notRunning:
            row(done: false, title: title, why: "Installed but not running, so cleanup is off.") {
                Button("Start Ollama") { actions.startOllama() }
            }
        case .modelMissing:
            if let progress = setup.ollamaPull {
                row(done: false, title: title, why: "Downloading \(setup.ollamaModel)…") {
                    ProgressView(value: progress).frame(width: 120)
                }
            } else {
                row(done: false, title: title,
                    why: "Ollama is running but the cleanup model \(setup.ollamaModel) isn't downloaded (several GB).") {
                    Button("Download") { actions.pullOllamaModel() }
                }
            }
        }
    }

    private func row(done: Bool, title: String, why: String,
                     @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(why).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !done { action() }
        }
    }
}
