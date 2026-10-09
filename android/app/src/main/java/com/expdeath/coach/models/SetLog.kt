package com.expdeath.coach.models

/** One logged set row. Strength sets carry weight/reps; cardio sets carry
 *  time/dist instead; check-only sets (stretches/holds) carry neither and
 *  rely on `done`. Mirrors the set shape in src/App.jsx / helpers.js. */
data class SetLog(
    val weight: String = "",
    val reps: String = "",
    val done: Boolean = false,
    val time: String = "",
    val dist: String = "",
    /** '' | "easy" | "good" | "grind" — per-set effort tap (Workout.jsx EFFORTS). */
    val effort: String = "",
) {
    /** setLogged() in helpers.js: a set counts once ticked done OR any
     *  number has been typed into it. */
    val isLogged: Boolean get() = done || weight.isNotEmpty() || reps.isNotEmpty() || time.isNotEmpty() || dist.isNotEmpty()

    /** fmtSet() in helpers.js. */
    val formatted: String
        get() {
            if (time.isNotEmpty() || dist.isNotEmpty()) {
                return listOfNotNull(if (time.isEmpty()) null else "${time}min", if (dist.isEmpty()) null else "${dist}km")
                    .joinToString(" · ")
            }
            if (weight.isEmpty() && reps.isEmpty()) return if (done) "✓" else "—"
            return "${weight.ifEmpty { "?" }}kg×${reps.ifEmpty { "?" }}"
        }

    fun toJson(): JSONValue = jobj {
        put("weight", weight); put("reps", reps); put("done", done)
        put("time", time); put("dist", dist); put("effort", effort)
    }

    companion object {
        /** Real quick-cardio sets are written as just `{ time, dist, done }`
         *  — every field must tolerate being absent, not just empty. */
        fun fromJson(v: JSONValue): SetLog? {
            val c = v.obj ?: return null
            return SetLog(
                weight = c.lenientString("weight") ?: "",
                reps = c.lenientString("reps") ?: "",
                done = c.lenientBool("done") ?: false,
                time = c.lenientString("time") ?: "",
                dist = c.lenientString("dist") ?: "",
                effort = c.lenientString("effort") ?: "",
            )
        }
    }
}
