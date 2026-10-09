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
    /// The saved workout this plan was built from — { id, name, source,
    /// trainer, adapt } (workouts.js), carried for every app's history.
    var fromWorkout: JSONValue? = nil

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
            name = c.lenientString(.name) ?? ""
            sets = c.lenientInt(.sets) ?? 3
            reps = c.lenientString(.reps) ?? ""
            rpe = c.lenientString(.rpe) ?? ""
            rest = c.lenientString(.rest) ?? ""
            notes = c.lenientString(.notes) ?? ""
            alt = c.lenientString(.alt) ?? ""
            suggestedWeight = c.lenientString(.suggestedWeight) ?? ""
            superset = c.lenientString(.superset) ?? ""
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
            desc = c.lenientString(.desc) ?? ""
            duration = c.lenientString(.duration) ?? ""
        }
    }

    init(sessionType: String = "", title: String = "", recoveryScore: Int? = nil, reasoning: String = "", warmup: [String] = [], exercises: [Exercise] = [], cardio: Cardio? = nil, cooldown: [String] = [], estTimeMin: Int = 0, concerns: String = "") {
        self.sessionType = sessionType; self.title = title; self.recoveryScore = recoveryScore
        self.reasoning = reasoning; self.warmup = warmup; self.exercises = exercises
        self.cardio = cardio; self.cooldown = cooldown; self.estTimeMin = estTimeMin; self.concerns = concerns
    }

    /// Fills the same defaults validatePlan() in src/utils/parser.js
    /// does, and never throws: a stored plan must always load, however
    /// sparse. Validation of a fresh AI response lives in fromAI().
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionType = c.lenientString(.sessionType) ?? ""
        title = c.lenientString(.title) ?? ""
        recoveryScore = c.lenientInt(.recoveryScore).map { max(0, min(100, $0)) } ?? 50
        reasoning = c.lenientString(.reasoning) ?? "Session chosen from your check-in and recent log."
        warmup = c.lenientStrings(.warmup) ?? []
        exercises = c.lenient([Exercise].self, .exercises) ?? []
        cardio = c.lenient(Cardio.self, .cardio)
        cooldown = c.lenientStrings(.cooldown) ?? []
        estTimeMin = c.lenientInt(.estTimeMin) ?? 60
        concerns = c.lenientString(.concerns) ?? ""
        if case .object? = c.lenient(JSONValue.self, .fromWorkout) { fromWorkout = c.lenient(JSONValue.self, .fromWorkout) }
    }

    enum AIResponseError: Error, Equatable {
        case missingSessionType
        /// A training day with no exercises means the response was
        /// truncated — the caller falls back to the next model instead
        /// of showing an empty workout.
        case noExercises
    }

    /// Decodes a plan Gemini just returned, rejecting the incomplete
    /// responses validatePlan() in src/utils/parser.js rejects.
    static func fromAI(_ data: Data) throws -> Plan {
        let plan = try JSONDecoder().decode(Plan.self, from: data)
        guard !plan.sessionType.isEmpty else { throw AIResponseError.missingSessionType }
        if !plan.sessionType.localizedCaseInsensitiveContains("rest") && plan.exercises.isEmpty {
            throw AIResponseError.noExercises
        }
        return plan
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
