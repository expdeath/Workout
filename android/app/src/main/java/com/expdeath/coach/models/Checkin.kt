package com.expdeath.coach.models

/** The `ci` state shape in src/App.jsx (the morning check-in). */
data class Checkin(
    val energy: Int = 7,
    val sleep: String = "OK",
    val soreness: String = "None",
    val soreAreas: String = "",
    val backTight: Boolean = false,
    /** Kept as a string (not Int) to match the web app. */
    val timeAvail: String = "60",
    val wish: String = "",
    val health: String? = null,
    val bodyKg: String = "",
    val notes: String = "",
    val prioritizeMuscle: String = "",
    /** A saved workout picked for today (workouts.js), and the add-ons ticked. */
    val templateId: String = "",
    val addOnIds: List<String> = emptyList(),
) {
    fun toJson(): JSONValue = jobj {
        put("energy", energy); put("sleep", sleep); put("soreness", soreness); put("soreAreas", soreAreas)
        put("backTight", backTight); put("timeAvail", timeAvail); put("wish", wish)
        putIfPresent("health", health)
        put("bodyKg", bodyKg); put("notes", notes); put("prioritizeMuscle", prioritizeMuscle)
        put("templateId", templateId); put("addOnIds", strings(addOnIds))
    }

    companion object {
        /** Older synced check-ins can predate a field added later — every
         *  field falls back to its default when absent. */
        fun fromJson(v: JSONValue): Checkin? {
            val c = v.obj ?: return null
            return Checkin(
                energy = c.lenientInt("energy") ?: 7,
                sleep = c.lenientString("sleep") ?: "OK",
                soreness = c.lenientString("soreness") ?: "None",
                soreAreas = c.lenientString("soreAreas") ?: "",
                backTight = c.lenientBool("backTight") ?: false,
                timeAvail = c.lenientString("timeAvail") ?: "60",
                wish = c.lenientString("wish") ?: "",
                health = c.lenientString("health"),
                bodyKg = c.lenientString("bodyKg") ?: "",
                notes = c.lenientString("notes") ?: "",
                prioritizeMuscle = c.lenientString("prioritizeMuscle") ?: "",
                templateId = c.lenientString("templateId") ?: "",
                addOnIds = c.lenientStrings("addOnIds") ?: emptyList(),
            )
        }
    }
}

/** The `fin` state shape in src/App.jsx (post-session rating). */
data class FinishInfo(val rpe: Int = 7, val pain: String = "", val feedback: String = "") {
    fun toJson(): JSONValue = jobj { put("rpe", rpe); put("pain", pain); put("feedback", feedback) }

    companion object {
        fun fromJson(v: JSONValue): FinishInfo? {
            val c = v.obj ?: return null
            return FinishInfo(
                rpe = c.lenientInt("rpe") ?: 7,
                pain = c.lenientString("pain") ?: "",
                feedback = c.lenientString("feedback") ?: "",
            )
        }
    }
}

/** A PR entry returned by detectPRs() in src/utils/stats.js. */
data class PRRecord(val name: String = "", val kind: String = "", val from: Double = 0.0, val to: Double = 0.0) {
    fun toJson(): JSONValue = jobj { put("name", name); put("kind", kind); put("from", from); put("to", to) }

    companion object {
        fun fromJson(v: JSONValue): PRRecord? {
            val c = v.obj ?: return null
            return PRRecord(
                name = c.lenientString("name") ?: "",
                kind = c.lenientString("kind") ?: "",
                from = c.lenientDouble("from") ?: 0.0,
                to = c.lenientDouble("to") ?: 0.0,
            )
        }
    }
}
