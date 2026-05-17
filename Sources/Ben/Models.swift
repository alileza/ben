import Foundation
import SwiftUI

/// User appearance preference. Persisted via `@AppStorage("appearance")` and
/// applied to the root view's `.preferredColorScheme`.
enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Match System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

/// Translation direction. SFSpeechRecognizer locale and the Translation
/// framework source/target locales are all derived from this single enum.
enum Direction: String, CaseIterable, Identifiable, Sendable {
    case enToDe = "en-de"
    case deToEn = "de-en"

    var id: String { rawValue }
    var label: String { self == .enToDe ? "EN → DE" : "DE → EN" }

    /// BCP-47 locale identifier passed to `SFSpeechRecognizer(locale:)`.
    var speechLocale: String { self == .enToDe ? "en-US" : "de-DE" }

    /// Two-letter code used by the Translation framework and for UI labels.
    var sourceCode: String { self == .enToDe ? "en" : "de" }
    var targetCode: String { self == .enToDe ? "de" : "en" }

    var opposite: Direction { self == .enToDe ? .deToEn : .enToDe }
}

/// One finalized utterance — a source transcript paired with its translation.
/// The UI keeps these two columns vertically aligned by rendering both as a
/// single row.
struct PairedRow: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let speaker: String
    let sourceLang: String
    let source: String
    let targetLang: String
    let translation: String
}

/// Mic peak sample for the diagnostics chart (sliding 30 s window).
struct MicPoint: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: Float
}

/// Translation latency sample for the diagnostics chart (sliding 30 s window).
struct LatencyPoint: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let ms: Int
}
