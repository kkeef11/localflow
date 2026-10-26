import CoreGraphics
import AppKit
import os

/// Listens globally for modifier-key flag changes via a CGEvent tap and reports
/// press/release of the two hotkeys LocalFlow cares about:
///   - Right Option (keycode 61) → dictation
///   - Right Shift (keycode 60) → command mode (wired starting Task 4.3)
///
/// The event tap runs its callback on whichever run loop it is attached to — here, the
/// main run loop (see `start()`), so `onDictation`/`onCommand` are always invoked on
/// the main thread/actor. The C callback can't capture Swift context, so `self` is
/// passed through as an opaque pointer via `userInfo` and recovered with
/// `Unmanaged.fromOpaque(...).takeUnretainedValue()`; ownership stays with the `self`
/// reference held by whoever created this manager (LocalFlowApp), matching the brief
/// exactly.
final class HotkeyManager {
    /// Debug visibility: `/usr/bin/log stream --predicate 'subsystem ==
    /// "com.kkeefer.LocalFlow"' --level debug` shows tap lifecycle + hotkey hits.
    fileprivate static let log = Logger(subsystem: "com.kkeefer.LocalFlow", category: "hotkeys")
    var onDictation: (Bool) -> Void = { _ in }
    var onCommand: (Bool) -> Void = { _ in }
    private var tap: CFMachPort?

    /// Creates the event tap if it doesn't exist yet. Returns whether hotkeys are live.
    /// Safe to call repeatedly: the health check retries it after the user grants Input
    /// Monitoring, since tap creation fails (returns nil) until then.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo!).takeUnretainedValue()
            // macOS disables a tap whose runloop stalls (e.g. under heavy first-transcription
            // load) by delivering .tapDisabledByTimeout. Without re-enabling here, the
            // hotkeys die permanently — the "worked once, then never again" failure mode.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                HotkeyManager.log.debug("tap disabled by system (\(type.rawValue)) — re-enabling")
                if let tap = mgr.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return nil
            }
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == 61 || keycode == 60 {
                HotkeyManager.log.debug("hotkey keycode=\(keycode) flags=\(event.flags.rawValue)")
            }
            if keycode == 61 { mgr.onDictation(event.flags.contains(.maskAlternate)) }
            if keycode == 60 { mgr.onCommand(event.flags.contains(.maskShift)) }
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: .listenOnly, eventsOfInterest: mask,
                                callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            Self.log.error("event tap creation FAILED — Input Monitoring/Accessibility not effective")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Self.log.debug("event tap created and enabled")
        return true
    }
}
