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

    static func pair(for preset: ModelPreset, memory: UInt64) -> Pair {
        switch preset {
        case .automatic: return forMemory(memory)
        case .compact: return compact
        case .full: return full
        }
    }
}

/// The model-size choice offered in the Setup window. `automatic` follows `ModelDefaults`.
enum ModelPreset: String, Codable, CaseIterable, Identifiable {
    case automatic, compact, full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .compact: return "Compact"
        case .full: return "Full quality"
        }
    }

    /// One line for the picker, specific to this Mac's memory.
    func detail(memory: UInt64) -> String {
        let gb = Int((Double(memory) / 1_073_741_824).rounded())
        switch self {
        case .automatic:
            let resolved = ModelDefaults.forMemory(memory) == ModelDefaults.compact ? "Compact" : "Full quality"
            return "\(resolved) on this \(gb) GB Mac."
        case .compact:
            return "~2.5 GB. Fastest; slightly less accurate on rare words and complex rewrites."
        case .full:
            return "~7.7 GB. Most accurate; best on Macs with 16 GB or more."
        }
    }

    /// Full-size models fill a Mac with less than 12 GB and make it swap and lag.
    func warning(memory: UInt64) -> String? {
        guard self == .full, memory < ModelDefaults.compactBelowBytes else { return nil }
        return "May be slow and make your Mac lag with less than 12 GB of memory."
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
