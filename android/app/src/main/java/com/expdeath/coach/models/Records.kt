package com.expdeath.coach.models

/** One day of Watch / typed-in health data. Mirrors the `health` store in
 *  src/db/db.js (putHealth/mergeHealth) and every field
 *  parseHealthNumbers() can fill. Every metric stays optional; keys this
 *  model doesn't know survive a round trip untouched. */
data class HealthRow(
    val date: String,
    val hrv: Double? = null,
    val rhr: Double? = null,
    val steps: Double? = null,
    val sleepH: Double? = null,
    val weightKg: Double? = null,
    val respRate: Double? = null,
    val wristC: Double? = null,
    val vo2max: Double? = null,
    val kcal: Double? = null,
    val exerciseMin: Double? = null,
    val distKm: Double? = null,
    val spo2: Double? = null,
    val raw: String? = null,
    val receivedAt: Double? = null,
    override val source: RawSource? = null,
) : RawPreserving {

    /** `this` with every metric `patch` carries copied over (mergeHealth). */
    fun patchedWith(patch: HealthRow): HealthRow = copy(
        hrv = patch.hrv ?: hrv, rhr = patch.rhr ?: rhr, steps = patch.steps ?: steps, sleepH = patch.sleepH ?: sleepH,
        weightKg = patch.weightKg ?: weightKg, respRate = patch.respRate ?: respRate, wristC = patch.wristC ?: wristC,
        vo2max = patch.vo2max ?: vo2max, kcal = patch.kcal ?: kcal, exerciseMin = patch.exerciseMin ?: exerciseMin,
        distKm = patch.distKm ?: distKm, spo2 = patch.spo2 ?: spo2,
    )

    override fun encodeKnown(): JSONValue.Obj = jobj {
        put("date", date)
        putIfPresent("hrv", hrv); putIfPresent("rhr", rhr); putIfPresent("steps", steps); putIfPresent("sleepH", sleepH)
        putIfPresent("weightKg", weightKg); putIfPresent("respRate", respRate); putIfPresent("wristC", wristC)
        putIfPresent("vo2max", vo2max); putIfPresent("kcal", kcal); putIfPresent("exerciseMin", exerciseMin)
        putIfPresent("distKm", distKm); putIfPresent("spo2", spo2)
        putIfPresent("raw", raw); putIfPresent("receivedAt", receivedAt)
    }

    companion object {
        fun fromJson(v: JSONValue): HealthRow? {
            val c = v.obj ?: return null
            val date = c.lenientString("date")
            if (date.isNullOrEmpty()) return null
            val h = HealthRow(
                date = date,
                hrv = c.lenientDouble("hrv"), rhr = c.lenientDouble("rhr"), steps = c.lenientDouble("steps"),
                sleepH = c.lenientDouble("sleepH"), weightKg = c.lenientDouble("weightKg"),
                respRate = c.lenientDouble("respRate"), wristC = c.lenientDouble("wristC"),
                vo2max = c.lenientDouble("vo2max"), kcal = c.lenientDouble("kcal"),
                exerciseMin = c.lenientDouble("exerciseMin"), distKm = c.lenientDouble("distKm"),
                spo2 = c.lenientDouble("spo2"),
                raw = c.lenientString("raw"), receivedAt = c.lenientDouble("receivedAt"),
            )
            return h.copy(source = rememberSource(v, h))
        }
    }
}

/** Append-only interaction log entry (logEvent() in src/db/db.js) —
 *  `data` is free-form since every event type carries its own payload. */
data class Event(
    val ts: Double,
    val iso: String,
    val type: String,
    val data: Map<String, JSONValue> = emptyMap(),
    override val source: RawSource? = null,
) : RawPreserving {
    override fun encodeKnown(): JSONValue.Obj = jobj {
        put("ts", ts); put("iso", iso); put("type", type); put("data", JSONValue.Obj(data))
    }

    companion object {
        fun fromJson(v: JSONValue): Event? {
            val c = v.obj ?: return null
            val type = c.lenientString("type")
            if (type.isNullOrEmpty()) return null
            val e = Event(
                ts = c.lenientDouble("ts") ?: 0.0,
                iso = c.lenientString("iso") ?: "",
                type = type,
                data = c.lenientObj("data") ?: emptyMap(),
            )
            return e.copy(source = rememberSource(v, e))
        }
    }
}

/** Personal coaching profile, custom routine and gym setup, editable in
 *  Settings — getAISettings()/setAISettings() in src/utils/storage.js;
 *  the newest edit (by updatedAt) wins across devices. A real stored
 *  object commonly has only the keys someone has actually edited: absent
 *  keys decode to defaults but are NOT written back unless changed. */
data class AISettings(
    val profile: String = "",
    val goals: String = "",
    val equipment: String = "",
    val routine: String = "",
    /** exercise name (lowercased) → cue note text. */
    val cueNotes: Map<String, String> = emptyMap(),
    /** Barbell weight in kg (Settings → gym setup, used by the plate math). */
    val barKg: Double? = null,
    /** Available plate sizes, comma-separated as typed ("20,15,10,5,2.5"). */
    val plates: String? = null,
    /** Sessions per week aimed for; null = from a "N sessions a week" goal, else 3. */
    val weeklyTarget: Int? = null,
    val updatedAt: Double = 0.0,
    override val source: RawSource? = null,
) : RawPreserving {
    override fun encodeKnown(): JSONValue.Obj = jobj {
        put("profile", profile); put("goals", goals); put("equipment", equipment); put("routine", routine)
        put("cueNotes", JSONValue.Obj(cueNotes.mapValues { JSONValue.Str(it.value) }))
        putIfPresent("barKg", barKg); putIfPresent("plates", plates); putIfPresent("weeklyTarget", weeklyTarget)
        put("updatedAt", updatedAt)
    }

    companion object {
        fun fromJson(v: JSONValue): AISettings? {
            val c = v.obj ?: return null
            val cue = c.lenientObj("cueNotes")?.let { m ->
                // [String: String]: any non-string value fails the whole map
                if (m.values.all { it is JSONValue.Str }) m.mapValues { (it.value as JSONValue.Str).v } else null
            }
            val s = AISettings(
                profile = c.lenientString("profile") ?: "",
                goals = c.lenientString("goals") ?: "",
                equipment = c.lenientString("equipment") ?: "",
                routine = c.lenientString("routine") ?: "",
                cueNotes = cue ?: emptyMap(),
                barKg = c.lenientDouble("barKg"),
                plates = c.lenientString("plates"),
                weeklyTarget = c.lenientDouble("weeklyTarget")?.toInt(),
                updatedAt = c.lenientDouble("updatedAt") ?: 0.0,
            )
            return s.copy(source = rememberSource(v, s))
        }
    }
}

/** Deletion tombstone — getDeletedIds()/setDeletedIds() in src/db/db.js.
 *  Kept permanently so a deleted session can never resurrect. */
data class DeletedId(val id: String, val at: Double = 0.0) {
    fun toJson(): JSONValue = jobj { put("id", id); put("at", at) }

    companion object {
        fun fromJson(v: JSONValue): DeletedId? {
            val c = v.obj ?: return null
            val id = c.lenientString("id") ?: return null
            return DeletedId(id, c.lenientDouble("at") ?: 0.0)
        }
    }
}

/** The full-state envelope in `coach-backup.json` (normalizeBackup() in
 *  src/db/sync.js) — the file every app reads/writes, so keep it
 *  compatible with the JS shape. */
data class Backup(
    val app: String = "coach",
    val version: Int = 4,
    val aiSettings: AISettings = AISettings(),
    val deletedIds: List<DeletedId> = emptyList(),
    val health: List<HealthRow> = emptyList(),
    val sessions: List<Session> = emptyList(),
    val events: List<Event> = emptyList(),
    /** Saved workouts (state workout-<id>) and the Settings switches —
     *  carried as-is; only written when there are any. */
    val workouts: List<JSONValue> = emptyList(),
    val prefs: JSONValue? = null,
    /** Rows that didn't fit the models above, kept verbatim and written
     *  back out so a malformed row is never silently dropped. */
    val unparsed: Unparsed = Unparsed(),
) {
    data class Unparsed(
        val health: List<JSONValue> = emptyList(),
        val sessions: List<JSONValue> = emptyList(),
        val events: List<JSONValue> = emptyList(),
    ) {
        val isEmpty: Boolean get() = health.isEmpty() && sessions.isEmpty() && events.isEmpty()
    }

    fun toJson(): JSONValue.Obj = jobj {
        put("app", app); put("version", version)
        put("aiSettings", aiSettings.toJson())
        put("deletedIds", JSONValue.Arr(deletedIds.map { it.toJson() }))
        put("health", JSONValue.Arr(health.map { it.toJson() } + unparsed.health))
        put("sessions", JSONValue.Arr(sessions.map { it.toJson() } + unparsed.sessions))
        put("events", JSONValue.Arr(events.map { it.toJson() } + unparsed.events))
        if (workouts.isNotEmpty()) put("workouts", JSONValue.Arr(workouts))
        putIfPresent("prefs", prefs)
    }

    companion object {
        /** A very old repo's backup file can predate a field entirely —
         *  every field is optional, and a row that doesn't decode is kept
         *  aside instead of failing. */
        fun fromJson(v: JSONValue): Backup? {
            val c = v.obj ?: return null
            val h = c["health"]?.let { LossyArray.decode(it, HealthRow::fromJson) }
            val s = c["sessions"]?.let { LossyArray.decode(it, Session::fromJson) }
            val e = c["events"]?.let { LossyArray.decode(it, Event::fromJson) }
            return Backup(
                app = c.lenientString("app") ?: "coach",
                version = c.lenientInt("version") ?: 1,
                aiSettings = c.lenient("aiSettings", AISettings::fromJson) ?: AISettings(),
                deletedIds = c["deletedIds"]?.let { LossyArray.decode(it, DeletedId::fromJson)?.items } ?: emptyList(),
                health = h?.items ?: emptyList(),
                sessions = s?.items ?: emptyList(),
                events = e?.items ?: emptyList(),
                unparsed = Unparsed(h?.unparsed ?: emptyList(), s?.unparsed ?: emptyList(), e?.unparsed ?: emptyList()),
                workouts = (c["workouts"] as? JSONValue.Arr)?.v ?: emptyList(),
                prefs = c["prefs"]?.takeIf { it !is JSONValue.Null },
            )
        }
    }
}
