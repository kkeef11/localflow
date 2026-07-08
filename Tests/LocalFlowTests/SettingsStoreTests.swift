import XCTest
@testable import LocalFlow

final class SettingsStoreTests: XCTestCase {
    func test_persists_and_reloads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lf-\(UUID()).json")
        let store = SettingsStore(fileURL: url)
        var s = store.settings
        s.dictionary = ["Acme", "kkeefer"]
        store.settings = s

        let reloaded = SettingsStore(fileURL: url)
        XCTAssertEqual(reloaded.settings.dictionary, ["Acme", "kkeefer"])
    }

    func test_defaults_when_no_file() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lf-\(UUID()).json")
        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings.sttModel, "large-v3")
        XCTAssertEqual(store.settings.llmModel, "qwen2.5:7b")
    }
}
