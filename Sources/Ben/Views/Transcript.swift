import SwiftUI

/// Source/translation in a SINGLE shared scroll. Each committed row is one
/// `HStack` containing both columns, so the two sides are always aligned
/// vertically — a taller source forces the translation column to expand to
/// match. The active in-progress row uses the same two-column structure and
/// sits pinned at the top under the status bar.
struct TranscriptView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            activeRow
            Divider()
            historyScroll
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
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
        .background(.regularMaterial)
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
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
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
                 : "Press Space or click Start to begin")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
    }
}

// MARK: - Row

/// A single committed utterance. Hovering grows the text to the active size
/// on both sides simultaneously via the shared `hovered` state.
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
                .fill(Color.primary.opacity(hovered ? 0.10 : 0.06))
                .frame(width: 1)
            HistoryCell(stamp: stamp,
                        speaker: row.speaker,
                        lang: row.targetLang,
                        accent: .green,
                        text: row.translation,
                        hovered: hovered)
        }
        .background(hovered ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stamp), \(row.speaker)")
        .accessibilityValue("Source \(row.sourceLang): \(row.source). Translation \(row.targetLang): \(row.translation).")
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
            .font(.caption2.monospaced())
            Text(text.isEmpty ? "—" : text)
                .font(hovered ? .body.weight(.medium) : .body)
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
                    .fill(text.isEmpty ? Color.secondary.opacity(0.4)
                                       : Color.red.opacity(0.85))
                    .frame(width: 6, height: 6)
                Text(lang)
                    .font(.caption.monospaced())
                    .foregroundStyle(accent)
                Text(speaker)
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
                Text(text.isEmpty ? "waiting" : "active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(text.isEmpty ? "—" : text)
                .font(.title3.weight(.medium))
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text.isEmpty ? "Waiting" : "Active") \(lang), \(speaker)")
        .accessibilityValue(text)
    }
}
