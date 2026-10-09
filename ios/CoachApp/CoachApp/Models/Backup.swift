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
        guard let id = c.lenientString(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "deletion marker without an id")
        }
        self.id = id
        at = c.lenientDouble(.at) ?? 0
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
    /// Saved workouts (state workout-<id>) and the Settings switches —
    /// carried as-is; only written when there are any.
    var workouts: [JSONValue] = []
    var prefs: JSONValue? = nil
    /// Rows that didn't fit the models above, kept verbatim (and written
    /// back out) so a malformed row is never silently dropped — see
    /// LossyArray in RawPreserving.swift.
    var unparsed: Unparsed = Unparsed()

    struct Unparsed: Equatable {
        var health: [JSONValue] = []
        var sessions: [JSONValue] = []
        var events: [JSONValue] = []
        var isEmpty: Bool { health.isEmpty && sessions.isEmpty && events.isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case app, version, aiSettings, deletedIds, health, sessions, events, workouts, prefs
    }

    init(app: String = "coach", version: Int = 4, aiSettings: AISettings = AISettings(), deletedIds: [DeletedId] = [], health: [HealthRow] = [], sessions: [Session] = [], events: [Event] = []) {
        self.app = app; self.version = version; self.aiSettings = aiSettings
        self.deletedIds = deletedIds; self.health = health; self.sessions = sessions; self.events = events
    }

    /// A very old repo's backup file can predate a field entirely (the
    /// `health` store, `deletedIds`, ...) — every field is optional, and
    /// a row that doesn't decode is kept aside instead of failing sync.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = c.lenientString(.app) ?? "coach"
        version = c.lenientInt(.version) ?? 1
        aiSettings = c.lenient(AISettings.self, .aiSettings) ?? AISettings()
        deletedIds = (c.lenient(LossyArray<DeletedId>.self, .deletedIds)?.items) ?? []
        let h = c.lenient(LossyArray<HealthRow>.self, .health)
        let s = c.lenient(LossyArray<Session>.self, .sessions)
        let e = c.lenient(LossyArray<Event>.self, .events)
        health = h?.items ?? []
        sessions = s?.items ?? []
        events = e?.items ?? []
        unparsed = Unparsed(health: h?.unparsed ?? [], sessions: s?.unparsed ?? [], events: e?.unparsed ?? [])
        workouts = c.lenient([JSONValue].self, .workouts) ?? []
        prefs = c.lenient(JSONValue.self, .prefs)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(app, forKey: .app)
        try c.encode(version, forKey: .version)
        try c.encode(aiSettings, forKey: .aiSettings)
        try c.encode(deletedIds, forKey: .deletedIds)
        try c.encode(health.map { try JSONValue.encoding($0) } + unparsed.health, forKey: .health)
        try c.encode(sessions.map { try JSONValue.encoding($0) } + unparsed.sessions, forKey: .sessions)
        try c.encode(events.map { try JSONValue.encoding($0) } + unparsed.events, forKey: .events)
        if !workouts.isEmpty { try c.encode(workouts, forKey: .workouts) }
        try c.encodeIfPresent(prefs, forKey: .prefs)
    }
}
