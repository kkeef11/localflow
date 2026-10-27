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

    // MARK: - Presets

    private func load(_ json: String) throws -> SettingsStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try json.write(to: url, atomically: true, encoding: .utf8)
        return SettingsStore(fileURL: url)
    }

    func test_presets_resolve_by_memory() {
        XCTAssertEqual(ModelDefaults.pair(for: .automatic, memory: 8 * gb), ModelDefaults.compact)
        XCTAssertEqual(ModelDefaults.pair(for: .automatic, memory: 16 * gb), ModelDefaults.full)
        XCTAssertEqual(ModelDefaults.pair(for: .full, memory: 8 * gb), ModelDefaults.full, "explicit choice wins over memory")
        XCTAssertEqual(ModelDefaults.pair(for: .compact, memory: 64 * gb), ModelDefaults.compact)
    }

    func test_full_preset_warns_only_on_small_macs() {
        XCTAssertNotNil(ModelPreset.full.warning(memory: 8 * gb))
        XCTAssertNil(ModelPreset.full.warning(memory: 16 * gb))
        XCTAssertNil(ModelPreset.compact.warning(memory: 8 * gb))
        XCTAssertEqual(ModelPreset.automatic.detail(memory: 8 * gb), "Compact on this 8 GB Mac.")
        XCTAssertEqual(ModelPreset.automatic.detail(memory: 16 * gb), "Full quality on this 16 GB Mac.")
    }

    func test_legacy_file_naming_a_preset_pair_becomes_that_preset() throws {
        let compact = try load(#"{"sttModel":"large-v3-v20240930_626MB","llmModel":"qwen2.5:3b"}"#)
        XCTAssertEqual(compact.settings.modelPreset, .compact)
        XCTAssertFalse(compact.settings.hasCustomModels)
        let full = try load(#"{"sttModel":"large-v3","llmModel":"qwen2.5:7b","dictionary":["Acme"]}"#)
        XCTAssertEqual(full.settings.modelPreset, .full)
        XCTAssertEqual(full.settings.dictionary, ["Acme"])
    }

    func test_custom_models_are_kept_and_flagged() throws {
        let store = try load(#"{"modelPreset":"compact","sttModel":"small.en"}"#)
        XCTAssertTrue(store.settings.hasCustomModels)
        XCTAssertEqual(store.settings.models(), .init(stt: "small.en", llm: "qwen2.5:3b"))
    }

    func test_saving_does_not_pin_todays_default_models() throws {
        let store = try load("{}")
        store.settings.dictionary = ["Acme"] // any save
        let data = try JSONEncoder().encode(store.settings)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("sttModel"), json)
        XCTAssertFalse(json.contains("llmModel"), json)
        XCTAssertTrue(json.contains(#""modelPreset":"automatic""#), json)
    }

    func test_unknown_preset_falls_back_instead_of_resetting_settings() throws {
        let store = try load(#"{"modelPreset":"huge","dictionary":["Acme"]}"#)
        XCTAssertEqual(store.settings.modelPreset, .automatic)
        XCTAssertEqual(store.settings.dictionary, ["Acme"])
    }
}
