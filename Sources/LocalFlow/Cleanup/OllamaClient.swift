import Foundation

/// Errors surfaced by `OllamaClient` beyond the usual `URLSession`/decoding failures.
enum OllamaError: Error, LocalizedError {
    /// The server responded with a non-2xx HTTP status. `body` is truncated so a large/HTML
    /// error page doesn't blow up log output or error descriptions.
    case badStatus(code: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            return "Ollama returned HTTP \(code): \(body)"
        }
    }
}

/// LLM client that talks to a local Ollama server's `/api/generate` endpoint.
///
/// `final class` with only `let` stored properties (`String`, `URL`, and
/// `URLSession`, all of which are themselves `Sendable`) satisfies the
/// `Sendable` requirement on `LLMGenerating` without any extra annotation —
/// the compiler verifies this automatically for a final class whose stored
/// properties are all immutable and Sendable.
final class OllamaClient: LLMGenerating {
    private let model: String
    private let baseURL: URL
    private let session: URLSession

    init(model: String, baseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared) {
        self.model = model; self.baseURL = baseURL; self.session = session
    }

    struct Response: Decodable { let response: String }

    func generate(system: String, prompt: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "system": system, "prompt": prompt, "stream": false]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data.prefix(500), encoding: .utf8) ?? "<non-UTF8 body>"
            throw OllamaError.badStatus(code: http.statusCode, body: bodyText)
        }
        return try JSONDecoder().decode(Response.self, from: data).response
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One line of `/api/pull`'s streamed NDJSON response.
    struct PullEvent: Decodable {
        let status: String?
        let total: Int64?
        let completed: Int64?
        let error: String?
    }

    /// Downloads `model` via the local server (`/api/pull`), reporting the current layer's
    /// progress (0...1; the multi-GB weights layer dominates; nil while Ollama is verifying). Ollama resumes partial pulls,
    /// so re-running after an interruption continues where it stopped. Only ever called from
    /// an explicit user action — models are several gigabytes.
    func pull(onProgress: @escaping @Sendable (Double?) -> Void) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300 // between streamed lines, not total
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Ollama explains failures as {"error": "..."} (unknown model, disk full, ...).
            var body = "pull of \(model) failed"
            if let line = try? await bytes.lines.first(where: { _ in true }) {
                body = (try? JSONDecoder().decode(PullEvent.self, from: Data(line.utf8)).error) ?? line
            }
            throw OllamaError.badStatus(code: http.statusCode, body: body)
        }
        for try await line in bytes.lines {
            onProgress(try Self.parsePullLine(line).fraction)
        }
    }

    /// Parses one pull line; a line carrying `error` (e.g. unknown model) becomes a throw.
    static func parsePullLine(_ line: String) throws -> (status: String, fraction: Double?) {
        let event = try JSONDecoder().decode(PullEvent.self, from: Data(line.utf8))
        if let error = event.error { throw OllamaError.badStatus(code: 200, body: error) }
        var fraction: Double?
        if let total = event.total, total > 0, let completed = event.completed {
            fraction = min(1, Double(completed) / Double(total))
        }
        return (event.status ?? "", fraction)
    }
}
