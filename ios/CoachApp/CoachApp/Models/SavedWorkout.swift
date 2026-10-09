import Foundation

/// A saved workout — the athlete's own or their trainer's (port of the
/// shape in src/utils/workouts.js). Stored as account state
/// `workout-<id>` in Firestore, so the library, weekday schedule and
/// daily add-ons are the same on the web and here.
struct SavedWorkout: Codable, Equatable, Identifiable {
    var id: String = ""
    var name: String = ""
    /// "session" | "addon" — an add-on rides along on the day's session.
    var kind: String = "session"
    /// "me" | "trainer"
    var source: String = "me"
    var trainer: String = ""
    var notes: String = ""
    /// Session only: let the coach adapt it to today (off = kept exactly as written).
    var adapt: Bool = false
    /// Weekdays, 0 = Sunday … 6 = Saturday. An add-on with none runs every day.
    var days: [Int] = []
    var exercises: [Exercise] = []
    var createdAt: Double = 0
    var updatedAt: Double = 0

    struct Exercise: Codable, Equatable {
        var name: String = ""
        var sets: Int = 3
        var reps: String = "10"
        var weight: String = ""
        var rest: String = ""
        var notes: String = ""

        init(name: String = "", sets: Int = 3, reps: String = "10", weight: String = "", rest: String = "", notes: String = "") {
            self.name = name; self.sets = sets; self.reps = reps; self.weight = weight; self.rest = rest; self.notes = notes
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.lenientString(.name) ?? ""
            sets = c.lenientInt(.sets) ?? 3
            reps = c.lenientString(.reps) ?? "10"
            weight = c.lenientString(.weight) ?? ""
            rest = c.lenientString(.rest) ?? ""
            notes = c.lenientString(.notes) ?? ""
        }
    }

    init(id: String = "", name: String = "", kind: String = "session", source: String = "me", trainer: String = "", notes: String = "", adapt: Bool = false, days: [Int] = [], exercises: [Exercise] = [], createdAt: Double = 0, updatedAt: Double = 0) {
        self.id = id; self.name = name; self.kind = kind; self.source = source; self.trainer = trainer
        self.notes = notes; self.adapt = adapt; self.days = days; self.exercises = exercises
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        name = c.lenientString(.name) ?? ""
        kind = c.lenientString(.kind) == "addon" ? "addon" : "session"
        source = c.lenientString(.source) == "trainer" ? "trainer" : "me"
        trainer = c.lenientString(.trainer) ?? ""
        notes = c.lenientString(.notes) ?? ""
        adapt = c.lenientBool(.adapt) ?? false
        days = c.lenient([Int].self, .days) ?? []
        exercises = c.lenient([Exercise].self, .exercises) ?? []
        createdAt = c.lenientDouble(.createdAt) ?? 0
        updatedAt = c.lenientDouble(.updatedAt) ?? 0
    }

    var isAddOn: Bool { kind == "addon" }
}

/// The saved-workout library (port of src/utils/workouts.js): list,
/// save, schedule, and turning a workout into today's plan.
enum Workouts {
    private static let prefix = "workout-"
    static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    /// Display order: Monday first.
    static let weekOrder = [1, 2, 3, 4, 5, 6, 0]

    static func list() -> [SavedWorkout] {
        Cloud.shared.stateKeys()
            .filter { $0.hasPrefix(prefix) }
            .compactMap { get(String($0.dropFirst(prefix.count))) }
            .sorted { $0.kind == $1.kind ? $0.name.localizedCompare($1.name) == .orderedAscending : !$0.isAddOn }
    }

    static func get(_ id: String?) -> SavedWorkout? {
        guard let id, !id.isEmpty, let v = Cloud.shared.stateValue(prefix + id),
              let data = try? JSONEncoder().encode(v),
              let w = try? JSONDecoder().decode(SavedWorkout.self, from: data), !w.id.isEmpty
        else { return nil }
        return w
    }

    /// Cleans and stores a workout; returns what was saved.
    @discardableResult
    static func save(_ w: SavedWorkout) -> SavedWorkout {
        let now = (Date().timeIntervalSince1970 * 1000).rounded()
        var clean = w
        if clean.id.isEmpty { clean.id = String(Int(now), radix: 36) + String(UUID().uuidString.prefix(4)).lowercased() }
        clean.name = w.name.trimmingCharacters(in: .whitespaces).isEmpty ? "My workout" : w.name.trimmingCharacters(in: .whitespaces)
        clean.trainer = w.trainer.trimmingCharacters(in: .whitespaces)
        clean.notes = w.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isAddOn { clean.adapt = false }
        clean.days = Array(Set(w.days.filter { (0...6).contains($0) })).sorted()
        clean.exercises = w.exercises
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { e in
                var e = e
                e.name = e.name.trimmingCharacters(in: .whitespaces)
                e.sets = min(max(e.sets, 1), 10)
                e.reps = e.reps.trimmingCharacters(in: .whitespaces).isEmpty ? "10" : e.reps.trimmingCharacters(in: .whitespaces)
                e.weight = e.weight.trimmingCharacters(in: .whitespaces)
                e.rest = e.rest.trimmingCharacters(in: .whitespaces)
                e.notes = e.notes.trimmingCharacters(in: .whitespaces)
                return e
            }
        if clean.createdAt == 0 { clean.createdAt = now }
        clean.updatedAt = now
        Cloud.shared.setState(prefix + clean.id, try? JSONValue.encoding(clean))
        return clean
    }

    static func delete(_ id: String) { Cloud.shared.setState(prefix + id, nil) }

    /// Raw state values — the backup file carries them as-is.
    static func rawAll() -> [JSONValue] {
        Cloud.shared.stateKeys().filter { $0.hasPrefix(prefix) }.sorted().compactMap { Cloud.shared.stateValue($0) }
    }

    private static func weekday(_ iso: String) -> Int {
        guard let d = Helpers.noonDate(iso) else { return Calendar.current.component(.weekday, from: Date()) - 1 }
        return Calendar.current.component(.weekday, from: d) - 1
    }

    /// Session workouts scheduled on `date`'s weekday, and the add-ons that run that day.
    static func scheduledFor(_ date: String = Helpers.todayStr(), _ all: [SavedWorkout] = list()) -> (sessions: [SavedWorkout], addOns: [SavedWorkout]) {
        let wd = weekday(date)
        return (
            all.filter { !$0.isAddOn && $0.days.contains(wd) },
            all.filter { $0.isAddOn && ($0.days.isEmpty || $0.days.contains(wd)) }
        )
    }

    /// "Mon · Wed · Fri", "Every day", or "" (not scheduled).
    static func daysLabel(_ w: SavedWorkout) -> String {
        if w.days.isEmpty { return w.isAddOn ? "Every day" : "" }
        if w.days.count == 7 { return "Every day" }
        return weekOrder.filter { w.days.contains($0) }.map { weekdays[$0] }.joined(separator: " · ")
    }

    /// A plan exercise from a saved one: its own weight, else the next
    /// step from the logged history.
    private static func planExercise(_ e: SavedWorkout.Exercise, _ history: [Session], note: String = "") -> Plan.Exercise {
        var w = e.weight
        if w.isEmpty {
            let last = Stats.lastPerformance(history, e.name)
            if let next = Stats.suggestNextWeight(last, e.reps) { w = "\(Helpers.fmtKg(next))kg" }
            else if let top = last?.sets.compactMap({ Double($0.weight) }).max(), top > 0 { w = "\(Helpers.fmtKg(top))kg" }
        } else if Double(w) != nil {
            w += "kg"
        }
        return Plan.Exercise(
            name: e.name, sets: e.sets, reps: e.reps, rpe: "", rest: e.rest.isEmpty ? "90s" : e.rest,
            notes: [note, e.notes].filter { !$0.isEmpty }.joined(separator: " · "), alt: "", suggestedWeight: w, superset: ""
        )
    }

    private static func guessType(_ w: SavedWorkout) -> String {
        let n = (w.name + " " + w.exercises.map(\.name).joined(separator: " ")).lowercased()
        func has(_ p: String) -> Bool { n.range(of: p, options: .regularExpression) != nil }
        let lifts = has("press|squat|curl|deadlift")
        if has("stretch|mobility|yoga") { return "Stretch & Mobility" }
        if has("run|cycle|bike|row|cardio|walk") && !lifts { return "Cardio" }
        if has("core|abs|plank") && !lifts && !has("row") { return "Core" }
        if has("push|chest") && !has("pull|leg") { return "Push" }
        if has("pull|back") && !has("push|leg") { return "Pull" }
        if has("leg|squat|lower") && !has("push|pull|upper") { return "Legs" }
        return "Full Body"
    }

    /// Without the AI (no key, offline, coach failed): exactly as written.
    static func templateToPlan(_ w: SavedWorkout, _ history: [Session]) -> Plan {
        let ex = w.exercises.map { planExercise($0, history) }
        return Plan(
            sessionType: guessType(w), title: w.name, recoveryScore: nil,
            reasoning: w.source == "trainer" ? "\(w.trainer.isEmpty ? "Your trainer" : w.trainer)'s workout, as written." : "Your saved workout, as written.",
            exercises: ex, estTimeMin: max(Int((Double(ex.reduce(0) { $0 + $1.sets }) * 2.5).rounded()), 30)
        )
    }

    /// Keep-exact mode: the coach may only add weights, cues and warnings.
    static func enforceExact(_ ai: Plan, _ w: SavedWorkout, _ history: [Session]) -> Plan {
        var out = ai
        out.title = w.name
        let byName = Dictionary(ai.exercises.map { ($0.name.trimmingCharacters(in: .whitespaces).lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        out.exercises = w.exercises.enumerated().map { i, e in
            var base = planExercise(e, history)
            let c = byName[e.name.lowercased()] ?? (i < ai.exercises.count ? ai.exercises[i] : Plan.Exercise())
            base.rpe = c.rpe
            if e.weight.isEmpty, !c.suggestedWeight.isEmpty { base.suggestedWeight = c.suggestedWeight }
            base.notes = [e.notes, c.notes != e.notes ? c.notes : ""].filter { !$0.isEmpty }.joined(separator: " · ")
            base.alt = c.alt
            return base
        }
        return out
    }

    /// Today's add-ons go on the end of the session.
    static func appendAddOns(_ plan: Plan, _ addOns: [SavedWorkout], _ history: [Session]) -> Plan {
        guard !addOns.isEmpty else { return plan }
        var out = plan
        let extra = addOns.flatMap { a in a.exercises.map { planExercise($0, history, note: "Add-on · \(a.name)") } }
        out.exercises += extra
        out.estTimeMin += extra.reduce(0) { $0 + $1.sets * 2 }
        return out
    }

    /// The workout as a brief for the coach's prompt (workoutBrief in workouts.js).
    static func brief(_ w: SavedWorkout) -> String {
        let who = w.source == "trainer" ? "written by the athlete's trainer\(w.trainer.isEmpty ? "" : " (\(w.trainer))")" : "saved by the athlete"
        let lines = w.exercises.enumerated().map { i, e in
            "\(i + 1). \(e.name) — \(e.sets) × \(e.reps)\(e.weight.isEmpty ? "" : " @ \(e.weight)")\(e.rest.isEmpty ? "" : ", rest \(e.rest)")\(e.notes.isEmpty ? "" : " (\(e.notes))")"
        }
        return "\"\(w.name)\", \(who)\(w.notes.isEmpty ? "" : " — notes: \(w.notes)"):\n" + lines.joined(separator: "\n")
    }
}
