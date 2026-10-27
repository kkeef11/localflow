import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var status: String = "Idle"
    @Published var history: [String] = []
    @Published var dictionaryText: String = ""
    /// Readiness of everything LocalFlow depends on, shown in the setup checklist.
    @Published var setup = SetupStatus()
    /// Non-blocking, informational message under the status line (e.g. cleanup was skipped).
    @Published var notice: String?

    func record(_ text: String) {
        guard !text.isEmpty else { return }
        history.insert(text, at: 0)
        if history.count > 50 { history.removeLast() }
    }

    /// Reflects `setup` in the status line — but only over "Idle" or a previous setup
    /// warning, never over an in-flight "Listening…"/"Transcribing…"/"Cleaning…".
    func applySetupStatus() {
        guard Self.isOverwritable(status) else { return }
        status = setup.summary ?? "Idle"
    }

    static func isOverwritable(_ status: String) -> Bool {
        status == "Idle" || ["Grant", "Ollama", "Speech", "Downloading", "Preparing"]
            .contains { status.hasPrefix($0) }
    }
}

enum PermissionState: Equatable {
    case granted, notDetermined, denied
}

/// Ollama readiness. Ollama is part of required setup; if it stops responding mid-session,
/// dictation still pastes the raw transcript (with a notice) rather than losing it.
enum OllamaStatus: Equatable {
    case unknown, ready, modelMissing, notRunning, notInstalled
}

enum SpeechModelState: Equatable {
    /// Not checked yet (launch). Treated as usable so the first launch doesn't flash errors.
    case unknown
    /// No completed download on disk; waiting for the user to start the download.
    case notDownloaded
    case downloading(fraction: Double)
    /// Loading into memory. The very first load also compiles the model for this Mac's
    /// Neural Engine, which can take several minutes.
    case loading
    case ready
    case failed(String)
}

struct SetupStatus: Equatable {
    var microphone: PermissionState = .granted
    var accessibility = true
    /// Whether the global hotkey event tap exists — the real test of Input Monitoring.
    var hotkeysActive = true
    var speechModel: SpeechModelState = .unknown
    var ollama: OllamaStatus = .unknown
    var ollamaModel = ""
    /// Configured speech model name, for the setup checklist's description and sizes.
    var sttModel = ""
    /// Progress of an in-app `ollama pull`, if one is running.
    var ollamaPull: Double?

    /// Setup steps still to do. Keeps the setup window opening at launch until all are done.
    var requiredItemsMissing: Bool {
        if microphone != .granted || !accessibility || !hotkeysActive { return true }
        switch speechModel {
        case .notDownloaded, .failed: return true
        default: break
        }
        switch ollama {
        case .notInstalled, .notRunning, .modelMissing: return true
        case .unknown, .ready: return false
        }
    }

    /// One-line status-bar summary of the most important missing item, or nil when ready.
    var summary: String? {
        if microphone != .granted { return "Grant Microphone access" }
        if !accessibility { return "Grant Accessibility & Input Monitoring" }
        if !hotkeysActive { return "Grant Input Monitoring, then relaunch" }
        switch speechModel {
        case .notDownloaded: return "Speech model not downloaded"
        case .downloading(let fraction): return "Downloading speech model… \(Int(fraction * 100))%"
        case .loading: return "Preparing speech model…"
        case .failed: return "Speech model failed to load"
        case .unknown, .ready: break
        }
        switch ollama {
        case .notInstalled: return "Ollama not installed"
        case .notRunning: return "Ollama not running"
        case .modelMissing: return "Ollama model \(ollamaModel) missing"
        case .unknown, .ready: return nil
        }
    }
}
