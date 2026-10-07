import Foundation

/// One training day. Mirrors the session object shape built in
/// src/App.jsx (generateWorkout / logQuickCardio) and stored by
/// putSession() in src/db/db.js.
struct Session: RawPreserving, Equatable, Identifiable {
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
    /// Set on sessions added after the fact (src/screens/AddPast.jsx).
    var backfilled: Bool? = nil
    /// The JSON this session was decoded from — see RawPreserving.swift.
    var source: RawSource? = nil

    enum CodingKeys: String, CodingKey {
        case id, date, startedAt, checkin, plan, log, finished, fin, durationMin, prs, debrief, updatedAt, deleted, backfilled
    }

    init(id: String, date: String, startedAt: Double, checkin: Checkin?, plan: Plan, log: [[SetLog]], finished: Bool = false, fin: FinishInfo? = nil, durationMin: Int? = nil, prs: [PRRecord]? = nil, debrief: String? = nil, updatedAt: Double = 0, deleted: Bool = false, backfilled: Bool? = nil) {
        self.id = id; self.date = date; self.startedAt = startedAt; self.checkin = checkin
        self.plan = plan; self.log = log; self.finished = finished; self.fin = fin
        self.durationMin = durationMin; self.prs = prs; self.debrief = debrief
        self.updatedAt = updatedAt; self.deleted = deleted; self.backfilled = backfilled
    }

    /// Lenient throughout: real sessions written by the web app omit
    /// keys and mix types (see RawPreserving.swift). Only a missing
    /// id/date makes a row unusable — the old app keys legacy rows by
    /// date alone, so a missing id falls back to the date like
    /// sessionId() in src/db/db.js.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let date = c.lenientString(.date), !date.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "session without a date")
        }
        self.date = date
        id = c.lenientString(.id).flatMap { $0.isEmpty ? nil : $0 } ?? date
        startedAt = c.lenientDouble(.startedAt) ?? 0
        checkin = c.lenient(Checkin.self, .checkin)
        plan = c.lenient(Plan.self, .plan) ?? Plan()
        log = c.lenient([[SetLog]].self, .log) ?? []
        finished = c.lenientBool(.finished) ?? false
        fin = c.lenient(FinishInfo.self, .fin)
        durationMin = c.lenientInt(.durationMin)
        prs = c.lenient([PRRecord].self, .prs)
        debrief = c.lenientString(.debrief)
        updatedAt = c.lenientDouble(.updatedAt) ?? 0
        deleted = c.lenientBool(.deleted) ?? false
        backfilled = c.lenientBool(.backfilled)
        try rememberSource(from: decoder)
    }

    func encodeKnown(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(checkin, forKey: .checkin)
        try c.encode(plan, forKey: .plan)
        try c.encode(log, forKey: .log)
        try c.encode(finished, forKey: .finished)
        try c.encodeIfPresent(fin, forKey: .fin)
        try c.encodeIfPresent(durationMin, forKey: .durationMin)
        try c.encodeIfPresent(prs, forKey: .prs)
        try c.encodeIfPresent(debrief, forKey: .debrief)
        try c.encode(updatedAt, forKey: .updatedAt)
        // the legacy tombstone flag is only ever written when set
        if deleted { try c.encode(deleted, forKey: .deleted) }
        try c.encodeIfPresent(backfilled, forKey: .backfilled)
    }

    func encode(to encoder: Encoder) throws { try encodePreserving(to: encoder) }
}
