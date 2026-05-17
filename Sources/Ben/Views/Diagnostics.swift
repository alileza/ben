import SwiftUI
import Charts

struct DiagnosticsPane: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiagnosticsHeader()
            HStack(spacing: 12) {
                MicCard(state: state)
                LatencyCard(state: state)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct DiagnosticsHeader: View {
    var body: some View {
        HStack {
            Text("DIAGNOSTICS · last 30 s")
                .font(.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Mic card

private struct MicCard: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("mic peak (0–1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.3f", state.micLevel))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(state.micLevel > 0.02 ? .green : .secondary)
            }
            MicBar(level: state.micLevel)
            MicChart(state: state)
                .frame(height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.04))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Microphone peak level")
        .accessibilityValue(String(format: "%.3f of 1.0", state.micLevel))
    }
}

private struct MicBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(barColor)
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, level * 3))))
            }
        }
        .frame(height: 6)
    }

    private var barColor: Color {
        if level > 0.4 { return .red }
        if level > 0.05 { return .green }
        return .blue
    }
}

private struct MicChart: View {
    let state: AppState
    private let window: TimeInterval = AppState.diagWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Chart(state.micPoints) { p in
                // Clamp at the display layer too so the line never escapes
                // its chart frame even if upstream feeds an out-of-range
                // value momentarily.
                LineMark(
                    x: .value("t", -ctx.date.timeIntervalSince(p.timestamp)),
                    y: .value("level", min(Double(p.level), 0.5))
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.linear)
            }
            .chartXScale(domain: -window...0)
            .chartXAxis { secondsAxis }
            .chartYScale(domain: 0...0.5)
            .chartYAxis { micYAxis }
            .clipped()
        }
    }

    private var secondsAxis: some AxisContent {
        AxisMarks(values: [-30, -20, -10, 0]) { v in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
            AxisValueLabel {
                if let s = v.as(Double.self) {
                    Text(s == 0 ? "now" : "\(Int(s)) s")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var micYAxis: some AxisContent {
        AxisMarks(position: .leading, values: [0, 0.25, 0.5]) { v in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
            AxisValueLabel {
                if let d = v.as(Double.self) {
                    Text(String(format: "%.2f", d))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Latency card

private struct LatencyCard: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("translation latency (ms)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(label)
                    .font(.caption.monospacedDigit())
            }
            LatencyChart(state: state)
                .frame(height: 92)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.04))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Translation latency")
        .accessibilityValue(label)
    }

    private var label: String {
        guard let last = state.latencyPoints.last else { return "— ms" }
        return "\(last.ms) ms · n=\(state.latencyPoints.count)"
    }
}

private struct LatencyChart: View {
    let state: AppState
    private let window: TimeInterval = AppState.diagWindow

    /// Cap the Y axis at the 95th percentile of recent latencies (rounded up
    /// to the nearest 100 ms, floored at 200 ms). Outliers above this line
    /// still render but visually pinned at the top — keeps the typical-range
    /// detail readable instead of being crushed by warmup spikes.
    private var yMax: Double {
        let samples = state.latencyPoints.map { Double($0.ms) }.sorted()
        guard !samples.isEmpty else { return 200 }
        let idx = max(0, Int(Double(samples.count - 1) * 0.95))
        let p95 = samples[idx]
        let rounded = (p95 / 100).rounded(.up) * 100
        return max(200, rounded)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Chart(state.latencyPoints) { p in
                let dt = -ctx.date.timeIntervalSince(p.timestamp)
                // Vertical bar per discrete translation event — no
                // interpolation across time gaps.
                BarMark(
                    x: .value("t", dt),
                    yStart: .value("base", 0),
                    yEnd:   .value("ms", min(Double(p.ms), yMax)),
                    width:  .fixed(3)
                )
                .foregroundStyle(p.ms > Int(yMax) ? .red : .green)
                .cornerRadius(1)
            }
            .chartXScale(domain: -window...0)
            .chartXAxis { secondsAxis }
            .chartYScale(domain: 0...yMax)
            .chartYAxis { msYAxis }
        }
    }

    private var secondsAxis: some AxisContent {
        AxisMarks(values: [-30, -20, -10, 0]) { v in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
            AxisValueLabel {
                if let s = v.as(Double.self) {
                    Text(s == 0 ? "now" : "\(Int(s)) s")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var msYAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
            AxisValueLabel {
                if let ms = v.as(Int.self) {
                    Text("\(ms)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
