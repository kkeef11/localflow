import CoreGraphics

/// Fixed-length ring of recent mic levels mapped to bar intensities (0...1) for the
/// waveform pill. Speech RMS is small (~0.02–0.1), so raw levels are lifted with a
/// gain + square-root perceptual curve; the view maps intensity onto bar heights.
struct WaveformModel: Equatable {
    static let gain: CGFloat = 25.0

    let barCount: Int
    private(set) var bars: [CGFloat]

    init(barCount: Int = 7) {
        self.barCount = barCount
        self.bars = Array(repeating: 0, count: barCount)
    }

    /// Appends a new level as the newest (rightmost) bar, dropping the oldest.
    /// intensity = sqrt(min(1, level * gain)), clamped to 0...1.
    mutating func push(level: Float) {
        let boosted = min(1.0, max(0, CGFloat(level)) * Self.gain)
        bars.removeFirst()
        bars.append(boosted.squareRoot())
    }

    mutating func reset() {
        bars = Array(repeating: 0, count: barCount)
    }
}
