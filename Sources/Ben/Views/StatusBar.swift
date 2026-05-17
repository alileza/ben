import SwiftUI
import CoreAudio

/// Top control bar. Owns no state of its own — everything is driven by
/// `AppState` (read-only here) and callbacks passed in from `ContentView`.
struct StatusBar: View {
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

            DirectionToggle(direction: state.direction,
                            onChange: onDirectionChanged)

            Pill(label: "mic",
                 value: String(format: "%.2f", state.micLevel),
                 color: state.micLevel > 0.02 ? .green : .secondary)

            Spacer()

            ExportMenuButton(state: state)

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

// MARK: - Building blocks

/// A small label + value capsule used throughout the status bar.
struct Pill: View {
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

/// One-click direction toggle styled to match the surrounding pills.
struct DirectionToggle: View {
    let direction: Direction
    let onChange: (Direction) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("direction")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            Button {
                onChange(direction.opposite)
            } label: {
                HStack(spacing: 4) {
                    Text(direction.label)
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
    }
}

/// Menu → save the committed transcript to disk. Disabled until there is at
/// least one finalized utterance.
struct ExportMenuButton: View {
    let state: AppState

    var body: some View {
        Menu {
            let src = state.direction.sourceCode
            let tgt = state.direction.targetCode
            Button("Source only (\(src))") { save(.source) }
            Button("Translation only (\(tgt))") { save(.translation) }
            Button("Both (paired)") { save(.both) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 10))
                Text("export").font(.system(size: 11))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06), in: Capsule())
            .foregroundStyle(state.pairedLines.isEmpty ? Color.secondary : Color.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(state.pairedLines.isEmpty)
        .help(state.pairedLines.isEmpty ? "No transcript yet" : "Save transcript as .txt")
    }

    private func save(_ kind: TranscriptKind) {
        TranscriptExport.save(
            lines: state.pairedLines,
            sessionStart: state.sessionStart,
            kind: kind
        )
    }
}

/// Compact button that opens a popover with the input-device list and the
/// hardware mic volume slider.
struct InputSourceButton: View {
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
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
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Slider(value: $volume, in: 0...1) { _ in
                    AudioDevices.setInputVolume(volume, for: effectiveID)
                }
                .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
    }

    private func deviceRow(label: String,
                           isSelected: Bool,
                           action: @escaping () -> Void) -> some View {
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
