import XCTest
import SwiftUI
@testable import LocalFlow

final class RecordingIndicatorTests: XCTestCase {
    func test_mode_colors_are_distinct_and_correct() {
        // #9D00FF and #37de43 as resolved RGB.
        let purple = NSColor(IndicatorMode.dictation.barColor).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(purple.redComponent),   157.0/255.0, accuracy: 0.01)
        XCTAssertEqual(Double(purple.greenComponent),   0.0,        accuracy: 0.01)
        XCTAssertEqual(Double(purple.blueComponent),   255.0/255.0, accuracy: 0.01)

        let green = NSColor(IndicatorMode.command.barColor).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(green.redComponent),    55.0/255.0,  accuracy: 0.01)
        XCTAssertEqual(Double(green.greenComponent), 222.0/255.0,  accuracy: 0.01)
        XCTAssertEqual(Double(green.blueComponent),   67.0/255.0,  accuracy: 0.01)
    }
}
