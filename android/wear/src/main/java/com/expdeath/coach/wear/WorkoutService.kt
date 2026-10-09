package com.expdeath.coach.wear

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseTrackedStatus
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import androidx.concurrent.futures.await
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import com.expdeath.coach.watchlink.WatchCommand
import com.expdeath.coach.watchlink.WatchState
import com.expdeath.coach.watchlink.WorkoutSummary
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.launch
import java.time.Instant

/** Runs for the length of a workout — the Wear OS twin of the Apple Watch
 *  app's HKWorkoutSession:
 *   • heart rate and energy from Health Services (shown live, sent to the
 *     phone at the end so it lands in Health Connect);
 *   • the rest-over buzz, on time with the screen off (a foreground
 *     service holding a wake lock only while a rest counts down);
 *   • the watch-face chip that brings COACH back with one tap.
 *  It stops itself when the phone's session finishes or is cancelled. */
class WorkoutService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var restJob: Job? = null
    private var ownsExercise = false
    private var startedAt = 0L
    private var lastSampleAt = 0L
    private val samples = ArrayList<Pair<Long, Int>>()
    private var kcal: Double? = null
    private var sessionType = ""
    private var finishing = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        PhoneLink.init(this)
        running = true
        startedAt = System.currentTimeMillis()
        startInForeground()
        scope.launch { startExercise() }
        scope.launch {
            PhoneLink.state.distinctUntilChangedBy { listOf(it.active, it.finished, it.rest, it.id) }.collect { s -> onState(s) }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        running = false
        heartRate.value = null
        scope.cancel()
        super.onDestroy()
    }

    private fun onState(s: WatchState) {
        if (s.type.isNotEmpty()) sessionType = s.type
        // finished: file it in Health Connect · cancelled on the phone: drop it
        if (!s.active) { finish(save = s.finished); return }
        scheduleRestBuzz(s)
    }

    // ── Rest ─────────────────────────────────────────────────────

    private fun scheduleRestBuzz(s: WatchState) {
        restJob?.cancel()
        val rest = s.rest ?: return
        val left = rest.endsAt - System.currentTimeMillis()
        if (left <= 0) return
        restJob = scope.launch {
            val wl = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "coach:rest").apply { acquire(left + 5_000) }
            try {
                if (left > 10_000) { delay(left - 10_000); buzz(longArrayOf(0, 60)) } // 10 s to go
                delay((rest.endsAt - System.currentTimeMillis()).coerceAtLeast(0))
                buzz(longArrayOf(0, 250, 120, 250, 120, 400)) // GO
            } finally {
                if (wl.isHeld) wl.release()
            }
        }
    }

    private fun buzz(pattern: LongArray) {
        val v = getSystemService(VibratorManager::class.java)?.defaultVibrator ?: return
        v.vibrate(VibrationEffect.createWaveform(pattern, -1))
    }

    // ── Heart rate (Health Services) ─────────────────────────────

    private val callback = object : ExerciseUpdateCallback {
        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            val boot = Instant.ofEpochMilli(System.currentTimeMillis() - SystemClock.elapsedRealtime())
            for (p in update.latestMetrics.getData(DataType.HEART_RATE_BPM)) {
                val bpm = p.value.toInt()
                if (bpm <= 0) continue
                heartRate.value = bpm
                val at = p.getTimeInstant(boot).toEpochMilli()
                if (at - lastSampleAt >= 5_000) { samples.add(at to bpm); lastSampleAt = at } // one every 5 s is plenty
            }
            update.latestMetrics.getData(DataType.CALORIES_TOTAL)?.let { kcal = it.total }
        }

        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) {}
        override fun onRegistered() {}
        override fun onRegistrationFailed(throwable: Throwable) {}
        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {}
    }

    private suspend fun startExercise() {
        if (!hasSensorPermission(this)) return
        try {
            val client = HealthServices.getClient(this).exerciseClient
            // never take over a run the watch's own app is tracking
            val info = client.getCurrentExerciseInfoAsync().await()
            if (info.exerciseTrackedStatus == ExerciseTrackedStatus.OTHER_APP_IN_PROGRESS) return
            val caps = client.getCapabilitiesAsync().await()
            val type = exerciseType(PhoneLink.state.value.type).takeIf { it in caps.supportedExerciseTypes } ?: ExerciseType.WORKOUT
            val supported = caps.getExerciseTypeCapabilities(type).supportedDataTypes
            val types = setOf(DataType.HEART_RATE_BPM, DataType.CALORIES_TOTAL).filter { it in supported }.toSet()
            client.setUpdateCallback(callback)
            client.startExerciseAsync(
                ExerciseConfig.builder(type).setDataTypes(types).setIsAutoPauseAndResumeEnabled(false).setIsGpsEnabled(false).build()
            ).await()
            ownsExercise = true
        } catch (_: Exception) {}
    }

    private fun finish(save: Boolean) {
        if (finishing) return
        finishing = true
        scope.launch {
            if (ownsExercise) try {
                val client = HealthServices.getClient(this@WorkoutService).exerciseClient
                client.endExerciseAsync().await()
                client.clearUpdateCallbackAsync(callback).await()
            } catch (_: Exception) {}
            val end = System.currentTimeMillis()
            // a few minutes of browsing isn't a workout worth filing
            if (save && ownsExercise && end - startedAt > 5 * 60_000L) {
                val bpm = samples.map { it.second }
                PhoneLink.send(WatchCommand.WORKOUT, workout = WorkoutSummary(
                    start = startedAt, end = end, type = sessionType, kcal = kcal,
                    avgHr = bpm.takeIf { it.isNotEmpty() }?.average(), maxHr = bpm.maxOrNull()?.toDouble(), hr = samples.toList(),
                ))
            }
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    // ── Foreground + watch-face chip ─────────────────────────────

    private fun startInForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Workout", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, WatchActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val title = PhoneLink.state.value.type.ifEmpty { "Workout" }
        val n = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("COACH")
            .setContentText(title)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setOngoing(true)
            .setContentIntent(open)
        OngoingActivity.Builder(this, NOTIFICATION_ID, n)
            .setStaticIcon(R.mipmap.ic_launcher)
            .setTouchIntent(open)
            .setStatus(Status.Builder().addTemplate("#type#").addPart("type", Status.TextPart(title)).build())
            .build()
            .apply(this)
        val fgsType = if (hasSensorPermission(this)) ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH else 0
        try {
            if (fgsType != 0) startForeground(NOTIFICATION_ID, n.build(), fgsType) else startForeground(NOTIFICATION_ID, n.build())
        } catch (_: Exception) {
            // not allowed to run in the foreground (e.g. sensors permission refused):
            // the activity still buzzes while it's on screen
            stopSelf()
        }
    }

    companion object {
        private const val CHANNEL = "workout"
        private const val NOTIFICATION_ID = 7
        @Volatile var running = false
        /** The latest heart rate, for the UI. */
        val heartRate = MutableStateFlow<Int?>(null)

        /** Heart rate on Wear OS 6+ is a Health permission; BODY_SENSORS before it. */
        val sensorPermission: String
            get() = if (Build.VERSION.SDK_INT >= 36) "android.permission.health.READ_HEART_RATE" else Manifest.permission.BODY_SENSORS

        fun hasSensorPermission(ctx: Context) =
            ContextCompat.checkSelfPermission(ctx, sensorPermission) == PackageManager.PERMISSION_GRANTED

        fun start(ctx: Context) {
            if (running) return
            ContextCompat.startForegroundService(ctx, Intent(ctx, WorkoutService::class.java))
        }

        /** Health Services' activity for a COACH session type. */
        fun exerciseType(sessionType: String): ExerciseType = when (sessionType.lowercase()) {
            "run" -> ExerciseType.RUNNING
            "cycle" -> ExerciseType.BIKING
            "walk" -> ExerciseType.WALKING
            "hike" -> ExerciseType.HIKING
            "stretch & mobility", "active recovery" -> ExerciseType.STRETCHING
            "cardio" -> ExerciseType.WORKOUT
            else -> ExerciseType.STRENGTH_TRAINING
        }
    }
}
