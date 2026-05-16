import AVFoundation
import CoreAudio

/// Captures mic audio at the hardware format. Each `start()` returns fresh
/// AsyncStreams; `stop()` finishes them and tears the engine down.
///
/// Format conversion is intentionally absent — SFSpeechRecognizer converts
/// internally, and doing it here was producing buffers the recognizer
/// silently rejected. Always feed raw mic buffers downstream.
final class AudioEngine: @unchecked Sendable {

    typealias BufferStream = AsyncStream<AVAudioPCMBuffer>
    typealias LevelStream  = AsyncStream<Float>

    private let engine = AVAudioEngine()
    private var bufferContinuation: BufferStream.Continuation?
    private var levelContinuation:  LevelStream.Continuation?
    private var running = false

    func start(deviceID: AudioDeviceID? = nil) throws -> (buffers: BufferStream, levels: LevelStream) {
        stop()

        let (buffers, bCont) = BufferStream.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )
        let (levels, lCont) = LevelStream.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )
        bufferContinuation = bCont
        levelContinuation  = lCont

        let input = engine.inputNode

        // Select a specific input device if requested. Must happen before any
        // tap is installed or the engine starts — AVAudioEngine caches the
        // format from the input device at start time.
        if let deviceID, deviceID != 0 {
            do {
                try input.auAudioUnit.setDeviceID(deviceID)
                logInfo("audio: input device set to id=\(deviceID)")
            } catch {
                logWarn("audio: setDeviceID(\(deviceID)) failed: \(error.localizedDescription) — falling back to system default")
            }
        }

        let format = input.outputFormat(forBus: 0)
        logInfo("audio: tap installed @ \(Int(format.sampleRate)) Hz, channels=\(format.channelCount)")

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buf, _ in
            bCont.yield(buf)
            guard let ch = buf.floatChannelData?[0] else { return }
            var peak: Float = 0
            for i in 0..<Int(buf.frameLength) {
                let v = abs(ch[i])
                if v > peak { peak = v }
            }
            lCont.yield(peak)
        }

        engine.prepare()
        try engine.start()
        running = true
        return (buffers, levels)
    }

    func stop() {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
            logInfo("audio: stopped")
        }
        bufferContinuation?.finish()
        levelContinuation?.finish()
        bufferContinuation = nil
        levelContinuation  = nil
    }
}
