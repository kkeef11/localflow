import SwiftUI
import AppKit

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
/// `Sendable` so the existential can be captured in `@Sendable` closures (the audio
/// thread's level callback) — trivially satisfied: `@MainActor` classes are Sendable.
@MainActor
protocol RecordingIndicating: Sendable {
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

/// Observable state the SwiftUI pill renders.
@MainActor
final class IndicatorViewModel: ObservableObject {
    enum Phase { case listening, processing }
    @Published var waveform = WaveformModel()
    @Published var phase: Phase = .listening
    @Published var mode: IndicatorMode = .dictation
}

/// Owns a borderless, non-activating panel that floats the waveform pill at the
/// bottom-center of the active screen. Never becomes key — must not steal the
/// paste target's focus.
@MainActor
final class RecordingIndicatorController: RecordingIndicating {
    private let viewModel = IndicatorViewModel()
    private var panel: NSPanel?

    func show(mode: IndicatorMode) {
        viewModel.mode = mode
        viewModel.phase = .listening
        viewModel.waveform.reset()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionPanel(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()   // shows WITHOUT activating the app
    }

    func updateLevel(_ level: Float) {
        guard viewModel.phase == .listening else { return }
        viewModel.waveform.push(level: level)
    }

    func beginProcessing() {
        viewModel.phase = .processing
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: IndicatorView(viewModel: viewModel))
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 90
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
