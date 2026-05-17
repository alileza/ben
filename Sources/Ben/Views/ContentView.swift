import SwiftUI
import Speech
import Translation
import AVFoundation
import CoreAudio

/// Root composition. Owns the audio + speech engines (as `@State`) and wires
/// them to the shared `AppState` via two SwiftUI lifecycle modifiers:
///
///   - `.translationTask(_:perform:)` activates a `TranslationSession` whose
///     body owns a request/response queue bound to `AppState`. Restarted
///     automatically whenever `translationConfig` changes.
///
///   - `.task(id: state.runId)` runs the audio + speech pipeline. Toggling
///     mic, changing input device, or changing direction increments `runId`
///     and reincarnates the pipeline with the new settings.
struct ContentView: View {
    let state: AppState
    let devices: AudioDevices

    @State private var audio = AudioEngine()
    @State private var speech = SpeechEngine()
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var silenceWatchdog: Task<Void, Never>?
    @State private var utteranceStartedAt: Date?

    // Persisted preferences (Settings → Audio).
    @AppStorage("silenceThreshold") private var silenceThresholdSeconds: Double = 1.0
    @AppStorage("softChunkLimit")   private var softChunkLimitSeconds:   Double = 5.0
    @AppStorage("hardChunkLimit")   private var hardChunkLimitSeconds:   Double = 10.0

    var body: some View {
        VStack(spacing: 0) {
            StatusStrip(state: state)
            TranscriptView(state: state)
            if state.showDiagnostics {
                DiagnosticsPane(state: state).frame(height: 160)
            }
            if state.showDebug {
                DebugPane().frame(height: 200)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                DirectionToggle(direction: state.direction, onChange: applyDirection)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                ExportMenuButton(state: state)
                InputSourceButton(state: state,
                                  devices: devices,
                                  onInputDeviceChanged: applyInputDevice)
                Button(state.isListening ? "Stop" : "Start", action: toggleMic)
                    .keyboardShortcut(.space, modifiers: [])
                    .accessibilityLabel(state.isListening ? "Stop microphone" : "Start microphone")
            }
        }
        .translationTask(translationConfig) { session in
            await runTranslator(session: session)
        }
        .task(id: state.runId) {
            await driveEngines()
        }
        .onAppear {
            translationConfig = .init(
                source: .init(identifier: state.direction.sourceCode),
                target: .init(identifier: state.direction.targetCode)
            )
            logInfo("ben started")
        }
    }

    // MARK: - Translator

    private func runTranslator(session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
            logInfo("translation: prepared \(state.direction.rawValue)")
        } catch {
            logError("translate prep: \(error.localizedDescription)")
            state.status = "translation not available — accept the download prompt"
            return
        }

        let (stream, cont) = AsyncStream<AppState.TranslateRequest>.makeStream()
        state.bindTranslator(cont)
        defer { cont.finish() }

        for await req in stream {
            guard !req.text.isEmpty else {
                state.deliverTranslation("", for: req)
                continue
            }
            let t0 = Date()
            do {
                let response = try await session.translate(req.text)
                state.recordMTLatency(Int(Date().timeIntervalSince(t0) * 1000))
                state.deliverTranslation(response.targetText, for: req)
            } catch {
                logError("translate: \(error.localizedDescription)")
                state.status = "translate: \(error.localizedDescription)"
                state.deliverTranslation("", for: req)
            }
        }
    }

    // MARK: - Engine driver

    private func driveEngines() async {
        guard state.isListening else { return }
        state.status = "starting"

        let speechStreams: (transcripts: SpeechEngine.TranscriptStream,
                            statuses:    SpeechEngine.StatusStream)
        let audioStreams:  (buffers: AudioEngine.BufferStream,
                            levels:  AudioEngine.LevelStream)
        do {
            speechStreams = try speech.start()
            audioStreams  = try audio.start(deviceID: state.selectedInputDeviceID)
        } catch {
            logError("start failed: \(error.localizedDescription)")
            state.status = "err: \(error.localizedDescription)"
            state.isListening = false
            return
        }
        state.status = "listening"

        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [speech] in
                    for await buf in audioStreams.buffers { speech.append(buf) }
                }
                group.addTask { @MainActor in
                    for await lvl in audioStreams.levels { state.sampleMicLevel(lvl) }
                }
                group.addTask { @MainActor in
                    for await msg in speechStreams.statuses { handleSpeechStatus(msg) }
                }
                group.addTask { @MainActor in
                    for await t in speechStreams.transcripts { handleTranscript(t) }
                }
            }
        } onCancel: {
            audio.stop()
            speech.cancel()
        }

        state.status = "idle"
        state.micLevel = 0
        logInfo("engines stopped")
    }

    private func handleSpeechStatus(_ msg: String) {
        logInfo("speech: \(msg)")
        if msg.contains("Siri and Dictation") {
            state.status = "enable Dictation in System Settings → Keyboard"
        } else if msg.lowercased().contains("error") {
            state.status = msg
        }
    }

    private func handleTranscript(_ t: Transcript) {
        if state.activeSource.isEmpty && !t.text.isEmpty {
            utteranceStartedAt = .now
        }
        state.activeSource = t.text
        if !t.text.isEmpty { state.postForTranslation(t.text) }

        if t.isFinal {
            silenceWatchdog?.cancel()
            utteranceStartedAt = nil
            let finalText = t.text
            Task { @MainActor in
                let translation = await state.translateCanonical(finalText)
                commitUtterance(source: finalText, translation: translation)
            }
        } else {
            armSilenceWatchdog()
            maybeForceChunk(currentText: t.text)
        }
    }

    // MARK: - Chunking

    private func armSilenceWatchdog() {
        silenceWatchdog?.cancel()
        let delay = silenceThresholdSeconds
        silenceWatchdog = Task { @MainActor [speech] in
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            guard !state.activeSource.isEmpty else { return }
            speech.endUtterance()
        }
    }

    private func maybeForceChunk(currentText: String) {
        guard let started = utteranceStartedAt else { return }
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < softChunkLimitSeconds { return }

        let atBoundary = endsAtWordBoundary(currentText)
        if (elapsed >= softChunkLimitSeconds && atBoundary) || elapsed >= hardChunkLimitSeconds {
            logInfo("chunk: forcing after \(Int(elapsed))s (boundary=\(atBoundary))")
            speech.endUtterance()
        }
    }

    private func endsAtWordBoundary(_ text: String) -> Bool {
        guard let last = text.last else { return true }
        return last.isWhitespace || last.isPunctuation
    }

    // MARK: - Commit

    private func commitUtterance(source: String, translation: String) {
        guard !source.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            state.pairedLines.append(PairedRow(
                timestamp: Date(),
                speaker: "S\(state.speakerId)",
                sourceLang: state.direction.sourceCode,
                source: source,
                targetLang: state.direction.targetCode,
                translation: translation
            ))
        }
        state.activeSource = ""
        state.activeTranslation = ""
    }

    // MARK: - User actions

    private func toggleMic() {
        if state.isListening {
            state.isListening = false
            state.runId &+= 1
            logInfo("mic: stop requested")
        } else {
            Task { @MainActor in
                logInfo("mic: requesting auth")
                let auth = await SpeechEngine.requestAuth()
                logInfo("mic: auth = \(authString(auth))")
                guard auth == .authorized else {
                    state.status = "speech \(authString(auth))"
                    return
                }
                speech.localeIdentifier = state.direction.speechLocale
                state.sessionStart = .now
                state.isListening = true
                state.runId &+= 1
            }
        }
    }

    private func applyInputDevice(_ id: AudioDeviceID?) {
        state.selectedInputDeviceID = id
        let name = devices.inputs.first(where: { $0.id == id })?.name ?? "default"
        logInfo("input device: \(name)")
        if state.isListening { state.runId &+= 1 }
    }

    private func applyDirection(_ new: Direction) {
        state.direction = new
        translationConfig = .init(
            source: .init(identifier: new.sourceCode),
            target: .init(identifier: new.targetCode)
        )
        speech.localeIdentifier = new.speechLocale
        state.pairedLines.removeAll()
        state.activeSource = ""
        state.activeTranslation = ""
        logInfo("direction: \(new.rawValue)")
        if state.isListening { state.runId &+= 1 }
    }

    private func authString(_ s: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "pending"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .authorized:    return "ok"
        @unknown default:    return "unknown"
        }
    }
}

// MARK: - Status strip (slim row of ambient state below the toolbar)

/// Thin status bar below the toolbar. Ambient indicators only — no controls.
private struct StatusStrip: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 18) {
            stateIndicator
            micIndicator
            Spacer()
        }
        .font(.caption.monospaced())
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private var stateIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isListening ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(state.status)
                .foregroundStyle(state.isListening ? .primary : .secondary)
        }
        .accessibilityLabel("State")
        .accessibilityValue(state.status)
    }

    private var micIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.fill").imageScale(.small)
            Text(String(format: "%.2f", state.micLevel))
                .monospacedDigit()
        }
        .foregroundStyle(state.micLevel > 0.02 ? .green : .secondary)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(String(format: "%.2f", state.micLevel))
    }
}
