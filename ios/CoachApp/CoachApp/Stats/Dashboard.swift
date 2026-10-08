import Foundation

/// Derived numbers for the dashboard-style screens (Today, Log, Progress,
/// Records) and the notification feed — mirrors src/utils/dashboard.js,
/// so both apps show the same figures from the same data.
enum Dashboard {
    // MARK: - Readiness pill

    enum Tone { case good, ok, low }
    struct Readiness { var label: String; var tone: Tone; var note: String }

    /// RESTED / STEADY / FATIGUED from the latest Watch day (≤ 2 days old)
    /// against the 30-day baseline, plus the training-load deload signal.
    /// nil when there's no recent health data and no load warning.
    static func readiness(_ history: [Session], _ health: [HealthRow]) -> Readiness? {
        let deload = Stats.deloadSignal(history)
        let cutoff = Helpers.daysAgoStr(2)
        let latest = health.filter { $0.date >= cutoff }.max { $0.date < $1.date }
        guard let h = latest else {
            return deload.map { Readiness(label: "Deload", tone: .low, note: $0.reason) }
        }
        let base = Stats.healthBaseline(history, health)
        var low = 0, good = 0
        var bits: [String] = []
        if let hrv = h.hrv, let b = base.hrv, b > 0 {
            let d = Int((hrv - b).rounded())
            bits.append("HRV \(Int(hrv.rounded())) ms (\(d >= 0 ? "+" : "")\(d) vs your average)")
            if hrv < b * 0.85 { low += 1 } else if hrv >= b * 0.95 { good += 1 }
        }
        if let rhr = h.rhr, let b = base.rhr {
            if rhr > b + 5 { low += 1; bits.append("resting HR \(Int(rhr.rounded())) — high") }
            else if rhr <= b + 1 { good += 1 }
        }
        if let sleep = h.sleepH {
            bits.append("slept \(String(format: "%.1f", sleep))h")
            if sleep < 6 { low += 1 } else if sleep >= 7 { good += 1 }
        }
        if deload != nil { low += 1 }
        guard !bits.isEmpty || deload != nil else { return nil }
        let note = bits.isEmpty ? (deload?.reason ?? "") : bits.joined(separator: " · ").prefix(1).uppercased() + bits.joined(separator: " · ").dropFirst()
        if low > 0 { return Readiness(label: "Fatigued", tone: .low, note: deload?.reason ?? note) }
        if good >= 2 { return Readiness(label: "Rested", tone: .good, note: note) }
        return Readiness(label: "Steady", tone: .ok, note: note)
    }

    // MARK: - Weekly target

    /// Settings value, else a "N sessions a week" goal, else 3.
    static func weeklyTarget(_ s: AISettings) -> Int {
        if let t = s.weeklyTarget, t > 0 { return min(t, 14) }
        let goal = Stats.goalProgress([], s.goals).first { $0.unit == " this week" }
        if let t = goal?.target, t > 0 { return min(Int(t), 14) }
        return 3
    }

    // MARK: - Ranges

    struct RangeSummary { var sessions: Int; var prevSessions: Int; var volume: Int; var kcal: Int }

    /// Sessions / volume in the last `days` days, and sessions in the
    /// `days` before that (for the "+16%" delta).
    static func rangeSummary(_ history: [Session], days: Int, bodyKg: Double) -> RangeSummary {
        let start = Helpers.daysAgoStr(days - 1), prevStart = Helpers.daysAgoStr(2 * days - 1)
        let cur = history.filter { $0.date >= start }
        let prev = history.filter { $0.date >= prevStart && $0.date < start }
        return RangeSummary(sessions: cur.count, prevSessions: prev.count,
                            volume: cur.reduce(0) { $0 + Stats.sessionVolume($1) },
                            kcal: cur.reduce(0) { $0 + Calories.estimate($1, bodyKg: bodyKg) })
    }

    /// Percent of the weekly target met over the last `weeks` weeks
    /// (this week counts pro rata), capped at 100.
    static func compliance(_ history: [Session], weeks: Int, target: Int) -> Int {
        guard target > 0, weeks > 0 else { return 0 }
        let done = history.filter { $0.date >= Helpers.daysAgoStr(weeks * 7 - 1) }.count
        return min(100, Int((Double(done) / Double(weeks * target) * 100).rounded()))
    }

    /// "+16%" style change; nil when there's nothing to compare with.
    static func deltaPercent(_ cur: Int, _ prev: Int) -> Int? {
        guard prev > 0 else { return nil }
        return Int(((Double(cur) - Double(prev)) / Double(prev) * 100).rounded())
    }

    // MARK: - Today's plan

    /// Expected kg lifted if every strength set hits the top of its rep
    /// range at the suggested (or last used) weight.
    static func projectedLoad(_ plan: Plan, _ history: [Session]) -> Int {
        var total = 0.0
        for ex in plan.exercises where Stats.logMode(ex.name, plan.sessionType) == "strength" {
            let reps = lastNumber(ex.reps) ?? 0
            let last = Stats.lastPerformance(history, ex.name)
            let lastBest: Double = last?.sets.compactMap { Double($0.weight) }.max() ?? 0
            let w: Double = Stats.suggestNextWeight(last, ex.reps) ?? firstNumber(ex.suggestedWeight) ?? lastBest
            total += Double(ex.sets) * reps * w
        }
        return Int(total.rounded())
    }

    /// "8-12" → 12, "10" → 10
    private static func lastNumber(_ s: String) -> Double? {
        let g: [String?]? = Stats.firstMatch(#"(\d+)\D*$"#, in: s)
        let v: String? = g.flatMap { $0[safe: 1] ?? nil }
        return v.flatMap(Double.init)
    }

    /// "24kg" → 24
    private static func firstNumber(_ s: String) -> Double? {
        let g: [String?]? = Stats.firstMatch(#"(\d+(?:\.\d+)?)"#, in: s)
        let v: String? = g.flatMap { $0[safe: 1] ?? nil }
        return v.flatMap(Double.init)
    }

    /// Mean of the plan's RPE targets ("7-8" → 7.5).
    static func averageRPE(_ plan: Plan) -> Double? {
        let vals = plan.exercises.compactMap { ex -> Double? in
            let n = (Stats.firstMatch(#"(\d+(?:\.\d+)?)(?:\s*-\s*(\d+(?:\.\d+)?))?"#, in: ex.rpe)).map { g in
                [(g[safe: 1] ?? nil), (g[safe: 2] ?? nil)].compactMap { $0.flatMap(Double.init) }
            } ?? []
            return n.isEmpty ? nil : n.reduce(0, +) / Double(n.count)
        }
        return vals.isEmpty ? nil : (vals.reduce(0, +) / Double(vals.count) * 2).rounded() / 2
    }

    // MARK: - Milestones

    struct Milestone: Identifiable {
        var id: String
        var icon: String // SF Symbol
        var title: String
        var value: Int
        var goal: Int
        var earned: Bool { value >= goal }
    }

    struct Ladder { var key: String; var icon: String; var unit: String; var value: Int; var steps: [Int] }

    static func ladders(_ history: [Session]) -> [Ladder] {
        let records = Stats.prRecords(history)
        let heaviest = Int(records.compactMap { $0.weight?.w }.max() ?? 0)
        let tonnes = history.reduce(0) { $0 + Stats.sessionVolume($1) } / 1000
        return [
            Ladder(key: "sessions", icon: "calendar", unit: "sessions", value: history.count, steps: [10, 25, 50, 100, 250]),
            Ladder(key: "streak", icon: "flame.fill", unit: "week streak", value: Stats.weekStats(history).streak, steps: [2, 4, 8, 12, 26]),
            Ladder(key: "tonnes", icon: "scalemass.fill", unit: "t lifted", value: tonnes, steps: [5, 10, 25, 50, 100]),
            Ladder(key: "heaviest", icon: "medal.fill", unit: "kg lift", value: heaviest, steps: [40, 60, 80, 100, 140]),
        ]
    }

    /// Every earned step plus the next one up on each ladder.
    static func milestones(_ history: [Session]) -> [Milestone] {
        ladders(history).flatMap { l -> [Milestone] in
            let title = { (n: Int) in l.key == "sessions" ? "\(n) Sessions" : l.key == "tonnes" ? "\(n)T Lifted" : l.key == "heaviest" ? "\(n) kg Lift" : "\(n) Wk Streak" }
            let earned = l.steps.filter { l.value >= $0 }.map { Milestone(id: "\(l.key)-\($0)", icon: l.icon, title: title($0), value: l.value, goal: $0) }
            let next = l.steps.first { l.value < $0 }.map { [Milestone(id: "\(l.key)-\($0)", icon: l.icon, title: title($0), value: l.value, goal: $0)] } ?? []
            return earned + next
        }
    }

    /// The grid on Records: each ladder's highest earned step and the
    /// next one up — the rest of the ladder is implied.
    static func keyMilestones(_ history: [Session]) -> [Milestone] {
        let all = milestones(history)
        return ladders(history).flatMap { l -> [Milestone] in
            let mine = all.filter { $0.id.hasPrefix(l.key + "-") }
            return [mine.last(where: \.earned), mine.first(where: { !$0.earned })].compactMap { $0 }
        }
    }

    /// The unearned milestone closest to done (by fraction), for the
    /// "next benchmark in reach" nudge.
    static func nextBenchmark(_ history: [Session]) -> Milestone? {
        milestones(history).filter { !$0.earned }.max { Double($0.value) / Double($0.goal) < Double($1.value) / Double($1.goal) }
    }

    // MARK: - Notifications

    struct Notice: Identifiable {
        var id: String
        var icon: String
        var title: String
        var body: String
        var at: Double // ms
        var screen: Screen
    }

    /// The in-app inbox, newest first: reviews, records set in the last
    /// two weeks, milestones crossed in the last month, a deload warning.
    /// Derived from data the app already has — nothing extra is stored
    /// except when you last looked (state `notifSeenAt`).
    static func notifications(_ history: [Session], weekly: WeeklyReviewCache?, monthly: MonthlyReportCache?) -> [Notice] {
        var out: [Notice] = []
        if let r = weekly {
            out.append(Notice(id: "weekly-\(r.week)", icon: "doc.text.magnifyingglass", title: "Weekly review ready",
                              body: String(r.text.prefix(120)), at: r.at, screen: .home))
        }
        if let r = monthly {
            out.append(Notice(id: "monthly-\(r.month)", icon: "calendar", title: "Monthly report ready",
                              body: "\(r.sum.count) sessions · \(r.sum.volume.formatted())kg lifted", at: r.at, screen: .home))
        }
        let sorted = history.sorted { $0.date < $1.date }
        let prCutoff = Helpers.daysAgoStr(13)
        for (i, s) in sorted.enumerated() where s.date >= prCutoff {
            for pr in Stats.detectPRs(s, Array(sorted[..<i])) {
                out.append(Notice(id: "pr-\(s.id)-\(pr.name)-\(pr.kind)", icon: "trophy.fill", title: "New record: \(pr.name)",
                                  body: "\(pr.kind == "weight" ? "Heaviest set" : "Est. 1RM") \(Helpers.fmtKg(pr.from)) → \(Helpers.fmtKg(pr.to))kg",
                                  at: at(s), screen: .records))
            }
        }
        let msCutoff = Helpers.daysAgoStr(29)
        for step in [10, 25, 50, 100, 250] where sorted.count >= step && sorted[step - 1].date >= msCutoff {
            out.append(Notice(id: "ms-sessions-\(step)", icon: "rosette", title: "Milestone: \(step) sessions",
                              body: "Logged on \(Helpers.fmtDate(sorted[step - 1].date)).", at: at(sorted[step - 1]), screen: .records))
        }
        if let d = Stats.deloadSignal(history) {
            out.append(Notice(id: "deload-\(Stats.mondayOf(Helpers.todayStr()))", icon: "exclamationmark.triangle.fill",
                              title: "Deload suggested", body: d.reason, at: Stats.dateMs(Stats.mondayOf(Helpers.todayStr())) * 1000, screen: .home))
        }
        return out.sorted { $0.at > $1.at }
    }

    /// When a session happened, in ms — its start time, else noon that
    /// day (Stats.dateMs is seconds at local noon).
    private static func at(_ s: Session) -> Double {
        s.startedAt > 0 ? s.startedAt : Stats.dateMs(s.date) * 1000
    }
}
