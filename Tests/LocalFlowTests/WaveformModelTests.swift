import XCTest
import CoreGraphics
@testable import LocalFlow

final class WaveformModelTests: XCTestCase {
    func test_starts_at_rest() {
        let m = WaveformModel()
        XCTAssertEqual(m.bars.count, 7) // reference design: 7 bars
        XCTAssertTrue(m.bars.allSatisfy { $0 == 0 })
    }
    func test_silent_push_stays_at_rest() {
        var m = WaveformModel(barCount: 4)
        m.push(level: 0)
        XCTAssertEqual(m.bars.last, 0)
    }
    func test_full_push_clamps_to_one() {
        var m = WaveformModel(barCount: 4)
        m.push(level: 1.0)
        XCTAssertEqual(m.bars.last, 1.0)
    }
    func test_push_applies_perceptual_sqrt_curve() {
        // intensity = sqrt(min(1, level * 60)): speech RMS is small (measured median
        // ≈ 0.006 on this hardware), so the curve lifts quiet levels into visible range.
        var m = WaveformModel(barCount: 4)
        m.push(level: 0.006)    // 0.006 * 60 = 0.36 → sqrt = 0.6
        XCTAssertEqual(m.bars.last!, 0.6, accuracy: 0.0001)
        m.push(level: 0.00015)  // 0.00015 * 60 = 0.009 → sqrt ≈ 0.0949
        XCTAssertEqual(m.bars.last!, 0.0949, accuracy: 0.001)
    }
    func test_push_clamps_out_of_range() {
        var m = WaveformModel(barCount: 2)
        m.push(level: -1); XCTAssertEqual(m.bars.last, 0)
        m.push(level: 5);  XCTAssertEqual(m.bars.last, 1.0)
    }
    func test_push_scrolls_and_keeps_length() {
        var m = WaveformModel(barCount: 3)
        m.push(level: 1.0)          // [0, 0, 1.0]
        m.push(level: 0)            // [0, 1.0, 0]
        XCTAssertEqual(m.bars.count, 3)
        XCTAssertEqual(m.bars[1], 1.0)
        XCTAssertEqual(m.bars[2], 0)
    }
    func test_reset_returns_to_rest() {
        var m = WaveformModel(barCount: 3)
        m.push(level: 1.0)
        m.reset()
        XCTAssertTrue(m.bars.allSatisfy { $0 == 0 })
    }
}
