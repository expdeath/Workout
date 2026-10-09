package com.expdeath.coach.ui.screens

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.Screen
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.sync.HealthIngest
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.CapsText
import com.expdeath.coach.ui.Chevron
import com.expdeath.coach.ui.Chip
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.CoachTextField
import com.expdeath.coach.ui.ErrorBox
import com.expdeath.coach.ui.Fill
import com.expdeath.coach.ui.Hairline
import com.expdeath.coach.ui.Pill
import com.expdeath.coach.ui.QLabel
import com.expdeath.coach.ui.ReadinessBar
import com.expdeath.coach.ui.ScreenHeader
import com.expdeath.coach.ui.SegGroup
import com.expdeath.coach.ui.StepSlider
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.VGap
import com.expdeath.coach.ui.sf

/** Ports CheckIn.jsx — the 60-second pre-session check-in. Pre-set for a
 *  normal day (AppState.buildDefaultCheckin); submitting hands AppState.ci
 *  to the AI via generateWorkout. */
@Composable
fun CheckInScreen(app: AppState) {
    val ctx = LocalContext.current
    // auto-open the extras when health data was pre-filled
    var autoFilled by remember { mutableStateOf(!app.ci.health.isNullOrEmpty()) }
    var showMore by remember { mutableStateOf(autoFilled) }
    val ci = app.ci
    val all = Workouts.list()
    val picked = all.firstOrNull { !it.isAddOn && it.id == ci.templateId }

    /** pasteHealth() + storeTodaysHealth(): today's health row keeps the raw
     *  text so Stats/AI context see it on later plans too. */
    fun pasteHealth() {
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(ctx)?.toString()?.trim()
        if (text.isNullOrEmpty()) return
        // today's text + every number it carries on today's row (storeTodaysHealth)
        val t = HealthIngest.storeToday(text)
        LocalStore.logEvent("health_pasted", mapOf("chars" to JSONValue.Num(t.length.toDouble())))
        app.ci = app.ci.copy(health = t)
        autoFilled = true
    }

    CoachScreen {
        Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(16.dp)) {
            ScreenHeader("Check-in", onBack = { app.screen = Screen.Home })

            // ── Today's workout: the coach plans it, or a saved one (+ add-ons)
            val sessions = all.filter { !it.isAddOn }
            val addOns = all.filter { it.isAddOn }
            val scheduled = Workouts.scheduledFor(Helpers.todayStr(), all).sessions.map { it.id }
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                CapsText("Today's workout")
                Fill()
                Chip(if (all.isEmpty()) "+ Add your own" else "My workouts") { app.openWorkouts(Screen.CheckIn) }
            }
            val options = listOf("" to "Coach plans it") + sessions.map { it.id to (it.name + if (it.id in scheduled) " · today" else "") }
            SegGroup(options, ci.templateId, minOf(options.size, 2)) { app.ci = app.ci.copy(templateId = it) }
            if (picked != null) {
                T((if (picked.source == "trainer") "${picked.trainer.ifEmpty { "Trainer" }}'s workout · " else "") +
                    if (picked.adapt) "The coach adapts it to how you feel today." else "Kept exactly as written — the coach fills in weights and flags recovery.",
                    Theme.meta(13f), Theme.muted, Modifier.padding(top = 8.dp))
            }
            for (a in addOns) {
                val on = a.id in ci.addOnIds
                val days = Workouts.daysLabel(a)
                Pill(on, "${if (on) "✓" else "+"} ${a.name} · ${days.ifEmpty { "add-on" }}", modifier = Modifier.padding(top = 8.dp)) {
                    app.ci = app.ci.copy(addOnIds = if (on) app.ci.addOnIds - a.id else app.ci.addOnIds + a.id)
                }
            }

            QLabel("Energy", "${ci.energy}/10")
            StepSlider(ci.energy) { app.ci = app.ci.copy(energy = it) }

            QLabel("Sleep")
            SegGroup(listOf("Great" to "Great", "OK" to "OK", "Poor" to "Poor"), ci.sleep) { app.ci = app.ci.copy(sleep = it) }

            QLabel("Soreness")
            SegGroup(listOf("None" to "None", "Light" to "Light", "Very sore" to "Very sore"), ci.soreness) { app.ci = app.ci.copy(soreness = it) }
            if (ci.soreness != "None") {
                CoachTextField(ci.soreAreas, { app.ci = app.ci.copy(soreAreas = it) }, "Where?", Modifier.padding(top = 10.dp))
            }

            QLabel("Gym time")
            SegGroup(listOf("30" to "30m", "45" to "45m", "60" to "60m", "75" to "75m+"), ci.timeAvail) { app.ci = app.ci.copy(timeAvail = it) }

            // more details
            Column(Modifier.padding(top = 22.dp)) {
                Hairline()
                Row(Modifier.fillMaxWidth().clickable { showMore = !showMore }.padding(vertical = 13.dp, horizontal = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    CapsText(if (showMore) "Fewer details" else "More details")
                    Fill()
                    Chevron(showMore)
                }
            }
            if (showMore) Column(Modifier.animateContentSize().padding(top = 4.dp)) {
                Pill(ci.backTight, if (ci.backTight) "✓ Lower back tight" else "Lower back tight?", warn = true) { app.ci = app.ci.copy(backTight = !app.ci.backTight) }
                app.muscleGap?.let { gap ->
                    Pill(
                        ci.prioritizeMuscle.isNotEmpty(),
                        if (ci.prioritizeMuscle.isEmpty()) "Prioritize ${gap.group.lowercase()}? ${gap.lastDaysAgo} days since last trained" else "✓ Prioritizing ${gap.group.lowercase()}",
                        modifier = Modifier.padding(top = 10.dp),
                    ) { app.ci = app.ci.copy(prioritizeMuscle = if (app.ci.prioritizeMuscle.isEmpty()) gap.group else "") }
                }
                if (picked == null) { // a saved workout sets its own focus
                    QLabel("Focus", top = 16.dp)
                    SegGroup(
                        listOf("" to "Coach's call", "lift" to "Lift", "cardio" to "Cardio", "core" to "Core", "stretch" to "Stretch", "surprise" to "🎲 Surprise me"),
                        ci.wish, 3,
                    ) { app.ci = app.ci.copy(wish = it) }
                }
                QLabel("Health data", top = 16.dp)
                Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (autoFilled && !ci.health.isNullOrEmpty()) {
                        Icon(sf("applewatch"), null, tint = Theme.green, modifier = Modifier.size(16.dp))
                        T(" Loaded from your watch", Theme.body(13f), Theme.green)
                    }
                    Fill()
                    Chip("Paste") { pasteHealth() }
                }
                CoachTextField(ci.health ?: "", { app.ci = app.ci.copy(health = it) }, "Sleep, HRV, resting HR…", singleLine = false, minLines = 3, style = Theme.body(14.5f), radius = Theme.radius)
                QLabel("Body weight", top = 16.dp)
                CoachTextField(ci.bodyKg, { v -> app.ci = app.ci.copy(bodyKg = v.filter { it.isDigit() || it == '.' }.take(6)) }, "kg", keyboard = KeyboardType.Decimal)
                CoachTextField(ci.notes, { app.ci = app.ci.copy(notes = it) }, "Anything else?", Modifier.padding(top = 10.dp))
            }

            ReadinessBar(Helpers.quickReadiness(ci), "Readiness", Modifier.padding(top = 24.dp))
            if (app.error.isNotEmpty()) ErrorBox(app.error, Modifier.padding(top = 14.dp))
            VGap(18.dp)
            BigButton(picked?.let { "Start ${it.name}" } ?: "Build session") { app.generateWorkout(app.ci) }
            VGap(24.dp)
        }
    }
}
