import Foundation

struct Settings: Codable, Equatable {
    var sttModel: String = "large-v3"
    var llmModel: String = "qwen2.5:7b"
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
        sttModel = try c.decodeIfPresent(String.self, forKey: .sttModel) ?? d.sttModel
        llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel) ?? d.llmModel
        dictionary = try c.decodeIfPresent([String].self, forKey: .dictionary) ?? d.dictionary
        contextModes = try c.decodeIfPresent([String: String].self, forKey: .contextModes) ?? d.contextModes
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
