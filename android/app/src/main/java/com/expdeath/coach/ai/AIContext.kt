package com.expdeath.coach.ai

import com.expdeath.coach.models.Session
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.fmt
import com.expdeath.coach.stats.nowSec
import kotlin.math.floor

/** Long-term AI context builder — ports src/utils/aiContext.js. The prompt
 *  already includes the last 6 sessions in full detail; this compresses
 *  EVERYTHING OLDER into a compact summary — per-exercise progression,
 *  weekly adherence, split balance, pain patterns, RPE trend — so years of
 *  history fit in a few hundred tokens and old data keeps steering today's plan. */
object AIContext {
    private const val MAX_CHARS = 1800

    private fun bestWeight(session: Session, exIndex: Int): Double? {
        val sets = session.log.getOrNull(exIndex) ?: return null
        var best: Double? = null
        for (s in sets) if (s.isLogged) {
            val w = parseDouble(s.weight) ?: continue
            if (best == null || w > best) best = w
        }
        return best
    }

    fun buildLongTermSummary(sessions: List<Session>): String {
        if (sessions.size < 5) return ""
        val lines = ArrayList<String>()

        lines.add("${sessions.size} sessions logged since ${sessions[0].date}.")

        // Weekly adherence, last 8 weeks (oldest → newest)
        val weekSec = 7 * 86400.0
        val now = nowSec()
        val weeks = IntArray(8)
        for (s in sessions) {
            val age = now - Stats.dateMs(s.date)
            val w = floor(age / weekSec).toInt()
            if (w in 0..7) weeks[7 - w] += 1
        }
        lines.add("Sessions per week, last 8 weeks (oldest→newest): ${weeks.joinToString(", ")}.")

        // Split balance, last 90 days
        val cutoff = now - 90 * 86400
        val split = LinkedHashMap<String, Int>()
        for (s in sessions) {
            if (Stats.dateMs(s.date) < cutoff) continue
            split.merge(s.plan.sessionType.ifEmpty { "Other" }, 1, Int::plus)
        }
        val splitTxt = split.entries.sortedByDescending { it.value }.joinToString(", ") { "${it.key} ${it.value}" }
        if (splitTxt.isNotEmpty()) lines.add("Split last 90 days: $splitTxt.")

        // Per-exercise progression across ALL history
        data class Point(val date: String, val w: Double)
        val byExercise = LinkedHashMap<String, Pair<String, MutableList<Point>>>()
        for (s in sessions) {
            s.plan.exercises.forEachIndexed { i, ex ->
                if (ex.name.isEmpty()) return@forEachIndexed
                val w = bestWeight(s, i) ?: return@forEachIndexed
                val key = ex.name.trim().lowercase()
                byExercise.getOrPut(key) { ex.name.trim() to ArrayList() }.second.add(Point(s.date, w))
            }
        }
        val top = byExercise.values.filter { it.second.size >= 2 }.sortedByDescending { it.second.size }.take(12)
        if (top.isNotEmpty()) {
            lines.add("Exercise progression (first → latest, best, times done):")
            for ((name, points) in top) {
                val firstW = points.first().w
                val last = points.last()
                val best = points.maxOf { it.w }
                lines.add("- $name: ${f(firstW)}kg → ${f(last.w)}kg (best ${f(best)}kg, ${points.size}x, last ${last.date})")
            }
        }

        // Recurring pain reports
        val pains = LinkedHashMap<String, Int>()
        for (s in sessions) {
            val p = s.fin?.pain?.trim()?.lowercase() ?: ""
            if (p.isEmpty()) continue
            pains.merge(p, 1, Int::plus)
        }
        val painTxt = pains.entries.sortedByDescending { it.value }.take(4).joinToString(", ") { "\"${it.key}\" x${it.value}" }
        if (painTxt.isNotEmpty()) lines.add("Recurring pain reports: $painTxt.")

        // RPE trend
        val rpes = sessions.filter { it.finished }.mapNotNull { it.fin?.rpe?.toDouble() }
        if (rpes.size >= 6) {
            val recent = rpes.takeLast(5).average()
            val prior = rpes.dropLast(5).average()
            lines.add("Avg session RPE: last 5 = ${fmt("%.1f", recent)}, all prior = ${fmt("%.1f", prior)}.")
        }

        var out = lines.joinToString("\n")
        if (out.length > MAX_CHARS) out = out.take(MAX_CHARS) + "…"
        return out
    }

    private fun f(v: Double): String = if (v % 1.0 == 0.0) v.toInt().toString() else v.toString()
}
