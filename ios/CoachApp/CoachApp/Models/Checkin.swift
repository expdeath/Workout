import Foundation

/// Mirrors the `ci` state shape in src/App.jsx (the morning check-in).
struct Checkin: Codable, Equatable {
    var energy: Int = 7
    var sleep: String = "OK"
    var soreness: String = "None"
    var soreAreas: String = ""
    var backTight: Bool = false
    /// Kept as a string (not Int) to match the web app — see
    /// parseInt(checkin.timeAvail, 10) call sites in gemini.js.
    var timeAvail: String = "60"
    var wish: String = ""
    var health: String? = nil
    var bodyKg: String = ""
    var notes: String = ""
    var prioritizeMuscle: String = ""

    init(energy: Int = 7, sleep: String = "OK", soreness: String = "None", soreAreas: String = "", backTight: Bool = false, timeAvail: String = "60", wish: String = "", health: String? = nil, bodyKg: String = "", notes: String = "", prioritizeMuscle: String = "") {
        self.energy = energy; self.sleep = sleep; self.soreness = soreness; self.soreAreas = soreAreas
        self.backTight = backTight; self.timeAvail = timeAvail; self.wish = wish; self.health = health
        self.bodyKg = bodyKg; self.notes = notes; self.prioritizeMuscle = prioritizeMuscle
    }

    /// Older synced check-ins can predate a field added later (e.g.
    /// `prioritizeMuscle`, added alongside the muscle-gap nudge) — those
    /// keys are simply absent from that JSON, not empty, so every
    /// non-Optional field here needs a decodeIfPresent fallback.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energy = try c.decodeIfPresent(Int.self, forKey: .energy) ?? 7
        sleep = try c.decodeIfPresent(String.self, forKey: .sleep) ?? "OK"
        soreness = try c.decodeIfPresent(String.self, forKey: .soreness) ?? "None"
        soreAreas = try c.decodeIfPresent(String.self, forKey: .soreAreas) ?? ""
        backTight = try c.decodeIfPresent(Bool.self, forKey: .backTight) ?? false
        timeAvail = try c.decodeIfPresent(String.self, forKey: .timeAvail) ?? "60"
        wish = try c.decodeIfPresent(String.self, forKey: .wish) ?? ""
        health = try c.decodeIfPresent(String.self, forKey: .health)
        bodyKg = try c.decodeIfPresent(String.self, forKey: .bodyKg) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        prioritizeMuscle = try c.decodeIfPresent(String.self, forKey: .prioritizeMuscle) ?? ""
    }
}

/// Mirrors the `fin` state shape in src/App.jsx (post-session rating).
struct FinishInfo: Codable, Equatable {
    var rpe: Int = 7
    var pain: String = ""
    var feedback: String = ""

    init(rpe: Int = 7, pain: String = "", feedback: String = "") {
        self.rpe = rpe; self.pain = pain; self.feedback = feedback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rpe = try c.decodeIfPresent(Int.self, forKey: .rpe) ?? 7
        pain = try c.decodeIfPresent(String.self, forKey: .pain) ?? ""
        feedback = try c.decodeIfPresent(String.self, forKey: .feedback) ?? ""
    }
}

/// Mirrors a PR entry returned by detectPRs() in src/utils/stats.js.
/// Always constructed with all four fields together on the JS side, but
/// kept lenient anyway — one malformed PR entry must not fail the whole
/// session (and the session's whole containing array) to decode.
struct PRRecord: Codable, Equatable {
    var name: String = ""
    var kind: String = ""
    var from: Double = 0
    var to: Double = 0

    init(name: String = "", kind: String = "", from: Double = 0, to: Double = 0) {
        self.name = name; self.kind = kind; self.from = from; self.to = to
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        from = try c.decodeIfPresent(Double.self, forKey: .from) ?? 0
        to = try c.decodeIfPresent(Double.self, forKey: .to) ?? 0
    }
}
