import Foundation

/// Pure training-history math — full port of src/utils/stats.js. Used by
/// the AI prompt builder (progression targets, health baselines, deload/
/// fatigue signals, muscle balance) and, in later phases, the Progress/
/// Records/History screens and the Home streak card.
enum Stats {
    private static let day: TimeInterval = 86400

    static func dateMs(_ iso: String) -> TimeInterval {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        guard let d = f.date(from: iso) else { return 0 }
        return d.timeIntervalSince1970 + 12 * 3600
    }

    // MARK: - Regex helper (mirrors JS's `re.exec(t)` capture groups)

    /// Returns capture groups (index 0 = whole match) for the first
    /// match, or nil. ICU regex syntax used by NSRegularExpression is
    /// close enough to JS's for every pattern ported here.
    static func firstMatch(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range) else { return nil }
        var groups: [String?] = []
        for i in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: text) { groups.append(String(text[r])) } else { groups.append(nil) }
        }
        return groups
    }

    private static func testRegex(_ pattern: String, _ text: String, caseInsensitive: Bool = true) -> Bool {
        firstMatch(pattern, in: text, caseInsensitive: caseInsensitive) != nil
    }

    // MARK: - Dates

    static func mondayOf(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        guard let d = f.date(from: iso) else { return iso }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let weekday = cal.component(.weekday, from: d) // 1=Sun...7=Sat
        let shift = (weekday + 5) % 7 // Mon=0 ... Sun=6
        let monday = cal.date(byAdding: .day, value: -shift, to: d) ?? d
        return f.string(from: monday)
    }

    static func todayIso() -> String { Helpers.todayStr() }

    // MARK: - Volume / best sets

    private static func bestSetWeight(_ session: Session, _ exIndex: Int) -> Double? {
        guard exIndex < session.log.count else { return nil }
        var best: Double? = nil
        for s in session.log[exIndex] where s.isLogged {
            if let w = Double(s.weight), best == nil || w > best! { best = w }
        }
        return best
    }

    private static func bestSetE1RM(_ session: Session, _ exIndex: Int) -> Double? {
        guard exIndex < session.log.count else { return nil }
        var best: Double? = nil
        for s in session.log[exIndex] where s.isLogged {
            if let e = epley1RM(s.weight, s.reps), best == nil || e > best! { best = e }
        }
        return best
    }

    static func sessionVolume(_ session: Session) -> Int {
        var vol = 0.0
        for ex in session.log {
            for s in ex where s.isLogged {
                if let w = Double(s.weight), let r = Double(s.reps) { vol += w * r }
            }
        }
        return Int(vol.rounded())
    }

    struct ExercisePoint { var date: String; var w: Double; var e: Double? }
    struct ExerciseSeriesEntry { var name: String; var points: [ExercisePoint] }

    /// Per-exercise series across all history, most-trained first.
    static func exerciseSeries(_ history: [Session]) -> [ExerciseSeriesEntry] {
        var map: [String: ExerciseSeriesEntry] = [:]
        var order: [String] = []
        for s in history {
            for (i, ex) in s.plan.exercises.enumerated() {
                guard !ex.name.isEmpty, let w = bestSetWeight(s, i) else { continue }
                let key = ex.name.trimmingCharacters(in: .whitespaces).lowercased()
                if map[key] == nil { map[key] = ExerciseSeriesEntry(name: ex.name.trimmingCharacters(in: .whitespaces), points: []); order.append(key) }
                map[key]!.points.append(ExercisePoint(date: s.date, w: w, e: bestSetE1RM(s, i)))
            }
        }
        return map.values.sorted { $0.points.count > $1.points.count }
    }

    struct WeeklyBucket { var start: String; var count: Int; var volume: Int }

    static func weeklyBuckets(_ history: [Session], n: Int = 8) -> [WeeklyBucket] {
        let thisMonday = mondayOf(todayIso())
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        var buckets: [WeeklyBucket] = []
        for i in stride(from: n - 1, through: 0, by: -1) {
            let start = f.string(from: Date(timeIntervalSince1970: dateMs(thisMonday) - Double(i) * 7 * day))
            buckets.append(WeeklyBucket(start: start, count: 0, volume: 0))
        }
        var index: [String: Int] = [:]
        for (i, b) in buckets.enumerated() { index[b.start] = i }
        for s in history {
            guard let i = index[mondayOf(s.date)] else { continue }
            buckets[i].count += 1
            buckets[i].volume += sessionVolume(s)
        }
        return buckets
    }

    struct ProgressionEntry { var name: String; var from: Double; var to: Double }

    static func progressions(_ history: [Session], days: Int = 7) -> [ProgressionEntry] {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * day
        var out: [ProgressionEntry] = []
        for ex in exerciseSeries(history) {
            let recent = ex.points.filter { dateMs($0.date) >= cutoff }
            let before = ex.points.filter { dateMs($0.date) < cutoff }
            guard !recent.isEmpty, !before.isEmpty else { continue }
            let to = recent.map(\.w).max()!
            let from = before.map(\.w).max()!
            if to > from { out.append(ProgressionEntry(name: ex.name, from: from, to: to)) }
        }
        return Array(out.sorted { ($0.to - $0.from) > ($1.to - $1.from) }.prefix(5))
    }

    static func weekStats(_ history: [Session], target: Int = 3) -> (thisWeek: Int, streak: Int) {
        var counts: [String: Int] = [:]
        for s in history { counts[mondayOf(s.date), default: 0] += 1 }
        let thisMonday = mondayOf(todayIso())
        let thisWeek = counts[thisMonday] ?? 0
        var streak = thisWeek >= target ? 1 : 0
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        var i = 1
        while true {
            let wk = f.string(from: Date(timeIntervalSince1970: dateMs(thisMonday) - Double(i) * 7 * day))
            if (counts[wk] ?? 0) >= target { streak += 1 } else { break }
            i += 1
        }
        return (thisWeek, streak)
    }

    struct LastPerformance { var date: String; var sets: [SetLog]; var repsRange: String }

    static func lastPerformance(_ history: [Session], _ exerciseName: String) -> LastPerformance? {
        let key = exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        for s in history.reversed() {
            guard let exI = s.plan.exercises.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key }) else { continue }
            let sets = (exI < s.log.count ? s.log[exI] : []).filter { $0.isLogged }
            if !sets.isEmpty {
                return LastPerformance(date: s.date, sets: sets, repsRange: s.plan.exercises[exI].reps)
            }
        }
        return nil
    }

    /// +2.5kg if every set hit the top of the rep range (or +5kg if
    /// every set was tapped "easy"), unless any set was a "grind".
    static func suggestNextWeight(_ lastPerf: LastPerformance?, _ repsRange: String) -> Double? {
        guard let lastPerf, !lastPerf.sets.isEmpty else { return nil }
        let topStr = repsRange.components(separatedBy: CharacterSet(charactersIn: "-–")).last ?? ""
        guard let top = Int(topStr.trimmingCharacters(in: .whitespaces)), top != 0 else { return nil }
        let weights = lastPerf.sets.compactMap { Double($0.weight) }
        guard !weights.isEmpty else { return nil }
        let allTopped = lastPerf.sets.allSatisfy { (Int($0.reps) ?? 0) >= top }
        guard allTopped else { return nil }
        let efforts = lastPerf.sets.map(\.effort).filter { !$0.isEmpty }
        if efforts.contains("grind") { return nil }
        let jump: Double = (efforts.count == lastPerf.sets.count && efforts.allSatisfy { $0 == "easy" }) ? 5 : 2.5
        return min(weights.max()! + jump, 200)
    }

    static func epley1RM(_ weight: String, _ reps: String) -> Double? {
        guard let w = Double(weight), let r = Int(reps), w > 0, r > 0 else { return nil }
        return (w * (1 + Double(r - 1) / 30) * 10).rounded() / 10
    }

    struct ExercisePR {
        var name: String
        var count: Int = 0
        var weight: (w: Double, reps: String, date: String)?
        var e1rm: (v: Double, date: String)?
    }

    /// All-time records per exercise, most-trained first.
    static func prRecords(_ history: [Session]) -> [ExercisePR] {
        var map: [String: ExercisePR] = [:]
        var order: [String] = []
        for s in history {
            for (i, ex) in s.plan.exercises.enumerated() {
                guard !ex.name.isEmpty, i < s.log.count else { continue }
                let key = ex.name.trimmingCharacters(in: .whitespaces).lowercased()
                for set in s.log[i] {
                    guard set.isLogged, let w = Double(set.weight), w > 0 else { continue }
                    if map[key] == nil { map[key] = ExercisePR(name: ex.name.trimmingCharacters(in: .whitespaces)); order.append(key) }
                    map[key]!.count += 1
                    if map[key]!.weight == nil || w > map[key]!.weight!.w {
                        map[key]!.weight = (w, set.reps, s.date)
                    }
                    if let e = epley1RM(set.weight, set.reps), map[key]!.e1rm == nil || e > map[key]!.e1rm!.v {
                        map[key]!.e1rm = (e, s.date)
                    }
                }
            }
        }
        return map.values.sorted { $0.count > $1.count }
    }

    /// New records set by `session` vs `prior` history (must not
    /// contain the session). First-time exercises don't count.
    static func detectPRs(_ session: Session, _ prior: [Session]) -> [PRRecord] {
        var before: [String: ExercisePR] = [:]
        for r in prRecords(prior) { before[r.name.lowercased()] = r }
        var out: [PRRecord] = []
        for rec in prRecords([session]) {
            guard let old = before[rec.name.lowercased()] else { continue }
            if let rw = rec.weight, let ow = old.weight, rw.w > ow.w {
                out.append(PRRecord(name: rec.name, kind: "weight", from: ow.w, to: rw.w))
            } else if let re = rec.e1rm, let oe = old.e1rm, re.v > oe.v {
                out.append(PRRecord(name: rec.name, kind: "e1rm", from: oe.v, to: re.v))
            }
        }
        return out
    }

    /// Deterministic progression targets for the AI prompt.
    static func progressionTargets(_ history: [Session], max: Int = 10) -> String {
        var out: [String] = []
        for ex in exerciseSeries(history).prefix(max) {
            guard let lp = lastPerformance(history, ex.name) else { continue }
            let target = suggestNextWeight(lp, lp.repsRange)
            let lastTxt = lp.sets.map { s -> String in
                s.formatted + (s.effort.isEmpty ? "" : "(\(s.effort))")
            }.joined(separator: " · ")
            let targetTxt = target != nil ? " → ready for \(fmtKg(target!))kg (all reps at top of range)" : " → hold weight, push reps"
            out.append("- \(ex.name): last \(lastTxt)\(targetTxt)")
        }
        return out.joined(separator: "\n")
    }

    private static func fmtKg(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    // MARK: - Health parsing

    struct HealthNumbers {
        var hrv, rhr, steps, sleepH, vo2max, kcal, exerciseMin, distKm, spo2, respRate, wristC: Double?
    }

    /// Pull HRV / resting-HR / steps / sleep / VO2max / energy / SpO2 …
    /// numbers out of a free-form health string (Watch shortcut payload).
    static func parseHealthNumbers(_ text: String?) -> HealthNumbers {
        let t = text ?? ""
        func num(_ pattern: String, clampLow: Double? = nil, clampHigh: Double? = nil) -> Double? {
            guard let g = firstMatch(pattern, in: t), let s = g[safe: 1] ?? nil else { return nil }
            guard let n = Double(s.replacingOccurrences(of: ",", with: "")) else { return nil }
            if let lo = clampLow, let hi = clampHigh, !(n >= lo && n <= hi) { return nil }
            return n
        }
        let hrv = num(#"hrv[^\d]{0,14}([\d.]+)"#)
        let rhr = num(#"(?:rhr|resting[^\d]{0,12}(?:heart[^\d]{0,8})?(?:rate)?)[^\d]{0,14}([\d.]+)"#)
        let stepsRaw = firstMatch(#"\bsteps[^\d]{0,14}([\d,]+(?:\.\d+)?)"#, in: t)?[safe: 1] ?? nil
        let steps = stepsRaw.flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }.map { $0.rounded() }

        var sleepH: Double? = nil
        if let slLabel = firstMatch(#"sleep\s*hrs?:?\s*([\d.]+)"#, in: t), let numStr = slLabel[safe: 1] ?? nil, let n = Double(numStr) {
            var sh = n
            if sh > 1200 { sh /= 3600 } else if sh > 20 { sh /= 60 }
            if sh > 11 { sh /= 2 }
            sleepH = (sh > 0 && sh < 20) ? (sh * 10).rounded() / 10 : nil
        }
        if sleepH == nil, !testRegex(#"sleep\s*hrs?:"#, t) {
            if let sl = firstMatch(#"sle(?:ep|pt)[^\d]{0,14}(\d{1,2})(?::(\d{2})|\s*h(?:ours?|rs?)?(?:\s*(\d{1,2})\s*m)?|(\.\d+))?"#, in: t),
               let hStr = sl[safe: 1] ?? nil, var sh = Double(hStr) {
                if let mm = sl[safe: 2] ?? nil, let m = Double(mm) { sh += m / 60 }
                else if let hm = sl[safe: 3] ?? nil, let m = Double(hm) { sh += m / 60 }
                else if let frac = sl[safe: 4] ?? nil, let f = Double(frac) { sh += f }
                sleepH = (sh > 0 && sh < 20) ? (sh * 10).rounded() / 10 : nil
            }
        }

        let spo2: Double? = {
            guard let n = num(#"spo2[^\d]{0,14}([\d.]+)"#) else { return nil }
            let pct = n <= 1 ? (n * 1000).rounded() / 10 : n
            return (pct >= 70 && pct <= 100) ? pct : nil
        }()

        return HealthNumbers(
            hrv: hrv, rhr: rhr, steps: steps, sleepH: sleepH,
            vo2max: num(#"vo2\s*max[^\d]{0,14}([\d.]+)"#, clampLow: 10, clampHigh: 90),
            kcal: num(#"(?:active\s*kcal|active\s*energy)[^\d]{0,14}([\d,]+(?:\.\d+)?)"#, clampLow: 1, clampHigh: 8000),
            exerciseMin: num(#"exercise\s*min[^\d]{0,14}([\d,]+(?:\.\d+)?)"#, clampLow: 1, clampHigh: 1000),
            distKm: num(#"distance\s*km[^\d]{0,14}([\d.]+)"#, clampLow: 0.1, clampHigh: 200),
            spo2: spo2,
            respRate: num(#"resp\s*rate[^\d]{0,14}([\d.]+)"#, clampLow: 5, clampHigh: 40),
            wristC: num(#"wrist\s*temp[^\d]{0,14}([\d.]+)"#, clampLow: 20, clampHigh: 45)
        )
    }

    struct HealthBaseline { var hrv, rhr, sleepH, respRate, wristC: Double? }

    /// 30-day baselines (each needs ≥3 samples).
    static func healthBaseline(_ history: [Session], _ healthLog: [HealthRow], days: Int = 30) -> HealthBaseline {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * day
        var acc: [String: [Double]] = ["hrv": [], "rhr": [], "sleepH": [], "respRate": [], "wristC": []]
        let range: [String: (Double, Double)] = ["hrv": (5, 300), "rhr": (30, 120), "sleepH": (2, 16), "respRate": (5, 40), "wristC": (30, 42)]
        func take(_ key: String, _ v: Double?) {
            guard let v, let r = range[key], v >= r.0, v <= r.1 else { return }
            acc[key, default: []].append(v)
        }
        var seen = Set<String>()
        for h in healthLog {
            guard dateMs(h.date) >= cutoff else { continue }
            seen.insert(h.date)
            take("hrv", h.hrv); take("rhr", h.rhr); take("sleepH", h.sleepH)
            take("respRate", h.respRate); take("wristC", h.wristC)
        }
        for s in history {
            guard dateMs(s.date) >= cutoff, !seen.contains(s.date) else { continue }
            let n = parseHealthNumbers(s.checkin?.health)
            take("hrv", n.hrv); take("rhr", n.rhr)
        }
        func avg(_ key: String) -> Double? {
            let a = acc[key] ?? []
            guard a.count >= 3 else { return nil }
            return (a.reduce(0, +) / Double(a.count) * 10).rounded() / 10
        }
        var out = HealthBaseline(hrv: avg("hrv"), rhr: avg("rhr"), sleepH: avg("sleepH"), respRate: avg("respRate"), wristC: avg("wristC"))
        out.hrv = out.hrv.map { $0.rounded() }
        out.rhr = out.rhr.map { $0.rounded() }
        return out
    }

    private static func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    /// Parsed health numbers → one compact human/AI-readable line.
    static func fmtHealthLine(_ n: HealthNumbers) -> String {
        var bits: [String] = []
        if let v = n.hrv { bits.append("HRV \(fmtKg(r1(v)))ms") }
        if let v = n.rhr { bits.append("RHR \(Int(v.rounded()))") }
        if let v = n.sleepH { bits.append("sleep \(fmtKg(v))h") }
        if let v = n.steps { bits.append("\(Int(v)) steps") }
        if let v = n.vo2max { bits.append("VO2max \(fmtKg(r1(v)))") }
        if let v = n.kcal { bits.append("\(Int(v.rounded()))kcal active") }
        if let v = n.exerciseMin { bits.append("\(Int(v.rounded()))min exercise") }
        if let v = n.distKm { bits.append("\(fmtKg(r1(v)))km") }
        if let v = n.spo2 { bits.append("SpO2 \(fmtKg(r1(v)))%") }
        if let v = n.respRate { bits.append("RR \(fmtKg(r1(v)))/min") }
        if let v = n.wristC { bits.append("wrist \(fmtKg(r1(v)))°C") }
        return bits.joined(separator: " · ")
    }

    /// Text block of the last n days of Watch data, for the AI prompt.
    static func healthTrend(_ healthLog: [HealthRow], n: Int = 7) -> String {
        let rows = Array(healthLog.suffix(n))
        guard rows.count >= 2 else { return "" }
        return rows.map { h -> String in
            var bits: [String] = []
            if let v = h.hrv { bits.append("HRV \(fmtKg(r1(v)))ms") }
            if let v = h.rhr { bits.append("RHR \(Int(v.rounded()))") }
            if let v = h.sleepH { bits.append("sleep \(fmtKg(r1(v)))h") }
            if let v = h.weightKg { bits.append("bodyweight \(fmtKg(r1(v)))kg") }
            if let v = h.steps { bits.append("\(Int(v)) steps") }
            if let v = h.vo2max { bits.append("VO2max \(fmtKg(r1(v)))") }
            if let v = h.respRate { bits.append("RR \(fmtKg(r1(v)))/min") }
            if let v = h.wristC { bits.append("wrist \(fmtKg(r1(v)))°C") }
            let joined = bits.joined(separator: " · ")
            return "\(h.date): \(joined.isEmpty ? (h.raw ?? "—") : joined)"
        }.joined(separator: "\n")
    }

    /// Volume + average RPE rising across 3 consecutive weeks → message
    /// for the AI prompt, or nil.
    static func fatigueSignal(_ history: [Session]) -> String? {
        let weeks = Array(weeklyBuckets(history, n: 4).prefix(3))
        guard weeks.allSatisfy({ $0.count >= 2 }) else { return nil }
        func rpeOf(_ start: String) -> Double? {
            let vals = history.filter { mondayOf($0.date) == start && $0.finished && $0.fin != nil }.map { Double($0.fin!.rpe) }
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }
        let rpes = weeks.map { rpeOf($0.start) }
        guard rpes.allSatisfy({ $0 != nil }) else { return nil }
        let r = rpes.map { $0! }
        let volUp = weeks[0].volume < weeks[1].volume && weeks[1].volume < weeks[2].volume
        let rpeUp = r[0] < r[1] && r[1] < r[2]
        guard volUp && rpeUp else { return nil }
        let volStr = weeks.map { String($0.volume) }.joined(separator: "→")
        let rpeStr = r.map { String(format: "%.1f", $0) }.joined(separator: "→")
        return "Training volume and average session RPE have both risen for 3 consecutive weeks (volume \(volStr)kg, RPE \(rpeStr)). Fatigue may be accumulating — consider a lighter session or deload if today's readiness is not clearly good."
    }

    struct StalledLift { var name: String; var weight: Double }

    static func stalledProgressions(_ history: [Session], days: Int = 35) -> [StalledLift] {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * day
        var out: [StalledLift] = []
        for ex in exerciseSeries(history) {
            let recent = ex.points.filter { dateMs($0.date) >= cutoff }
            guard recent.count >= 3 else { continue }
            let last3 = recent.suffix(3).map(\.w)
            let a = last3[0], b = last3[1], c = last3[2]
            if c <= a && c <= b { out.append(StalledLift(name: ex.name, weight: c)) }
        }
        return out
    }

    struct DeloadSignal { var reason: String }

    static func deloadSignal(_ history: [Session]) -> DeloadSignal? {
        if let fatigue = fatigueSignal(history) {
            _ = fatigue
            return DeloadSignal(reason: "Volume and session effort have both climbed for 3 straight weeks. A lighter week now (−30-40% volume, nothing near failure) usually buys the next PR.")
        }
        let stalled = stalledProgressions(history)
        let weeks = Array(weeklyBuckets(history, n: 4).prefix(3))
        let consistent = weeks.allSatisfy { $0.count >= 3 }
        if consistent && stalled.count >= 2 {
            let names = stalled.prefix(3).map(\.name).joined(separator: ", ")
            let verb = stalled.count > 1 ? "have" : "has"
            return DeloadSignal(reason: "\(names) \(verb) stopped progressing despite consistent training — a classic sign accumulated fatigue is masking fitness. Consider a deload week (−30-40% volume, no failure), then rebuild.")
        }
        return nil
    }

    // MARK: - Muscle-group tagging

    private static let muscleRules: [(String, String)] = [
        ("Cardio", #"bike|cycling|treadmill|stair|elliptical|jump rope|sprint|incline walk|\berg\b|swim|\brun(?:ning)?\b|\bjogg?(?:ing)?\b|\brower\b|row(?:ing)?\s*machine|cross[- ]?trainer|air ?dyne|assault ?bike|brisk walk|walking pad|\bhike\b|hiking|\bruck(?:ing)?\b|\bcardio\b"#),
        ("Core", #"plank|crunch|\babs?\b|core|russian|leg raise|knee raise|dead bug|pallof|rollout|woodchop"#),
        ("Legs", #"squat|\bleg\b|lunge|calf|hamstring|quad|glute|hip thrust|\brdl\b|romanian|adductor|abductor|step[- ]?up|nordic|kettlebell swing|\bkb swing\b"#),
        ("Back", #"\brows?\b|rowing|pulldown|pull[- ]?down|pull[- ]?up|chin[- ]?up|\blats?\b|deadlift|shrug|back extension|face pull|hyperextension"#),
        ("Shoulders", #"shoulder|overhead|\bohp\b|lateral raise|side raise|rear delt|delt|arnold|military|upright"#),
        ("Chest", #"bench|chest|\bpecs?\b|\bfly\b|flye|dips?\b|push[- ]?up|crossover|incline.*press"#),
        ("Arms", #"curl|tricep|bicep|pushdown|push[- ]?down|extension|skull|hammer|preacher|kickback|forearm|wrist"#),
    ]

    static func muscleGroupOf(_ name: String?) -> String {
        let n = name ?? ""
        for (group, pattern) in muscleRules where testRegex(pattern, n) { return group }
        return "Other"
    }

    static func isCardio(_ name: String?) -> Bool { muscleGroupOf(name) == "Cardio" }

    private static let stretchPattern = #"stretch|mobility|cat[- ]?cow|world'?s greatest|90.?90|couch|floss|thoracic|opener|pigeon|pose|yoga|foam roll|dead ?bug|bird ?dog|hollow|plank|cobra|down(?:ward)? dog|hip (?:switch|circle|opener)|breathing"#

    static func logMode(_ name: String?, _ sessionType: String?) -> String {
        if isCardio(name) { return "cardio" }
        if testRegex(stretchPattern, name ?? "") { return "check" }
        if testRegex(#"stretch|mobility|recovery"#, sessionType ?? "") { return "check" }
        return "strength"
    }

    struct MuscleBalanceEntry { var group: String; var sets: Int; var volume: Int; var lastDaysAgo: Int? }

    static func muscleBalance(_ history: [Session], days: Int = 14) -> [MuscleBalanceEntry] {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * day
        struct Acc { var sets = 0; var volume = 0.0; var last: Double? = nil }
        var map: [String: Acc] = [:]
        for s in history {
            for (i, ex) in s.plan.exercises.enumerated() {
                guard i < s.log.count else { continue }
                let done = s.log[i].filter { $0.isLogged }
                guard !done.isEmpty else { continue }
                let group = muscleGroupOf(ex.name)
                guard group != "Other", group != "Cardio" else { continue }
                var g = map[group] ?? Acc()
                let ms = dateMs(s.date)
                if g.last == nil || ms > g.last! { g.last = ms }
                if ms >= cutoff {
                    g.sets += done.count
                    for set in done {
                        if let w = Double(set.weight), let r = Double(set.reps) { g.volume += w * r }
                    }
                }
                map[group] = g
            }
        }
        return map.map { (group, g) in
            MuscleBalanceEntry(
                group: group, sets: g.sets, volume: Int(g.volume.rounded()),
                lastDaysAgo: g.last.map { max(0, Int(((Date().timeIntervalSince1970 - $0) / day).rounded())) }
            )
        }.sorted { $0.sets > $1.sets }
    }

    static func muscleGapNote(_ history: [Session]) -> String {
        let bal = muscleBalance(history)
        guard !bal.isEmpty else { return "" }
        let line = bal.map { g -> String in
            let ago = (g.lastDaysAgo ?? 0) >= 7 ? " (last \(g.lastDaysAgo!)d ago)" : ""
            return "\(g.group) \(g.sets) sets\(ago)"
        }.joined(separator: ", ")
        let gaps = bal.filter { ($0.lastDaysAgo ?? 0) >= 10 }.map(\.group)
        var out = "Muscle balance last 14 days: \(line)."
        if !gaps.isEmpty { out += " NOT TRAINED IN 10+ DAYS: \(gaps.joined(separator: ", ")) — bias today's selection toward the gap if recovery allows." }
        return out
    }

    static let muscleFixTips: [String: String] = [
        "Legs": "Leg Press, Romanian Deadlift, Walking Lunges",
        "Back": "Lat Pulldown, Chest Supported Row, Face Pull",
        "Shoulders": "Machine Shoulder Press, Cable Lateral Raise",
        "Chest": "Flat Dumbbell Press, Incline Machine Press",
        "Arms": "Cable Curl, Rope Tricep Pushdown",
        "Core": "Plank, Cable Crunch, Hanging Knee Raise",
    ]

    static func biggestMuscleGap(_ history: [Session]) -> (group: String, lastDaysAgo: Int)? {
        let bal = muscleBalance(history).filter { ($0.lastDaysAgo ?? -1) >= 10 }
        guard let worst = bal.max(by: { $0.lastDaysAgo! < $1.lastDaysAgo! }) else { return nil }
        return (worst.group, worst.lastDaysAgo!)
    }

    // MARK: - Recovery caution ("make it harder" nudge)

    static func recoveryCaution(_ checkin: Checkin?, _ history: [Session], _ healthLog: [HealthRow]) -> String? {
        var bits: [String] = []
        if testRegex("poor", checkin?.sleep ?? "") { bits.append("sleep was poor last night") }
        let today = parseHealthNumbers(checkin?.health)
        if let sh = today.sleepH, sh < 6, bits.isEmpty { bits.append("you only slept \(fmtKg(sh))h") }
        let base = healthBaseline(history, healthLog)
        if let t = today.hrv, let b = base.hrv {
            let d = Int((((t - b) / b) * 100).rounded())
            if d <= -10 { bits.append("HRV is \(abs(d))% below your 30-day normal") }
        }
        if let t = today.rhr, let b = base.rhr {
            let d = Int((((t - b) / b) * 100).rounded())
            if d >= 7 { bits.append("resting heart rate is running a bit high") }
        }
        if let t = today.respRate, let b = base.respRate, (t - b) / b >= 0.1 {
            bits.append("your overnight breathing rate is running high")
        }
        if let t = today.wristC, let b = base.wristC, t - b >= 0.4 {
            bits.append("wrist temperature is above your normal — a common early illness sign")
        }
        if testRegex("very sore", checkin?.soreness ?? "") { bits.append("you're still quite sore") }
        if fatigueSignal(history) != nil { bits.append("volume and effort have been climbing for a few weeks") }
        guard !bits.isEmpty else { return nil }
        let list = bits.count > 1 ? bits.dropLast().joined(separator: ", ") + " and " + bits.last! : bits[0]
        return "Heads-up: \(list). Extra work is your call — maybe keep a rep or two in the tank."
    }

    // MARK: - Monthly / weekly reports

    struct MonthSummary: Codable {
        var month: String
        var count: Int; var prevCount: Int
        var volume: Int; var prevVolume: Int
        var split: String
        var avgRpe: Double?
        var progressions: String
        var sleepAvg: Double?; var sleepPrev: Double?
        var rhrAvg: Double?; var rhrPrev: Double?
        var hrvAvg: Double?
        var vo2Avg: Double?; var vo2Prev: Double?
        var weightStart: Double?; var weightEnd: Double?
    }

    static func monthSummary(_ history: [Session], _ healthLog: [HealthRow], ym: String) -> MonthSummary? {
        let parts = ym.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let (y, m) = (parts[0], parts[1])
        var comps = DateComponents(); comps.year = y; comps.month = m - 1; comps.day = 15
        let prevDate = Calendar(identifier: .gregorian).date(from: comps) ?? Date()
        let prevCal = Calendar(identifier: .gregorian)
        let prevY = prevCal.component(.year, from: prevDate), prevM = prevCal.component(.month, from: prevDate)
        let prevYm = "\(prevY)-\(String(format: "%02d", prevM))"

        let sessions = history.filter { $0.date.hasPrefix(ym) }
        guard !sessions.isEmpty else { return nil }
        let prevSessions = history.filter { $0.date.hasPrefix(prevYm) }

        let volume = sessions.reduce(0) { $0 + sessionVolume($1) }
        let prevVolume = prevSessions.reduce(0) { $0 + sessionVolume($1) }

        var ups: [String] = []
        for ex in exerciseSeries(history) {
            let inPts = ex.points.filter { $0.date.hasPrefix(ym) }
            let before = ex.points.filter { $0.date < "\(ym)-01" }
            guard !inPts.isEmpty, !before.isEmpty else { continue }
            let to = inPts.map(\.w).max()!, from = before.map(\.w).max()!
            if to > from { ups.append("\(ex.name) \(fmtKg(from))→\(fmtKg(to))kg") }
        }

        var split: [String: Int] = [:]
        for s in sessions { split[s.plan.sessionType.isEmpty ? "Other" : s.plan.sessionType, default: 0] += 1 }
        func avg(_ arr: [Double]) -> Double? { arr.isEmpty ? nil : (arr.reduce(0, +) / Double(arr.count) * 10).rounded() / 10 }
        let hRows = healthLog.filter { $0.date.hasPrefix(ym) }
        let hPrev = healthLog.filter { $0.date.hasPrefix(prevYm) }
        func pick(_ rows: [HealthRow], _ key: KeyPath<HealthRow, Double?>) -> [Double] { rows.compactMap { $0[keyPath: key] }.filter { $0 > 0 } }
        let weights = pick(hRows, \.weightKg)
        let rpes = sessions.compactMap { $0.fin?.rpe }.map(Double.init)

        return MonthSummary(
            month: ym, count: sessions.count, prevCount: prevSessions.count,
            volume: volume, prevVolume: prevVolume,
            split: split.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "),
            avgRpe: avg(rpes),
            progressions: ups.prefix(6).joined(separator: ", ").isEmpty ? "none" : ups.prefix(6).joined(separator: ", "),
            sleepAvg: avg(pick(hRows, \.sleepH)), sleepPrev: avg(pick(hPrev, \.sleepH)),
            rhrAvg: avg(pick(hRows, \.rhr)), rhrPrev: avg(pick(hPrev, \.rhr)),
            hrvAvg: avg(pick(hRows, \.hrv)),
            vo2Avg: avg(pick(hRows, \.vo2max)), vo2Prev: avg(pick(hPrev, \.vo2max)),
            weightStart: weights.first, weightEnd: weights.last
        )
    }

    struct WeekSummary { var count: Int; var lines: String; var progressions: String }

    static func lastWeekSummary(_ history: [Session]) -> WeekSummary? {
        let cutoff = Date().timeIntervalSince1970 - 7 * day
        let recent = history.filter { dateMs($0.date) >= cutoff }
        guard !recent.isEmpty else { return nil }
        let lines = recent.map { s -> String in
            let vol = sessionVolume(s)
            let notFinished = s.finished ? "" : " (not finished)"
            let rpe = s.fin.map { String($0.rpe) } ?? "?"
            let pain = (s.fin?.pain.isEmpty == false) ? ", pain: \(s.fin!.pain)" : ""
            let volTxt = vol > 0 ? ", volume \(vol)kg" : ""
            return "\(s.date) \(s.plan.sessionType)\(notFinished) — RPE \(rpe)\(pain)\(volTxt)"
        }
        let ups = progressions(history, days: 7).map { "\($0.name) \(fmtKg($0.from))→\(fmtKg($0.to))kg" }
        return WeekSummary(count: recent.count, lines: lines.joined(separator: "\n"), progressions: ups.isEmpty ? "none" : ups.joined(separator: ", "))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
