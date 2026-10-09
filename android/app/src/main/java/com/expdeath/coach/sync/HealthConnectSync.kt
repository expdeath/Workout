package com.expdeath.coach.sync

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.expdeath.coach.app.CoachApplication
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.persistence.Defaults
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.fmt
import com.expdeath.coach.stats.rounded
import kotlinx.coroutines.CompletableDeferred
import java.time.Instant
import java.time.LocalDate
import kotlin.reflect.KClass

/** Health Connect → the account's health rows — the Android twin of
 *  HealthKitSync.swift (which replaced the Gym Check-in Shortcut → GitHub
 *  health-inbox pipeline; the inbox is still drained, so both can run side
 *  by side).
 *
 *  Reads the same metrics per calendar day and writes them the way the rest
 *  of the system already understands: typed fields on the day's HealthRow
 *  (mergeHealth — never clobbers fields another source wrote) plus the same
 *  "HRVavg(ms): … SleepHrs: …" text the Shortcut produced, which pre-fills
 *  today's check-in (healthText-<date>) and feeds the AI. Health Connect's
 *  aggregates de-duplicate sources, and sleep intervals are merged — so a
 *  night recorded by both a watch and the phone counts once.
 *
 *  Differences from HealthKit, by necessity: HRV is RMSSD (Health Connect
 *  has no SDNN); there's no wrist-temperature reading to map. */
object HealthConnectSync {
    private val ctx get() = CoachApplication.context

    val isAvailable: Boolean
        get() = HealthConnectClient.getSdkStatus(ctx) == HealthConnectClient.SDK_AVAILABLE

    /** Health Connect is on the device but needs installing/updating. */
    val needsUpdate: Boolean
        get() = HealthConnectClient.getSdkStatus(ctx) == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED

    private val client: HealthConnectClient get() = HealthConnectClient.getOrCreate(ctx)

    /** Whether the permission sheet has been shown on this device. */
    var requested: Boolean
        get() = Defaults.string("healthconnect-requested") == "1"
        set(v) = Defaults.set(if (v) "1" else null, "healthconnect-requested")

    private val recordTypes: List<KClass<out Record>> = listOf(
        HeartRateVariabilityRmssdRecord::class, RestingHeartRateRecord::class, StepsRecord::class, Vo2MaxRecord::class,
        ActiveCaloriesBurnedRecord::class, ExerciseSessionRecord::class, DistanceRecord::class, RespiratoryRateRecord::class,
        WeightRecord::class, OxygenSaturationRecord::class, SleepSessionRecord::class,
    )

    val permissions: Set<String> = recordTypes.map { HealthPermission.getReadPermission(it) }.toSet()

    /** MainActivity's permission launcher — set while the activity lives. */
    var launcher: ((Set<String>) -> Unit)? = null
    private var pending: CompletableDeferred<Set<String>>? = null

    /** Called by MainActivity with what the user granted. */
    fun onPermissionResult(granted: Set<String>) {
        pending?.complete(granted)
        pending = null
    }

    /** Shows Health Connect's permission screen. Returns true when anything was granted. */
    suspend fun requestAccess(): Boolean {
        if (!isAvailable) return false
        val launch = launcher ?: return false
        val d = CompletableDeferred<Set<String>>()
        pending = d
        launch(permissions)
        val granted = d.await()
        requested = true
        return granted.isNotEmpty()
    }

    suspend fun grantedCount(): Int = try {
        if (!isAvailable) 0 else client.permissionController.getGrantedPermissions().intersect(permissions).size
    } catch (_: Exception) { 0 }

    // ── Sync ─────────────────────────────────────────────────────

    /** Bump when how a day is read changes: the next sync re-reads every
     *  day in range once (not only missing ones), fixing stored rows. */
    private const val READ_VERSION = "1"

    /** Today plus any of the last `days` days with no row yet. Returns how
     *  many days were written. */
    suspend fun sync(days: Int = 7): Int {
        if (!isAvailable || !requested || (Cloud.account == null && !Cloud.offline)) return 0
        if (grantedCount() == 0) return 0
        val reread = Defaults.string("healthconnect-read-version") != READ_VERSION
        val today = LocalDate.now(Helpers.zone)
        val have = LocalStore.backup.health.map { it.date }.toSet()
        var written = 0
        for (back in 0 until days) {
            val day = today.minusDays(back.toLong())
            val iso = day.toString()
            // past days: only fill gaps (a finished day doesn't change);
            // today: always refresh — steps/kcal keep climbing
            if (back > 0 && iso in have && !reread) continue
            val m = try { readDay(day) } catch (_: Exception) { continue }
            if (m.isEmpty) continue
            val text = m.shortcutText
            LocalStore.mergeHealth(HealthRow(
                date = iso, hrv = m.hrv, rhr = m.rhr, steps = m.steps, sleepH = m.sleepH, weightKg = m.weightKg,
                respRate = m.respRate, wristC = m.wristC, vo2max = m.vo2max, kcal = m.kcal,
                exerciseMin = m.exerciseMin, distKm = m.distKm, spo2 = m.spo2, raw = text.take(300),
            ))
            if (back == 0) Cloud.setState("healthText-$iso", JSONValue.Str(text))
            written += 1
        }
        if (reread && days >= 7) Defaults.set(READ_VERSION, "healthconnect-read-version")
        if (written > 0) LocalStore.logEvent("healthconnect_synced", mapOf("days" to JSONValue.Num(written.toDouble())))
        return written
    }

    // ── One day ──────────────────────────────────────────────────

    data class DayMetrics(
        val hrv: Double? = null, val rhr: Double? = null, val steps: Double? = null, val sleepH: Double? = null,
        val vo2max: Double? = null, val kcal: Double? = null, val exerciseMin: Double? = null, val distKm: Double? = null,
        val respRate: Double? = null, val wristC: Double? = null, val weightKg: Double? = null, val spo2: Double? = null,
    ) {
        val isEmpty: Boolean
            get() = listOf(hrv, rhr, steps, sleepH, vo2max, kcal, exerciseMin, distKm, respRate, wristC, weightKg, spo2).all { it == null }

        /** The Gym Check-in Shortcut's text format, so parseHealthNumbers
         *  (every app) reads it exactly like a Shortcut delivery. */
        val shortcutText: String
            get() {
                fun f(v: Double?, digits: Int = 1) = v?.let { fmt("%.${digits}f", it) } ?: ""
                return listOf(
                    "HRVavg(ms): ${f(hrv)}", "RHRavg(bpm): ${f(rhr)}", "StepsToday: ${f(steps, 0)}",
                    "SleepHrs: ${f(sleepH, 2)}", "VO2Max: ${f(vo2max)}", "ActiveKcal: ${f(kcal, 0)}",
                    "ExerciseMin: ${f(exerciseMin, 0)}", "DistanceKm: ${f(distKm, 2)}",
                    "RespRate(brpm): ${f(respRate)}", "WristTemp: ${f(wristC, 2)}",
                    weightKg?.let { "Weight ${fmt("%.1f", it)}kg" } ?: "",
                    spo2?.let { "SpO2 ${fmt("%.0f", it)}%" } ?: "",
                ).filter { !it.endsWith(": ") && it.isNotEmpty() }.joinToString(" ")
            }
    }

    private fun startOf(day: LocalDate): Instant = day.atStartOfDay(Helpers.zone).toInstant()

    private suspend fun <T : Record> records(type: KClass<T>, start: Instant, end: Instant): List<T> = try {
        val out = ArrayList<T>()
        var token: String? = null
        do {
            val r = client.readRecords(ReadRecordsRequest(type, TimeRangeFilter.between(start, end), pageToken = token))
            out.addAll(r.records)
            token = r.pageToken
        } while (token != null)
        out
    } catch (_: Exception) { emptyList() }

    suspend fun readDay(day: LocalDate): DayMetrics {
        val start = startOf(day)
        val end = startOf(day.plusDays(1))
        val agg = try {
            client.aggregate(AggregateRequest(
                setOf(
                    StepsRecord.COUNT_TOTAL, ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL,
                    DistanceRecord.DISTANCE_TOTAL, ExerciseSessionRecord.EXERCISE_DURATION_TOTAL, RestingHeartRateRecord.BPM_AVG,
                ),
                TimeRangeFilter.between(start, end),
            ))
        } catch (_: Exception) { null }

        val hrv = records(HeartRateVariabilityRmssdRecord::class, start, end).map { it.heartRateVariabilityMillis }.averageOrNull()
        val resp = records(RespiratoryRateRecord::class, start, end).map { it.rate }.averageOrNull()
        val spo2 = records(OxygenSaturationRecord::class, start, end).map { it.percentage.value }.averageOrNull()
        // VO₂max is measured every few days — the latest value up to this day
        val vo2 = records(Vo2MaxRecord::class, end.minusSeconds(30 * 86400L), end).maxByOrNull { it.time }?.vo2MillilitersPerMinuteKilogram
        val weight = records(WeightRecord::class, end.minusSeconds(86400L), end).maxByOrNull { it.time }?.weight?.inKilograms

        return DayMetrics(
            hrv = hrv,
            rhr = agg?.get(RestingHeartRateRecord.BPM_AVG)?.toDouble(),
            steps = agg?.get(StepsRecord.COUNT_TOTAL)?.toDouble()?.rounded(),
            kcal = agg?.get(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)?.inKilocalories?.takeIf { it > 0 },
            exerciseMin = agg?.get(ExerciseSessionRecord.EXERCISE_DURATION_TOTAL)?.toMillis()?.let { it / 60000.0 }?.takeIf { it > 0 },
            distKm = agg?.get(DistanceRecord.DISTANCE_TOTAL)?.inKilometers?.takeIf { it > 0 },
            respRate = resp,
            wristC = null,
            spo2 = spo2,
            vo2max = vo2,
            weightKg = weight,
            sleepH = sleepHours(day),
        )
    }

    private fun List<Double>.averageOrNull(): Double? = if (isEmpty()) null else average()

    private val asleepStages = setOf(
        SleepSessionRecord.STAGE_TYPE_SLEEPING, SleepSessionRecord.STAGE_TYPE_LIGHT,
        SleepSessionRecord.STAGE_TYPE_DEEP, SleepSessionRecord.STAGE_TYPE_REM,
    )

    /** The night ending on this day: asleep intervals between 18:00 the
     *  evening before and 14:00 this day, from every source, merged so
     *  watch + phone overlap is counted once. */
    private suspend fun sleepHours(day: LocalDate): Double? {
        val dayStart = startOf(day)
        val start = dayStart.minusSeconds(6 * 3600L)
        val end = dayStart.plusSeconds(14 * 3600L)
        val intervals = ArrayList<Pair<Instant, Instant>>()
        for (s in records(SleepSessionRecord::class, start, end)) {
            // a session without stages counts as asleep throughout
            val parts = if (s.stages.isEmpty()) listOf(s.startTime to s.endTime)
            else s.stages.filter { it.stage in asleepStages }.map { it.startTime to it.endTime }
            for ((a, b) in parts) intervals.add(maxOf(a, start) to minOf(b, end))
        }
        val hours = mergedDurationSec(intervals.map { it.first.toEpochMilli() / 1000.0 to it.second.toEpochMilli() / 1000.0 }) / 3600
        return if (hours > 0) (hours * 100).rounded() / 100 else null
    }

    /** Total seconds covered by possibly-overlapping (start, end) intervals. */
    fun mergedDurationSec(intervals: List<Pair<Double, Double>>): Double {
        var total = 0.0
        var cur: Pair<Double, Double>? = null
        for (iv in intervals.sortedBy { it.first }) {
            if (iv.second - iv.first <= 0) continue
            val c = cur
            if (c != null && iv.first <= c.second) {
                cur = c.first to maxOf(c.second, iv.second)
            } else {
                if (c != null) total += c.second - c.first
                cur = iv
            }
        }
        return total + (cur?.let { it.second - it.first } ?: 0.0)
    }
}
