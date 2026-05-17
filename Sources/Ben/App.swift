import SwiftUI

/// Ben — native macOS app for real-time speech translation between English
/// and German.
///
/// Pipeline:
///   AVAudioEngine (mic) → SFSpeechRecognizer → Translation framework
///
/// All on-device; no network, no API keys.
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

/// Adds toggles for the diagnostics and debug panes to the standard View menu.
struct ViewMenuCommands: Commands {
    @Bindable var state: AppState

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Toggle("Show Debug Logs",  isOn: $state.showDebug)
                .keyboardShortcut("d", modifiers: [.command, .option])
            Toggle("Show Diagnostics", isOn: $state.showDiagnostics)
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
