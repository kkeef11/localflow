import AppKit

/// Maps the frontmost app's bundle identifier to a tone label (e.g. "casual"
/// for Slack, "professional" for Mail) so `CleanupService` can adapt its
/// system prompt to where the dictated text is headed. Unknown or absent
/// bundle IDs fall back to "neutral" so the app degrades gracefully when the
/// frontmost app isn't in the user's configured `modes` map.
struct ContextProvider {
    let modes: [String: String]

    func toneLabel(forBundleID id: String?) -> String {
        guard let id, let tone = modes[id] else { return "neutral" }
        return tone
    }

    @MainActor static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
