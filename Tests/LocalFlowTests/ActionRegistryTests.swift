import XCTest
@testable import LocalFlow

final class ActionRegistryTests: XCTestCase {
    let reg = ActionRegistry()
    func test_open_app_extracts_argument() {
        let m = reg.match("open Safari")
        XCTAssertEqual(m?.action.id, "open")
        XCTAssertEqual(m?.argument, "Safari")
    }
    func test_open_is_case_insensitive() {
        XCTAssertEqual(reg.match("OPEN slack")?.argument, "slack")
    }
    func test_copy_matches_no_argument() {
        XCTAssertEqual(reg.match("copy that")?.action.id, "copy")
    }
    func test_unrecognized_returns_nil() {
        XCTAssertNil(reg.match("make this more formal"))
    }
    func test_open_with_path_traversal_returns_nil() {
        XCTAssertNil(reg.match("open ../../../Users/evil/Malicious.app"))
        XCTAssertNil(reg.match("open /Applications/Safari.app"))
    }
}
