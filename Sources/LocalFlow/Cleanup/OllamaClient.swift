import Foundation

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
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(Response.self, from: data).response
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
