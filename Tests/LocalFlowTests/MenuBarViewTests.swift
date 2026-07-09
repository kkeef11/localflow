import SwiftUI
import XCTest
@testable import LocalFlow

final class MenuBarViewTests: XCTestCase {
    func test_idle_is_green() {
        XCTAssertEqual(MenuBarView.statusDotColor(for: "Idle"), .green)
    }

    func test_error_prefix_is_red() {
        XCTAssertEqual(MenuBarView.statusDotColor(for: "Error: transcription failed"), .red)
    }

    func test_health_warnings_are_orange() {
        XCTAssertEqual(MenuBarView.statusDotColor(for: "Grant Accessibility & Input Monitoring"), .orange)
        XCTAssertEqual(MenuBarView.statusDotColor(for: "Ollama not running (ollama serve)"), .orange)
    }

    func test_transient_states_are_orange() {
        XCTAssertEqual(MenuBarView.statusDotColor(for: "Recording…"), .orange)
        XCTAssertEqual(MenuBarView.statusDotColor(for: "Transcribing…"), .orange)
    }
}
