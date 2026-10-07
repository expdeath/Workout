import Foundation

/// Personal coaching profile, custom routine and gym setup, editable in
/// Settings. Mirrors getAISettings()/setAISettings() in
/// src/utils/storage.js — newest edit (by updatedAt) wins across
/// devices.
///
/// setAISettings() shallow-merges patches, so a real stored object
/// commonly has only the keys someone has actually edited. Absent keys
/// decode to defaults here but are NOT written back unless changed
/// (RawPreserving.swift) — nor is any key this model doesn't know.
struct AISettings: RawPreserving, Equatable {
    var profile: String = ""
    var goals: String = ""
    var equipment: String = ""
    var routine: String = ""
    /// exercise name (lowercased) → cue note text.
    var cueNotes: [String: String] = [:]
    /// Barbell weight in kg (Settings → gym setup, used by the plate math).
    var barKg: Double? = nil
    /// Available plate sizes, comma-separated as typed ("20,15,10,5,2.5").
    var plates: String? = nil
    var updatedAt: Double = 0
    var source: RawSource? = nil

    enum CodingKeys: String, CodingKey {
        case profile, goals, equipment, routine, cueNotes, barKg, plates, updatedAt
    }

    init(profile: String = "", goals: String = "", equipment: String = "", routine: String = "", cueNotes: [String: String] = [:], barKg: Double? = nil, plates: String? = nil, updatedAt: Double = 0) {
        self.profile = profile; self.goals = goals; self.equipment = equipment
        self.routine = routine; self.cueNotes = cueNotes; self.barKg = barKg
        self.plates = plates; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = c.lenientString(.profile) ?? ""
        goals = c.lenientString(.goals) ?? ""
        equipment = c.lenientString(.equipment) ?? ""
        routine = c.lenientString(.routine) ?? ""
        cueNotes = c.lenient([String: String].self, .cueNotes) ?? [:]
        barKg = c.lenientDouble(.barKg)
        plates = c.lenientString(.plates)
        updatedAt = c.lenientDouble(.updatedAt) ?? 0
        try rememberSource(from: decoder)
    }

    func encodeKnown(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(profile, forKey: .profile)
        try c.encode(goals, forKey: .goals)
        try c.encode(equipment, forKey: .equipment)
        try c.encode(routine, forKey: .routine)
        try c.encode(cueNotes, forKey: .cueNotes)
        try c.encodeIfPresent(barKg, forKey: .barKg)
        try c.encodeIfPresent(plates, forKey: .plates)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws { try encodePreserving(to: encoder) }
}
