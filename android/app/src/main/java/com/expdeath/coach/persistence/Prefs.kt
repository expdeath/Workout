package com.expdeath.coach.persistence

import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.stats.nowMs
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.sync.Cloud

/** Settings → Alerts & reports switches: account state `prefs` in
 *  Firestore, shared with the web and iPhone apps (getPrefs in
 *  src/utils/storage.js). All on by default. */
object Prefs {
    val defaults: Map<String, Boolean> = mapOf(
        "restSound" to true,     // beep when the rest timer ends
        "restVibrate" to true,   // …and buzz
        "restNotify" to true,    // …and notify when the app is in the background
        "keepAwake" to true,     // screen stays on during a workout
        "weeklyReview" to true,  // Sunday AI review
        "monthlyReport" to true, // new-month AI report
        "debrief" to true,       // two-sentence AI debrief after each session
    )

    private val stored: Map<String, JSONValue> get() = Cloud.stateValue("prefs")?.obj ?: emptyMap()

    fun isOn(key: String): Boolean = stored[key]?.bool ?: defaults[key] ?: true

    fun set(key: String, on: Boolean) {
        val o = LinkedHashMap(stored)
        o[key] = JSONValue.Bool(on)
        Cloud.setState("prefs", JSONValue.Obj(o))
    }

    /** The raw value, for the backup file. */
    val raw: JSONValue? get() = Cloud.stateValue("prefs")
}

/** May the app send data to Google Gemini? Account state `aiConsent`
 *  { allowed, at, version }, shared with the other apps — asked once per
 *  account (AIConsentScreen), changeable in Settings → AI Coach. Nothing
 *  reaches Gemini without it (Gemini.post). */
object AIConsent {
    const val version = 1

    private val stored: Map<String, JSONValue>? get() = Cloud.stateValue("aiConsent")?.obj

    /** The athlete has answered the consent screen (yes or no). */
    val answered: Boolean get() = stored != null

    val allowed: Boolean get() = stored?.get("allowed")?.bool ?: false

    fun set(allowed: Boolean) {
        Cloud.setState("aiConsent", JSONValue.obj(
            "allowed" to JSONValue.Bool(allowed),
            "at" to JSONValue.Num(nowMs().rounded()),
            "version" to JSONValue.Num(version.toDouble()),
        ))
    }
}
