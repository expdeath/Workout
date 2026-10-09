import Foundation

/// Long-term AI context builder — ports src/utils/aiContext.js. The
/// prompt already includes the last 6 sessions in full detail; this
/// compresses EVERYTHING OLDER into a compact summary — per-exercise
/// progression, weekly adherence, split balance, pain patterns, RPE
/// trend — so years of history fit in a few hundred tokens and old data
/// keeps steering today's plan.
enum AIContext {
    private static let maxChars = 1800

    private static func bestWeight(_ session: Session, _ exIndex: Int) -> Double? {
        guard exIndex < session.log.count else { return nil }
        var best: Double? = nil
        for s in session.log[exIndex] where s.isLogged {
            if let w = Double(s.weight), best == nil || w > best! { best = w }
        }
        return best
    }

    static func buildLongTermSummary(_ sessions: [Session]) -> String {
        guard sessions.count >= 5 else { return "" }
        var lines: [String] = []

        lines.append("\(sessions.count) sessions logged since \(sessions[0].date).")

        // Weekly adherence, last 8 weeks (oldest → newest)
        let weekMs: TimeInterval = 7 * 86400
        let now = Date().timeIntervalSince1970
        var weeks = [Int](repeating: 0, count: 8)
        for s in sessions {
            let age = now - Stats.dateMs(s.date)
            let w = Int(floor(age / weekMs))
            if w >= 0 && w < 8 { weeks[7 - w] += 1 }
        }
        lines.append("Sessions per week, last 8 weeks (oldest→newest): \(weeks.map(String.init).joined(separator: ", ")).")

        // Split balance, last 90 days
        let cutoff = now - 90 * 86400
        var split: [String: Int] = [:]
        for s in sessions {
            guard Stats.dateMs(s.date) >= cutoff else { continue }
            split[s.plan.sessionType.isEmpty ? "Other" : s.plan.sessionType, default: 0] += 1
        }
        let splitTxt = split.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        if !splitTxt.isEmpty { lines.append("Split last 90 days: \(splitTxt).") }

        // Per-exercise progression across ALL history
        struct Point { var date: String; var w: Double }
        var byExercise: [String: (name: String, points: [Point])] = [:]
        var order: [String] = []
        for s in sessions {
            for (i, ex) in s.plan.exercises.enumerated() {
                guard !ex.name.isEmpty, let w = bestWeight(s, i) else { continue }
                let key = ex.name.trimmingCharacters(in: .whitespaces).lowercased()
                if byExercise[key] == nil { byExercise[key] = (ex.name.trimmingCharacters(in: .whitespaces), []); order.append(key) }
                byExercise[key]!.points.append(Point(date: s.date, w: w))
            }
        }
        let top = byExercise.values.filter { $0.points.count >= 2 }.sorted { $0.points.count > $1.points.count }.prefix(12)
        if !top.isEmpty {
            lines.append("Exercise progression (first → latest, best, times done):")
            for e in top {
                let firstW = e.points.first!.w
                let last = e.points.last!
                let best = e.points.map(\.w).max()!
                lines.append("- \(e.name): \(fmt(firstW))kg → \(fmt(last.w))kg (best \(fmt(best))kg, \(e.points.count)x, last \(last.date))")
            }
        }

        // Recurring pain reports
        var pains: [String: Int] = [:]
        for s in sessions {
            let p = s.fin?.pain.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            guard !p.isEmpty else { continue }
            pains[p, default: 0] += 1
        }
        let painTxt = pains.sorted { $0.value > $1.value }.prefix(4).map { "\"\($0.key)\" x\($0.value)" }.joined(separator: ", ")
        if !painTxt.isEmpty { lines.append("Recurring pain reports: \(painTxt).") }

        // RPE trend
        let rpes = sessions.filter { $0.finished }.compactMap { $0.fin?.rpe }.map(Double.init)
        if rpes.count >= 6 {
            func avg(_ a: [Double]) -> Double { a.reduce(0, +) / Double(a.count) }
            let recent = avg(Array(rpes.suffix(5)))
            let prior = avg(Array(rpes.dropLast(5)))
            lines.append("Avg session RPE: last 5 = \(String(format: "%.1f", recent)), all prior = \(String(format: "%.1f", prior)).")
        }

        var out = lines.joined(separator: "\n")
        if out.count > maxChars {
            out = String(out.prefix(maxChars)) + "…"
        }
        return out
    }

    private static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }
}
