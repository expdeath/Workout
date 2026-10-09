import Foundation

/// Deletion tombstone — mirrors src/db/db.js getDeletedIds()/setDeletedIds().
/// Kept permanently so a deleted session can never resurrect from a
/// device that was offline when it was deleted (src/db/sync.js).
struct DeletedId: Codable, Equatable {
    var id: String
    var at: Double = 0

    init(id: String, at: Double = 0) {
        self.id = id; self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
    }
}

/// The full-state envelope synced to `coach-backup.json` in the user's
/// GitHub data repo. Mirrors normalizeBackup()'s return shape in
/// src/db/sync.js exactly (field names included) — this is the file both
/// the web app and this app read/write, so keep it byte-for-byte
/// compatible with the JS shape.
struct Backup: Codable, Equatable {
    var app: String = "coach"
    var version: Int = 4
    var aiSettings: AISettings = AISettings()
    var deletedIds: [DeletedId] = []
    var health: [HealthRow] = []
    var sessions: [Session] = []
    var events: [Event] = []

    init(app: String = "coach", version: Int = 4, aiSettings: AISettings = AISettings(), deletedIds: [DeletedId] = [], health: [HealthRow] = [], sessions: [Session] = [], events: [Event] = []) {
        self.app = app; self.version = version; self.aiSettings = aiSettings
        self.deletedIds = deletedIds; self.health = health; self.sessions = sessions; self.events = events
    }

    /// A very old repo's backup file can predate a field entirely (the
    /// `health` store, `deletedIds`, ...) — decodeIfPresent everywhere
    /// so an old backup still loads instead of failing sync outright.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? "coach"
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        aiSettings = try c.decodeIfPresent(AISettings.self, forKey: .aiSettings) ?? AISettings()
        deletedIds = try c.decodeIfPresent([DeletedId].self, forKey: .deletedIds) ?? []
        health = try c.decodeIfPresent([HealthRow].self, forKey: .health) ?? []
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        events = try c.decodeIfPresent([Event].self, forKey: .events) ?? []
    }
}
