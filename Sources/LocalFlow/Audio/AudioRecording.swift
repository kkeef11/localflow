/// Minimal seam over `AudioRecorder` so `DictationController` can be exercised in tests
/// without touching real microphone hardware. `AudioRecorder` conforms to this; tests
/// substitute a fake that never starts an `AVAudioEngine`.
protocol AudioRecording: Sendable {
    func start() throws
    func stop() -> [Float]
    /// Called with a normalized RMS level (roughly 0...1) per captured buffer, from the
    /// audio thread. Set before `start()`, cleared after `stop()`. Consumers must hop to
    /// the main actor before touching UI.
    var onLevel: (@Sendable (Float) -> Void)? { get set }
}
