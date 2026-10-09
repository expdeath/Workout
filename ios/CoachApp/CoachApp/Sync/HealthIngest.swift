import Foundation

/// Typed-in / pasted health text → today's check-in and health row — port
/// of src/utils/healthIngest.js (storeTodaysHealth, looksLikeHealthData,
/// reparseHealthRows).
enum HealthIngest {
    private static let key = "healthText-"

    /// Health text received for today (Apple Health, the inbox or a paste), or "".
    static func todaysText() -> String {
        if case .string(let t)? = Cloud.shared.stateValue(key + Helpers.todayStr()) { return t }
        return ""
    }

    /// Persist health text for today: the check-in prefill, plus every
    /// number it carries on today's health row. Returns the stored text.
    @discardableResult
    static func storeToday(_ text: String) -> String {
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !t.isEmpty else { return t }
        Cloud.shared.setState(key + Helpers.todayStr(), .string(t))
        record(t)
        return t
    }

    /// Only the fields this payload carries — a partial payload must not
    /// null out values an earlier one delivered.
    private static func record(_ text: String) {
        let n = Stats.parseHealthNumbers(text)
        let nums = [n.hrv, n.rhr, n.steps, n.sleepH, n.vo2max, n.kcal, n.exerciseMin, n.distKm, n.spo2, n.respRate, n.wristC]
        guard nums.contains(where: { ($0 ?? 0) != 0 }) else { return }
        LocalStore.shared.mergeHealth(HealthRow(
            date: Helpers.todayStr(), hrv: n.hrv, rhr: n.rhr, steps: n.steps, sleepH: n.sleepH,
            respRate: n.respRate, wristC: n.wristC, vo2max: n.vo2max, kcal: n.kcal,
            exerciseMin: n.exerciseMin, distKm: n.distKm, spo2: n.spo2, raw: String(text.prefix(300))
        ))
    }

    /// Heuristic: does clipboard text look like watch/health data?
    static func looksLikeHealthData(_ text: String?) -> Bool {
        guard let text, !text.isEmpty, text.count <= 600 else { return false }
        return text.range(of: #"\b(hrv|rhr|steps|sleep|bpm|resting|heart|vo2|spo2|kcal)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            && text.contains(where: \.isNumber)
    }

    /// Re-parse every stored raw payload with the current parser and fill
    /// fields the row is missing (and repair sleep rows stored before the
    /// double-source dedupe), so parser upgrades reach already-ingested days.
    static func reparseRows() {
        for r in LocalStore.shared.backup.health {
            guard let raw = r.raw else { continue }
            let n = Stats.parseHealthNumbers(raw)
            func fill(_ cur: Double?, _ v: Double?, repair: Bool = false) -> Double? {
                guard let v, v != 0, cur == nil || repair else { return nil }
                return v
            }
            let patch = HealthRow(
                date: r.date, hrv: fill(r.hrv, n.hrv), rhr: fill(r.rhr, n.rhr), steps: fill(r.steps, n.steps),
                sleepH: fill(r.sleepH, n.sleepH, repair: (r.sleepH ?? 0) > 11),
                respRate: fill(r.respRate, n.respRate), wristC: fill(r.wristC, n.wristC), vo2max: fill(r.vo2max, n.vo2max),
                kcal: fill(r.kcal, n.kcal), exerciseMin: fill(r.exerciseMin, n.exerciseMin), distKm: fill(r.distKm, n.distKm),
                spo2: fill(r.spo2, n.spo2)
            )
            if HealthRow.metricKeys.contains(where: { patch[keyPath: $0] != nil }) { LocalStore.shared.mergeHealth(patch) }
        }
    }
}
