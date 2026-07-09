import SwiftUI

/// Which pipeline the pill is showing — drives its color.
enum IndicatorMode {
    case dictation
    case command

    /// Bar/dot tint. Dictation #9D00FF (purple), command #37de43 (green).
    var barColor: Color {
        switch self {
        case .dictation: return Color(red: 157/255, green: 0/255, blue: 255/255)
        case .command:   return Color(red: 55/255, green: 222/255, blue: 67/255)
        }
    }
}

/// Lifecycle the `DictationController` drives; implemented by the real panel
/// controller and by `NoopIndicator` (tests / when no UI is desired).
@MainActor
protocol RecordingIndicating {
    func show(mode: IndicatorMode)
    func updateLevel(_ level: Float)
    func beginProcessing()
    func hide()
}

/// Does nothing — the default so headless/test contexts need no panel.
@MainActor
final class NoopIndicator: RecordingIndicating {
    func show(mode: IndicatorMode) {}
    func updateLevel(_ level: Float) {}
    func beginProcessing() {}
    func hide() {}
}
