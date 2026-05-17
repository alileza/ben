import Speech
import AVFoundation

struct Transcript: Sendable {
    let text: String
    let isFinal: Bool
}

/// Wraps SFSpeechRecognizer for an open-ended session. Auto-restarts the
/// recognition task after finals AND after recoverable errors (e.g. the
/// recognizer's "No speech detected" timeout during long pauses), so a
/// single `start()` covers the full mic session.
///
/// Important: callbacks from a *previous* recognitionTask can fire after we've
/// already moved on to a new one. We tag the callback closure with the request
/// instance it belongs to and discard stale invocations — otherwise the old
/// task's error nils out the new task's state, producing immediate "No speech
/// detected" errors after direction switches.
final class SpeechEngine: NSObject, @unchecked Sendable, SFSpeechRecognizerDelegate {

    typealias TranscriptStream = AsyncStream<Transcript>
    typealias StatusStream     = AsyncStream<String>

    var localeIdentifier: String = "en-US"

    private var recognizer: SFSpeechRecognizer?
    private var currentRequest: SFSpeechAudioBufferRecognitionRequest?
    private var currentTask: SFSpeechRecognitionTask?
    private var transcriptContinuation: TranscriptStream.Continuation?
    private var statusContinuation:     StatusStream.Continuation?

    /// When true, the engine restarts a new task after each final / recoverable
    /// error. Flipped off by `cancel()`.
    private var autoRestart: Bool = false

    enum SpeechError: LocalizedError {
        case recognizerUnavailable(locale: String)
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable(let l):
                return "Speech unavailable for \(l). Enable Dictation in System Settings → Keyboard, and ensure the language is installed."
            }
        }
    }

    static func requestAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
    }

    func start() throws -> (transcripts: TranscriptStream, statuses: StatusStream) {
        cancel()

        let locale = Locale(identifier: localeIdentifier)
        guard let r = SFSpeechRecognizer(locale: locale) else {
            throw SpeechError.recognizerUnavailable(locale: localeIdentifier)
        }
        r.delegate = self
        recognizer = r

        let (transcripts, tCont) = TranscriptStream.makeStream()
        let (statuses,    sCont) = StatusStream.makeStream()
        transcriptContinuation = tCont
        statusContinuation     = sCont

        sCont.yield("locale=\(localeIdentifier) available=\(r.isAvailable) onDevice=\(r.supportsOnDeviceRecognition)")

        guard r.isAvailable else {
            throw SpeechError.recognizerUnavailable(locale: localeIdentifier)
        }

        autoRestart = true
        startNewTask()
        return (transcripts, statuses)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        currentRequest?.append(buffer)
    }

    /// Force end-of-utterance — recognizer emits a final and we restart.
    func endUtterance() {
        currentRequest?.endAudio()
    }

    func cancel() {
        autoRestart = false
        currentTask?.cancel()
        currentTask = nil
        currentRequest?.endAudio()
        currentRequest = nil
        transcriptContinuation?.finish()
        statusContinuation?.finish()
        transcriptContinuation = nil
        statusContinuation     = nil
    }

    // MARK: - Private

    private func startNewTask() {
        guard let recognizer, autoRestart else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        if #available(macOS 13.0, *) {
            req.addsPunctuation = true
        }
        currentRequest = req

        // Capture `req` to identify this task in the callback. Any callback
        // invocation where self.currentRequest !== req is from a previous,
        // already-superseded task and must be ignored.
        currentTask = recognizer.recognitionTask(with: req) { [weak self, weak req] result, error in
            guard let self, let req, self.currentRequest === req else { return }

            if let result {
                self.transcriptContinuation?.yield(
                    Transcript(text: result.bestTranscription.formattedString,
                               isFinal: result.isFinal)
                )
                if result.isFinal {
                    self.currentRequest = nil
                    self.currentTask = nil
                    self.startNewTask()
                }
            }
            if let error = error as NSError? {
                let isCancel = error.domain == "kAFAssistantErrorDomain" && error.code == 216
                if !isCancel {
                    self.statusContinuation?.yield("task error: \(error.localizedDescription)")
                }
                self.currentRequest = nil
                self.currentTask = nil
                // Recoverable: "No speech detected" (1110) and similar are
                // expected during long pauses. Restart the task so continuous
                // mic stays continuous.
                if !isCancel { self.startNewTask() }
            }
        }
    }

    // MARK: - SFSpeechRecognizerDelegate

    nonisolated func speechRecognizer(_ r: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        logInfo("speech availability changed: \(available)")
    }
}
