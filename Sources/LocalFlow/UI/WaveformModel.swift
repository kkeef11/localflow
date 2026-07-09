import CoreGraphics

/// Fixed-length ring of recent mic levels mapped to bar heights (0...1) for the
/// waveform pill. Silent input maps to a visible floor so the pill never looks empty.
struct WaveformModel {
    static let floor: CGFloat = 0.1
    static let gain: CGFloat = 8.0

    let barCount: Int
    private(set) var bars: [CGFloat]

    init(barCount: Int = 20) {
        self.barCount = barCount
        self.bars = Array(repeating: Self.floor, count: barCount)
    }

    /// Appends a new level as the newest (rightmost) bar, dropping the oldest.
    mutating func push(level: Float) {
        let scaled = CGFloat(level) * Self.gain
        let height = min(1.0, max(Self.floor, scaled))
        bars.removeFirst()
        bars.append(height)
    }

    mutating func reset() {
        bars = Array(repeating: Self.floor, count: barCount)
    }
}
