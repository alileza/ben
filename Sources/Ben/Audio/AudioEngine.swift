import AVFoundation
import CoreAudio

/// Captures mic audio and republishes it as mono Float32 buffers (extracted
/// from channel 0 of the hardware format) — SFSpeechRecognizer expects mono
/// or stereo and silently drops everything when handed a multi-channel
/// buffer from an aggregate device. The sample rate is left at the
/// hardware rate (typically 44.1/48 kHz); the recognizer down-samples
/// internally.
final class AudioEngine: @unchecked Sendable {

    typealias BufferStream = AsyncStream<AVAudioPCMBuffer>
    typealias LevelStream  = AsyncStream<Float>

    private let engine = AVAudioEngine()
    private var bufferContinuation: BufferStream.Continuation?
    private var levelContinuation:  LevelStream.Continuation?
    private var running = false

    func start(deviceID: AudioDeviceID? = nil) throws -> (buffers: BufferStream, levels: LevelStream) {
        stop()

        let (buffers, bCont) = BufferStream.makeStream(bufferingPolicy: .bufferingOldest(16))
        let (levels,  lCont) = LevelStream.makeStream(bufferingPolicy: .bufferingOldest(16))
        bufferContinuation = bCont
        levelContinuation  = lCont

        let input = engine.inputNode

        // Pin to a specific input device before tapping. AVAudioEngine caches
        // the input format at engine.start() time.
        if let deviceID, deviceID != 0 {
            do {
                try input.auAudioUnit.setDeviceID(deviceID)
                logInfo("audio: input device set to id=\(deviceID)")
            } catch {
                logWarn("audio: setDeviceID(\(deviceID)) failed: \(error.localizedDescription) — falling back to system default")
            }
        }

        let hwFormat = input.outputFormat(forBus: 0)
        logInfo("audio: tap installed @ \(Int(hwFormat.sampleRate)) Hz, hw channels=\(hwFormat.channelCount)")

        // Force a mono target format (Float32 at the hardware sample rate).
        // SFSpeechRecognizer accepts 1- or 2-channel buffers; multi-channel
        // virtual devices (aggregate, BlackHole, etc.) silently produce no
        // transcripts, so we always downmix here.
        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate:   hwFormat.sampleRate,
            channels:     1,
            interleaved:  false
        )!
        let converter = AVAudioConverter(from: hwFormat, to: monoFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buf, _ in
            // Convert to mono. If the format is already mono, the converter
            // passes through; we still hand the recognizer a fresh buffer
            // that matches `monoFormat` exactly.
            let outCapacity = AVAudioFrameCount(
                Double(buf.frameLength) * monoFormat.sampleRate / hwFormat.sampleRate
            )
            guard let monoBuf = AVAudioPCMBuffer(pcmFormat: monoFormat,
                                                 frameCapacity: max(outCapacity, buf.frameLength)),
                  let converter = converter else { return }

            var fed = false
            var err: NSError?
            converter.convert(to: monoBuf, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buf
            }
            if err != nil { return }

            bCont.yield(monoBuf)

            // Peak level off the resulting mono buffer.
            guard let ch = monoBuf.floatChannelData?[0] else { return }
            var peak: Float = 0
            for i in 0..<Int(monoBuf.frameLength) {
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
