import Foundation

/// Date formatting shared across screens/sync — ports the relevant bits
/// of src/utils/helpers.js.
enum Helpers {
    static func todayStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    /// "2026-08-29" → "Sat, Aug 29" — mirrors fmtDate() in helpers.js.
    static func fmtDate(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let date = parser.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "EEE, MMM d"
        out.timeZone = .current
        return out.string(from: date)
    }

    // MARK: - Set-input sanitation — ports the clamp helpers in
    // src/utils/helpers.js. Clamp instead of reject: typos like
    // 1000kg become 200, so nothing silly reaches the log or the AI.

    static let maxWeightKg = 200.0
    static let maxReps = 30
    static let maxTimeMin = 300.0
    static let maxDistKm = 100.0

    private static func cleanDecimal(_ v: String, max: Double) -> String {
        var s = v.filter { $0.isNumber || $0 == "." }
        if let firstDot = s.firstIndex(of: ".") {
            let afterDot = s[s.index(after: firstDot)...].filter { $0 != "." }
            s = String(s[..<firstDot]) + "." + String(afterDot.prefix(2))
        }
        guard !s.isEmpty else { return "" }
        if let n = Double(s), n > max {
            return max.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(max)) : String(max)
        }
        return s
    }

    static func cleanWeight(_ v: String) -> String { cleanDecimal(v, max: maxWeightKg) }
    static func cleanTime(_ v: String) -> String { cleanDecimal(v, max: maxTimeMin) }
    static func cleanDist(_ v: String) -> String { cleanDecimal(v, max: maxDistKm) }

    static func cleanReps(_ v: String) -> String {
        let s = v.filter(\.isNumber)
        guard !s.isEmpty, let n = Int(s) else { return "" }
        return String(min(n, maxReps))
    }

    /// The date `n` days before todayStr(), same yyyy-MM-dd form —
    /// ports daysAgoStr() (used to backdate quick logs).
    static func daysAgoStr(_ n: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: d)
    }

    /// Client-side readiness estimate shown before the AI answers —
    /// ports quickReadiness() in helpers.js.
    static func quickReadiness(_ c: Checkin) -> Int {
        var s = 50
        s += (c.energy - 5) * 5
        switch c.sleep {
        case "Great": s += 15
        case "OK": s += 5
        case "Poor": s -= 15
        default: break
        }
        switch c.soreness {
        case "None": s += 10
        case "Light": s -= 5
        case "Very sore": s -= 20
        default: break
        }
        if c.backTight { s -= 8 }
        return max(5, min(98, s))
    }
}
