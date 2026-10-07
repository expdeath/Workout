import Foundation

/// MET-based calorie estimate — port of src/utils/calories.js. Computed
/// on the fly from session/health data; nothing is stored.
enum Calories {
    private static let metBySessionType: [String: Double] = [
        "Run": 9.8, "Cycle": 7.5, "Walk": 4.3, "Hike": 6.0, "Cardio": 7.0,
        "Active Recovery": 4.0, "Stretch & Mobility": 2.5,
        "Push": 5.0, "Pull": 5.0, "Legs": 5.0, "Full Body": 5.0, "Core": 5.0,
    ]
    private static let defaultMet = 4.0
    static let defaultBodyKg = 75.0

    /// Most recent known body weight across the health log, kg.
    static func latestBodyWeightKg(_ health: [HealthRow], fallback: Double = defaultBodyKg) -> Double {
        health.filter { ($0.weightKg ?? 0) > 0 }.max { $0.date < $1.date }?.weightKg ?? fallback
    }

    /// Estimated calories burned for one session.
    static func estimate(_ s: Session, bodyKg: Double = defaultBodyKg) -> Int {
        let type = s.plan.sessionType
        guard !type.isEmpty, type != "Rest Day" else { return 0 }
        let met = metBySessionType[type] ?? defaultMet
        let minutes = Double(s.durationMin ?? (s.plan.estTimeMin > 0 ? s.plan.estTimeMin : 0))
        guard minutes > 0 else { return 0 }
        return Int((met * bodyKg * minutes / 60).rounded())
    }

    /// { thisWeek, allTime } estimated-calorie totals across history.
    static func stats(_ history: [Session], bodyKg: Double = defaultBodyKg) -> (thisWeek: Int, allTime: Int) {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        var week = 0, all = 0
        for s in history {
            let k = estimate(s, bodyKg: bodyKg)
            all += k
            if let d = Helpers.noonDate(s.date), d >= weekAgo { week += k }
        }
        return (week, all)
    }
}
