package com.expdeath.coach.models

/** PLAN_SCHEMA in src/api/gemini.js — the structured-output shape Gemini
 *  returns for a generated session. Only sessionType/exercises/estTimeMin
 *  are `required` in the schema, so every other field decodes leniently
 *  with the defaults validatePlan() in src/utils/parser.js fills. */
data class Plan(
    val sessionType: String = "",
    val title: String = "",
    val recoveryScore: Int? = null,
    val reasoning: String = "",
    val warmup: List<String> = emptyList(),
    val exercises: List<Exercise> = emptyList(),
    val cardio: Cardio? = null,
    val cooldown: List<String> = emptyList(),
    val estTimeMin: Int = 0,
    val concerns: String = "",
) {
    data class Exercise(
        val name: String = "",
        val sets: Int = 3,
        val reps: String = "",
        val rpe: String = "",
        val rest: String = "",
        val notes: String = "",
        val alt: String = "",
        val suggestedWeight: String = "",
        val superset: String = "",
    ) {
        fun toJson(): JSONValue = jobj {
            put("name", name); put("sets", sets); put("reps", reps); put("rpe", rpe); put("rest", rest)
            put("notes", notes); put("alt", alt); put("suggestedWeight", suggestedWeight); put("superset", superset)
        }

        companion object {
            fun fromJson(v: JSONValue): Exercise? {
                val c = v.obj ?: return null
                return Exercise(
                    name = c.lenientString("name") ?: "",
                    sets = c.lenientInt("sets") ?: 3,
                    reps = c.lenientString("reps") ?: "",
                    rpe = c.lenientString("rpe") ?: "",
                    rest = c.lenientString("rest") ?: "",
                    notes = c.lenientString("notes") ?: "",
                    alt = c.lenientString("alt") ?: "",
                    suggestedWeight = c.lenientString("suggestedWeight") ?: "",
                    superset = c.lenientString("superset") ?: "",
                )
            }
        }
    }

    data class Cardio(val desc: String = "", val duration: String = "") {
        fun toJson(): JSONValue = jobj { put("desc", desc); put("duration", duration) }

        companion object {
            fun fromJson(v: JSONValue): Cardio? {
                val c = v.obj ?: return null
                return Cardio(desc = c.lenientString("desc") ?: "", duration = c.lenientString("duration") ?: "")
            }
        }
    }

    fun toJson(): JSONValue = jobj {
        put("sessionType", sessionType); put("title", title)
        putIfPresent("recoveryScore", recoveryScore)
        put("reasoning", reasoning); put("warmup", strings(warmup))
        put("exercises", JSONValue.Arr(exercises.map { it.toJson() }))
        putIfPresent("cardio", cardio?.toJson())
        put("cooldown", strings(cooldown)); put("estTimeMin", estTimeMin); put("concerns", concerns)
    }

    class AIResponseError(message: String) : Exception(message)

    companion object {
        /** Fills the same defaults validatePlan() does, and never fails: a
         *  stored plan must always load, however sparse. Validation of a
         *  fresh AI response lives in fromAI(). */
        fun fromJson(v: JSONValue): Plan? {
            val c = v.obj ?: return null
            return Plan(
                sessionType = c.lenientString("sessionType") ?: "",
                title = c.lenientString("title") ?: "",
                recoveryScore = c.lenientInt("recoveryScore")?.coerceIn(0, 100) ?: 50,
                reasoning = c.lenientString("reasoning") ?: "Session chosen from your check-in and recent log.",
                warmup = c.lenientStrings("warmup") ?: emptyList(),
                exercises = c.lenientList("exercises", Exercise::fromJson) ?: emptyList(),
                cardio = c.lenient("cardio", Cardio::fromJson),
                cooldown = c.lenientStrings("cooldown") ?: emptyList(),
                estTimeMin = c.lenientInt("estTimeMin") ?: 60,
                concerns = c.lenientString("concerns") ?: "",
            )
        }

        /** Decodes a plan Gemini just returned, rejecting the incomplete
         *  responses validatePlan() in src/utils/parser.js rejects. */
        fun fromAI(text: String): Plan {
            val v = JSONValue.parse(text) ?: throw AIResponseError("invalid JSON")
            val plan = fromJson(v) ?: throw AIResponseError("not an object")
            if (plan.sessionType.isEmpty()) throw AIResponseError("missingSessionType")
            if (!plan.sessionType.contains("rest", ignoreCase = true) && plan.exercises.isEmpty()) {
                // a training day with no exercises means the response was truncated
                throw AIResponseError("noExercises")
            }
            return plan
        }
    }
}

/** The fixed session types Gemini is constrained to (PLAN_SCHEMA enum). */
enum class SessionType(val raw: String) {
    Push("Push"), Pull("Pull"), Legs("Legs"), FullBody("Full Body"), Core("Core"), Cardio("Cardio"),
    StretchMobility("Stretch & Mobility"), ActiveRecovery("Active Recovery"), RestDay("Rest Day"),
    Run("Run"), Cycle("Cycle"), Walk("Walk"), Hike("Hike"),
}
