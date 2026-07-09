import ApplicationServices
import Foundation

/// Lightweight, dependency-free readiness probes surfaced as a warning status in the menu
/// bar. Both checks are best-effort: a failure here degrades the status text but never blocks
/// dictation, since the underlying pipeline (WhisperKit, cleanup skip-on-error) already
/// tolerates Ollama being down or Accessibility being ungranted.
enum HealthCheck {
    /// Hits Ollama's local `/api/tags` endpoint. Localhost-only, matching this app's
    /// no-outbound-network constraint. A short timeout keeps `wire()`'s startup check snappy
    /// even when Ollama isn't running (connection refused is fast, but a hung/firewalled port
    /// shouldn't stall status reporting).
    static func ollamaReachable() async -> Bool {
        var req = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        req.timeoutInterval = 1.5
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    /// Whether this process currently holds Accessibility (and, transitively, Input
    /// Monitoring) trust — required for the global hotkey and synthetic keystroke injection.
    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}
