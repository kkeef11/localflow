import XCTest
@testable import LocalFlow

final class MockURLProtocol: URLProtocol {
    // Swift 6 strict concurrency: URLProtocol's class-side API is not
    // Sendable-checked, and this mutable static is only ever written from
    // the test's main-actor setup and read from URLSession's background
    // loading callback within a single, serialized test run. There is no
    // concurrent access in practice, so `nonisolated(unsafe)` is the
    // minimal, honest annotation rather than introducing a lock for
    // single-threaded test scaffolding.
    nonisolated(unsafe) static var responseData: Data = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class OllamaClientTests: XCTestCase {
    func test_parses_response_field() async throws {
        MockURLProtocol.responseData = #"{"response":"Send the email to John."}"#.data(using: .utf8)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = OllamaClient(model: "qwen2.5:7b", session: URLSession(configuration: config))
        let out = try await client.generate(system: "sys", prompt: "raw")
        XCTAssertEqual(out, "Send the email to John.")
    }
}
