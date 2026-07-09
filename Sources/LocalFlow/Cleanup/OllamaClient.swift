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
}
