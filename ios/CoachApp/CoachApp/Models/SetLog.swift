import Foundation

/// One logged set row. Strength sets carry weight/reps; cardio sets carry
/// time/dist instead; check-only sets (stretches/holds) carry neither and
/// rely on `done`. Mirrors the set shape in src/App.jsx / src/utils/helpers.js.
struct SetLog: Codable, Equatable {
    var weight: String = ""
    var reps: String = ""
    var done: Bool = false
    var time: String = ""
    var dist: String = ""
    /// '' | "easy" | "good" | "grind" — per-set effort tap (src/screens/Workout.jsx EFFORTS).
    var effort: String = ""

    init(weight: String = "", reps: String = "", done: Bool = false, time: String = "", dist: String = "", effort: String = "") {
        self.weight = weight; self.reps = reps; self.done = done
        self.time = time; self.dist = dist; self.effort = effort
    }

    /// Real quick-cardio sets (src/App.jsx logQuickCardio) are written
    /// as just `{ time, dist, done }` — no weight/reps/effort keys at
    /// all — so every field here must tolerate being absent, not just
    /// empty. Swift's synthesized Decodable does NOT fall back to a
    /// property's default value for a missing key (only Optional
    /// properties get that for free); it throws instead.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weight = try c.decodeIfPresent(String.self, forKey: .weight) ?? ""
        reps = try c.decodeIfPresent(String.self, forKey: .reps) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? ""
        dist = try c.decodeIfPresent(String.self, forKey: .dist) ?? ""
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? ""
    }

    /// Mirrors setLogged() in src/utils/helpers.js: a set counts once
    /// ticked done OR any number has been typed into it.
    var isLogged: Bool {
        done || !weight.isEmpty || !reps.isEmpty || !time.isEmpty || !dist.isEmpty
    }

    /// Mirrors fmtSet() in src/utils/helpers.js.
    var formatted: String {
        if !time.isEmpty || !dist.isEmpty {
            return [time.isEmpty ? nil : "\(time)min", dist.isEmpty ? nil : "\(dist)km"]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
        if weight.isEmpty && reps.isEmpty {
            return done ? "✓" : "—"
        }
        return "\(weight.isEmpty ? "?" : weight)kg×\(reps.isEmpty ? "?" : reps)"
    }
}
