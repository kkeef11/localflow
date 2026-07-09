import AppKit

/// A single whitelisted app action. `run` is invoked by the caller (CommandRouter, Task 4.2)
/// with the `argument` returned alongside it from `ActionRegistry.match`.
struct AppAction {
    let id: String
    let run: @MainActor (String?) -> Void
}

/// Matches a transcribed phrase against a fixed, closed set of app actions.
///
/// This is a security boundary, not a convenience feature: only `open <app>`, `copy`, and
/// `paste` are recognized. There is no shell, no arbitrary command execution, and no way to
/// extend the whitelist from user input. Anything that doesn't match one of these three
/// prefixes returns `nil`.
struct ActionRegistry {
    /// Directories searched, in order, when resolving an app name to a launchable URL.
    /// Deliberately limited to standard installation locations; this is a lookup, not a
    /// filesystem-wide search.
    private static let searchDirectories = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    func match(_ phrase: String) -> (action: AppAction, argument: String?)? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("open ") {
            // "open " is a fixed-length ASCII prefix, so dropping that many characters from
            // the original (case-preserved) string is exactly the case-insensitive prefix
            // range — no NSRange/utf16 offset juggling required.
            // Whisper punctuates transcripts ("Open Microsoft Excel."), so strip
            // trailing punctuation as well as whitespace — filenames are matched exactly.
            let arg = String(trimmed.dropFirst("open ".count))
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".,!?;:")))
            // Reject arguments containing path separators to prevent traversal
            guard !arg.contains("/") else { return nil }
            return (AppAction(id: "open") { name in
                guard let name, !name.isEmpty else { return }
                guard let url = Self.resolveApplicationURL(named: name) else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }, arg)
        }
        if lower.hasPrefix("copy") {
            return (AppAction(id: "copy") { _ in
                Self.postKeyCombo(keyCode: 0x08, flags: .maskCommand) // Cmd+C
            }, nil)
        }
        if lower.hasPrefix("paste") {
            return (AppAction(id: "paste") { _ in
                Self.postKeyCombo(keyCode: 0x09, flags: .maskCommand) // Cmd+V
            }, nil)
        }
        return nil
    }

    /// Resolves an app name (with or without ".app") to its bundle URL by looking in the
    /// standard app directories.
    ///
    /// `NSWorkspace.launchApplication(_:)` and `NSWorkspace.fullPath(forApplication:)` are
    /// both deprecated (macOS 11+, in favor of `URLForApplicationWithBundleIdentifier:`),
    /// but that replacement takes a bundle identifier, not a human-spoken app name — it
    /// doesn't fit this lookup. Rather than call a deprecated by-name API, this resolves the
    /// name directly against the filesystem (an exact-name fast path, then a case-insensitive
    /// directory scan) and launches the result via the modern
    /// `openApplication(at:configuration:)`. This only finds top-level apps in standard
    /// locations, which is a fine trade-off for a voice command whitelist.
    private static func resolveApplicationURL(named name: String) -> URL? {
        guard !name.contains("/"), !name.contains("..") else { return nil }
        let candidateFileNames = name.lowercased().hasSuffix(".app") ? [name] : [name, "\(name).app"]
        let fm = FileManager.default

        for directory in searchDirectories {
            for candidate in candidateFileNames {
                let path = "\(directory)/\(candidate)"
                if fm.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }

        let targetNames = Set(candidateFileNames.map { $0.lowercased() })
        for directory in searchDirectories {
            guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            if let match = entries.first(where: { targetNames.contains($0.lowercased()) }) {
                return URL(fileURLWithPath: "\(directory)/\(match)")
            }
        }
        return nil
    }

    /// Posts a keyDown/keyUp pair for `keyCode` with `flags` held (e.g. Cmd+C, Cmd+V).
    /// Shared by the `copy` and `paste` actions to avoid duplicating the CGEvent boilerplate.
    private static func postKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
