import SwiftUI

/// Optional bottom pane showing the in-app debug log (a ring buffer mirrored
/// to `os.log`). Toggled from View → Show Debug Logs (⌥⌘D).
struct DebugPane: View {
    @State private var log = DebugLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            entries
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var header: some View {
        HStack {
            Text("DEBUG · last \(log.entries.count) events")
                .font(.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { log.clear() }
                .controlSize(.mini)
                .buttonStyle(.bordered)
            Text(#"tail: log stream --predicate 'subsystem == "com.local.ben"'"#)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var entries: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(log.entries) { e in
                        DebugRow(entry: e).id(e.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .onChange(of: log.entries.count) { _, _ in
                if let last = log.entries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct DebugRow: View {
    let entry: DebugLog.Entry

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    var body: some View {
        let color: Color = {
            switch entry.level {
            case .info:  return .secondary
            case .warn:  return .yellow
            case .error: return .red
            }
        }()
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFmt.string(from: entry.timestamp))
                .foregroundStyle(.tertiary)
            Text(entry.level.rawValue.uppercased())
                .frame(width: 38, alignment: .leading)
                .foregroundStyle(color)
            Text(entry.message)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.caption.monospaced())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue.capitalized) log")
        .accessibilityValue(entry.message)
    }
}
