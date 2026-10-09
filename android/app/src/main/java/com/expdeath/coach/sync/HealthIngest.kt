package com.expdeath.coach.sync

import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats

/** Typed-in / pasted health text → today's check-in and health row — port
 *  of src/utils/healthIngest.js (storeTodaysHealth, looksLikeHealthData,
 *  reparseHealthRows). */
object HealthIngest {
    private const val KEY = "healthText-"

    /** Health text received for today (Health Connect, the inbox or a paste), or "". */
    fun todaysText(): String = Cloud.stateValue(KEY + Helpers.todayStr())?.string ?: ""

    /** Persist health text for today: the check-in prefill, plus every
     *  number it carries on today's health row. Returns the stored text. */
    fun storeToday(text: String): String {
        val t = text.trim().take(2000)
        if (t.isEmpty()) return t
        Cloud.setState(KEY + Helpers.todayStr(), JSONValue.Str(t))
        record(t)
        return t
    }

    /** Only the fields this payload carries — a partial payload must not
     *  null out values an earlier one delivered. */
    private fun record(text: String) {
        val n = Stats.parseHealthNumbers(text)
        val row = HealthRow(
            date = Helpers.todayStr(), hrv = n.hrv, rhr = n.rhr, steps = n.steps, sleepH = n.sleepH,
            vo2max = n.vo2max, kcal = n.kcal, exerciseMin = n.exerciseMin, distKm = n.distKm,
            spo2 = n.spo2, respRate = n.respRate, wristC = n.wristC, raw = text.take(300),
        )
        if (listOf(n.hrv, n.rhr, n.steps, n.sleepH, n.vo2max, n.kcal, n.exerciseMin, n.distKm, n.spo2, n.respRate, n.wristC).any { it != null && it != 0.0 }) {
            LocalStore.mergeHealth(row)
        }
    }

    /** Heuristic: does clipboard text look like watch/health data? */
    fun looksLikeHealthData(text: String?): Boolean {
        if (text.isNullOrEmpty() || text.length > 600) return false
        return Regex("""\b(hrv|rhr|steps|sleep|bpm|resting|heart|vo2|spo2|kcal)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text) &&
            text.any { it.isDigit() }
    }

    /** Re-parse every stored raw payload with the current parser and fill
     *  fields the row is missing (and repair sleep rows stored before the
     *  double-source dedupe), so parser upgrades reach already-ingested days. */
    fun reparseRows() {
        for (r in LocalStore.backup.health) {
            val raw = r.raw ?: continue
            val n = Stats.parseHealthNumbers(raw)
            fun fill(cur: Double?, v: Double?, repair: Boolean = false) = if (v != null && v != 0.0 && (cur == null || repair)) v else null
            val patch = HealthRow(
                date = r.date,
                hrv = fill(r.hrv, n.hrv), rhr = fill(r.rhr, n.rhr), steps = fill(r.steps, n.steps),
                sleepH = fill(r.sleepH, n.sleepH, (r.sleepH ?: 0.0) > 11),
                vo2max = fill(r.vo2max, n.vo2max), kcal = fill(r.kcal, n.kcal), exerciseMin = fill(r.exerciseMin, n.exerciseMin),
                distKm = fill(r.distKm, n.distKm), spo2 = fill(r.spo2, n.spo2), respRate = fill(r.respRate, n.respRate),
                wristC = fill(r.wristC, n.wristC),
            )
            val any = listOf(patch.hrv, patch.rhr, patch.steps, patch.sleepH, patch.vo2max, patch.kcal, patch.exerciseMin, patch.distKm, patch.spo2, patch.respRate, patch.wristC).any { it != null }
            if (any) LocalStore.mergeHealth(patch)
        }
    }
}
