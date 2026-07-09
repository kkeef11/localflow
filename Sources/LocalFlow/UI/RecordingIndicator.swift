import SwiftUI
import AppKit

/// Which pipeline the pill is showing — drives its variant per the reference design:
/// dictation = light pill (white background, black border/bars/dots),
/// command = dark pill (black background, white border/bars/dots).
enum IndicatorMode {
    case dictation
    case command

    var background: Color {
        switch self {
        case .dictation: return .white
        case .command:   return .black
        }
    }

    /// Border, bars, and dots all share this color.
    var foreground: Color {
        switch self {
        case .dictation: return .black
        case .command:   return .white
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
            contentRect: NSRect(origin: .zero, size: IndicatorView.pillSize),
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
