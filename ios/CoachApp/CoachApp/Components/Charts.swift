import SwiftUI
import Charts

// Ports src/components/Charts.jsx onto Swift Charts: 2px lines with
// round caps and a light area wash, ≤24px columns, hairline gridlines,
// labels in ink colours, tap/drag to read a value.

struct ChartPoint: Identifiable, Equatable {
    var label: String
    var value: Double
    var id: String { label + "\(value)" }
}

/// Single-series line chart (exercise trends, recovery).
struct LineChartView: View {
    let points: [ChartPoint]
    var unit = ""
    var color: Color = Theme.chartAmber
    @State private var selected: String?

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                AreaMark(x: .value("When", "\(i)|\(p.label)"), y: .value("Value", p.value))
                    .foregroundStyle(color.opacity(0.1))
                LineMark(x: .value("When", "\(i)|\(p.label)"), y: .value("Value", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if i == points.count - 1 || selected == "\(i)|\(p.label)" {
                    PointMark(x: .value("When", "\(i)|\(p.label)"), y: .value("Value", p.value))
                        .foregroundStyle(color)
                        .symbolSize(70)
                        .annotation(position: .top) {
                            Text("\(fmt(p.value))\(unit)").font(Theme.mono(11)).foregroundStyle(Theme.text)
                        }
                }
            }
        }
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: axisLabels) { v in
                AxisValueLabel { Text((v.as(String.self) ?? "").split(separator: "|").last.map(String.init) ?? "").font(Theme.mono(10)).foregroundStyle(Theme.muted) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel().font(Theme.mono(10)).foregroundStyle(Theme.muted)
            }
        }
        .frame(height: 180)
    }

    /// First, middle, last — enough to read the time span without clutter.
    private var axisLabels: [String] {
        let keys = points.enumerated().map { "\($0.offset)|\($0.element.label)" }
        guard keys.count > 3 else { return keys }
        return [keys.first!, keys[keys.count / 2], keys.last!]
    }

    private func fmt(_ v: Double) -> String { v.rounded() == v ? String(Int64(v)) : String(format: "%.1f", v) }
}

/// Single-series bar chart (weekly volume / sessions).
struct BarChartView: View {
    let bars: [ChartPoint]
    var unit = ""
    var color: Color = Theme.chartTeal
    @State private var selected: String?

    var body: some View {
        Chart {
            ForEach(bars) { b in
                BarMark(x: .value("Week", b.label), y: .value("Value", b.value), width: .fixed(22))
                    .foregroundStyle(color)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    .annotation(position: .top) {
                        if selected == b.label {
                            Text("\(Self.fmtN(b.value))\(unit)").font(Theme.mono(11)).foregroundStyle(Theme.text)
                        }
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(Theme.mono(10)).foregroundStyle(Theme.muted) }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel { Text(Self.fmtN(v.as(Double.self) ?? 0)).font(Theme.mono(10)).foregroundStyle(Theme.muted) }
            }
        }
        .frame(height: 180)
    }

    static func fmtN(_ n: Double) -> String {
        n >= 10000 ? "\(Int((n / 1000).rounded()))k" : Int(n).formatted()
    }
}

/// Training-day heatmap: last `weeks` weeks, Monday on top, deeper teal
/// = bigger session (TrainingHeatmap in Charts.jsx).
struct TrainingHeatmapView: View {
    /// date (yyyy-MM-dd) → total volume that day
    let days: [String: Int]
    var weeks = 16

    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        let thisMonday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let start = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: thisMonday) ?? today
        let maxVol = max(days.values.max() ?? 1, 1)
        let f: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f }()
        GeometryReader { geo in
            let gap: CGFloat = 3
            let cell = min((geo.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks), 18)
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let date = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? today
                            let vol = days[f.string(from: date)]
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(vol, maxVol: maxVol, future: date > today))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(height: 7 * 18 + 6 * 3)
    }

    private func color(_ vol: Int?, maxVol: Int, future: Bool) -> Color {
        if future { return .clear }
        guard let vol else { return Theme.bgPill }
        // logged but no volume (cardio / mobility) → the lightest step
        let t = vol <= 0 ? 0.25 : 0.35 + 0.65 * Double(vol) / Double(maxVol)
        return Theme.chartTeal.opacity(t)
    }
}
