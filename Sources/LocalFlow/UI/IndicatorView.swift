import SwiftUI

/// The floating pill, matching the reference design: 44pt tall, fully rounded,
/// 1.5pt border. Light variant (dictation) or dark variant (command). Shows 7
/// live waveform bars while listening, or three pulsing dots while processing.
struct IndicatorView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    static let pillSize = CGSize(width: 120, height: 44)

    /// Reference bar heights (px): organic varied baseline; live intensity scales
    /// each bar between 30% (rest, mirrors the reference's scaleY 0.3) and 100%.
    private static let baseHeights: [CGFloat] = [20, 28, 16, 24, 14, 26, 18]

    var body: some View {
        ZStack {
            Capsule().fill(viewModel.mode.background)
            Capsule().strokeBorder(viewModel.mode.foreground, lineWidth: 1.5)
            content
        }
        .frame(width: Self.pillSize.width, height: Self.pillSize.height)
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .listening:
            HStack(spacing: 5) {
                ForEach(Array(viewModel.waveform.bars.enumerated()), id: \.offset) { i, intensity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(viewModel.mode.foreground)
                        .frame(width: 4,
                               height: Self.baseHeights[i % Self.baseHeights.count] * (0.3 + 0.7 * intensity))
                }
            }
            .animation(.easeOut(duration: 0.1), value: viewModel.waveform)
        case .processing:
            PulsingDots(color: viewModel.mode.foreground)
        }
    }
}

/// Three dots pulsing per the reference: 8pt, 1.2s cycle, staggered 0/0.2/0.4s,
/// opacity 0.25→1 and scale 0.8→1 peaking at 40% of the cycle. Driven by
/// `TimelineView(.animation)` — recomputed every frame — because animating a phase
/// variable with `withAnimation` only interpolates endpoint values (the bug that
/// froze the first version of these dots).
private struct PulsingDots: View {
    let color: Color
    private static let period = 1.2
    private static let delays = [0.0, 0.2, 0.4]

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    let raw = (now - Self.delays[i]).truncatingRemainder(dividingBy: Self.period) / Self.period
                    let phase = raw < 0 ? raw + 1 : raw
                    // Triangle wave peaking at 40% of the cycle, smoothstepped.
                    let tri = phase < 0.4 ? phase / 0.4 : max(0, (0.8 - phase) / 0.4)
                    let eased = tri * tri * (3 - 2 * tri)
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .opacity(0.25 + 0.75 * eased)
                        .scaleEffect(0.8 + 0.2 * eased)
                }
            }
        }
    }
}
