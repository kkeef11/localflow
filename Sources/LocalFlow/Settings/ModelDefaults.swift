import Foundation

/// Default speech and cleanup models, chosen by how much memory the Mac has.
///
/// Both models stay loaded while dictating. Whisper large-v3 (~3 GB) plus qwen2.5:7b
/// (~5 GB) fills an 8 GB Mac and pushes everything into swap — dictations then took over a
/// minute and the whole Mac lagged (measured on an 8 GB M3). The compact pair uses ~2.6 GB.
/// An explicit `sttModel` / `llmModel` in settings.json always wins over these defaults.
enum ModelDefaults {
    struct Pair: Equatable {
        let stt: String
        let llm: String
    }

    /// Below this, use the compact pair. 12 GB sits between the 8 GB and 16 GB tiers.
    static let compactBelowBytes: UInt64 = 12 * 1_073_741_824

    static let full = Pair(stt: "large-v3", llm: "qwen2.5:7b")
    static let compact = Pair(stt: "large-v3-v20240930_626MB", llm: "qwen2.5:3b")

    static func forMemory(_ bytes: UInt64) -> Pair {
        bytes < compactBelowBytes ? compact : full
    }

    static var forThisMac: Pair {
        forMemory(ProcessInfo.processInfo.physicalMemory)
    }
}

/// How a model is described in the setup checklist. Unknown names (set by hand in
/// settings.json) fall back to the raw name and a size-free description.
enum ModelInfo {
    static func speech(_ model: String) -> (name: String, size: String?) {
        switch model {
        case "large-v3": return ("Whisper large-v3", "~3 GB")
        case "large-v3-v20240930_626MB": return ("Whisper large-v3 turbo (compressed)", "~0.6 GB")
        case "large-v3-v20240930_turbo": return ("Whisper large-v3 turbo", "~1.6 GB")
        case "small.en": return ("Whisper small (English)", "~0.5 GB")
        default:
            // WhisperKit's compressed variants carry their size in the name, e.g. "_626MB".
            if let range = model.range(of: #"_(\d+)MB$"#, options: .regularExpression) {
                let megabytes = Double(model[range].dropFirst().dropLast(2)) ?? 0
                return ("Whisper \(model)", String(format: "~%.1f GB", megabytes / 1024))
            }
            return ("Whisper \(model)", nil)
        }
    }

    static func cleanupSize(_ model: String) -> String? {
        switch model {
        case "qwen2.5:7b": return "~4.7 GB"
        case "qwen2.5:3b": return "~1.9 GB"
        case "qwen2.5:1.5b": return "~1 GB"
        default: return nil
        }
    }
}
