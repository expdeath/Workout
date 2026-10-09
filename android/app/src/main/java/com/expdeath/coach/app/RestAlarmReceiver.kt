package com.expdeath.coach.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.expdeath.coach.R

/** The rest timer's "Rest over — GO" alert. A real alarm-backed
 *  notification, so it fires with the phone locked or in another app — the
 *  Android twin of the iPhone app's UNUserNotificationCenter request. */
object RestNotifier {
    private const val SOUND = "rest_sound"
    private const val SILENT = "rest_silent"
    private const val ID = 4201

    private fun channels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(SOUND, "Rest timer", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "When the rest between sets is over"
        })
        nm.createNotificationChannel(NotificationChannel(SILENT, "Rest timer (silent)", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "When the rest between sets is over, without a sound"
            setSound(null, null)
        })
    }

    private fun pending(ctx: Context, exName: String, sound: Boolean): PendingIntent =
        PendingIntent.getBroadcast(
            ctx, ID,
            Intent(ctx, RestAlarmReceiver::class.java).putExtra("ex", exName).putExtra("sound", sound),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun canNotify(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun schedule(ctx: Context, seconds: Double, exName: String, sound: Boolean) {
        channels(ctx)
        val am = ctx.getSystemService(AlarmManager::class.java)
        val at = SystemClock.elapsedRealtime() + (seconds * 1000).toLong()
        val pi = pending(ctx, exName, sound)
        // exact when the user allows it; otherwise the system may shift it by a few seconds
        if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
            am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
        }
    }

    fun cancel(ctx: Context) {
        ctx.getSystemService(AlarmManager::class.java).cancel(pending(ctx, "", false))
        NotificationManagerCompat.from(ctx).cancel(ID)
    }

    fun post(ctx: Context, exName: String, sound: Boolean) {
        channels(ctx)
        if (!canNotify(ctx)) return
        val open = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(ctx, if (sound) SOUND else SILENT)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("⏱ Rest over — GO")
            .setContentText("Next set: $exName")
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .build()
        try { NotificationManagerCompat.from(ctx).notify(ID, n) } catch (_: SecurityException) {}
    }

    /** In-app rest-over: a buzz and/or a short beep (haptics + a system sound on iOS). */
    fun buzz(ctx: Context) {
        val v = if (Build.VERSION.SDK_INT >= 31) ctx.getSystemService(VibratorManager::class.java).defaultVibrator
        else @Suppress("DEPRECATION") ctx.getSystemService(Vibrator::class.java)
        v?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 120, 80, 120), -1))
    }

    fun tick(ctx: Context) {
        val v = if (Build.VERSION.SDK_INT >= 31) ctx.getSystemService(VibratorManager::class.java).defaultVibrator
        else @Suppress("DEPRECATION") ctx.getSystemService(Vibrator::class.java)
        v?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
    }

    fun beep() {
        try {
            val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90)
            tg.startTone(ToneGenerator.TONE_PROP_BEEP2, 300)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ tg.release() }, 600)
        } catch (_: Exception) {}
    }
}

/** Fires the rest-over notification when the app isn't in front. */
class RestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (MainActivity.inForeground) return // the in-app bar beeps and buzzes instead
        RestNotifier.post(context, intent.getStringExtra("ex") ?: "", intent.getBooleanExtra("sound", true))
    }
}
