import XCTest
@testable import LocalFlow

final class PromptBuilderTests: XCTestCase {
    func test_includes_core_rules() {
        let p = PromptBuilder.cleanupSystemPrompt(toneLabel: "professional", dictionary: ["Acme"])
        XCTAssertTrue(p.contains("dictation"))
        XCTAssertTrue(p.lowercased().contains("do not answer"))
        XCTAssertTrue(p.contains("only the cleaned"))
        XCTAssertTrue(p.contains("scratch that"))
        XCTAssertTrue(p.contains("new paragraph"))
    }
    func test_injects_tone_and_dictionary() {
        let p = PromptBuilder.cleanupSystemPrompt(toneLabel: "casual", dictionary: ["Acme", "kkeefer"])
        XCTAssertTrue(p.contains("casual"))
        XCTAssertTrue(p.contains("Acme"))
        XCTAssertTrue(p.contains("kkeefer"))
    }
    func test_has_six_examples() {
        let p = PromptBuilder.cleanupSystemPrompt(toneLabel: "neutral", dictionary: [])
        // Six worked examples, each marked "Input:"
        let count = p.components(separatedBy: "Input:").count - 1
        XCTAssertGreaterThanOrEqual(count, 6)
    }
}
