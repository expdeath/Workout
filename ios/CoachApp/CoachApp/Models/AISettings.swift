import Foundation

/// Personal coaching profile + custom routine, editable in Settings.
/// Mirrors getAISettings()/setAISettings() in src/utils/storage.js —
/// travels inside the cloud backup, newest edit (by updatedAt) wins on
/// merge (src/db/sync.js).
struct AISettings: Codable, Equatable {
    var profile: String = ""
    var goals: String = ""
    var equipment: String = ""
    var routine: String = ""
    /// exercise name (lowercased) → cue note text.
    var cueNotes: [String: String] = [:]
    var updatedAt: Double = 0

    init(profile: String = "", goals: String = "", equipment: String = "", routine: String = "", cueNotes: [String: String] = [:], updatedAt: Double = 0) {
        self.profile = profile; self.goals = goals; self.equipment = equipment
        self.routine = routine; self.cueNotes = cueNotes; self.updatedAt = updatedAt
    }

    /// setAISettings() in storage.js shallow-merges patches, so a real
    /// stored object commonly has only the keys someone has actually
    /// edited — e.g. `{ profile: "...", updatedAt: 123 }` with goals/
    /// equipment/routine/cueNotes never having been written at all.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decodeIfPresent(String.self, forKey: .profile) ?? ""
        goals = try c.decodeIfPresent(String.self, forKey: .goals) ?? ""
        equipment = try c.decodeIfPresent(String.self, forKey: .equipment) ?? ""
        routine = try c.decodeIfPresent(String.self, forKey: .routine) ?? ""
        cueNotes = try c.decodeIfPresent([String: String].self, forKey: .cueNotes) ?? [:]
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
    }
}
