import SwiftUI
import Speech
import Translation
import AVFoundation

// MARK: - State

@Observable
@MainActor
final class AppState {
    var direction: Direction = .enToDe
    var status: String = "idle"
    var isListening: Bool = false
    var micLevel: Float = 0

    var pairedLines: [PairedRow] = []

    var activeSource: String = ""
    var activeTranslation: String = ""

    var sessionStart: Date = .now
    var speakerId: Int = 1

    /// Increment to (re)start the engine driver task. See `.task(id:)`.
    var runId: Int = 0

    // View toggles, driven by the menu bar.
    var showDebug: Bool = false
    var showDiagnostics: Bool = false

    /// Input device chosen by the user. `nil` means "use system default".
    var selectedInputDeviceID: AudioDeviceID? = nil

    // Diagnostics — sliding 30 s window, points are time-stamped so the chart
    // axis can drift left independently of new data arriving.
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
        if let firstKept = micPoints.firstIndex(where: { $0.timestamp >= cutoff }), firstKept > 0 {
            micPoints.removeFirst(firstKept)
        }
    }

    func recordMTLatency(_ ms: Int) {
        let now = Date()
        latencyPoints.append(LatencyPoint(timestamp: now, ms: ms))
        let cutoff = now.addingTimeInterval(-Self.diagWindow)
        if let firstKept = latencyPoints.firstIndex(where: { $0.timestamp >= cutoff }), firstKept > 0 {
            latencyPoints.removeFirst(firstKept)
        }
    }

    // MARK: - Translation queue (re-bindable)
    // Each .translationTask activation hands us a fresh continuation so the
    // queue survives direction changes (AsyncStreams are single-iterator).

    @ObservationIgnored
    private var translationContinuation: AsyncStream<String>.Continuation?

    func bindTranslator(_ cont: AsyncStream<String>.Continuation) {
        translationContinuation?.finish()
        translationContinuation = cont
    }

    func postForTranslation(_ text: String) {
        translationContinuation?.yield(text)
    }
}

struct MicPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: Float
}

struct LatencyPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let ms: Int
}

// MARK: - Top-level view

struct ContentView: View {
    let state: AppState
    let devices: AudioDevices
    @State private var audio = AudioEngine()
    @State private var speech = SpeechEngine()
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var silenceWatchdog: Task<Void, Never>?
    private let utteranceSilenceSeconds: TimeInterval = 1.0

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(
                state: state,
                devices: devices,
                onToggleMic: toggleMic,
                onDirectionChanged: applyDirection,
                onInputDeviceChanged: applyInputDevice
            )

            TwoColumnTranscript(state: state)

            if state.showDiagnostics {
                DiagnosticsPane(state: state)
                    .frame(height: 160)
            }

            if state.showDebug {
                DebugPane()
                    .frame(height: 200)
            }
        }
        .background(Color(white: 0.05))
        .translationTask(translationConfig) { session in
            do {
                try await session.prepareTranslation()
                logInfo("translation: prepared \(state.direction.rawValue)")
            } catch {
                logError("translate prep: \(error.localizedDescription)")
                state.status = "translation not available — accept the download prompt"
                return
            }

            // Each activation owns its own stream. Bind it to AppState so the
            // speech handler can post into the *current* translator regardless
            // of how many times direction has changed.
            let (stream, cont) = AsyncStream<String>.makeStream()
            state.bindTranslator(cont)
            defer { cont.finish() }

            for await text in stream {
                guard !text.isEmpty else { continue }
                let t0 = Date()
                do {
                    let response = try await session.translate(text)
                    let ms = Int(Date().timeIntervalSince(t0) * 1000)
                    state.activeTranslation = response.targetText
                    state.recordMTLatency(ms)
                } catch {
                    logError("translate: \(error.localizedDescription)")
                    state.status = "translate: \(error.localizedDescription)"
                }
            }
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

    // MARK: - Lifecycle

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
                    for await msg in speechStreams.statuses {
                        logInfo("speech: \(msg)")
                        if msg.contains("Siri and Dictation") {
                            state.status = "enable Dictation in System Settings → Keyboard"
                        } else if msg.lowercased().contains("error") {
                            state.status = msg
                        }
                    }
                }
                group.addTask { @MainActor in
                    for await t in speechStreams.transcripts {
                        state.activeSource = t.text
                        if !t.text.isEmpty { state.postForTranslation(t.text) }
                        if t.isFinal {
                            commitLines(forFinalSource: t.text)
                            silenceWatchdog?.cancel()
                        } else {
                            armSilenceWatchdog()
                        }
                    }
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

    /// SFSpeechRecognizer rarely fires `isFinal` on its own in continuous mode.
    /// We force it by calling `endUtterance()` after 1 s of no new transcript,
    /// which is what the user perceives as "a stop = a new line".
    private func armSilenceWatchdog() {
        silenceWatchdog?.cancel()
        silenceWatchdog = Task { @MainActor [speech] in
            try? await Task.sleep(for: .seconds(utteranceSilenceSeconds))
            if Task.isCancelled { return }
            guard !state.activeSource.isEmpty else { return }
            speech.endUtterance()
        }
    }

    private func commitLines(forFinalSource text: String) {
        guard !text.isEmpty else { return }
        state.pairedLines.append(PairedRow(
            timestamp: Date(),
            speaker: "S\(state.speakerId)",
            sourceLang: state.direction.sourceCode,
            source: text,
            targetLang: state.direction.targetCode,
            translation: state.activeTranslation
        ))
        state.activeSource = ""
        state.activeTranslation = ""
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

// MARK: - Status bar

private struct StatusBar: View {
    let state: AppState
    let devices: AudioDevices
    let onToggleMic: () -> Void
    let onDirectionChanged: (Direction) -> Void
    let onInputDeviceChanged: (AudioDeviceID?) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Pill(label: "state",
                 value: state.status,
                 color: state.isListening ? .green : .secondary)
            Pill(label: "device", value: "apple", color: .secondary)

            HStack(spacing: 6) {
                Text("direction")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                Button {
                    let next: Direction = state.direction == .enToDe ? .deToEn : .enToDe
                    onDirectionChanged(next)
                } label: {
                    HStack(spacing: 4) {
                        Text(state.direction.label)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .help("Click to swap direction")
            }

            Pill(label: "mic",
                 value: String(format: "%.2f", state.micLevel),
                 color: state.micLevel > 0.02 ? .green : .secondary)

            Spacer()

            InputSourceButton(state: state,
                              devices: devices,
                              onInputDeviceChanged: onInputDeviceChanged)

            Button(state.isListening ? "stop mic" : "start mic", action: onToggleMic)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.10))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct Pill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06), in: Capsule())
                .foregroundStyle(color)
        }
    }
}

/// Compact button → popover with input device list and hardware volume slider.
private struct InputSourceButton: View {
    let state: AppState
    let devices: AudioDevices
    let onInputDeviceChanged: (AudioDeviceID?) -> Void
    @State private var open = false
    @State private var volume: Float = 0.5

    private var effectiveID: AudioDeviceID {
        state.selectedInputDeviceID ?? devices.systemDefault
    }

    private var label: String {
        if let id = state.selectedInputDeviceID,
           let dev = devices.inputs.first(where: { $0.id == id }) {
            return dev.name
        }
        return devices.systemDefaultName
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.system(size: 10))
                Text(label).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06), in: Capsule())
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .help("Choose input device and adjust mic volume")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            InputSourcePopover(state: state,
                               devices: devices,
                               volume: $volume,
                               onInputDeviceChanged: onInputDeviceChanged)
                .frame(width: 280)
        }
        .onChange(of: effectiveID, initial: true) { _, _ in
            volume = AudioDevices.inputVolume(for: effectiveID) ?? 0.5
        }
    }
}

private struct InputSourcePopover: View {
    let state: AppState
    let devices: AudioDevices
    @Binding var volume: Float
    let onInputDeviceChanged: (AudioDeviceID?) -> Void

    private var effectiveID: AudioDeviceID {
        state.selectedInputDeviceID ?? devices.systemDefault
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INPUT DEVICE")
                .font(.system(size: 9, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                deviceRow(label: "System default · \(devices.systemDefaultName)",
                          isSelected: state.selectedInputDeviceID == nil) {
                    onInputDeviceChanged(nil)
                }
                ForEach(devices.inputs) { dev in
                    deviceRow(label: dev.name,
                              isSelected: state.selectedInputDeviceID == dev.id) {
                        onInputDeviceChanged(dev.id)
                    }
                }
            }

            Divider()

            HStack {
                Text("VOLUME")
                    .font(.system(size: 9, weight: .medium))
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int(volume * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                Slider(value: $volume, in: 0...1) { _ in
                    AudioDevices.setInputVolume(volume, for: effectiveID)
                }
                .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
    }

    private func deviceRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color(white: 0.4))
                Text(label).foregroundStyle(.primary)
                Spacer()
            }
            .font(.system(size: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transcript pane

/// Source/translation in a SINGLE shared scroll, each row a two-column HStack
/// so the two sides are always aligned vertically (a tall source forces the
/// translation column to expand to the same height, and vice versa). Active
/// row pinned at the bottom uses the same column structure for a clean diff.
private struct TwoColumnTranscript: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            activeRow              // sits right under the status bar
            Divider()
            historyScroll          // newest near the top, older further down
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07))
    }

    // History — single scroll so left/right scroll together by construction.
    // Newest at the top (just under the active row); older further down.
    private var historyScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(state.pairedLines.reversed())) { row in
                        PairedRowView(row: row, sessionStart: state.sessionStart)
                            .id(row.id)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.top)
            .onChange(of: state.pairedLines.count) { _, _ in
                if let newest = state.pairedLines.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newest.id, anchor: .top)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // Active row — both columns side by side, locked at the bottom.
    private var activeRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ActiveCell(text: state.activeSource,
                       lang: state.direction.sourceCode,
                       accent: .blue,
                       speaker: "S\(state.speakerId)")
            verticalDivider
            ActiveCell(text: state.activeTranslation,
                       lang: state.direction.targetCode,
                       accent: .green,
                       speaker: "S\(state.speakerId)")
        }
        .background(Color(white: 0.11))
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
    }
}

private struct PairedRowView: View {
    let row: PairedRow
    let sessionStart: Date
    @State private var hovered = false

    var body: some View {
        let secs = Int(row.timestamp.timeIntervalSince(sessionStart))
        let stamp = String(format: "%02d:%02d", secs / 60, secs % 60)
        HStack(alignment: .top, spacing: 0) {
            HistoryCell(stamp: stamp,
                        speaker: row.speaker,
                        lang: row.sourceLang,
                        accent: .blue,
                        text: row.source,
                        hovered: hovered)
            Rectangle()
                .fill(Color.white.opacity(hovered ? 0.10 : 0.06))
                .frame(width: 1)
            HistoryCell(stamp: stamp,
                        speaker: row.speaker,
                        lang: row.targetLang,
                        accent: .green,
                        text: row.translation,
                        hovered: hovered)
        }
        .background(hovered ? Color.white.opacity(0.04) : .clear)
        .contentShape(Rectangle())   // make full row hoverable
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

private struct HistoryCell: View {
    let stamp: String
    let speaker: String
    let lang: String
    let accent: Color
    let text: String
    let hovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: hovered ? 4 : 2) {
            HStack(spacing: 8) {
                Text(stamp).foregroundStyle(.tertiary)
                Text(lang).foregroundStyle(accent)
                Text(speaker).foregroundStyle(.orange)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, design: .monospaced))
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: hovered ? 16 : 13,
                              weight: hovered ? .medium : .regular))
                .foregroundStyle(text.isEmpty ? .tertiary
                                              : (hovered ? .primary : .secondary))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, hovered ? 6 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActiveCell: View {
    let text: String
    let lang: String
    let accent: Color
    let speaker: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(text.isEmpty ? Color.gray.opacity(0.4) : Color.red.opacity(0.85))
                    .frame(width: 6, height: 6)
                Text(lang)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(accent)
                Text(speaker)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange)
                Text(text.isEmpty ? "waiting" : "active")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
    }
}

// MARK: - Debug pane

struct DebugPane: View {
    @State private var log = DebugLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DEBUG · last \(log.entries.count) events")
                    .font(.system(size: 10, weight: .medium))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("clear") { log.clear() }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                Text("tail: log stream --predicate 'subsystem == \"com.local.ben\"'")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(white: 0.10))
            .overlay(alignment: .bottom) { Divider() }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(log.entries) { e in
                            DebugRow(entry: e).id(e.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .onChange(of: log.entries.count) { _, _ in
                    if let last = log.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(white: 0.04))
        .overlay(alignment: .top) { Divider() }
    }
}

private struct DebugRow: View {
    let entry: DebugLog.Entry

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    var body: some View {
        let color: Color = {
            switch entry.level {
            case .info:  return .secondary
            case .warn:  return .yellow
            case .error: return .red
            }
        }()
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFmt.string(from: entry.timestamp))
                .foregroundStyle(.tertiary)
            Text(entry.level.rawValue.uppercased())
                .frame(width: 38, alignment: .leading)
                .foregroundStyle(color)
            Text(entry.message)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}
