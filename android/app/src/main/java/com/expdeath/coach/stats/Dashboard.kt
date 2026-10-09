package com.expdeath.coach.stats

import com.expdeath.coach.app.Screen
import com.expdeath.coach.models.AISettings
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.MonthlyReportCache
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.WeeklyReviewCache
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.persistence.LocalStore

/** MET-based calorie estimate — port of src/utils/calories.js. Computed on
 *  the fly from session/health data; nothing is stored. */
object Calories {
    private val metBySessionType = mapOf(
        "Run" to 9.8, "Cycle" to 7.5, "Walk" to 4.3, "Hike" to 6.0, "Cardio" to 7.0,
        "Active Recovery" to 4.0, "Stretch & Mobility" to 2.5,
        "Push" to 5.0, "Pull" to 5.0, "Legs" to 5.0, "Full Body" to 5.0, "Core" to 5.0,
    )
    private const val defaultMet = 4.0
    const val defaultBodyKg = 75.0

    /** Most recent known body weight across the health log, kg. */
    fun latestBodyWeightKg(health: List<HealthRow>, fallback: Double = defaultBodyKg): Double =
        health.filter { (it.weightKg ?: 0.0) > 0 }.maxByOrNull { it.date }?.weightKg ?: fallback

    /** Estimated calories burned for one session. */
    fun estimate(s: Session, bodyKg: Double = defaultBodyKg): Int {
        val type = s.plan.sessionType
        if (type.isEmpty() || type == "Rest Day") return 0
        val met = metBySessionType[type] ?: defaultMet
        val minutes = (s.durationMin ?: (if (s.plan.estTimeMin > 0) s.plan.estTimeMin else 0)).toDouble()
        if (minutes <= 0) return 0
        return (met * bodyKg * minutes / 60).rounded().toInt()
    }

    data class Totals(val thisWeek: Int, val allTime: Int)

    fun stats(history: List<Session>, bodyKg: Double = defaultBodyKg): Totals {
        val weekAgo = System.currentTimeMillis() - 7 * 86_400_000L
        var week = 0; var all = 0
        for (s in history) {
            val k = estimate(s, bodyKg)
            all += k
            val d = Helpers.noonDate(s.date)
            if (d != null && d.toEpochMilli() >= weekAgo) week += k
        }
        return Totals(week, all)
    }
}

/** Derived numbers for the dashboard-style screens (Today, Log, Progress,
 *  Records) and the notification feed — mirrors src/utils/dashboard.js. */
object Dashboard {
    // ── Readiness pill ───────────────────────────────────────────────

    enum class Tone { Good, Ok, Low }
    data class Readiness(val label: String, val tone: Tone, val note: String)

    /** RESTED / STEADY / FATIGUED from the latest Watch day (≤ 2 days old)
     *  against the 30-day baseline, plus the training-load deload signal. */
    fun readiness(history: List<Session>, health: List<HealthRow>): Readiness? {
        val deload = Stats.deloadSignal(history)
        val cutoff = Helpers.daysAgoStr(2)
        val h = health.filter { it.date >= cutoff }.maxByOrNull { it.date }
            ?: return deload?.let { Readiness("Deload", Tone.Low, it.reason) }
        val base = Stats.healthBaseline(history, health)
        var low = 0; var good = 0
        val bits = ArrayList<String>()
        if (h.hrv != null && base.hrv != null && base.hrv > 0) {
            val d = (h.hrv - base.hrv).rounded().toInt()
            bits.add("HRV ${h.hrv.rounded().toInt()} ms (${if (d >= 0) "+" else ""}$d vs your average)")
            if (h.hrv < base.hrv * 0.85) low += 1 else if (h.hrv >= base.hrv * 0.95) good += 1
        }
        if (h.rhr != null && base.rhr != null) {
            if (h.rhr > base.rhr + 5) { low += 1; bits.add("resting HR ${h.rhr.rounded().toInt()} — high") }
            else if (h.rhr <= base.rhr + 1) good += 1
        }
        h.sleepH?.let { sleep ->
            bits.add("slept ${fmt("%.1f", sleep)}h")
            if (sleep < 6) low += 1 else if (sleep >= 7) good += 1
        }
        if (deload != null) low += 1
        if (bits.isEmpty() && deload == null) return null
        val joined = bits.joinToString(" · ")
        val note = if (bits.isEmpty()) deload?.reason ?: "" else joined.take(1).uppercase() + joined.drop(1)
        if (low > 0) return Readiness("Fatigued", Tone.Low, deload?.reason ?: note)
        if (good >= 2) return Readiness("Rested", Tone.Good, note)
        return Readiness("Steady", Tone.Ok, note)
    }

    // ── Weekly target ────────────────────────────────────────────────

    /** Settings value, else a "N sessions a week" goal, else 3. */
    fun weeklyTarget(s: AISettings): Int {
        val t = s.weeklyTarget
        if (t != null && t > 0) return minOf(t, 14)
        val goal = Stats.goalProgress(emptyList(), s.goals).firstOrNull { it.unit == " this week" }
        val gt = goal?.target
        if (gt != null && gt > 0) return minOf(gt.toInt(), 14)
        return 3
    }

    // ── Ranges ───────────────────────────────────────────────────────

    data class RangeSummary(val sessions: Int, val prevSessions: Int, val volume: Int, val kcal: Int)

    /** Sessions / volume in the last `days` days, and sessions in the
     *  `days` before that (for the "+16%" delta). */
    fun rangeSummary(history: List<Session>, days: Int, bodyKg: Double): RangeSummary {
        val start = Helpers.daysAgoStr(days - 1); val prevStart = Helpers.daysAgoStr(2 * days - 1)
        val cur = history.filter { it.date >= start }
        val prev = history.filter { it.date >= prevStart && it.date < start }
        return RangeSummary(cur.size, prev.size, cur.sumOf { Stats.sessionVolume(it) }, cur.sumOf { Calories.estimate(it, bodyKg) })
    }

    /** Percent of the weekly target met over the last `weeks` weeks, capped at 100. */
    fun compliance(history: List<Session>, weeks: Int, target: Int): Int {
        if (target <= 0 || weeks <= 0) return 0
        val done = history.count { it.date >= Helpers.daysAgoStr(weeks * 7 - 1) }
        return minOf(100, (done.toDouble() / (weeks * target) * 100).rounded().toInt())
    }

    /** "+16%" style change; null when there's nothing to compare with. */
    fun deltaPercent(cur: Int, prev: Int): Int? {
        if (prev <= 0) return null
        return ((cur.toDouble() - prev) / prev * 100).rounded().toInt()
    }

    // ── Today's plan ─────────────────────────────────────────────────

    /** Expected kg lifted if every strength set hits the top of its rep
     *  range at the suggested (or last used) weight. */
    fun projectedLoad(plan: Plan, history: List<Session>): Int {
        var total = 0.0
        for (ex in plan.exercises) {
            if (Stats.logMode(ex.name, plan.sessionType) != "strength") continue
            val reps = lastNumber(ex.reps) ?: 0.0
            val last = Stats.lastPerformance(history, ex.name)
            val lastBest = last?.sets?.mapNotNull { parseDouble(it.weight) }?.maxOrNull() ?: 0.0
            val w = Stats.suggestNextWeight(last, ex.reps) ?: firstNumber(ex.suggestedWeight) ?: lastBest
            total += ex.sets * reps * w
        }
        return total.rounded().toInt()
    }

    /** "8-12" → 12, "10" → 10 */
    private fun lastNumber(s: String): Double? = Stats.firstMatch("""(\d+)\D*$""", s)?.safe(1)?.let { parseDouble(it) }

    /** "24kg" → 24 */
    private fun firstNumber(s: String): Double? = Stats.firstMatch("""(\d+(?:\.\d+)?)""", s)?.safe(1)?.let { parseDouble(it) }

    /** Mean of the plan's RPE targets ("7-8" → 7.5). */
    fun averageRPE(plan: Plan): Double? {
        val vals = plan.exercises.mapNotNull { ex ->
            val g = Stats.firstMatch("""(\d+(?:\.\d+)?)(?:\s*-\s*(\d+(?:\.\d+)?))?""", ex.rpe)
            val n = g?.let { listOfNotNull(it.safe(1), it.safe(2)).mapNotNull { s -> parseDouble(s) } } ?: emptyList()
            if (n.isEmpty()) null else n.sum() / n.size
        }
        return if (vals.isEmpty()) null else (vals.sum() / vals.size * 2).rounded() / 2
    }

    // ── Milestones ───────────────────────────────────────────────────

    data class Milestone(val id: String, val icon: String, val title: String, val value: Int, val goal: Int) {
        val earned: Boolean get() = value >= goal
    }

    data class Ladder(val key: String, val icon: String, val unit: String, val value: Int, val steps: List<Int>)

    fun ladders(history: List<Session>): List<Ladder> {
        val records = Stats.prRecords(history)
        val heaviest = (records.mapNotNull { it.weight?.w }.maxOrNull() ?: 0.0).toInt()
        val tonnes = history.sumOf { Stats.sessionVolume(it) } / 1000
        return listOf(
            Ladder("sessions", "calendar", "sessions", history.size, listOf(10, 25, 50, 100, 250)),
            // the streak against your own weekly target — the same number the streak stat shows
            Ladder("streak", "flame.fill", "week streak", Stats.weekStats(history, weeklyTarget(LocalStore.backup.aiSettings)).streak, listOf(2, 4, 8, 12, 26)),
            Ladder("tonnes", "scalemass.fill", "t lifted", tonnes, listOf(5, 10, 25, 50, 100)),
            Ladder("heaviest", "medal.fill", "kg lift", heaviest, listOf(40, 60, 80, 100, 140)),
        )
    }

    /** Every earned step plus the next one up on each ladder. */
    fun milestones(history: List<Session>): List<Milestone> = ladders(history).flatMap { l ->
        fun title(n: Int) = when (l.key) {
            "sessions" -> "$n Sessions"; "tonnes" -> "${n}T Lifted"; "heaviest" -> "$n kg Lift"; else -> "$n Wk Streak"
        }
        val earned = l.steps.filter { l.value >= it }.map { Milestone("${l.key}-$it", l.icon, title(it), l.value, it) }
        val next = l.steps.firstOrNull { l.value < it }?.let { listOf(Milestone("${l.key}-$it", l.icon, title(it), l.value, it)) } ?: emptyList()
        earned + next
    }

    /** The grid on Records: each ladder's highest earned step and the next one up. */
    fun keyMilestones(history: List<Session>): List<Milestone> {
        val all = milestones(history)
        return ladders(history).flatMap { l ->
            val mine = all.filter { it.id.startsWith(l.key + "-") }
            listOfNotNull(mine.lastOrNull { it.earned }, mine.firstOrNull { !it.earned })
        }
    }

    /** The unearned milestone closest to done (by fraction). */
    fun nextBenchmark(history: List<Session>): Milestone? =
        milestones(history).filter { !it.earned }.maxByOrNull { it.value.toDouble() / it.goal }

    // ── Notifications ────────────────────────────────────────────────

    data class Notice(val id: String, val icon: String, val title: String, val body: String, val at: Double, val screen: Screen)

    /** The in-app inbox, newest first: reviews, records set in the last two
     *  weeks, milestones crossed in the last month, a deload warning.
     *  Derived from data the app already has — only when you last looked
     *  is stored (state `notifSeenAt`). */
    fun notifications(history: List<Session>, weekly: WeeklyReviewCache?, monthly: MonthlyReportCache?): List<Notice> {
        val out = ArrayList<Notice>()
        weekly?.let { r ->
            out.add(Notice("weekly-${r.week}", "doc.text.magnifyingglass", "Weekly review ready", r.text.take(120), r.at, Screen.Home))
        }
        monthly?.let { r ->
            out.add(Notice("monthly-${r.month}", "calendar", "Monthly report ready", "${r.sum.count} sessions · ${r.sum.volume.formatted()}kg lifted", r.at, Screen.Home))
        }
        val sorted = history.sortedBy { it.date }
        val prCutoff = Helpers.daysAgoStr(13)
        sorted.forEachIndexed { i, s ->
            if (s.date < prCutoff) return@forEachIndexed
            for (pr in Stats.detectPRs(s, sorted.subList(0, i))) {
                out.add(Notice(
                    "pr-${s.id}-${pr.name}-${pr.kind}", "trophy.fill", "New record: ${pr.name}",
                    "${if (pr.kind == "weight") "Heaviest set" else "Est. 1RM"} ${Helpers.fmtKg(pr.from)} → ${Helpers.fmtKg(pr.to)}kg",
                    at(s), Screen.Records,
                ))
            }
        }
        val msCutoff = Helpers.daysAgoStr(29)
        for (step in listOf(10, 25, 50, 100, 250)) {
            if (sorted.size >= step && sorted[step - 1].date >= msCutoff) {
                out.add(Notice("ms-sessions-$step", "rosette", "Milestone: $step sessions",
                    "Logged on ${Helpers.fmtDate(sorted[step - 1].date)}.", at(sorted[step - 1]), Screen.Records))
            }
        }
        Stats.deloadSignal(history)?.let { d ->
            val monday = Stats.mondayOf(Helpers.todayStr())
            out.add(Notice("deload-$monday", "exclamationmark.triangle.fill", "Deload suggested", d.reason, Stats.dateMs(monday) * 1000, Screen.Home))
        }
        return out.sortedByDescending { it.at }
    }

    /** When a session happened, in ms — its start time, else noon that day. */
    private fun at(s: Session): Double = if (s.startedAt > 0) s.startedAt else Stats.dateMs(s.date) * 1000
}
