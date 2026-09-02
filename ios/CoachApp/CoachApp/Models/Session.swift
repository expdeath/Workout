import Foundation

/// One training day. Mirrors the session object shape built in
/// src/App.jsx (generateWorkout / logQuickCardio) and stored by
/// putSession() in src/db/db.js.
struct Session: Codable, Equatable, Identifiable {
    /// `${date}#${startedAt}` — unique per session so same-day workouts
    /// never overwrite each other (src/db/db.js sessionId()).
    var id: String
    var date: String
    var startedAt: Double
    var checkin: Checkin?
    var plan: Plan
    /// log[exerciseIndex][setIndex]
    var log: [[SetLog]]
    var finished: Bool = false
    var fin: FinishInfo? = nil
    var durationMin: Int? = nil
    var prs: [PRRecord]? = nil
    var debrief: String? = nil
    /// Lets cloud sync pick the newer copy on a merge conflict
    /// (src/db/sync.js pickSession).
    var updatedAt: Double = 0
    /// Legacy in-place tombstone marker some old backups may still
    /// carry — normalizeBackup() folds these into `deletedIds` and
    /// drops the row. Current writes always use hardDelete instead, so
    /// this key is absent from virtually every real session.
    var deleted: Bool = false

    init(id: String, date: String, startedAt: Double, checkin: Checkin?, plan: Plan, log: [[SetLog]], finished: Bool = false, fin: FinishInfo? = nil, durationMin: Int? = nil, prs: [PRRecord]? = nil, debrief: String? = nil, updatedAt: Double = 0, deleted: Bool = false) {
        self.id = id; self.date = date; self.startedAt = startedAt; self.checkin = checkin
        self.plan = plan; self.log = log; self.finished = finished; self.fin = fin
        self.durationMin = durationMin; self.prs = prs; self.debrief = debrief
        self.updatedAt = updatedAt; self.deleted = deleted
    }

    /// `deleted` and `updatedAt` are absent from plenty of genuine
    /// session JSON (see field comments) — decodeIfPresent avoids a
    /// whole-array decode failure over one missing key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt) ?? 0
        checkin = try c.decodeIfPresent(Checkin.self, forKey: .checkin)
        plan = try c.decode(Plan.self, forKey: .plan)
        log = try c.decodeIfPresent([[SetLog]].self, forKey: .log) ?? []
        finished = try c.decodeIfPresent(Bool.self, forKey: .finished) ?? false
        fin = try c.decodeIfPresent(FinishInfo.self, forKey: .fin)
        durationMin = try c.decodeIfPresent(Int.self, forKey: .durationMin)
        prs = try c.decodeIfPresent([PRRecord].self, forKey: .prs)
        debrief = try c.decodeIfPresent(String.self, forKey: .debrief)
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }
}
