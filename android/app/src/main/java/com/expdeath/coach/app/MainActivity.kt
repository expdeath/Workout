package com.expdeath.coach.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.sync.HealthConnectSync
import com.expdeath.coach.ui.RootScreen
import kotlinx.coroutines.CompletableDeferred

class MainActivity : ComponentActivity() {
    private val healthPermissions = registerForActivityResult(PermissionController.createRequestPermissionResultContract()) {
        HealthConnectSync.onPermissionResult(it)
    }
    private var notifyAnswer: CompletableDeferred<Boolean>? = null
    private val notifyPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        notifyAnswer?.complete(it); notifyAnswer = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        HealthConnectSync.launcher = { healthPermissions.launch(it) }
        current = this
        val app = state ?: run {
            val start = if (BuildConfigHelper.debug) DebugSeed.applyIfRequested(intent) else null
            AppState(start).also { state = it }
        }
        setContent { RootScreen(app) }
    }

    override fun onResume() { super.onResume(); inForeground = true }
    override fun onPause() { super.onPause(); inForeground = false }

    override fun onDestroy() {
        if (current === this) { current = null; HealthConnectSync.launcher = null }
        super.onDestroy()
    }

    /** Android 13+: ask once before the first rest-over notification. */
    suspend fun askNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < 33 || RestNotifier.canNotify(this)) return true
        val d = CompletableDeferred<Boolean>()
        notifyAnswer = d
        notifyPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        return d.await()
    }

    companion object {
        /** One app state per process, kept across activity re-creation. */
        var state: AppState? = null
        var current: MainActivity? = null
        @Volatile var inForeground = false

        init {
            // back in the foreground: Health Connect + Watch inbox + backup
            ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) {
                    if (Cloud.account != null) state?.maybeSyncOnForeground()
                }
            })
        }
    }
}

/** BuildConfig.DEBUG without importing the generated class everywhere. */
object BuildConfigHelper {
    val debug: Boolean get() = com.expdeath.coach.BuildConfig.DEBUG
}
