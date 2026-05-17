import SwiftUI
import CoreAudio

// Toolbar-item controls. The custom always-on status bar was replaced with a
// native `.toolbar { … }` in `ContentView`; what's left here are the small
// reusable views the toolbar populates.

/// One-click swap between EN→DE and DE→EN. Rendered as a borderless button
/// in the toolbar — a single chevron-style affordance that flips on tap.
struct DirectionToggle: View {
    let direction: Direction
    let onChange: (Direction) -> Void

    var body: some View {
        Button {
            let next = direction.opposite
            onChange(next)
        } label: {
            HStack(spacing: 6) {
                Text(direction.label)
                    .font(.body.monospaced())
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .help("Swap translation direction")
        .accessibilityLabel("Translation direction")
        .accessibilityValue(direction.label)
        .accessibilityHint("Activate to swap direction")
    }
}

/// Toolbar menu — save the committed transcript to disk. Disabled until
/// there's at least one finalized utterance.
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
            Label("Export", systemImage: "square.and.arrow.down")
        }
        .disabled(state.pairedLines.isEmpty)
        .help(state.pairedLines.isEmpty ? "No transcript yet" : "Save transcript as .txt")
    }

    private func save(_ kind: TranscriptKind) {
        TranscriptExport.save(lines: state.pairedLines,
                              sessionStart: state.sessionStart,
                              kind: kind)
    }
}

/// Toolbar button that opens a popover with the input-device list and the
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
            Label(label, systemImage: "mic.fill")
        }
        .help("Choose input device and adjust mic volume")
        .accessibilityLabel("Input device")
        .accessibilityValue(label)
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
                .font(.caption2.weight(.semibold))
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
                    .font(.caption2.weight(.semibold))
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int(volume * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Slider(value: $volume, in: 0...1) { _ in
                    AudioDevices.setInputVolume(volume, for: effectiveID)
                }
                .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption2)
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
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(label).foregroundStyle(.primary)
                Spacer()
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
