import AppKit
import ApplicationServices
import AVFoundation
import Foundation

/// Lightweight, dependency-free readiness probes surfaced in the status line and the setup
/// checklist. All checks are best-effort: a failure here degrades the status text but never
/// blocks dictation, since the underlying pipeline (WhisperKit, cleanup skip-on-error) already
/// tolerates Ollama being down.
enum HealthCheck {
    static let ollamaBaseURL = URL(string: "http://localhost:11434")!

    /// Classifies Ollama's state by asking the local server which models it has
    /// (`/api/tags`). Localhost-only, matching this app's no-outbound-network constraint. A
    /// short timeout keeps the check snappy even when the port is hung or firewalled.
    static func ollamaStatus(model: String, baseURL: URL = ollamaBaseURL,
                             session: URLSession = .shared) async -> OllamaStatus {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 1.5
        guard let (data, response) = try? await session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return ollamaInstalled() ? .notRunning : .notInstalled
        }
        struct Tags: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }
        let names = (try? JSONDecoder().decode(Tags.self, from: data))?.models.map(\.name) ?? []
        return modelAvailable(model, in: names) ? .ready : .modelMissing
    }

    /// Ollama lists untagged pulls as `name:latest`, so `llama3` matches `llama3:latest`.
    static func modelAvailable(_ model: String, in names: [String]) -> Bool {
        let wanted = model.contains(":") ? model : model + ":latest"
        return names.contains(wanted)
    }

    /// Where the Ollama desktop app (or its CLI, for Homebrew installs) is, if anywhere.
    static func ollamaAppURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama")
            ?? ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
                .map { URL(fileURLWithPath: $0) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func ollamaInstalled() -> Bool {
        ollamaAppURL() != nil
            || ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"].contains {
                FileManager.default.isExecutableFile(atPath: $0)
            }
    }

    /// Whether this process currently holds Accessibility trust — required for synthetic
    /// keystroke injection (macOS silently drops posted events otherwise).
    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Whether macOS will actually deliver keyboard events to our listen-only tap. Creating
    /// the tap succeeds either way, so this — not tap creation — is the real check.
    static func inputMonitoringGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func microphonePermission() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}

/// The three privacy permissions LocalFlow needs, and how to send the user to each one.
/// Nothing here can grant a permission — only the user can, in System Settings.
enum Permission {
    case microphone, accessibility, inputMonitoring

    var settingsURL: URL {
        let anchor: String
        switch self {
        case .microphone: anchor = "Privacy_Microphone"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    /// Shows the system prompt where macOS offers one (microphone: once, ever; the others:
    /// a dialog pointing at System Settings), then opens the matching Settings pane so the
    /// user lands in the right place either way.
    @MainActor
    func request() {
        switch self {
        case .microphone:
            if HealthCheck.microphonePermission() == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
                return
            }
        case .accessibility:
            let prompt = "AXTrustedCheckOptionPrompt" as CFString
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        }
        NSWorkspace.shared.open(settingsURL)
    }
}
