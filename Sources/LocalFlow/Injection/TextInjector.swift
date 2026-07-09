import AppKit
import ApplicationServices

/// Injects transcribed text into whatever app currently has focus, and reads/replaces
/// the current text selection via the Accessibility API.
///
/// v1 trade-offs (accepted, revisit only if they cause real issues):
/// - Injection works by stashing the target text on the general pasteboard and
///   synthesizing Cmd+V, then restoring the pasteboard shortly after. This is simple and
///   works in nearly every app, but it only preserves the pasteboard's plain-text contents:
///   if the user had an image or other non-string item on the clipboard before dictating,
///   that item is lost after the restore.
/// - The restore is scheduled after `pasteboardRestoreDelay` rather than being synchronized
///   with the paste actually landing. If the target app is unusually slow to process the
///   synthetic Cmd+V, the pasteboard could be restored before the paste completes, causing
///   the wrong text to be pasted. This is a known, accepted race for v1.
@MainActor
final class TextInjector: TextInjecting {
    /// How long to wait after posting Cmd+V before restoring the pasteboard's previous
    /// contents. Long enough for the paste to land in the vast majority of apps; see the
    /// type-level doc comment for the accepted race this trades off against.
    private static let pasteboardRestoreDelay: TimeInterval = 0.25

    func inject(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        pasteCmdV()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteboardRestoreDelay) {
            pb.clearContents()
            if let saved {
                pb.setString(saved, forType: .string)
            }
        }
    }

    func readSelection() -> String? {
        let system = AXUIElementCreateSystemWide()
        // AXUIElementCopyAttributeValue's out parameter is typed `CFTypeRef?`, which in Swift
        // is just `AnyObject?`; no unsafe bridging cast is needed here.
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        // AXUIElement is a genuine distinct CF type, not a typealias for AnyObject, so
        // narrowing from the AnyObject we got back requires a downcast. It is safe here
        // because the Accessibility API is documented to hand back an AXUIElement for this
        // attribute; `as!` (rather than `unsafeDowncast`) keeps a runtime check in place in
        // case that ever changes, at the cost of a trap instead of a silent bad read.
        let element = focused as! AXUIElement
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    func replaceSelection(with text: String) {
        inject(text) // Pasting over an active selection replaces it.
    }

    private func pasteCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgSessionEventTap)
        vUp?.post(tap: .cgSessionEventTap)
    }
}
