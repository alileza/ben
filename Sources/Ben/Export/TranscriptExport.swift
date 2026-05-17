import AppKit
import UniformTypeIdentifiers

enum TranscriptKind: String, CaseIterable, Identifiable {
    case source       // spoken-language column only
    case translation  // translated-language column only
    case both         // both, paired
    var id: String { rawValue }
}

enum TranscriptExport {
    /// Build the .txt body for the given lines.
    static func render(_ lines: [PairedRow],
                       sessionStart: Date,
                       kind: TranscriptKind) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        var out = "Ben transcript\n"
        out += "Session start: \(dateFormatter.string(from: sessionStart))\n"
        out += "Lines: \(lines.count)\n"
        out += "Kind: \(kind.rawValue)\n"
        out += String(repeating: "─", count: 40) + "\n\n"

        let rowTimeFmt = DateFormatter()
        rowTimeFmt.dateFormat = "HH:mm:ss"

        for row in lines {
            let stamp = "[\(rowTimeFmt.string(from: row.timestamp))]"
            switch kind {
            case .source:
                out += "\(stamp) \(row.sourceLang): \(row.source)\n"
            case .translation:
                let t = row.translation.isEmpty ? "—" : row.translation
                out += "\(stamp) \(row.targetLang): \(t)\n"
            case .both:
                let t = row.translation.isEmpty ? "—" : row.translation
                out += "\(stamp)\n"
                out += "  \(row.sourceLang): \(row.source)\n"
                out += "  \(row.targetLang): \(t)\n\n"
            }
        }
        return out
    }

    /// Show an NSSavePanel and write the transcript on confirm. Main-actor-only.
    @MainActor
    static func save(lines: [PairedRow], sessionStart: Date, kind: TranscriptKind) {
        let body = render(lines, sessionStart: sessionStart, kind: kind)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: sessionStart)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ben-\(kind.rawValue)-\(stamp).txt"
        panel.canCreateDirectories = true
        panel.title = "Save Transcript"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            logInfo("export: wrote \(lines.count) lines (\(kind.rawValue)) → \(url.path)")
        } catch {
            logError("export: \(error.localizedDescription)")
        }
    }
}
