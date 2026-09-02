import Foundation

/// Mirrors PLAN_SCHEMA in src/api/gemini.js — the structured-output shape
/// Gemini returns for a generated session. Only sessionType/exercises/
/// estTimeMin are marked `required` in the schema, so every other field
/// needs a custom lenient decode: Swift's synthesized Decodable does NOT
/// fall back to a property's default value when a JSON key is simply
/// absent (unlike JS's duck typing) — it throws. validatePlan() in
/// src/utils/parser.js does exactly this same defaulting on the JS side.
struct Plan: Codable, Equatable {
    var sessionType: String = ""
    var title: String = ""
    var recoveryScore: Int? = nil
    var reasoning: String = ""
    var warmup: [String] = []
    var exercises: [Exercise] = []
    var cardio: Cardio? = nil
    var cooldown: [String] = []
    var estTimeMin: Int = 0
    var concerns: String = ""

    struct Exercise: Codable, Equatable {
        var name: String = ""
        var sets: Int = 3
        var reps: String = ""
        var rpe: String = ""
        var rest: String = ""
        var notes: String = ""
        var alt: String = ""
        var suggestedWeight: String = ""
        var superset: String = ""

        init(name: String = "", sets: Int = 3, reps: String = "", rpe: String = "", rest: String = "", notes: String = "", alt: String = "", suggestedWeight: String = "", superset: String = "") {
            self.name = name; self.sets = sets; self.reps = reps; self.rpe = rpe
            self.rest = rest; self.notes = notes; self.alt = alt
            self.suggestedWeight = suggestedWeight; self.superset = superset
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            sets = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 3
            reps = try c.decodeIfPresent(String.self, forKey: .reps) ?? ""
            rpe = try c.decodeIfPresent(String.self, forKey: .rpe) ?? ""
            rest = try c.decodeIfPresent(String.self, forKey: .rest) ?? ""
            notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
            alt = try c.decodeIfPresent(String.self, forKey: .alt) ?? ""
            suggestedWeight = try c.decodeIfPresent(String.self, forKey: .suggestedWeight) ?? ""
            superset = try c.decodeIfPresent(String.self, forKey: .superset) ?? ""
        }
    }

    struct Cardio: Codable, Equatable {
        var desc: String = ""
        var duration: String = ""

        init(desc: String = "", duration: String = "") {
            self.desc = desc; self.duration = duration
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            desc = try c.decodeIfPresent(String.self, forKey: .desc) ?? ""
            duration = try c.decodeIfPresent(String.self, forKey: .duration) ?? ""
        }
    }

    init(sessionType: String = "", title: String = "", recoveryScore: Int? = nil, reasoning: String = "", warmup: [String] = [], exercises: [Exercise] = [], cardio: Cardio? = nil, cooldown: [String] = [], estTimeMin: Int = 0, concerns: String = "") {
        self.sessionType = sessionType; self.title = title; self.recoveryScore = recoveryScore
        self.reasoning = reasoning; self.warmup = warmup; self.exercises = exercises
        self.cardio = cardio; self.cooldown = cooldown; self.estTimeMin = estTimeMin; self.concerns = concerns
    }

    /// Mirrors validatePlan() in src/utils/parser.js: fills sensible
    /// defaults and clamps, so a technically-valid-but-sparse AI
    /// response never reaches the UI half-empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionType = try c.decodeIfPresent(String.self, forKey: .sessionType) ?? ""
        guard !sessionType.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .sessionType, in: c, debugDescription: "plan missing sessionType")
        }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        let rawScore = try c.decodeIfPresent(Int.self, forKey: .recoveryScore)
        recoveryScore = rawScore.map { max(0, min(100, $0)) } ?? 50
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning) ?? "Session chosen from your check-in and recent log."
        warmup = try c.decodeIfPresent([String].self, forKey: .warmup) ?? []
        exercises = try c.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
        cardio = try c.decodeIfPresent(Cardio.self, forKey: .cardio)
        cooldown = try c.decodeIfPresent([String].self, forKey: .cooldown) ?? []
        estTimeMin = try c.decodeIfPresent(Int.self, forKey: .estTimeMin) ?? 60
        concerns = try c.decodeIfPresent(String.self, forKey: .concerns) ?? ""
        // A training day with no exercises means the response was
        // truncated — throw so the caller falls back to the next model
        // instead of showing an empty workout.
        if !sessionType.localizedCaseInsensitiveContains("rest") && exercises.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .exercises, in: c, debugDescription: "plan has no exercises (truncated response)")
        }
    }
}

/// The fixed session types Gemini is constrained to (PLAN_SCHEMA enum) —
/// kept as plain strings on Plan itself for forward-compatible decoding,
/// this just gives call sites a typed way to compare/display them.
enum SessionType: String, CaseIterable {
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case fullBody = "Full Body"
    case core = "Core"
    case cardio = "Cardio"
    case stretchMobility = "Stretch & Mobility"
    case activeRecovery = "Active Recovery"
    case restDay = "Rest Day"
    case run = "Run"
    case cycle = "Cycle"
    case walk = "Walk"
    case hike = "Hike"
}
