import SwiftUI

@main
struct BenApp: App {
    @State private var appState = AppState()
    @State private var devices = AudioDevices()

    var body: some Scene {
        WindowGroup("Ben") {
            ContentView(state: appState, devices: devices)
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .commands {
            ViewMenuCommands(state: appState)
        }
    }
}

/// Adds two toggles to the standard View menu (after the sidebar group, which
/// is where macOS lets apps put their custom view-state toggles).
struct ViewMenuCommands: Commands {
    @Bindable var state: AppState

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Toggle("Show Debug Logs", isOn: $state.showDebug)
                .keyboardShortcut("d", modifiers: [.command, .option])
            Toggle("Show Diagnostics", isOn: $state.showDiagnostics)
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

enum Direction: String, CaseIterable, Identifiable {
    case enToDe = "en-de"
    case deToEn = "de-en"
    var id: String { rawValue }
    var label: String { self == .enToDe ? "EN → DE" : "DE → EN" }
    var speechLocale: String { self == .enToDe ? "en-US" : "de-DE" }
    var sourceCode: String { self == .enToDe ? "en" : "de" }
    var targetCode: String { self == .enToDe ? "de" : "en" }
}

/// One committed utterance — source and its translation, paired so the two
/// columns in the UI always align.
struct PairedRow: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let speaker: String
    let sourceLang: String
    let source: String
    let targetLang: String
    let translation: String
}
