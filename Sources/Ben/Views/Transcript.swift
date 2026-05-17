import SwiftUI

/// Source/translation in a SINGLE shared scroll. Each committed row is one
/// `HStack` containing both columns, so the two sides are always aligned
/// vertically — a taller source forces the translation column to expand to
/// match (and vice versa). The active in-progress row uses the same
/// two-column structure and sits pinned at the top under the status bar.
struct TranscriptView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            activeRow
            Divider()
            historyScroll
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07))
    }

    // MARK: - Active

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

    // MARK: - History

    private var historyScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if state.pairedLines.isEmpty {
                    emptyHint
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(state.pairedLines.reversed())) { row in
                            PairedRowView(row: row, sessionStart: state.sessionStart)
                                .id(row.id)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
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

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(state.isListening
                 ? "Listening — speak to get started"
                 : "Click \"start mic\" or press space to begin")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
    }
}

// MARK: - Row

/// A single committed utterance. Hovering grows the text to the active size
/// on both sides simultaneously (synced via `hovered` in this struct).
struct PairedRowView: View {
    let row: PairedRow
    let sessionStart: Date
    @State private var hovered = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        let stamp = Self.timeFormatter.string(from: row.timestamp)
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
        .contentShape(Rectangle())
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
                    .fill(text.isEmpty ? Color.gray.opacity(0.4)
                                       : Color.red.opacity(0.85))
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
