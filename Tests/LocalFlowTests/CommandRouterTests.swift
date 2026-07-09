import XCTest
@testable import LocalFlow

final class CommandRouterTests: XCTestCase {
    let router = CommandRouter(registry: ActionRegistry())
    func test_action_phrase_routes_to_action() {
        XCTAssertEqual(router.decide("open Safari"), .action(id: "open", argument: "Safari"))
    }
    func test_non_action_routes_to_rewrite() {
        XCTAssertEqual(router.decide("make this more formal"), .rewrite(instruction: "make this more formal"))
    }
    func test_empty_routes_to_none() {
        XCTAssertEqual(router.decide("   "), .none)
    }
}
