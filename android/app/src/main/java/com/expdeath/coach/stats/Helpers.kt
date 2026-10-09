package com.expdeath.coach.stats

import com.expdeath.coach.models.Checkin
import com.expdeath.coach.models.parseDouble
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor

/** Swift's `.rounded()` — to nearest, halves away from zero (JS Math.round
 *  for the positive numbers this app deals in). */
fun Double.rounded(): Double = if (this >= 0) floor(this + 0.5) else -floor(-this + 0.5)

/** Milliseconds since 1970, as JS Date.now(). */
fun nowMs(): Double = System.currentTimeMillis().toDouble()

/** Seconds since 1970, as Swift Date().timeIntervalSince1970. */
fun nowSec(): Double = System.currentTimeMillis() / 1000.0

/** `String(format:)` with the POSIX locale (no thousands separators, '.' decimals). */
fun fmt(format: String, vararg args: Any?): String = String.format(Locale.US, format, *args)

/** Thousands-separated integer, like Swift's `Int.formatted()`. */
fun Int.formatted(): String = String.format(Locale.getDefault(), "%,d", this)

/** nil instead of a crash for an out-of-range index — shared app-wide. */
fun <T> List<T>.safe(i: Int): T? = if (i in indices) this[i] else null

/** Date formatting and set-input sanitation — ports helpers.js. */
object Helpers {
    val zone: ZoneId get() = ZoneId.systemDefault()

    fun todayStr(): String = LocalDate.now(zone).toString()

    fun parseDate(iso: String): LocalDate? = try { LocalDate.parse(iso) } catch (_: Exception) { null }

    /** "2026-08-29" → noon that day, local time (the web's `date + 'T12:00:00'`), in ms. */
    fun noonDate(iso: String): Instant? = parseDate(iso)?.atTime(12, 0)?.atZone(zone)?.toInstant()

    /** "2026-08-29" → "Sat, Aug 29" — fmtDate() in helpers.js. */
    fun fmtDate(iso: String): String {
        val d = parseDate(iso) ?: return iso
        return d.format(DateTimeFormatter.ofPattern("EEE, MMM d", Locale.getDefault()))
    }

    // ── Set-input sanitation — clamp instead of reject: typos like
    //    1000kg become 200, so nothing silly reaches the log or the AI.

    const val maxWeightKg = 200.0
    const val maxReps = 30
    const val maxTimeMin = 300.0
    const val maxDistKm = 100.0

    private fun cleanDecimal(v: String, max: Double): String {
        var s = v.filter { it.isDigit() || it == '.' }
        val firstDot = s.indexOf('.')
        if (firstDot >= 0) {
            val afterDot = s.substring(firstDot + 1).filter { it != '.' }
            s = s.substring(0, firstDot) + "." + afterDot.take(2)
        }
        if (s.isEmpty()) return ""
        val n = parseDouble(s)
        if (n != null && n > max) {
            return if (max % 1.0 == 0.0) max.toInt().toString() else max.toString()
        }
        return s
    }

    fun cleanWeight(v: String) = cleanDecimal(v, maxWeightKg)
    fun cleanTime(v: String) = cleanDecimal(v, maxTimeMin)
    fun cleanDist(v: String) = cleanDecimal(v, maxDistKm)

    fun cleanReps(v: String): String {
        val s = v.filter { it.isDigit() }
        if (s.isEmpty()) return ""
        val n = s.toIntOrNull() ?: return ""
        return minOf(n, maxReps).toString()
    }

    /** The date `n` days before todayStr() — daysAgoStr() (backdating quick logs). */
    fun daysAgoStr(n: Int): String = LocalDate.now(zone).minusDays(n.toLong()).toString()

    /** Client-side readiness estimate shown before the AI answers — quickReadiness(). */
    fun quickReadiness(c: Checkin): Int {
        var s = 50
        s += (c.energy - 5) * 5
        when (c.sleep) {
            "Great" -> s += 15
            "OK" -> s += 5
            "Poor" -> s -= 15
        }
        when (c.soreness) {
            "None" -> s += 10
            "Light" -> s -= 5
            "Very sore" -> s -= 20
        }
        if (c.backTight) s -= 8
        return s.coerceIn(5, 98)
    }

    // ── Plate math (DEFAULT_BAR_KG / parsePlates / plateBreakdown) ──

    const val defaultBarKg = 20.0
    val defaultPlates = listOf(25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25)

    /** "25, 20, 2.5" → [25, 20, 2.5] (deduped, largest first), or null. */
    fun parsePlates(text: String?): List<Double>? {
        val list = (text ?: "").split(Regex("[,\\s]+")).filter { it.isNotEmpty() }
            .mapNotNull { parseDouble(it) }
            .filter { it > 0 && it <= 50 }
        return if (list.isEmpty()) null else list.toSet().sortedDescending()
    }

    data class PlateBreakdown(val bar: Double, val perSide: List<Double>, val loaded: Double, val exact: Boolean)

    /** Greedy per-side barbell breakdown for a target total, or null when
     *  the target isn't a positive number. */
    fun plateBreakdown(target: Double?, barKg: Double = defaultBarKg, plates: List<Double> = defaultPlates): PlateBreakdown? {
        val t = target ?: return null
        if (t <= 0) return null
        if (t <= barKg) return PlateBreakdown(barKg, emptyList(), barKg, t == barKg)
        var side = (t - barKg) / 2
        val perSide = ArrayList<Double>()
        for (p in plates.sortedDescending()) {
            while (side >= p - 1e-9) {
                perSide.add(p)
                side -= p
            }
        }
        val loaded = barKg + 2 * perSide.sum()
        return PlateBreakdown(barKg, perSide, loaded, abs(loaded - t) < 0.05)
    }

    /** JS-style number text: 20 not 20.0, 2.5 stays 2.5. */
    fun fmtKg(n: Double): String = if (n.rounded() == n && abs(n) < 1e15) n.toLong().toString() else n.toString()
}
