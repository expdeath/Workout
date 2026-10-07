import SwiftUI

/// Ports src/screens/Progress.jsx — stat tiles, training-day heatmap,
/// per-exercise trend (weight / e1RM), weekly volume or sessions,
/// records, muscle balance, goals and recovery (HRV / RHR / sleep / body
/// weight from the Watch).
struct ProgressScreen: View {
    @Environment(AppState.self) private var appState
    @State private var exIdx = 0
    @State private var exMetric = "w" // w = best set weight · e = est. 1RM
    @State private var weekMode = "volume"
    @State private var recMode = "hrv"

    private struct RecMode { var key: String; var label: String; var points: [ChartPoint]; var unit: String; var color: Color; var desc: String }

    var body: some View {
        let history = appState.history
        let health = LocalStore.shared.backup.health.sorted { $0.date < $1.date }
        let recModes = recoveryModes(health).filter { $0.points.count >= 2 }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(back: "Home", title: "PROGRESS", onBack: { appState.screen = .home })

                if history.count < 2 && recModes.isEmpty {
                    Text("Charts unlock after a couple of logged sessions.\nKeep training — the picture builds itself.")
                        .font(Theme.body(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.top, 80)
                } else {
                    if history.count >= 2 { trainingSections(history, health) }
                    if !recModes.isEmpty {
                        recoveryCard(recModes)
                    } else {
                        Text("Recovery charts (HRV, resting HR) appear after two days of Watch data — run the Gym Check-in shortcut daily.")
                            .font(Theme.mono(12.5)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer().frame(height: 60)
            }
            .padding(16)
        }
        .coachScreen()
    }

    // MARK: - Training

    @ViewBuilder
    private func trainingSections(_ history: [Session], _ health: [HealthRow]) -> some View {
        let week = Stats.weekStats(history)
        let kcal = Calories.stats(history, bodyKg: Calories.latestBodyWeightKg(health))
        HStack(spacing: 8) {
            StatTile(label: "This week", value: "\(week.thisWeek)", unit: "sessions")
            StatTile(label: "Week streak (≥3)", value: "\(week.streak)", unit: "wks")
            StatTile(label: "🔥 This week", value: kcal.thisWeek.formatted(), unit: "kcal")
        }

        CoachCard {
            CardLabel(text: "Training days")
            TrainingHeatmapView(days: history.reduce(into: [String: Int]()) { $0[$1.date, default: 0] += Stats.sessionVolume($1) })
            Text("Last 16 weeks, Monday-top. Deeper teal = bigger session.").font(Theme.mono(12)).foregroundStyle(Theme.muted)
        }

        exerciseCard(history)

        CoachCard {
            HStack {
                CardLabel(text: "Weekly training")
                Spacer()
                Chip(title: "Volume", on: weekMode == "volume") { weekMode = "volume" }
                Chip(title: "Sessions", on: weekMode == "sessions") { weekMode = "sessions" }
            }
            let weeks = Stats.weeklyBuckets(history, n: 8)
            if weekMode == "volume" {
                BarChartView(bars: weeks.map { ChartPoint(label: RecordsView.shortDate($0.start), value: Double($0.volume)) }, unit: "kg")
            } else {
                BarChartView(bars: weeks.map { ChartPoint(label: RecordsView.shortDate($0.start), value: Double($0.count)) }, color: Theme.chartAmber)
            }
            Text(weekMode == "volume" ? "Total kg lifted per week, last 8 weeks." : "Sessions logged per week, last 8 weeks.")
                .font(Theme.mono(12)).foregroundStyle(Theme.muted)
        }

        let records = Array(Stats.prRecords(history).filter { $0.weight != nil }.prefix(10))
        if !records.isEmpty {
            CoachCard {
                CardLabel(text: "🏆 Records")
                ForEach(records, id: \.name) { r in
                    HStack {
                        Text(r.name).font(Theme.mono(13)).foregroundStyle(Theme.textBody)
                        Spacer()
                        Text("\(Helpers.fmtKg(r.weight!.w))kg × \(r.weight!.reps.isEmpty ? "?" : r.weight!.reps)\(r.e1rm.map { " · e1RM \(Helpers.fmtKg($0.v))kg" } ?? "")")
                            .font(Theme.mono(12.5)).foregroundStyle(Theme.muted)
                    }
                }
                Text("All-time heaviest set per exercise, with estimated 1RM (Epley).").font(Theme.mono(12)).foregroundStyle(Theme.muted)
            }
        }

        let balance = Stats.muscleBalance(history)
        if !balance.isEmpty {
            CoachCard {
                CardLabel(text: "Muscle balance — last 14 days")
                let maxSets = max(balance.map(\.sets).max() ?? 1, 1)
                ForEach(balance, id: \.group) { b in
                    let gap = (b.lastDaysAgo ?? 0) >= 10
                    HStack(spacing: 8) {
                        Text(b.group).font(Theme.body(13)).frame(width: 82, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.bgPill)
                                Capsule().fill(gap ? Theme.amber : Theme.teal)
                                    .frame(width: geo.size.width * max(Double(b.sets) / Double(maxSets), b.sets > 0 ? 0.06 : 0))
                            }
                        }
                        .frame(height: 8)
                        Text(b.sets > 0 ? "\(b.sets) sets" : "\(b.lastDaysAgo.map(String.init) ?? "—")d ago")
                            .font(Theme.mono(12)).foregroundStyle(gap ? Theme.amber : Theme.muted).frame(width: 70, alignment: .trailing)
                    }
                }
                if balance.contains(where: { ($0.lastDaysAgo ?? 0) >= 10 }) {
                    Text("⚠ amber = not trained in 10+ days. The coach sees this too.").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                }
            }
        }

        let goals = Stats.goalProgress(history, LocalStore.shared.backup.aiSettings.goals)
        if !goals.isEmpty {
            CoachCard {
                CardLabel(text: "Goals")
                ForEach(Array(goals.enumerated()), id: \.offset) { _, g in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(g.text).font(Theme.body(14))
                            Spacer()
                            if let t = g.target, let c = g.current {
                                Text("\(Helpers.fmtKg(c)) / \(Helpers.fmtKg(t))\(g.unit)").font(Theme.mono(12.5)).foregroundStyle(Theme.muted)
                            }
                        }
                        if let t = g.target, let c = g.current, t > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.bgPill)
                                    Capsule().fill(c >= t ? Theme.teal : Theme.amber).frame(width: geo.size.width * min(c / t, 1))
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                    .padding(.top, 4)
                }
                Text("Edit goals in Settings → AI Coach. Lifts track your all-time best set.").font(Theme.mono(12)).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder
    private func exerciseCard(_ history: [Session]) -> some View {
        let chartable = Array(Stats.exerciseSeries(history).filter { $0.points.count >= 2 }.prefix(8))
        if !chartable.isEmpty {
            let sel = chartable[min(exIdx, chartable.count - 1)]
            let e1 = sel.points.filter { $0.e != nil }
            let showE1 = e1.count >= 2
            let metric = exMetric == "e" && showE1 ? "e" : "w"
            let pts = metric == "e" ? e1 : sel.points
            CoachCard {
                HStack {
                    CardLabel(text: metric == "e" ? "Estimated 1RM per session (kg)" : "Best set weight per session (kg)")
                    Spacer()
                    if showE1 {
                        Chip(title: "Weight", on: metric == "w") { exMetric = "w" }
                        Chip(title: "e1RM", on: metric == "e") { exMetric = "e" }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(chartable.enumerated()), id: \.offset) { i, s in
                            Chip(title: s.name, on: s.name == sel.name) { exIdx = i }
                        }
                    }
                }
                LineChartView(points: pts.map { ChartPoint(label: RecordsView.shortDate($0.date), value: metric == "e" ? ($0.e ?? $0.w) : $0.w) }, unit: "kg")
                ForEach(Array(pts.suffix(4).reversed().enumerated()), id: \.offset) { _, p in
                    HStack {
                        Text(Helpers.fmtDate(p.date))
                        Spacer()
                        Text("\(Helpers.fmtKg(metric == "e" ? (p.e ?? p.w) : p.w))kg")
                    }
                    .font(Theme.mono(12.5)).foregroundStyle(Theme.muted)
                }
                if metric == "e" {
                    Text("Estimated one-rep max (Epley) from the best set each session — strength, independent of the rep range you trained.")
                        .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: - Recovery

    private func recoveryModes(_ health: [HealthRow]) -> [RecMode] {
        let recent = health.suffix(30)
        func pts(_ k: KeyPath<HealthRow, Double?>) -> [ChartPoint] {
            recent.compactMap { h in h[keyPath: k].flatMap { $0 > 0 ? ChartPoint(label: RecordsView.shortDate(h.date), value: $0) : nil } }
        }
        return [
            RecMode(key: "hrv", label: "HRV", points: pts(\.hrv), unit: "ms", color: Theme.chartTeal,
                    desc: "HRV (ms), daily from Watch. Higher and stable is good — dips flag poor recovery."),
            RecMode(key: "rhr", label: "Resting HR", points: pts(\.rhr), unit: "", color: Theme.chartAmber,
                    desc: "Resting heart rate (bpm). Lower and stable is good — a climb suggests fatigue or illness."),
            RecMode(key: "sleep", label: "Sleep", points: pts(\.sleepH), unit: "h", color: Theme.chartTeal,
                    desc: "Sleep (hours). Under ~6h the coach eases off intensity."),
            RecMode(key: "weight", label: "Body wt", points: pts(\.weightKg), unit: "kg", color: Theme.chartAmber,
                    desc: "Body weight (kg), from check-ins. Trend matters, not the daily noise."),
        ]
    }

    private func recoveryCard(_ modes: [RecMode]) -> some View {
        let active = modes.first { $0.key == recMode } ?? modes[0]
        return CoachCard {
            HStack {
                CardLabel(text: "Recovery")
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(modes, id: \.key) { m in Chip(title: m.label, on: m.key == active.key) { recMode = m.key } }
                }
            }
            LineChartView(points: active.points, unit: active.unit, color: active.color)
            Text(active.desc).font(Theme.mono(12)).foregroundStyle(Theme.muted)
        }
    }
}
