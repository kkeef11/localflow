/// Minimal seam over `AudioRecorder` so `DictationController` can be exercised in tests
/// without touching real microphone hardware. `AudioRecorder` conforms to this; tests
/// substitute a fake that never starts an `AVAudioEngine`.
protocol AudioRecording: Sendable {
    func start() throws
    func stop() -> [Float]
}
