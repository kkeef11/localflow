@preconcurrency import AVFoundation

enum AudioRecorderError: Error {
    case converterUnavailable
}

/// Tracks whether the converter's input block has already handed off the source buffer.
/// The AVAudioConverter input block type is `@Sendable`, which makes Swift 6 flag a plain
/// captured `var` as unsafe even though the block only ever runs synchronously on the calling
/// thread inside a single `convert(to:error:withInputFrom:)` call. Wrapping the flag in a
/// reference type captured as `let` sidesteps that (harmless, but noisy) warning.
private final class FeedFlag: @unchecked Sendable {
    var fed = false
}

/// Captures microphone audio and produces 16kHz mono Float32 samples.
///
/// The tap closure below runs on a real-time audio thread while `stop()` is called from the
/// caller's thread (typically the main thread). `buffers` is therefore mutated from two threads
/// and is guarded by `buffersLock` to avoid a data race / torn reads.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var buffers: [Float] = []
    private let buffersLock = NSLock()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!

    func start() throws {
        buffersLock.lock()
        buffers.removeAll()
        buffersLock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.converterUnavailable
        }
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) else { return }

            var conversionError: NSError?
            let feedFlag = FeedFlag()
            let status = converter.convert(to: out, error: &conversionError) { _, inputStatus in
                if feedFlag.fed {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                feedFlag.fed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, let channelData = out.floatChannelData else { return }

            let samples = UnsafeBufferPointer(start: channelData[0], count: Int(out.frameLength))
            self.buffersLock.lock()
            self.buffers.append(contentsOf: samples)
            self.buffersLock.unlock()
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        buffersLock.lock()
        defer { buffersLock.unlock() }
        return buffers
    }
}
