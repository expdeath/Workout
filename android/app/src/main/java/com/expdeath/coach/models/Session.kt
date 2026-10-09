package com.expdeath.coach.models

/** One training day. Mirrors the session object built in src/App.jsx and
 *  stored by putSession() in src/db/db.js. */
data class Session(
    /** `${date}#${startedAt}` — unique per session so same-day workouts
     *  never overwrite each other (db.js sessionId()). */
    val id: String,
    val date: String,
    val startedAt: Double,
    val checkin: Checkin?,
    val plan: Plan,
    /** log[exerciseIndex][setIndex] */
    val log: List<List<SetLog>>,
    val finished: Boolean = false,
    val fin: FinishInfo? = null,
    val durationMin: Int? = null,
    val prs: List<PRRecord>? = null,
    val debrief: String? = null,
    /** Lets sync pick the newer copy on a conflict (sync.js pickSession). */
    val updatedAt: Double = 0.0,
    /** Legacy in-place tombstone some old backups still carry. */
    val deleted: Boolean = false,
    /** Set on sessions added after the fact (AddPast.jsx). */
    val backfilled: Boolean? = null,
    /** The JSON this session was decoded from — see RawPreserving.kt. */
    override val source: RawSource? = null,
) : RawPreserving {

    override fun encodeKnown(): JSONValue.Obj = jobj {
        put("id", id); put("date", date); put("startedAt", startedAt)
        putIfPresent("checkin", checkin?.toJson())
        put("plan", plan.toJson())
        put("log", JSONValue.Arr(log.map { ex -> JSONValue.Arr(ex.map { it.toJson() }) }))
        put("finished", finished)
        putIfPresent("fin", fin?.toJson())
        putIfPresent("durationMin", durationMin)
        putIfPresent("prs", prs?.let { p -> JSONValue.Arr(p.map { it.toJson() }) })
        putIfPresent("debrief", debrief)
        put("updatedAt", updatedAt)
        // the legacy tombstone flag is only ever written when set
        if (deleted) put("deleted", true)
        putIfPresent("backfilled", backfilled)
    }

    companion object {
        /** Lenient throughout. Only a missing date makes a row unusable; a
         *  missing id falls back to the date like sessionId() in db.js. */
        fun fromJson(v: JSONValue): Session? {
            val c = v.obj ?: return null
            val date = c.lenientString("date")
            if (date.isNullOrEmpty()) return null
            val s = Session(
                id = c.lenientString("id")?.ifEmpty { null } ?: date,
                date = date,
                startedAt = c.lenientDouble("startedAt") ?: 0.0,
                checkin = c.lenient("checkin", Checkin::fromJson),
                plan = c.lenient("plan", Plan::fromJson) ?: Plan(),
                log = c.lenientList("log") { row -> (row as? JSONValue.Arr)?.v?.map { SetLog.fromJson(it) ?: return@lenientList null } }
                    ?: emptyList(),
                finished = c.lenientBool("finished") ?: false,
                fin = c.lenient("fin", FinishInfo::fromJson),
                durationMin = c.lenientInt("durationMin"),
                prs = c.lenientList("prs", PRRecord::fromJson),
                debrief = c.lenientString("debrief"),
                updatedAt = c.lenientDouble("updatedAt") ?: 0.0,
                deleted = c.lenientBool("deleted") ?: false,
                backfilled = c.lenientBool("backfilled"),
            )
            return s.copy(source = rememberSource(v, s))
        }
    }
}
