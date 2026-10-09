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
    /// A saved workout picked for today (src/utils/workouts.js), and the add-ons ticked.
    var templateId: String = ""
    var addOnIds: [String] = []

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
        energy = c.lenientInt(.energy) ?? 7
        sleep = c.lenientString(.sleep) ?? "OK"
        soreness = c.lenientString(.soreness) ?? "None"
        soreAreas = c.lenientString(.soreAreas) ?? ""
        backTight = c.lenientBool(.backTight) ?? false
        timeAvail = c.lenientString(.timeAvail) ?? "60"
        wish = c.lenientString(.wish) ?? ""
        health = c.lenientString(.health)
        bodyKg = c.lenientString(.bodyKg) ?? ""
        notes = c.lenientString(.notes) ?? ""
        prioritizeMuscle = c.lenientString(.prioritizeMuscle) ?? ""
        templateId = c.lenientString(.templateId) ?? ""
        addOnIds = c.lenientStrings(.addOnIds) ?? []
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
        rpe = c.lenientInt(.rpe) ?? 7
        pain = c.lenientString(.pain) ?? ""
        feedback = c.lenientString(.feedback) ?? ""
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
        name = c.lenientString(.name) ?? ""
        kind = c.lenientString(.kind) ?? ""
        from = c.lenientDouble(.from) ?? 0
        to = c.lenientDouble(.to) ?? 0
    }
}
