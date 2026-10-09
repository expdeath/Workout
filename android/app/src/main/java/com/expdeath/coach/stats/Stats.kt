package com.expdeath.coach.stats

import com.expdeath.coach.models.Checkin
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.PRRecord
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.models.jobj
import com.expdeath.coach.models.lenientDouble
import com.expdeath.coach.models.lenientInt
import com.expdeath.coach.models.lenientString
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.models.parseInt
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.abs
import kotlin.math.max

/** Pure training-history math — full port of src/utils/stats.js (and
 *  Stats.swift). Feeds the AI prompt builder (progression targets, health
 *  baselines, deload/fatigue signals, muscle balance) and the screens. */
object Stats {
    private const val DAY = 86400.0

    /** Seconds since 1970 at local noon of `iso` (0 when it doesn't parse). */
    fun dateMs(iso: String): Double = Helpers.noonDate(iso)?.let { it.toEpochMilli() / 1000.0 } ?: 0.0

    // ── Regex helper (JS's `re.exec(t)` capture groups) ──────────────

    /** Capture groups (index 0 = whole match) for the first match, or null. */
    fun firstMatch(pattern: String, text: String, caseInsensitive: Boolean = true): List<String?>? {
        val re = try {
            if (caseInsensitive) Regex(pattern, RegexOption.IGNORE_CASE) else Regex(pattern)
        } catch (_: Exception) { return null }
        val m = re.find(text) ?: return null
        return m.groups.map { it?.value }
    }

    private fun testRegex(pattern: String, text: String, caseInsensitive: Boolean = true) =
        firstMatch(pattern, text, caseInsensitive) != null

    // ── Dates ────────────────────────────────────────────────────────

    fun mondayOf(iso: String): String {
        val d = Helpers.parseDate(iso) ?: return iso
        return d.minusDays((d.dayOfWeek.value - 1).toLong()).toString()
    }

    fun todayIso(): String = Helpers.todayStr()

    // ── Volume / best sets ───────────────────────────────────────────

    private fun bestSetWeight(session: Session, exIndex: Int): Double? {
        val sets = session.log.safe(exIndex) ?: return null
        var best: Double? = null
        for (s in sets) if (s.isLogged) {
            val w = parseDouble(s.weight) ?: continue
            if (best == null || w > best) best = w
        }
        return best
    }

    private fun bestSetE1RM(session: Session, exIndex: Int): Double? {
        val sets = session.log.safe(exIndex) ?: return null
        var best: Double? = null
        for (s in sets) if (s.isLogged) {
            val e = epley1RM(s.weight, s.reps) ?: continue
            if (best == null || e > best) best = e
        }
        return best
    }

    fun sessionVolume(session: Session): Int {
        var vol = 0.0
        for (ex in session.log) for (s in ex) if (s.isLogged) {
            val w = parseDouble(s.weight); val r = parseDouble(s.reps)
            if (w != null && r != null) vol += w * r
        }
        return vol.rounded().toInt()
    }

    data class ExercisePoint(val date: String, val w: Double, val e: Double?)
    data class ExerciseSeriesEntry(val name: String, val points: MutableList<ExercisePoint>)

    /** Per-exercise series across all history, most-trained first. */
    fun exerciseSeries(history: List<Session>): List<ExerciseSeriesEntry> {
        val map = LinkedHashMap<String, ExerciseSeriesEntry>()
        for (s in history) {
            s.plan.exercises.forEachIndexed { i, ex ->
                if (ex.name.isEmpty()) return@forEachIndexed
                val w = bestSetWeight(s, i) ?: return@forEachIndexed
                val key = ex.name.trim().lowercase()
                map.getOrPut(key) { ExerciseSeriesEntry(ex.name.trim(), ArrayList()) }
                    .points.add(ExercisePoint(s.date, w, bestSetE1RM(s, i)))
            }
        }
        return map.values.sortedByDescending { it.points.size }
    }

    data class WeeklyBucket(val start: String, var count: Int, var volume: Int)

    fun weeklyBuckets(history: List<Session>, n: Int = 8): List<WeeklyBucket> {
        val thisMonday = LocalDate.parse(mondayOf(todayIso()))
        val buckets = (n - 1 downTo 0).map { i -> WeeklyBucket(thisMonday.minusWeeks(i.toLong()).toString(), 0, 0) }
        val index = buckets.withIndex().associate { it.value.start to it.index }
        for (s in history) {
            val i = index[mondayOf(s.date)] ?: continue
            buckets[i].count += 1
            buckets[i].volume += sessionVolume(s)
        }
        return buckets
    }

    data class ProgressionEntry(val name: String, val from: Double, val to: Double)

    fun progressions(history: List<Session>, days: Int = 7): List<ProgressionEntry> {
        val cutoff = nowSec() - days * DAY
        val out = ArrayList<ProgressionEntry>()
        for (ex in exerciseSeries(history)) {
            val recent = ex.points.filter { dateMs(it.date) >= cutoff }
            val before = ex.points.filter { dateMs(it.date) < cutoff }
            if (recent.isEmpty() || before.isEmpty()) continue
            val to = recent.maxOf { it.w }
            val from = before.maxOf { it.w }
            if (to > from) out.add(ProgressionEntry(ex.name, from, to))
        }
        return out.sortedByDescending { it.to - it.from }.take(5)
    }

    data class WeekStats(val thisWeek: Int, val streak: Int)

    fun weekStats(history: List<Session>, target: Int = 3): WeekStats {
        val counts = HashMap<String, Int>()
        for (s in history) counts.merge(mondayOf(s.date), 1, Int::plus)
        val thisMonday = LocalDate.parse(mondayOf(todayIso()))
        val thisWeek = counts[thisMonday.toString()] ?: 0
        var streak = if (thisWeek >= target) 1 else 0
        var i = 1L
        while (true) {
            val wk = thisMonday.minusWeeks(i).toString()
            if ((counts[wk] ?: 0) >= target) streak += 1 else break
            i += 1
        }
        return WeekStats(thisWeek, streak)
    }

    data class LastPerformance(val date: String, val sets: List<SetLog>, val repsRange: String)

    fun lastPerformance(history: List<Session>, exerciseName: String): LastPerformance? {
        val key = exerciseName.trim().lowercase()
        if (key.isEmpty()) return null
        for (s in history.asReversed()) {
            val exI = s.plan.exercises.indexOfFirst { it.name.trim().lowercase() == key }
            if (exI < 0) continue
            val sets = (s.log.safe(exI) ?: emptyList()).filter { it.isLogged }
            if (sets.isNotEmpty()) return LastPerformance(s.date, sets, s.plan.exercises[exI].reps)
        }
        return null
    }

    /** +2.5kg if every set hit the top of the rep range (or +5kg if every
     *  set was tapped "easy"), unless any set was a "grind". */
    fun suggestNextWeight(lastPerf: LastPerformance?, repsRange: String): Double? {
        if (lastPerf == null || lastPerf.sets.isEmpty()) return null
        val topStr = repsRange.split('-', '–').last()
        val top = parseInt(topStr.trim(' ')) ?: return null
        if (top == 0) return null
        val weights = lastPerf.sets.mapNotNull { parseDouble(it.weight) }
        if (weights.isEmpty()) return null
        val allTopped = lastPerf.sets.all { (parseInt(it.reps) ?: 0) >= top }
        if (!allTopped) return null
        val efforts = lastPerf.sets.map { it.effort }.filter { it.isNotEmpty() }
        if ("grind" in efforts) return null
        val jump = if (efforts.size == lastPerf.sets.size && efforts.all { it == "easy" }) 5.0 else 2.5
        return minOf(weights.max() + jump, 200.0)
    }

    fun epley1RM(weight: String, reps: String): Double? {
        val w = parseDouble(weight) ?: return null
        val r = parseInt(reps) ?: return null
        if (w <= 0 || r <= 0) return null
        return (w * (1 + (r - 1) / 30.0) * 10).rounded() / 10
    }

    data class WeightRecord(val w: Double, val reps: String, val date: String)
    data class E1rmRecord(val v: Double, val date: String)
    data class ExercisePR(val name: String, var count: Int = 0, var weight: WeightRecord? = null, var e1rm: E1rmRecord? = null)

    /** All-time records per exercise, most-trained first. */
    fun prRecords(history: List<Session>): List<ExercisePR> {
        val map = LinkedHashMap<String, ExercisePR>()
        for (s in history) {
            s.plan.exercises.forEachIndexed { i, ex ->
                if (ex.name.isEmpty() || i >= s.log.size) return@forEachIndexed
                val key = ex.name.trim().lowercase()
                for (set in s.log[i]) {
                    if (!set.isLogged) continue
                    val w = parseDouble(set.weight) ?: continue
                    if (w <= 0) continue
                    val r = map.getOrPut(key) { ExercisePR(ex.name.trim()) }
                    r.count += 1
                    if (r.weight == null || w > r.weight!!.w) r.weight = WeightRecord(w, set.reps, s.date)
                    val e = epley1RM(set.weight, set.reps)
                    if (e != null && (r.e1rm == null || e > r.e1rm!!.v)) r.e1rm = E1rmRecord(e, s.date)
                }
            }
        }
        return map.values.sortedByDescending { it.count }
    }

    /** New records set by `session` vs `prior` history (which must not
     *  contain the session). First-time exercises don't count. */
    fun detectPRs(session: Session, prior: List<Session>): List<PRRecord> {
        val before = prRecords(prior).associateBy { it.name.lowercase() }
        val out = ArrayList<PRRecord>()
        for (rec in prRecords(listOf(session))) {
            val old = before[rec.name.lowercase()] ?: continue
            val rw = rec.weight; val ow = old.weight
            val re = rec.e1rm; val oe = old.e1rm
            if (rw != null && ow != null && rw.w > ow.w) {
                out.add(PRRecord(rec.name, "weight", ow.w, rw.w))
            } else if (re != null && oe != null && re.v > oe.v) {
                out.add(PRRecord(rec.name, "e1rm", oe.v, re.v))
            }
        }
        return out
    }

    /** Deterministic progression targets for the AI prompt. */
    fun progressionTargets(history: List<Session>, max: Int = 10): String {
        val out = ArrayList<String>()
        for (ex in exerciseSeries(history).take(max)) {
            val lp = lastPerformance(history, ex.name) ?: continue
            val target = suggestNextWeight(lp, lp.repsRange)
            val lastTxt = lp.sets.joinToString(" · ") { s -> s.formatted + (if (s.effort.isEmpty()) "" else "(${s.effort})") }
            val targetTxt = if (target != null) " → ready for ${fmtKg(target)}kg (all reps at top of range)" else " → hold weight, push reps"
            out.add("- ${ex.name}: last $lastTxt$targetTxt")
        }
        return out.joinToString("\n")
    }

    fun fmtKg(v: Double): String = if (v % 1.0 == 0.0) v.toInt().toString() else v.toString()

    // ── Health parsing ───────────────────────────────────────────────

    data class HealthNumbers(
        val hrv: Double? = null, val rhr: Double? = null, val steps: Double? = null, val sleepH: Double? = null,
        val vo2max: Double? = null, val kcal: Double? = null, val exerciseMin: Double? = null, val distKm: Double? = null,
        val spo2: Double? = null, val respRate: Double? = null, val wristC: Double? = null,
    )

    /** HRV / resting-HR / steps / sleep / VO2max / energy / SpO2 … numbers
     *  out of a free-form health string (Watch shortcut payload). */
    fun parseHealthNumbers(text: String?): HealthNumbers {
        val t = text ?: ""
        fun num(pattern: String, clampLow: Double? = null, clampHigh: Double? = null): Double? {
            val g = firstMatch(pattern, t) ?: return null
            val s = g.safe(1) ?: return null
            val n = parseDouble(s.replace(",", "")) ?: return null
            if (clampLow != null && clampHigh != null && !(n >= clampLow && n <= clampHigh)) return null
            return n
        }
        val hrv = num("""hrv[^\d]{0,14}([\d.]+)""")
        val rhr = num("""(?:rhr|resting[^\d]{0,12}(?:heart[^\d]{0,8})?(?:rate)?)[^\d]{0,14}([\d.]+)""")
        val stepsRaw = firstMatch("""\bsteps[^\d]{0,14}([\d,]+(?:\.\d+)?)""", t)?.safe(1)
        val steps = stepsRaw?.let { parseDouble(it.replace(",", "")) }?.rounded()

        var sleepH: Double? = null
        val slLabel = firstMatch("""sleep\s*hrs?:?\s*([\d.]+)""", t)
        val labelNum = slLabel?.safe(1)?.let { parseDouble(it) }
        if (labelNum != null) {
            var sh = labelNum
            if (sh > 1200) sh /= 3600 else if (sh > 20) sh /= 60
            if (sh > 11) sh /= 2
            sleepH = if (sh > 0 && sh < 20) (sh * 10).rounded() / 10 else null
        }
        if (sleepH == null && !testRegex("""sleep\s*hrs?:""", t)) {
            val sl = firstMatch("""sle(?:ep|pt)[^\d]{0,14}(\d{1,2})(?::(\d{2})|\s*h(?:ours?|rs?)?(?:\s*(\d{1,2})\s*m)?|(\.\d+))?""", t)
            var sh = sl?.safe(1)?.let { parseDouble(it) }
            if (sl != null && sh != null) {
                val mm = sl.safe(2)?.let { parseDouble(it) }
                val hm = sl.safe(3)?.let { parseDouble(it) }
                val frac = sl.safe(4)?.let { parseDouble(it) }
                when {
                    mm != null -> sh += mm / 60
                    hm != null -> sh += hm / 60
                    frac != null -> sh += frac
                }
                sleepH = if (sh > 0 && sh < 20) (sh * 10).rounded() / 10 else null
            }
        }

        val spo2 = num("""spo2[^\d]{0,14}([\d.]+)""")?.let { n ->
            val pct = if (n <= 1) (n * 1000).rounded() / 10 else n
            if (pct in 70.0..100.0) pct else null
        }

        return HealthNumbers(
            hrv = hrv, rhr = rhr, steps = steps, sleepH = sleepH,
            vo2max = num("""vo2\s*max[^\d]{0,14}([\d.]+)""", 10.0, 90.0),
            kcal = num("""(?:active\s*kcal|active\s*energy)[^\d]{0,14}([\d,]+(?:\.\d+)?)""", 1.0, 8000.0),
            exerciseMin = num("""exercise\s*min[^\d]{0,14}([\d,]+(?:\.\d+)?)""", 1.0, 1000.0),
            distKm = num("""distance\s*km[^\d]{0,14}([\d.]+)""", 0.1, 200.0),
            spo2 = spo2,
            respRate = num("""resp\s*rate[^\d]{0,14}([\d.]+)""", 5.0, 40.0),
            wristC = num("""wrist\s*temp[^\d]{0,14}([\d.]+)""", 20.0, 45.0),
        )
    }

    data class HealthBaseline(val hrv: Double?, val rhr: Double?, val sleepH: Double?, val respRate: Double?, val wristC: Double?)

    /** 30-day baselines (each needs ≥3 samples). */
    fun healthBaseline(history: List<Session>, healthLog: List<HealthRow>, days: Int = 30): HealthBaseline {
        val cutoff = nowSec() - days * DAY
        val acc = HashMap<String, MutableList<Double>>()
        val range = mapOf("hrv" to (5.0 to 300.0), "rhr" to (30.0 to 120.0), "sleepH" to (2.0 to 16.0), "respRate" to (5.0 to 40.0), "wristC" to (30.0 to 42.0))
        fun take(key: String, v: Double?) {
            if (v == null) return
            val r = range[key] ?: return
            if (v < r.first || v > r.second) return
            acc.getOrPut(key) { ArrayList() }.add(v)
        }
        val seen = HashSet<String>()
        for (h in healthLog) {
            if (dateMs(h.date) < cutoff) continue
            seen.add(h.date)
            take("hrv", h.hrv); take("rhr", h.rhr); take("sleepH", h.sleepH)
            take("respRate", h.respRate); take("wristC", h.wristC)
        }
        for (s in history) {
            if (dateMs(s.date) < cutoff || s.date in seen) continue
            val n = parseHealthNumbers(s.checkin?.health)
            take("hrv", n.hrv); take("rhr", n.rhr)
        }
        fun avg(key: String): Double? {
            val a = acc[key] ?: emptyList<Double>()
            if (a.size < 3) return null
            return (a.sum() / a.size * 10).rounded() / 10
        }
        return HealthBaseline(avg("hrv")?.rounded(), avg("rhr")?.rounded(), avg("sleepH"), avg("respRate"), avg("wristC"))
    }

    private fun r1(x: Double) = (x * 10).rounded() / 10

    /** Parsed health numbers → one compact human/AI-readable line. */
    fun fmtHealthLine(n: HealthNumbers): String {
        val bits = ArrayList<String>()
        n.hrv?.let { bits.add("HRV ${fmtKg(r1(it))}ms") }
        n.rhr?.let { bits.add("RHR ${it.rounded().toInt()}") }
        n.sleepH?.let { bits.add("sleep ${fmtKg(it)}h") }
        n.steps?.let { bits.add("${it.toInt()} steps") }
        n.vo2max?.let { bits.add("VO2max ${fmtKg(r1(it))}") }
        n.kcal?.let { bits.add("${it.rounded().toInt()}kcal active") }
        n.exerciseMin?.let { bits.add("${it.rounded().toInt()}min exercise") }
        n.distKm?.let { bits.add("${fmtKg(r1(it))}km") }
        n.spo2?.let { bits.add("SpO2 ${fmtKg(r1(it))}%") }
        n.respRate?.let { bits.add("RR ${fmtKg(r1(it))}/min") }
        n.wristC?.let { bits.add("wrist ${fmtKg(r1(it))}°C") }
        return bits.joinToString(" · ")
    }

    /** Text block of the last n days of Watch data, for the AI prompt. */
    fun healthTrend(healthLog: List<HealthRow>, n: Int = 7): String {
        val rows = healthLog.takeLast(n)
        if (rows.size < 2) return ""
        return rows.joinToString("\n") { h ->
            val bits = ArrayList<String>()
            h.hrv?.let { bits.add("HRV ${fmtKg(r1(it))}ms") }
            h.rhr?.let { bits.add("RHR ${it.rounded().toInt()}") }
            h.sleepH?.let { bits.add("sleep ${fmtKg(r1(it))}h") }
            h.weightKg?.let { bits.add("bodyweight ${fmtKg(r1(it))}kg") }
            h.steps?.let { bits.add("${it.toInt()} steps") }
            h.vo2max?.let { bits.add("VO2max ${fmtKg(r1(it))}") }
            h.respRate?.let { bits.add("RR ${fmtKg(r1(it))}/min") }
            h.wristC?.let { bits.add("wrist ${fmtKg(r1(it))}°C") }
            val joined = bits.joinToString(" · ")
            "${h.date}: ${joined.ifEmpty { h.raw ?: "—" }}"
        }
    }

    /** Volume + average RPE rising across 3 consecutive weeks → message for
     *  the AI prompt, or null. */
    fun fatigueSignal(history: List<Session>): String? {
        val weeks = weeklyBuckets(history, 4).take(3)
        if (!weeks.all { it.count >= 2 }) return null
        fun rpeOf(start: String): Double? {
            val vals = history.filter { mondayOf(it.date) == start && it.finished && it.fin != null }.map { it.fin!!.rpe.toDouble() }
            if (vals.isEmpty()) return null
            return vals.sum() / vals.size
        }
        val rpes = weeks.map { rpeOf(it.start) }
        if (!rpes.all { it != null }) return null
        val r = rpes.map { it!! }
        val volUp = weeks[0].volume < weeks[1].volume && weeks[1].volume < weeks[2].volume
        val rpeUp = r[0] < r[1] && r[1] < r[2]
        if (!(volUp && rpeUp)) return null
        val volStr = weeks.joinToString("→") { it.volume.toString() }
        val rpeStr = r.joinToString("→") { fmt("%.1f", it) }
        return "Training volume and average session RPE have both risen for 3 consecutive weeks (volume ${volStr}kg, RPE $rpeStr). Fatigue may be accumulating — consider a lighter session or deload if today's readiness is not clearly good."
    }

    data class StalledLift(val name: String, val weight: Double)

    fun stalledProgressions(history: List<Session>, days: Int = 35): List<StalledLift> {
        val cutoff = nowSec() - days * DAY
        val out = ArrayList<StalledLift>()
        for (ex in exerciseSeries(history)) {
            val recent = ex.points.filter { dateMs(it.date) >= cutoff }
            if (recent.size < 3) continue
            val last3 = recent.takeLast(3).map { it.w }
            val (a, b, c) = last3
            if (c <= a && c <= b) out.add(StalledLift(ex.name, c))
        }
        return out
    }

    data class DeloadSignal(val reason: String)

    fun deloadSignal(history: List<Session>): DeloadSignal? {
        if (fatigueSignal(history) != null) {
            return DeloadSignal("Volume and session effort have both climbed for 3 straight weeks. A lighter week now (−30-40% volume, nothing near failure) usually buys the next PR.")
        }
        val stalled = stalledProgressions(history)
        val weeks = weeklyBuckets(history, 4).take(3)
        val consistent = weeks.all { it.count >= 3 }
        if (consistent && stalled.size >= 2) {
            val names = stalled.take(3).joinToString(", ") { it.name }
            val verb = if (stalled.size > 1) "have" else "has"
            return DeloadSignal("$names $verb stopped progressing despite consistent training — a classic sign accumulated fatigue is masking fitness. Consider a deload week (−30-40% volume, no failure), then rebuild.")
        }
        return null
    }

    // ── Muscle-group tagging ─────────────────────────────────────────

    private val muscleRules: List<Pair<String, String>> = listOf(
        "Cardio" to """bike|cycling|treadmill|stair|elliptical|jump rope|sprint|incline walk|\berg\b|swim|\brun(?:ning)?\b|\bjogg?(?:ing)?\b|\brower\b|row(?:ing)?\s*machine|cross[- ]?trainer|air ?dyne|assault ?bike|brisk walk|walking pad|\bhike\b|hiking|\bruck(?:ing)?\b|\bcardio\b""",
        "Core" to """plank|crunch|\babs?\b|core|russian|leg raise|knee raise|dead bug|pallof|rollout|woodchop""",
        "Legs" to """squat|\bleg\b|lunge|calf|hamstring|quad|glute|hip thrust|\brdl\b|romanian|adductor|abductor|step[- ]?up|nordic|kettlebell swing|\bkb swing\b""",
        "Back" to """\brows?\b|rowing|pulldown|pull[- ]?down|pull[- ]?up|chin[- ]?up|\blats?\b|deadlift|shrug|back extension|face pull|hyperextension""",
        "Shoulders" to """shoulder|overhead|\bohp\b|lateral raise|side raise|rear delt|delt|arnold|military|upright""",
        "Chest" to """bench|chest|\bpecs?\b|\bfly\b|flye|dips?\b|push[- ]?up|crossover|incline.*press""",
        "Arms" to """curl|tricep|bicep|pushdown|push[- ]?down|extension|skull|hammer|preacher|kickback|forearm|wrist""",
    )

    fun muscleGroupOf(name: String?): String {
        val n = name ?: ""
        for ((group, pattern) in muscleRules) if (testRegex(pattern, n)) return group
        return "Other"
    }

    fun isCardio(name: String?) = muscleGroupOf(name) == "Cardio"

    private const val stretchPattern = """stretch|mobility|cat[- ]?cow|world'?s greatest|90.?90|couch|floss|thoracic|opener|pigeon|pose|yoga|foam roll|dead ?bug|bird ?dog|hollow|plank|cobra|down(?:ward)? dog|hip (?:switch|circle|opener)|breathing"""

    fun logMode(name: String?, sessionType: String?): String {
        if (isCardio(name)) return "cardio"
        if (testRegex(stretchPattern, name ?: "")) return "check"
        if (testRegex("""stretch|mobility|recovery""", sessionType ?: "")) return "check"
        return "strength"
    }

    data class MuscleBalanceEntry(val group: String, val sets: Int, val volume: Int, val lastDaysAgo: Int?)

    fun muscleBalance(history: List<Session>, days: Int = 14): List<MuscleBalanceEntry> {
        val cutoff = nowSec() - days * DAY
        class Acc { var sets = 0; var volume = 0.0; var last: Double? = null }
        val map = LinkedHashMap<String, Acc>()
        for (s in history) {
            s.plan.exercises.forEachIndexed { i, ex ->
                if (i >= s.log.size) return@forEachIndexed
                val done = s.log[i].filter { it.isLogged }
                if (done.isEmpty()) return@forEachIndexed
                val group = muscleGroupOf(ex.name)
                if (group == "Other" || group == "Cardio") return@forEachIndexed
                val g = map.getOrPut(group) { Acc() }
                val ms = dateMs(s.date)
                if (g.last == null || ms > g.last!!) g.last = ms
                if (ms >= cutoff) {
                    g.sets += done.size
                    for (set in done) {
                        val w = parseDouble(set.weight); val r = parseDouble(set.reps)
                        if (w != null && r != null) g.volume += w * r
                    }
                }
            }
        }
        return map.map { (group, g) ->
            MuscleBalanceEntry(
                group, g.sets, g.volume.rounded().toInt(),
                g.last?.let { max(0, ((nowSec() - it) / DAY).rounded().toInt()) },
            )
        }.sortedByDescending { it.sets }
    }

    fun muscleGapNote(history: List<Session>): String {
        val bal = muscleBalance(history)
        if (bal.isEmpty()) return ""
        val line = bal.joinToString(", ") { g ->
            val ago = if ((g.lastDaysAgo ?: 0) >= 7) " (last ${g.lastDaysAgo}d ago)" else ""
            "${g.group} ${g.sets} sets$ago"
        }
        val gaps = bal.filter { (it.lastDaysAgo ?: 0) >= 10 }.map { it.group }
        var out = "Muscle balance last 14 days: $line."
        if (gaps.isNotEmpty()) out += " NOT TRAINED IN 10+ DAYS: ${gaps.joinToString(", ")} — bias today's selection toward the gap if recovery allows."
        return out
    }

    val muscleFixTips = mapOf(
        "Legs" to "Leg Press, Romanian Deadlift, Walking Lunges",
        "Back" to "Lat Pulldown, Chest Supported Row, Face Pull",
        "Shoulders" to "Machine Shoulder Press, Cable Lateral Raise",
        "Chest" to "Flat Dumbbell Press, Incline Machine Press",
        "Arms" to "Cable Curl, Rope Tricep Pushdown",
        "Core" to "Plank, Cable Crunch, Hanging Knee Raise",
    )

    data class MuscleGap(val group: String, val lastDaysAgo: Int)

    fun biggestMuscleGap(history: List<Session>): MuscleGap? {
        val bal = muscleBalance(history).filter { (it.lastDaysAgo ?: -1) >= 10 }
        val worst = bal.maxByOrNull { it.lastDaysAgo!! } ?: return null
        return MuscleGap(worst.group, worst.lastDaysAgo!!)
    }

    // ── Recovery caution ("make it harder" nudge) ────────────────────

    fun recoveryCaution(checkin: Checkin?, history: List<Session>, healthLog: List<HealthRow>): String? {
        val bits = ArrayList<String>()
        if (testRegex("poor", checkin?.sleep ?: "")) bits.add("sleep was poor last night")
        val today = parseHealthNumbers(checkin?.health)
        val sh = today.sleepH
        if (sh != null && sh < 6 && bits.isEmpty()) bits.add("you only slept ${fmtKg(sh)}h")
        val base = healthBaseline(history, healthLog)
        if (today.hrv != null && base.hrv != null) {
            val d = (((today.hrv - base.hrv) / base.hrv) * 100).rounded().toInt()
            if (d <= -10) bits.add("HRV is ${abs(d)}% below your 30-day normal")
        }
        if (today.rhr != null && base.rhr != null) {
            val d = (((today.rhr - base.rhr) / base.rhr) * 100).rounded().toInt()
            if (d >= 7) bits.add("resting heart rate is running a bit high")
        }
        if (today.respRate != null && base.respRate != null && (today.respRate - base.respRate) / base.respRate >= 0.1) {
            bits.add("your overnight breathing rate is running high")
        }
        if (today.wristC != null && base.wristC != null && today.wristC - base.wristC >= 0.4) {
            bits.add("wrist temperature is above your normal — a common early illness sign")
        }
        if (testRegex("very sore", checkin?.soreness ?: "")) bits.add("you're still quite sore")
        if (fatigueSignal(history) != null) bits.add("volume and effort have been climbing for a few weeks")
        if (bits.isEmpty()) return null
        val list = if (bits.size > 1) bits.dropLast(1).joinToString(", ") + " and " + bits.last() else bits[0]
        return "Heads-up: $list. Extra work is your call — maybe keep a rep or two in the tank."
    }

    // ── Monthly / weekly reports ─────────────────────────────────────

    data class MonthSummary(
        val month: String,
        val count: Int, val prevCount: Int,
        val volume: Int, val prevVolume: Int,
        val split: String,
        val avgRpe: Double?,
        val progressions: String,
        val sleepAvg: Double?, val sleepPrev: Double?,
        val rhrAvg: Double?, val rhrPrev: Double?,
        val hrvAvg: Double?,
        val vo2Avg: Double?, val vo2Prev: Double?,
        val weightStart: Double?, val weightEnd: Double?,
    ) {
        fun toJson(): JSONValue = jobj {
            put("month", month); put("count", count); put("prevCount", prevCount)
            put("volume", volume); put("prevVolume", prevVolume); put("split", split)
            putIfPresent("avgRpe", avgRpe); put("progressions", progressions)
            putIfPresent("sleepAvg", sleepAvg); putIfPresent("sleepPrev", sleepPrev)
            putIfPresent("rhrAvg", rhrAvg); putIfPresent("rhrPrev", rhrPrev); putIfPresent("hrvAvg", hrvAvg)
            putIfPresent("vo2Avg", vo2Avg); putIfPresent("vo2Prev", vo2Prev)
            putIfPresent("weightStart", weightStart); putIfPresent("weightEnd", weightEnd)
        }

        companion object {
            fun fromJson(v: JSONValue): MonthSummary? {
                val c = v.obj ?: return null
                return MonthSummary(
                    month = c.lenientString("month") ?: return null,
                    count = c.lenientInt("count") ?: 0, prevCount = c.lenientInt("prevCount") ?: 0,
                    volume = c.lenientInt("volume") ?: 0, prevVolume = c.lenientInt("prevVolume") ?: 0,
                    split = c.lenientString("split") ?: "", avgRpe = c.lenientDouble("avgRpe"),
                    progressions = c.lenientString("progressions") ?: "",
                    sleepAvg = c.lenientDouble("sleepAvg"), sleepPrev = c.lenientDouble("sleepPrev"),
                    rhrAvg = c.lenientDouble("rhrAvg"), rhrPrev = c.lenientDouble("rhrPrev"),
                    hrvAvg = c.lenientDouble("hrvAvg"), vo2Avg = c.lenientDouble("vo2Avg"), vo2Prev = c.lenientDouble("vo2Prev"),
                    weightStart = c.lenientDouble("weightStart"), weightEnd = c.lenientDouble("weightEnd"),
                )
            }
        }
    }

    fun monthSummary(history: List<Session>, healthLog: List<HealthRow>, ym: String): MonthSummary? {
        val parts = ym.split("-").mapNotNull { it.toIntOrNull() }
        if (parts.size != 2) return null
        val prev = try { YearMonth.of(parts[0], parts[1]).minusMonths(1) } catch (_: Exception) { return null }
        val prevYm = "${prev.year}-${fmt("%02d", prev.monthValue)}"

        val sessions = history.filter { it.date.startsWith(ym) }
        if (sessions.isEmpty()) return null
        val prevSessions = history.filter { it.date.startsWith(prevYm) }

        val volume = sessions.sumOf { sessionVolume(it) }
        val prevVolume = prevSessions.sumOf { sessionVolume(it) }

        val ups = ArrayList<String>()
        for (ex in exerciseSeries(history)) {
            val inPts = ex.points.filter { it.date.startsWith(ym) }
            val before = ex.points.filter { it.date < "$ym-01" }
            if (inPts.isEmpty() || before.isEmpty()) continue
            val to = inPts.maxOf { it.w }; val from = before.maxOf { it.w }
            if (to > from) ups.add("${ex.name} ${fmtKg(from)}→${fmtKg(to)}kg")
        }

        val split = LinkedHashMap<String, Int>()
        for (s in sessions) split.merge(s.plan.sessionType.ifEmpty { "Other" }, 1, Int::plus)
        fun avg(arr: List<Double>): Double? = if (arr.isEmpty()) null else (arr.sum() / arr.size * 10).rounded() / 10
        val hRows = healthLog.filter { it.date.startsWith(ym) }
        val hPrev = healthLog.filter { it.date.startsWith(prevYm) }
        fun pick(rows: List<HealthRow>, f: (HealthRow) -> Double?) = rows.mapNotNull(f).filter { it > 0 }
        val weights = pick(hRows) { it.weightKg }
        val rpes = sessions.mapNotNull { it.fin?.rpe?.toDouble() }
        val upsTxt = ups.take(6).joinToString(", ")

        return MonthSummary(
            month = ym, count = sessions.size, prevCount = prevSessions.size,
            volume = volume, prevVolume = prevVolume,
            split = split.entries.sortedByDescending { it.value }.joinToString(", ") { "${it.key} ${it.value}" },
            avgRpe = avg(rpes),
            progressions = upsTxt.ifEmpty { "none" },
            sleepAvg = avg(pick(hRows) { it.sleepH }), sleepPrev = avg(pick(hPrev) { it.sleepH }),
            rhrAvg = avg(pick(hRows) { it.rhr }), rhrPrev = avg(pick(hPrev) { it.rhr }),
            hrvAvg = avg(pick(hRows) { it.hrv }),
            vo2Avg = avg(pick(hRows) { it.vo2max }), vo2Prev = avg(pick(hPrev) { it.vo2max }),
            weightStart = weights.firstOrNull(), weightEnd = weights.lastOrNull(),
        )
    }

    data class WeekSummary(val count: Int, val lines: String, val progressions: String)

    fun lastWeekSummary(history: List<Session>): WeekSummary? {
        val cutoff = nowSec() - 7 * DAY
        val recent = history.filter { dateMs(it.date) >= cutoff }
        if (recent.isEmpty()) return null
        val lines = recent.map { s ->
            val vol = sessionVolume(s)
            val notFinished = if (s.finished) "" else " (not finished)"
            val rpe = s.fin?.rpe?.toString() ?: "?"
            val pain = if (s.fin?.pain?.isNotEmpty() == true) ", pain: ${s.fin.pain}" else ""
            val volTxt = if (vol > 0) ", volume ${vol}kg" else ""
            "${s.date} ${s.plan.sessionType}$notFinished — RPE $rpe$pain$volTxt"
        }
        val ups = progressions(history, 7).map { "${it.name} ${fmtKg(it.from)}→${fmtKg(it.to)}kg" }
        return WeekSummary(recent.size, lines.joinToString("\n"), if (ups.isEmpty()) "none" else ups.joinToString(", "))
    }

    // ── Goals (Goals.swift) ──────────────────────────────────────────

    data class GoalProgress(val text: String, val current: Double?, val target: Double?, val unit: String)

    /** Goals (one per line, Settings → AI Coach) → progress, like
     *  goalProgress() in stats.js: "4 sessions a week" tracks this week's
     *  count; "Bench Press 80kg" tracks the best set of the matching
     *  exercise; anything else is listed without a bar. */
    fun goalProgress(history: List<Session>, goalsText: String): List<GoalProgress> {
        val lines = goalsText.split("\n").map { it.trim(' ') }.filter { it.isNotEmpty() }
        if (lines.isEmpty()) return emptyList()
        val records = prRecords(history)
        val thisWeek = weekStats(history).thisWeek
        return lines.map { text ->
            val g = firstMatch("""(\d+)\s*(?:x|sessions?|days?)\s*(?:a|per|/)\s*week""", text)
            val n = g?.safe(1)?.let { parseDouble(it) }
            if (n != null) return@map GoalProgress(text, thisWeek.toDouble(), n, " this week")
            val k = firstMatch("""^(.*?)\s+(\d+(?:\.\d+)?)\s*kg\b""", text)
            val namePart = k?.safe(1)?.trim(' ')?.lowercase()
            val target = k?.safe(2)?.let { parseDouble(it) }
            if (namePart != null && target != null) {
                val rec = records.firstOrNull { r ->
                    r.weight != null && (r.name.lowercase().contains(namePart) || namePart.contains(r.name.lowercase()))
                }
                val w = rec?.weight
                if (w != null) return@map GoalProgress(text, w.w, target, "kg")
            }
            GoalProgress(text, null, null, "")
        }
    }
}
