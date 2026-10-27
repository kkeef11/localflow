import Foundation

struct Settings: Codable, Equatable {
    /// Model size chosen in Setup. `automatic` picks by the Mac's memory (ModelDefaults).
    var modelPreset: ModelPreset = .automatic
    /// Custom model names set by hand in settings.json. nil = use the preset's model.
    /// Optional so they're omitted when saving — otherwise any save would pin today's default.
    var sttModel: String?
    var llmModel: String?
    var dictionary: [String] = []
    var contextModes: [String: String] = [
        "com.tinyspeck.slackmacgap": "casual",
        "com.apple.mail": "professional",
        "com.microsoft.VSCode": "code"
    ]

    init() {}

    /// Missing keys fall back to defaults instead of failing the whole decode. The
    /// synthesized decoder would reject a settings file written by an older version as soon
    /// as a field is added — silently resetting the user's dictionary on upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        // try?: an unknown value (e.g. from a newer version) falls back instead of failing.
        modelPreset = (try? c.decodeIfPresent(ModelPreset.self, forKey: .modelPreset)) ?? d.modelPreset
        sttModel = try c.decodeIfPresent(String.self, forKey: .sttModel)
        llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel)
        dictionary = try c.decodeIfPresent([String].self, forKey: .dictionary) ?? d.dictionary
        contextModes = try c.decodeIfPresent([String: String].self, forKey: .contextModes) ?? d.contextModes
        // Earlier builds stored both model names. A pair that is exactly one preset becomes
        // that preset, so it shows as a choice in Setup rather than as "Custom".
        if let stt = sttModel, let llm = llmModel {
            for preset in [ModelPreset.compact, .full]
            where ModelDefaults.pair(for: preset, memory: 0) == .init(stt: stt, llm: llm) {
                modelPreset = preset
                sttModel = nil
                llmModel = nil
            }
        }
    }

    /// Whether settings.json names models outside the presets.
    var hasCustomModels: Bool { sttModel != nil || llmModel != nil }

    /// The models to run: the preset's pair, with any custom names replacing it.
    func models(memory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> ModelDefaults.Pair {
        let base = ModelDefaults.pair(for: modelPreset, memory: memory)
        return .init(stt: sttModel ?? base.stt, llm: llmModel ?? base.llm)
    }
}

final class SettingsStore {
    private let fileURL: URL
    var settings: Settings { didSet { save() } }

    static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    init(fileURL: URL = SettingsStore.defaultFileURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
            // Keep an unreadable file instead of letting the next save overwrite it.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backup = fileURL.appendingPathExtension("unreadable")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: fileURL, to: backup)
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: fileURL)
        }
    }
}
