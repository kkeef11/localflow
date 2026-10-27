import XCTest
@testable import LocalFlow

final class ModelDefaultsTests: XCTestCase {
    private let gb: UInt64 = 1_073_741_824

    func test_8gb_mac_gets_compact_pair() {
        XCTAssertEqual(ModelDefaults.forMemory(8 * gb), ModelDefaults.compact)
        XCTAssertEqual(ModelDefaults.compact, .init(stt: "large-v3-v20240930_626MB", llm: "qwen2.5:3b"))
    }

    func test_16gb_and_up_keep_full_quality_pair() {
        XCTAssertEqual(ModelDefaults.forMemory(16 * gb), ModelDefaults.full)
        XCTAssertEqual(ModelDefaults.forMemory(64 * gb), ModelDefaults.full)
        XCTAssertEqual(ModelDefaults.full, .init(stt: "large-v3", llm: "qwen2.5:7b"))
    }

    func test_explicit_setting_overrides_memory_default() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try #"{"sttModel":"small.en","llmModel":"llama3"}"#.write(to: url, atomically: true, encoding: .utf8)
        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings.sttModel, "small.en")
        XCTAssertEqual(store.settings.llmModel, "llama3")
    }

    func test_speech_model_descriptions() {
        XCTAssertEqual(ModelInfo.speech("large-v3").size, "~3 GB")
        XCTAssertEqual(ModelInfo.speech("large-v3-v20240930_626MB").size, "~0.6 GB")
        XCTAssertEqual(ModelInfo.speech("large-v3_947MB").size, "~0.9 GB", "size parsed from WhisperKit's _NNNMB suffix")
        XCTAssertNil(ModelInfo.speech("something-custom").size)
        XCTAssertEqual(ModelInfo.speech("something-custom").name, "Whisper something-custom")
    }

    func test_cleanup_sizes() {
        XCTAssertEqual(ModelInfo.cleanupSize("qwen2.5:3b"), "~1.9 GB")
        XCTAssertNil(ModelInfo.cleanupSize("llama3"))
    }
}
