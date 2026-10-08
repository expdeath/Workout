import SwiftUI

/// Ports src/screens/Progress.jsx — a range switch (8 weeks · 3 months ·
/// year) over the summary, consistency heatmap, lift progression, weekly
/// training, muscle balance, goals and recovery (HRV / RHR / sleep / body
/// weight).
struct ProgressScreen: View {
    @Environment(AppState.self) private var appState
    @State private var range = "8w"
    @State private var exIdx = 0
    @State private var exMetric = "w" // w = best set weight · e = est. 1RM
    @State private var weekMode = "volume"
    @State private var recMode = "hrv"

    private struct RecMode { var key: String; var label: String; var points: [ChartPoint]; var unit: String; var color: Color; var desc: String }

    private var days: Int { range == "8w" ? 56 : range == "3m" ? 91 : 364 }
    private var weeks: Int { days / 7 }

    var body: some View {
        let all = appState.history
        let start = Helpers.daysAgoStr(days - 1)
        let history = all.filter { $0.date >= start }
        let health = LocalStore.shared.backup.health.sorted { $0.date < $1.date }
        let recModes = recoveryModes(health.filter { $0.date >= start }).filter { $0.points.count >= 2 }
        let settings = LocalStore.shared.backup.aiSettings
        let target = Dashboard.weeklyTarget(settings)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(title: "Progress")
                SegmentedTabs(options: [("8w", "8 Weeks"), ("3m", "3 Months"), ("1y", "Year")], value: $range)

                if all.count < 2 && recModes.isEmpty {
                    Text("Log two sessions to unlock charts.")
                        .font(Theme.body(15)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    summary(all, health: health, target: target)
                    consistency(all, target: target)
                    exerciseCard(history)
                    weeklyCard(all)
                    balanceCard(all)
                    goalsCard(all, settings: settings)
                    if !recModes.isEmpty {
                        recoveryCard(recModes, history: all, health: health)
                    } else {
                        Text("Recovery charts appear after two days of Health data.")
                            .font(Theme.body(13.5)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        .coachScreen()
    }

    // MARK: - Summary + consistency

    private func summary(_ all: [Session], health: [HealthRow], target: Int) -> some View {
        let r = Dashboard.rangeSummary(all, days: days, bodyKg: Calories.latestBodyWeightKg(health))
        let delta = Dashboard.deltaPercent(r.sessions, r.prevSessions)
        let streak = Stats.weekStats(all, target: target).streak
        return HStack(spacing: 0) {
            summaryCol("Sessions", "\(r.sessions)", sub: delta.map { "\($0 >= 0 ? "↗ +" : "↘ ")\($0)%" } ?? "Logged", subColor: delta == nil ? Theme.muted : ((delta ?? 0) >= 0 ? Theme.green : Theme.red))
            Rectangle().fill(Theme.border).frame(width: 1, height: 52)
            summaryCol("Volume", r.volume >= 10000 ? "\(r.volume / 1000)T" : "\(Helpers.fmtKg(Double(r.volume) / 1000))T", sub: "Lifted", subColor: Theme.muted)
            Rectangle().fill(Theme.border).frame(width: 1, height: 52)
            summaryCol("Streak", "\(streak)wk", sub: streak > 0 ? "Active" : "—", subColor: streak > 0 ? Theme.amberText : Theme.muted)
        }
        .padding(.vertical, 14)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func summaryCol(_ label: String, _ value: String, sub: String?, subColor: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).capsLabel(Theme.muted, size: 11)
            Text(value).font(Theme.head(30, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            if let sub { Text(sub).capsLabel(subColor, size: 11) }
        }
        .frame(maxWidth: .infinity)
    }

    private func consistency(_ all: [Session], target: Int) -> some View {
        let pct = Dashboard.compliance(all, weeks: weeks, target: target)
        return CoachCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Consistency").font(Theme.head(22, weight: .bold)).textCase(.uppercase).tracking(0.5)
                    Text("Daily training frequency").font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
                StatusPill(text: "\(pct)% compliance", color: pct >= 80 ? Theme.green : Theme.amberText)
            }
            TrainingHeatmapView(days: all.reduce(into: [String: Int]()) { $0[$1.date, default: 0] += Stats.sessionVolume($1) }, weeks: weeks)
                .padding(.vertical, 6)
            HStack {
                Text("Target: \(target) sessions/wk").font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
                Spacer()
                HeatLegend()
            }
        }
    }

    // MARK: - Lift progression

    @ViewBuilder
    private func exerciseCard(_ history: [Session]) -> some View {
        let chartable = Array(Stats.exerciseSeries(history).filter { $0.points.count >= 2 }.prefix(10))
        if !chartable.isEmpty {
            let sel = chartable[min(exIdx, chartable.count - 1)]
            let e1 = sel.points.filter { $0.e != nil }
            let showE1 = e1.count >= 2
            let metric = exMetric == "e" && showE1 ? "e" : "w"
            let pts = metric == "e" ? e1 : sel.points
            let vals = pts.map { metric == "e" ? ($0.e ?? $0.w) : $0.w }
            let latest = vals.last ?? 0, first = vals.first ?? 0
            let isPR = latest >= (vals.max() ?? 0) && latest > first
            CoachCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if isPR { StatusPill(text: "New PR", color: Theme.amberText, dot: false) }
                            Text("Lift progression").capsLabel()
                        }
                        Text(sel.name).font(Theme.head(22, weight: .bold)).textCase(.uppercase).tracking(0.5).lineLimit(2)
                    }
                    Spacer()
                    if showE1 {
                        HStack(spacing: 4) {
                            Chip(title: "Weight", on: metric == "w") { exMetric = "w" }
                            Chip(title: "1RM", on: metric == "e") { exMetric = "e" }
                        }
                    }
                }
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(Helpers.fmtKg(latest))").font(Theme.head(36, weight: .bold)).foregroundStyle(Theme.amberText)
                    Text("kg").capsLabel(Theme.amberText, size: 15)
                    let d = latest - first
                    Text("\(d >= 0 ? "+" : "")\(Helpers.fmtKg(d)) kg progression").capsLabel(d >= 0 ? Theme.green : Theme.red, size: 12)
                }
                LineChartView(points: pts.map { ChartPoint(label: RecordsView.shortDate($0.date), value: metric == "e" ? ($0.e ?? $0.w) : $0.w) },
                              unit: "kg", color: Theme.amber, height: 170)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(chartable.enumerated()), id: \.offset) { i, s in
                            Chip(title: s.name, on: s.name == sel.name) { exIdx = i }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Weekly training, balance, goals

    private func weeklyCard(_ all: [Session]) -> some View {
        CoachCard {
            HStack {
                CardLabel(text: "Weekly training")
                Spacer()
                Chip(title: "Volume", on: weekMode == "volume") { weekMode = "volume" }
                Chip(title: "Sessions", on: weekMode == "sessions") { weekMode = "sessions" }
            }
            let buckets = Stats.weeklyBuckets(all, n: min(weeks, 12))
            if weekMode == "volume" {
                BarChartView(bars: buckets.map { ChartPoint(label: RecordsView.shortDate($0.start), value: Double($0.volume)) }, unit: "kg")
            } else {
                BarChartView(bars: buckets.map { ChartPoint(label: RecordsView.shortDate($0.start), value: Double($0.count)) }, color: Theme.chartGreen)
            }
        }
    }

    @ViewBuilder
    private func balanceCard(_ all: [Session]) -> some View {
        let balance = Stats.muscleBalance(all)
        if !balance.isEmpty {
            CoachCard {
                SectionHead(title: "Muscle balance", trailing: "14 days", trailingColor: Theme.muted)
                let maxSets = max(balance.map(\.sets).max() ?? 1, 1)
                ForEach(balance, id: \.group) { b in
                    let gap = (b.lastDaysAgo ?? 0) >= 10
                    HStack(spacing: 10) {
                        Text(b.group).font(Theme.body(13.5)).foregroundStyle(Theme.textBody).frame(width: 84, alignment: .leading)
                        ProgressLine(fraction: max(Double(b.sets) / Double(maxSets), b.sets > 0 ? 0.06 : 0), color: gap ? Theme.red : Theme.amber, height: 7)
                        Text(b.sets > 0 ? "\(b.sets) sets" : "\(b.lastDaysAgo.map(String.init) ?? "—")d ago")
                            .font(Theme.meta(12.5)).foregroundStyle(gap ? Theme.red : Theme.muted).frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func goalsCard(_ all: [Session], settings: AISettings) -> some View {
        let goals = Stats.goalProgress(all, settings.goals)
        if !goals.isEmpty {
            CoachCard {
                CardLabel(text: "Goals")
                ForEach(Array(goals.enumerated()), id: \.offset) { _, g in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(g.text).font(Theme.body(14))
                            Spacer()
                            if let t = g.target, let c = g.current {
                                Text("\(Helpers.fmtKg(c)) / \(Helpers.fmtKg(t))\(g.unit)").font(Theme.head(15, weight: .bold)).foregroundStyle(Theme.amberText)
                            }
                        }
                        if let t = g.target, let c = g.current, t > 0 {
                            ProgressLine(fraction: c / t, color: c >= t ? Theme.green : Theme.amber, height: 7)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Recovery

    private func recoveryModes(_ health: [HealthRow]) -> [RecMode] {
        func pts(_ k: KeyPath<HealthRow, Double?>) -> [ChartPoint] {
            health.compactMap { h in h[keyPath: k].flatMap { $0 > 0 ? ChartPoint(label: RecordsView.shortDate(h.date), value: $0) : nil } }
        }
        return [
            RecMode(key: "hrv", label: "HRV", points: pts(\.hrv), unit: "ms", color: Theme.green, desc: "Higher and steady is good."),
            RecMode(key: "rhr", label: "Resting HR", points: pts(\.rhr), unit: "bpm", color: Theme.amber, desc: "Lower and steady is good."),
            RecMode(key: "sleep", label: "Sleep", points: pts(\.sleepH), unit: "h", color: Theme.green, desc: "Under ~6h, the coach eases off."),
            RecMode(key: "weight", label: "Body wt", points: pts(\.weightKg), unit: "kg", color: Theme.amber, desc: "Watch the trend, not the day."),
        ]
    }

    private func recoveryCard(_ modes: [RecMode], history: [Session], health: [HealthRow]) -> some View {
        let active = modes.first { $0.key == recMode } ?? modes[0]
        let latest = active.points.last?.value ?? 0
        let prior = active.points.dropLast().suffix(7).map(\.value)
        let avg = prior.isEmpty ? nil : prior.reduce(0, +) / Double(prior.count)
        let readiness = Dashboard.readiness(history, health)
        return CoachCard {
            HStack {
                Image(systemName: "heart.text.square").foregroundStyle(Theme.green)
                Text("Recovery & \(active.label)").capsLabel()
                Spacer()
                if let r = readiness {
                    StatusPill(text: r.tone == .good ? "Optimal recovery" : r.tone == .ok ? "Steady" : "Strained",
                               color: r.tone == .good ? Theme.green : r.tone == .ok ? Theme.amberText : Theme.red)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(Helpers.fmtKg((latest * 10).rounded() / 10)).font(Theme.head(38, weight: .bold))
                Text(active.unit).capsLabel(Theme.muted, size: 14)
                Spacer()
                if let avg {
                    let d = latest - avg
                    Text("\(d >= 0 ? "+" : "")\(Helpers.fmtKg((d * 10).rounded() / 10))\(active.unit) vs 7d avg").capsLabel(Theme.green, size: 11)
                }
            }
            LineChartView(points: active.points, unit: active.unit, color: active.color, height: 140)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(modes, id: \.key) { m in Chip(title: m.label, on: m.key == active.key) { recMode = m.key } }
                }
            }
            Text(active.desc).font(Theme.body(13)).foregroundStyle(Theme.muted)
        }
    }
}
