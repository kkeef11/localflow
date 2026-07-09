import XCTest
import SwiftUI
@testable import LocalFlow

final class RecordingIndicatorTests: XCTestCase {
    /// Reference design: dictation = light pill (white bg, black border/bars/dots),
    /// command = dark pill (black bg, white border/bars/dots).
    func test_dictation_is_light_variant() {
        let bg = NSColor(IndicatorMode.dictation.background).usingColorSpace(.sRGB)!
        let fg = NSColor(IndicatorMode.dictation.foreground).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(bg.redComponent), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(bg.greenComponent), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(bg.blueComponent), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(fg.redComponent), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(fg.greenComponent), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(fg.blueComponent), 0.0, accuracy: 0.01)
    }
    func test_command_is_dark_variant() {
        let bg = NSColor(IndicatorMode.command.background).usingColorSpace(.sRGB)!
        let fg = NSColor(IndicatorMode.command.foreground).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(bg.redComponent), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(bg.greenComponent), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(bg.blueComponent), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(fg.redComponent), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(fg.greenComponent), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(fg.blueComponent), 1.0, accuracy: 0.01)
    }
}
