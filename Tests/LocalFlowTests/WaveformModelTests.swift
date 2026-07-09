import XCTest
import CoreGraphics
@testable import LocalFlow

final class WaveformModelTests: XCTestCase {
    func test_starts_flat_at_floor() {
        let m = WaveformModel(barCount: 20)
        XCTAssertEqual(m.bars.count, 20)
        XCTAssertTrue(m.bars.allSatisfy { $0 == 0.1 })
    }
    func test_silent_push_maps_to_floor() {
        var m = WaveformModel(barCount: 4)
        m.push(level: 0)
        XCTAssertEqual(m.bars.last, 0.1)
    }
    func test_full_push_clamps_to_one() {
        var m = WaveformModel(barCount: 4)
        m.push(level: 1.0)
        XCTAssertEqual(m.bars.last, 1.0)
    }
    func test_mid_push_applies_gain() {
        var m = WaveformModel(barCount: 4)
        m.push(level: 0.05) // 0.05 * 8 = 0.4
        XCTAssertEqual(m.bars.last!, 0.4, accuracy: 0.0001)
    }
    func test_push_clamps_out_of_range() {
        var m = WaveformModel(barCount: 2)
        m.push(level: -1); XCTAssertEqual(m.bars.last, 0.1)
        m.push(level: 5);  XCTAssertEqual(m.bars.last, 1.0)
    }
    func test_push_scrolls_and_keeps_length() {
        var m = WaveformModel(barCount: 3)
        m.push(level: 1.0)          // [.1, .1, 1.0]
        m.push(level: 0)            // [.1, 1.0, .1]
        XCTAssertEqual(m.bars.count, 3)
        XCTAssertEqual(m.bars[1], 1.0)
        XCTAssertEqual(m.bars[2], 0.1)
    }
    func test_reset_returns_to_floor() {
        var m = WaveformModel(barCount: 3)
        m.push(level: 1.0)
        m.reset()
        XCTAssertTrue(m.bars.allSatisfy { $0 == 0.1 })
    }
}
