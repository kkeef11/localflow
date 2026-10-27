import XCTest
@testable import LocalFlow

final class SettingsStoreTests: XCTestCase {
    func test_persists_and_reloads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lf-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

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
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings.sttModel, ModelDefaults.forThisMac.stt)
        XCTAssertEqual(store.settings.llmModel, ModelDefaults.forThisMac.llm)
    }

    func test_older_file_missing_keys_keeps_values_and_fills_defaults() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lf-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try #"{"dictionary":["Acme"],"llmModel":"llama3"}"#.write(to: url, atomically: true, encoding: .utf8)

        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings.dictionary, ["Acme"])
        XCTAssertEqual(store.settings.llmModel, "llama3")
        XCTAssertEqual(store.settings.sttModel, ModelDefaults.forThisMac.stt, "missing key → memory-based default")
        XCTAssertEqual(store.settings.contextModes, Settings().contextModes)
    }

    func test_unreadable_file_is_backed_up_not_overwritten() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lf-\(UUID()).json")
        let backup = url.appendingPathExtension("unreadable")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: backup)
        }
        try "not json".write(to: url, atomically: true, encoding: .utf8)

        let store = SettingsStore(fileURL: url)
        store.settings.dictionary = ["new"]
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "not json")
    }
}
