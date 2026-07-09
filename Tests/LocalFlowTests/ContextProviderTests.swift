import XCTest
@testable import LocalFlow

final class ContextProviderTests: XCTestCase {
    let provider = ContextProvider(modes: [
        "com.tinyspeck.slackmacgap": "casual",
        "com.apple.mail": "professional"
    ])
    func test_maps_known_bundle() {
        XCTAssertEqual(provider.toneLabel(forBundleID: "com.apple.mail"), "professional")
        XCTAssertEqual(provider.toneLabel(forBundleID: "com.tinyspeck.slackmacgap"), "casual")
    }
    func test_unknown_and_nil_default_to_neutral() {
        XCTAssertEqual(provider.toneLabel(forBundleID: "com.unknown.app"), "neutral")
        XCTAssertEqual(provider.toneLabel(forBundleID: nil), "neutral")
    }
}
