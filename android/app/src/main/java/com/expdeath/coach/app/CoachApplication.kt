package com.expdeath.coach.app

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.sync.WearBridge
import java.lang.ref.WeakReference

class CoachApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        Cloud.configure()
        WearBridge.start()
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) { current = WeakReference(activity) }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) { current = WeakReference(activity) }
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) { if (current?.get() === activity) current = null }
        })
    }

    companion object {
        private lateinit var instance: CoachApplication
        private var current: WeakReference<Activity>? = null

        val context: Context get() = instance.applicationContext

        /** The foreground activity — Google's / Apple's sign-in sheets and
         *  Play billing present on it. */
        val activity: Activity? get() = current?.get()
    }
}
