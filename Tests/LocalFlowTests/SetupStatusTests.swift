import XCTest
@testable import LocalFlow

final class SetupStatusTests: XCTestCase {
    func test_defaults_are_ready_and_quiet() {
        let setup = SetupStatus()
        XCTAssertNil(setup.summary)
        XCTAssertFalse(setup.requiredItemsMissing)
    }

    func test_permissions_take_priority_over_models() {
        var setup = SetupStatus()
        setup.speechModel = .notDownloaded
        setup.ollama = .notRunning
        setup.accessibility = false
        XCTAssertEqual(setup.summary, "Grant Accessibility & Input Monitoring")
        setup.microphone = .denied
        XCTAssertEqual(setup.summary, "Grant Microphone access")
    }

    func test_missing_tap_asks_for_input_monitoring() {
        var setup = SetupStatus()
        setup.hotkeysActive = false
        XCTAssertTrue(setup.requiredItemsMissing)
        XCTAssertEqual(setup.summary, "Grant Input Monitoring, then relaunch")
    }

    func test_speech_model_states() {
        var setup = SetupStatus()
        setup.speechModel = .notDownloaded
        XCTAssertTrue(setup.requiredItemsMissing)
        XCTAssertEqual(setup.summary, "Speech model not downloaded")
        setup.speechModel = .downloading(fraction: 0.42)
        XCTAssertFalse(setup.requiredItemsMissing)
        XCTAssertEqual(setup.summary, "Downloading speech model… 42%")
        setup.speechModel = .failed("boom")
        XCTAssertTrue(setup.requiredItemsMissing)
    }

    func test_ollama_is_optional_but_reported() {
        var setup = SetupStatus()
        setup.ollamaModel = "qwen2.5:7b"
        setup.ollama = .modelMissing
        XCTAssertFalse(setup.requiredItemsMissing, "dictation works without Ollama")
        XCTAssertEqual(setup.summary, "Ollama model qwen2.5:7b missing (cleanup off)")
        setup.ollama = .notInstalled
        XCTAssertEqual(setup.summary, "Ollama not installed (cleanup off)")
    }

    @MainActor
    func test_apply_never_stomps_in_flight_status() {
        let state = AppState()
        state.setup.ollama = .notRunning
        state.status = "Listening…"
        state.applySetupStatus()
        XCTAssertEqual(state.status, "Listening…")
        state.status = "Idle"
        state.applySetupStatus()
        XCTAssertEqual(state.status, "Ollama not running (cleanup off)")
        state.setup.ollama = .ready
        state.applySetupStatus()
        XCTAssertEqual(state.status, "Idle", "a resolved warning clears itself")
    }
}

final class HealthCheckTests: XCTestCase {
    func test_model_matching_handles_implicit_latest_tag() {
        XCTAssertTrue(HealthCheck.modelAvailable("qwen2.5:7b", in: ["qwen2.5:7b", "llama3:latest"]))
        XCTAssertTrue(HealthCheck.modelAvailable("llama3", in: ["llama3:latest"]))
        XCTAssertFalse(HealthCheck.modelAvailable("qwen2.5:7b", in: ["qwen2.5:14b"]))
        XCTAssertFalse(HealthCheck.modelAvailable("qwen2.5:7b", in: []))
    }

    private func mockSession(_ json: String) -> URLSession {
        MockURLProtocol.responseData = Data(json.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func test_status_ready_when_model_listed() async {
        let session = mockSession(#"{"models":[{"name":"qwen2.5:7b","size":1}]}"#)
        let status = await HealthCheck.ollamaStatus(model: "qwen2.5:7b", session: session)
        XCTAssertEqual(status, .ready)
    }

    func test_status_model_missing_when_not_listed() async {
        let session = mockSession(#"{"models":[]}"#)
        let status = await HealthCheck.ollamaStatus(model: "qwen2.5:7b", session: session)
        XCTAssertEqual(status, .modelMissing)
    }
}

final class OllamaPullTests: XCTestCase {
    func test_progress_fraction() throws {
        let line = #"{"status":"pulling abc","digest":"sha256:abc","total":200,"completed":50}"#
        XCTAssertEqual(try OllamaClient.parsePullLine(line).fraction, 0.25)
    }

    func test_status_only_line_has_no_fraction() throws {
        XCTAssertNil(try OllamaClient.parsePullLine(#"{"status":"verifying sha256 digest"}"#).fraction)
    }

    func test_error_line_throws() {
        XCTAssertThrowsError(try OllamaClient.parsePullLine(#"{"error":"pull model manifest: file does not exist"}"#))
    }
}

private final class StateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [SpeechModelState] = []
    func append(_ state: SpeechModelState) { lock.lock(); states.append(state); lock.unlock() }
    var last: SpeechModelState? { lock.lock(); defer { lock.unlock() }; return states.last }
}

final class WhisperModelCacheTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lf-models-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func test_no_marker_means_not_downloaded() throws {
        let base = try tempDir()
        XCTAssertNil(WhisperKitTranscriber.completedModelFolder(model: "large-v3", in: base))
    }

    func test_marker_pointing_at_existing_folder_is_reused() throws {
        let base = try tempDir()
        let folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try folder.path.write(to: base.appendingPathComponent("large-v3.ready"), atomically: true, encoding: .utf8)
        XCTAssertEqual(WhisperKitTranscriber.completedModelFolder(model: "large-v3", in: base)?.path, folder.path)
    }

    func test_marker_for_deleted_folder_is_ignored() throws {
        let base = try tempDir()
        try "/nonexistent/lf-model".write(to: base.appendingPathComponent("large-v3.ready"), atomically: true, encoding: .utf8)
        XCTAssertNil(WhisperKitTranscriber.completedModelFolder(model: "large-v3", in: base))
    }

    func test_retry_after_failed_cached_load_keeps_the_download() async throws {
        // A cached load can fail transiently (memory pressure, offline). Retry must not
        // throw away the marker, or the files become unusable without a network.
        let base = try tempDir()
        let folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = base.appendingPathComponent("large-v3.ready")
        try folder.path.write(to: marker, atomically: true, encoding: .utf8)
        let states = StateLog()
        let transcriber = WhisperKitTranscriber(model: "large-v3", modelsDirectory: base,
                                                onState: { states.append($0) })
        await transcriber.retry() // empty folder: the load fails, without touching the network
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        guard case .failed = states.last else { return XCTFail("expected .failed, got \(String(describing: states.last))") }
    }

    func test_transcribe_without_download_fails_fast_without_network() async throws {
        let base = try tempDir()
        let transcriber = WhisperKitTranscriber(model: "large-v3", modelsDirectory: base)
        do {
            _ = try await transcriber.transcribe(samples: [])
            XCTFail("expected modelNotDownloaded")
        } catch let error as TranscriberError {
            XCTAssertEqual(error, .modelNotDownloaded)
        }
    }
}
