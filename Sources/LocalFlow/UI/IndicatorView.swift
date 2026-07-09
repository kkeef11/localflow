import SwiftUI

/// The floating pill: a dark capsule with animated waveform bars while listening,
/// or three pulsing dots while processing. Tinted by mode.
struct IndicatorView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    var body: some View {
        ZStack {
            Capsule().fill(Color.black.opacity(0.82))
            content
                .padding(.horizontal, 20)
        }
        .frame(width: 260, height: 60)
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .listening:
            HStack(spacing: 3) {
                ForEach(Array(viewModel.waveform.bars.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(viewModel.mode.barColor)
                        .frame(width: 3, height: max(4, h * 34))
                }
            }
            .animation(.easeOut(duration: 0.08), value: viewModel.waveform.bars)
        case .processing:
            ProcessingDots(color: viewModel.mode.barColor)
        }
    }
}

/// Three dots that pulse in sequence while the transcript is being processed.
private struct ProcessingDots: View {
    let color: Color
    @State private var t = 0.0
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .opacity(0.35 + 0.65 * abs(sin(t + Double(i) * 0.6)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                t = .pi * 2
            }
        }
    }
}
