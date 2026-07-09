import CoreGraphics
import AppKit

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
    var onDictation: (Bool) -> Void = { _ in }
    var onCommand: (Bool) -> Void = { _ in }
    private var tap: CFMachPort?

    func start() {
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let callback: CGEventTapCallBack = { _, _, event, userInfo in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo!).takeUnretainedValue()
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == 61 { mgr.onDictation(event.flags.contains(.maskAlternate)) }
            if keycode == 60 { mgr.onCommand(event.flags.contains(.maskShift)) }
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: .listenOnly, eventsOfInterest: mask,
                                callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            NSLog("LocalFlow: event tap failed — grant Input Monitoring & Accessibility")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
