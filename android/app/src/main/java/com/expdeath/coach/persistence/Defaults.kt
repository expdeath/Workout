package com.expdeath.coach.persistence

import android.content.Context
import android.content.SharedPreferences
import com.expdeath.coach.app.CoachApplication

/** Small non-secret per-device settings (SharedPreferences) — the
 *  UserDefaults counterpart in Defaults.swift. */
object Defaults {
    private const val PREFIX = "coach."
    private val p: SharedPreferences
        get() = CoachApplication.context.getSharedPreferences("coach", Context.MODE_PRIVATE)

    fun string(key: String): String? = p.getString(PREFIX + key, null)

    fun set(value: String?, key: String) {
        p.edit().apply { if (value != null) putString(PREFIX + key, value) else remove(PREFIX + key) }.apply()
    }

    /** Removes every coach.* default — used by wipeLocal(). */
    fun removeAll() {
        p.edit().apply { p.all.keys.filter { it.startsWith(PREFIX) }.forEach { remove(it) } }.apply()
    }
}
