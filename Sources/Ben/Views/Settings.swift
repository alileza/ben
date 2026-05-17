import SwiftUI

/// The Settings window (opened with ⌘,). Standard macOS tabbed layout.
/// All preferences are backed by `@AppStorage`; the source of truth lives in
/// `UserDefaults` so views that read them via the same keys stay in sync.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AudioSettings()
                .tabItem { Label("Audio", systemImage: "waveform") }
        }
        .scenePadding()
        .frame(minWidth: 460, minHeight: 280)
    }
}

private struct GeneralSettings: View {
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("defaultDirection") private var defaultDirection: Direction = .enToDe

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.label).tag($0) }
                }
                Picker("Default direction", selection: $defaultDirection) {
                    ForEach(Direction.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Source") {
                    Link("github.com/alileza/ben",
                         destination: URL(string: "https://github.com/alileza/ben")!)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AudioSettings: View {
    @AppStorage("silenceThreshold") private var silenceThreshold: Double = 1.0
    @AppStorage("softChunkLimit")   private var softChunkLimit:   Double = 5.0
    @AppStorage("hardChunkLimit")   private var hardChunkLimit:   Double = 10.0

    var body: some View {
        Form {
            Section("Chunking") {
                Slider(value: $silenceThreshold, in: 0.4...3.0, step: 0.1) {
                    Text("Silence threshold")
                } minimumValueLabel: {
                    Text("0.4 s").foregroundStyle(.secondary).font(.caption.monospacedDigit())
                } maximumValueLabel: {
                    Text("3.0 s").foregroundStyle(.secondary).font(.caption.monospacedDigit())
                }
                Text("Pause this long ends an utterance and starts a new line. Default: 1.0 s.")
                    .foregroundStyle(.secondary).font(.caption)

                Slider(value: $softChunkLimit, in: 3.0...15.0, step: 0.5) {
                    Text("Soft chunk limit")
                } minimumValueLabel: {
                    Text("3 s").foregroundStyle(.secondary).font(.caption.monospacedDigit())
                } maximumValueLabel: {
                    Text("15 s").foregroundStyle(.secondary).font(.caption.monospacedDigit())
                }
                Text("In a long monologue, chunk on the next word boundary after this. Default: 5 s.")
                    .foregroundStyle(.secondary).font(.caption)

                Slider(value: $hardChunkLimit, in: 5.0...30.0, step: 1) {
                    Text("Hard chunk limit")
                } minimumValueLabel: {
                    Text("5 s").foregroundStyle(.secondary).font(.caption.monospacedDigit())
                } maximumValueLabel: {
                    Text("30 s").foregroundStyle(.secondary).font(.caption.monospacedDigit())
                }
                Text("Maximum utterance length, even mid-word. Default: 10 s.")
                    .foregroundStyle(.secondary).font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
