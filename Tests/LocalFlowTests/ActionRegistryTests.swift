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
    func test_open_strips_trailing_punctuation_from_whisper_transcripts() {
        // Whisper punctuates: speaking "open Microsoft Excel" transcribes as
        // "Open Microsoft Excel." — the argument must not carry the period.
        XCTAssertEqual(reg.match("Open Microsoft Excel.")?.argument, "Microsoft Excel")
        XCTAssertEqual(reg.match("open Safari!")?.argument, "Safari")
        XCTAssertEqual(reg.match("Open Notes?")?.argument, "Notes")
    }

    // MARK: - App-name resolution (fixture directory, not the real /Applications)

    private func makeAppsDir(_ appNames: [String]) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lf-apps-\(UUID().uuidString)")
        for name in appNames {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.path
    }

    func test_resolve_exact_name_still_wins_over_substring() throws {
        let dir = try makeAppsDir(["Safari.app", "Safari Technology Preview.app"])
        let reg = ActionRegistry(searchDirectories: [dir])
        XCTAssertEqual(reg.resolveApplicationURL(named: "Safari")?.lastPathComponent, "Safari.app")
    }

    func test_resolve_unique_substring_matches() throws {
        let dir = try makeAppsDir(["Microsoft Excel.app", "Notes.app"])
        let reg = ActionRegistry(searchDirectories: [dir])
        XCTAssertEqual(reg.resolveApplicationURL(named: "excel")?.lastPathComponent, "Microsoft Excel.app")
    }

    func test_resolve_ambiguous_substring_returns_nil() throws {
        let dir = try makeAppsDir(["Microsoft Excel.app", "Microsoft Outlook.app"])
        let reg = ActionRegistry(searchDirectories: [dir])
        XCTAssertNil(reg.resolveApplicationURL(named: "microsoft"))
    }

    func test_resolve_no_match_returns_nil() throws {
        let dir = try makeAppsDir(["Notes.app"])
        let reg = ActionRegistry(searchDirectories: [dir])
        XCTAssertNil(reg.resolveApplicationURL(named: "excel"))
    }
}
