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
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: fileURL)
        }
    }
}
