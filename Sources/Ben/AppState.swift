import Foundation
import CoreAudio

/// Shared application state. Owned at the `App` level via `@State`; every
/// view reads from it directly. `@Observable` tracks property access at body
/// granularity, so each small view re-renders only on changes to the
/// properties it actually reads.
@Observable
@MainActor
final class AppState {

    // MARK: - Session

    var direction: Direction = .enToDe
    var status: String = "idle"
    var isListening: Bool = false
    var sessionStart: Date = .now
    var speakerId: Int = 1

    /// Bump to (re)start the engine driver task. See `.task(id:)` in
    /// `ContentView` — changing this id cancels and restarts the engines.
    var runId: Int = 0

    // MARK: - Transcript

    var pairedLines: [PairedRow] = []
    var activeSource: String = ""
    var activeTranslation: String = ""

    // MARK: - UI toggles (driven from the View menu)

    var showDebug: Bool = false
    var showDiagnostics: Bool = true

    // MARK: - Audio input

    /// `nil` means "use the system default device"; LaunchServices /
    /// CoreAudio picks the appropriate one at engine start.
    var selectedInputDeviceID: AudioDeviceID? = nil
    var micLevel: Float = 0

    // MARK: - Diagnostics (sliding 30 s window)

    static let diagWindow: TimeInterval = 30

    var micPoints: [MicPoint] = []
    var latencyPoints: [LatencyPoint] = []

    private var lastMicSampleAt: Date = .distantPast

    func sampleMicLevel(_ level: Float) {
        micLevel = level
        let now = Date()
        guard now.timeIntervalSince(lastMicSampleAt) >= 0.1 else { return }
        lastMicSampleAt = now
        micPoints.append(MicPoint(timestamp: now, level: level))
        let cutoff = now.addingTimeInterval(-Self.diagWindow)
        if let first = micPoints.firstIndex(where: { $0.timestamp >= cutoff }),
           first > 0 {
            micPoints.removeFirst(first)
        }
    }

    func recordMTLatency(_ ms: Int) {
        let now = Date()
        latencyPoints.append(LatencyPoint(timestamp: now, ms: ms))
        let cutoff = now.addingTimeInterval(-Self.diagWindow)
        if let first = latencyPoints.firstIndex(where: { $0.timestamp >= cutoff }),
           first > 0 {
            latencyPoints.removeFirst(first)
        }
    }

    // MARK: - Translation request / response queue
    //
    // `.translationTask` hands us a fresh `TranslationSession` each activation;
    // we bind a new `AsyncStream<TranslateRequest>.Continuation` per activation
    // so the queue survives direction changes (AsyncStream is single-iterator).
    // The request carries a UUID; callers that need a canonical response (the
    // commit on `isFinal`) can await via `translateCanonical(_:)`. Partial
    // requests via `postForTranslation(_:)` are fire-and-forget.

    struct TranslateRequest: Sendable {
        let id: UUID
        let text: String
        let needsResponse: Bool
    }

    @ObservationIgnored
    private var translationContinuation: AsyncStream<TranslateRequest>.Continuation?

    @ObservationIgnored
    private var pendingResponses: [UUID: CheckedContinuation<String, Never>] = [:]

    func bindTranslator(_ cont: AsyncStream<TranslateRequest>.Continuation) {
        // Resolve any outstanding awaits with empty results so the awaiter
        // doesn't deadlock when we swap continuations on direction change.
        for (_, k) in pendingResponses { k.resume(returning: "") }
        pendingResponses.removeAll()
        translationContinuation?.finish()
        translationContinuation = cont
    }

    /// Fire-and-forget partial translation. Updates `activeTranslation` when
    /// the result lands but the speech handler doesn't wait.
    func postForTranslation(_ text: String) {
        translationContinuation?.yield(
            TranslateRequest(id: UUID(), text: text, needsResponse: false)
        )
    }

    /// Awaitable canonical translation. Used at utterance final so the
    /// committed (source, translation) pair always corresponds.
    func translateCanonical(_ text: String) async -> String {
        guard let cont = translationContinuation else { return "" }
        let id = UUID()
        return await withCheckedContinuation { cc in
            pendingResponses[id] = cc
            cont.yield(TranslateRequest(id: id, text: text, needsResponse: true))
        }
    }

    /// Called by the `.translationTask` body when a translation finishes.
    func deliverTranslation(_ translation: String, for request: TranslateRequest) {
        activeTranslation = translation
        if request.needsResponse,
           let cc = pendingResponses.removeValue(forKey: request.id) {
            cc.resume(returning: translation)
        }
    }
}
