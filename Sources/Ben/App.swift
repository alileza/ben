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

    /// Persisted in UserDefaults; users can change it from Settings → General.
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    var body: some Scene {
        WindowGroup("Ben") {
            ContentView(state: appState, devices: devices)
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AppInfoCommands()
            FileMenuCommands(state: appState)
            ViewMenuCommands(state: appState)
            HelpMenuCommands()
        }

        Window("About Ben", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)

        Settings {
            SettingsView()
        }
    }
}

// MARK: - About menu item

/// Replaces the default "About Ben" menu item so it opens our custom window
/// instead of the system-generated panel.
struct AppInfoCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Ben") {
                openWindow(id: "about")
            }
        }
    }
}

// MARK: - Commands

/// Adds File-menu entries: New Session, Export Transcript submenu.
struct FileMenuCommands: Commands {
    @Bindable var state: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Session") {
                state.pairedLines.removeAll()
                state.activeSource = ""
                state.activeTranslation = ""
                state.sessionStart = .now
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(state.pairedLines.isEmpty && state.activeSource.isEmpty)
        }
        CommandGroup(after: .saveItem) {
            Menu("Export Transcript") {
                Button("Source Only (\(state.direction.sourceCode))") {
                    TranscriptExport.save(lines: state.pairedLines,
                                          sessionStart: state.sessionStart,
                                          kind: .source)
                }
                Button("Translation Only (\(state.direction.targetCode))") {
                    TranscriptExport.save(lines: state.pairedLines,
                                          sessionStart: state.sessionStart,
                                          kind: .translation)
                }
                Button("Both (Paired)") {
                    TranscriptExport.save(lines: state.pairedLines,
                                          sessionStart: state.sessionStart,
                                          kind: .both)
                }
            }
            .disabled(state.pairedLines.isEmpty)
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

/// Replaces the default Help menu items with project links.
struct HelpMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Ben on GitHub",
                 destination: URL(string: "https://github.com/alileza/ben")!)
            Link("Report an Issue",
                 destination: URL(string: "https://github.com/alileza/ben/issues/new/choose")!)
            Divider()
            Link("Landing page",
                 destination: URL(string: "https://alileza.github.io/ben/")!)
        }
    }
}
