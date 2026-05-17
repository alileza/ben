import Foundation
import OSLog

/// Ring-buffered logger. UI reads `entries` (main-actor); engines call the
/// free functions below which are non-isolated and hop to main internally.
/// Also forwards every line to os.log so `log stream` shows them.
@MainActor
@Observable
final class DebugLog {
    static let shared = DebugLog()

    enum Level: String { case info, warn, error }

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String
    }

    private(set) var entries: [Entry] = []
    private let cap = 400
    private let osLog = Logger(subsystem: "com.local.ben", category: "ben")

    private init() {}

    fileprivate func append(_ level: Level, _ message: String) {
        let entry = Entry(timestamp: .now, level: level, message: message)
        entries.append(entry)
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
        switch level {
        case .info:  osLog.info("\(message, privacy: .public)")
        case .warn:  osLog.warning("\(message, privacy: .public)")
        case .error: osLog.error("\(message, privacy: .public)")
        }
    }

    func clear() { entries.removeAll() }
}

// MARK: - Free functions (callable from any isolation context).

nonisolated func logInfo(_ message: String) {
    Task { @MainActor in DebugLog.shared.append(.info,  message) }
}
nonisolated func logWarn(_ message: String) {
    Task { @MainActor in DebugLog.shared.append(.warn,  message) }
}
nonisolated func logError(_ message: String) {
    Task { @MainActor in DebugLog.shared.append(.error, message) }
}
