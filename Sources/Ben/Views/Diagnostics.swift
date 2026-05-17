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
        .background(Color(white: 0.04))
        .overlay(alignment: .top) { Divider() }
    }
}

private struct DiagnosticsHeader: View {
    var body: some View {
        HStack {
            Text("DIAGNOSTICS · last 30 s")
                .font(.system(size: 10, weight: .medium))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(white: 0.10))
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
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.3f", state.micLevel))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(state.micLevel > 0.02 ? .green : .secondary)
            }
            MicBar(level: state.micLevel)
            MicChart(state: state)
                .frame(height: 72)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MicBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
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
                LineMark(
                    x: .value("t", -ctx.date.timeIntervalSince(p.timestamp)),
                    y: .value("level", Double(p.level))
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.linear)
            }
            .chartXScale(domain: -window...0)
            .chartXAxis { secondsAxis }
            .chartYScale(domain: 0...0.5)
            .chartYAxis { micYAxis }
        }
    }

    private var secondsAxis: some AxisContent {
        AxisMarks(values: [-30, -20, -10, 0]) { v in
            AxisGridLine().foregroundStyle(.white.opacity(0.05))
            AxisValueLabel {
                if let s = v.as(Double.self) {
                    Text(s == 0 ? "now" : "\(Int(s)) s")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var micYAxis: some AxisContent {
        AxisMarks(position: .leading, values: [0, 0.25, 0.5]) { v in
            AxisGridLine().foregroundStyle(.white.opacity(0.05))
            AxisValueLabel {
                if let d = v.as(Double.self) {
                    Text(String(format: "%.2f", d))
                        .font(.system(size: 9, design: .monospaced))
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
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            LatencyChart(state: state)
                .frame(height: 92)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var label: String {
        guard let last = state.latencyPoints.last else { return "— ms" }
        return "\(last.ms) ms · n=\(state.latencyPoints.count)"
    }
}

private struct LatencyChart: View {
    let state: AppState
    private let window: TimeInterval = AppState.diagWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Chart(state.latencyPoints) { p in
                let dt = -ctx.date.timeIntervalSince(p.timestamp)
                LineMark(x: .value("t", dt), y: .value("ms", p.ms))
                    .foregroundStyle(.green)
                PointMark(x: .value("t", dt), y: .value("ms", p.ms))
                    .foregroundStyle(.green)
                    .symbolSize(14)
            }
            .chartXScale(domain: -window...0)
            .chartXAxis { secondsAxis }
            .chartYAxis { msYAxis }
        }
    }

    private var secondsAxis: some AxisContent {
        AxisMarks(values: [-30, -20, -10, 0]) { v in
            AxisGridLine().foregroundStyle(.white.opacity(0.05))
            AxisValueLabel {
                if let s = v.as(Double.self) {
                    Text(s == 0 ? "now" : "\(Int(s)) s")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var msYAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
            AxisGridLine().foregroundStyle(.white.opacity(0.05))
            AxisValueLabel {
                if let ms = v.as(Int.self) {
                    Text("\(ms)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
