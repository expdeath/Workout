package com.expdeath.coach.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.Screen
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.MonthlyReportCache
import com.expdeath.coach.models.SavedWorkout
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.WeeklyReviewCache
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Calories
import com.expdeath.coach.stats.Dashboard
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.fmt
import com.expdeath.coach.stats.nowMs
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.CapsText
import com.expdeath.coach.ui.CoachCard
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.ExpandableText
import com.expdeath.coach.ui.Fill
import com.expdeath.coach.ui.IconWell
import com.expdeath.coach.ui.LaunchTile
import com.expdeath.coach.ui.ProgressLine
import com.expdeath.coach.ui.QuickCardioSheet
import com.expdeath.coach.ui.SectionHead
import com.expdeath.coach.ui.StatBlock
import com.expdeath.coach.ui.StatusPill
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.TabHeader
import com.expdeath.coach.ui.TextButtonC
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.Title
import com.expdeath.coach.ui.sf
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter

fun toneColor(t: Dashboard.Tone): Color = when (t) {
    Dashboard.Tone.Good -> Theme.green
    Dashboard.Tone.Ok -> Theme.amberText
    Dashboard.Tone.Low -> Theme.red
}

/** 12400 → "12.4k" */
fun kgShort(kg: Int): String = if (kg >= 1000) fmt("%.1fk", kg / 1000.0).replace(".0k", "k") else "$kg"

/** Ports Home.jsx — the Today tab: readiness, this week's numbers, the
 *  start button, quick launchers, today's plan and the coach's notes. */
@Composable
fun HomeScreen(app: AppState) {
    val scope = rememberCoroutineScope()
    var quickKind by remember { mutableStateOf<String?>(null) }
    val settings = LocalStore.backup.aiSettings
    val health = LocalStore.backup.health
    val target = Dashboard.weeklyTarget(settings)
    val week = Stats.weekStats(app.history, target)
    val kcal = Calories.stats(app.history, Calories.latestBodyWeightKg(health)).thisWeek
    val readiness = Dashboard.readiness(app.history, health)
    val doneToday = app.todayPlan?.finished == true
    val inProgress = app.todayPlan != null && app.todayPlan?.finished == false
    // dismissing today's recovery notice is account state, so every device hides it
    val noticeDismissed = Cloud.stateValue("noticeDismissed")?.string ?: ""
    val showReview = app.weeklyReview?.let { nowMs() - it.at < 7 * 86400 * 1000.0 } == true
    val showMonthly = app.monthlyReport?.let { nowMs() - it.at < 10 * 86400 * 1000.0 } == true

    LaunchedEffect(Unit) { app.maybeSyncOnForeground() }

    CoachScreen {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            TabHeader(app, "Today")
            // hero
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                CapsText(LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE, d MMM")))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val name = app.firstName
                    val title = when {
                        doneToday -> name?.let { "Nice work, $it." } ?: "Session done."
                        inProgress -> "${app.todayPlan?.plan?.sessionType ?: "Session"} in progress"
                        else -> name?.let { "Ready, $it?" } ?: "Ready?"
                    }
                    Title(title, 36f, modifier = Modifier.weight(1f), tracking = 0.6f)
                    if (doneToday) StatusPill("Done", Theme.green)
                    else if (readiness != null) StatusPill(readiness.label, toneColor(readiness.tone))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatBlock("${week.thisWeek}", "This week", modifier = Modifier.weight(1f))
                StatBlock("${week.streak}", "Streak (wks)", Theme.amberText, Modifier.weight(1f))
                StatBlock(if (kcal >= 10000) "${kcal / 1000}k" else "$kcal", "Active kcal", modifier = Modifier.weight(1f))
            }
            BigButton(
                if (inProgress) "Resume ${app.todayPlan?.plan?.sessionType ?: ""}" else if (doneToday) "Plan another session" else "Start workout",
                icon = "play.fill",
            ) {
                if (inProgress) app.screen = Screen.Workout
                else scope.launch {
                    app.ci = app.prepareCheckin()
                    app.error = ""
                    app.screen = Screen.CheckIn
                }
            }
            // quick launch
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionHead("Quick launch", "Manual activity") { app.screen = Screen.AddPast }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (!inProgress) LaunchTile("timer", "Quick", modifier = Modifier.weight(1f)) {
                        scope.launch {
                            val checkin = app.prepareCheckin()
                            app.ci = checkin
                            LocalStore.logEvent("quick_start")
                            app.generateWorkout(checkin.copy(notes = "Quick start — assumed a normal day."))
                        }
                    }
                    for ((kind, icon, label) in listOf(Triple("run", "figure.run", "Run"), Triple("cycle", "bicycle", "Ride"), Triple("walk", "figure.walk", "Walk"), Triple("hike", "figure.hiking", "Hike"))) {
                        LaunchTile(icon, label, Theme.green, Modifier.weight(1f)) { quickKind = kind }
                    }
                }
            }
            // today's focus
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val t = app.todayPlan
                val scheduled = Workouts.scheduledFor()
                if (t != null) SectionHead("Today's focus", if (t.finished) "Completed" else "Scheduled", if (t.finished) Theme.green else Theme.amberText)
                else SectionHead("Today's focus", "My workouts") { app.openWorkouts(Screen.Home) }
                when {
                    t != null -> PlanCard(app, t)
                    scheduled.sessions.isNotEmpty() -> SavedCard(app, scheduled.sessions.first(), scheduled.sessions.size - 1, scheduled.addOns)
                    else -> CoachCard {
                        Title("No plan yet", 24f)
                        T("A one-minute check-in and the coach builds today's session around your recovery.", Theme.body(14f), Theme.muted)
                    }
                }
            }
            if (readiness != null && noticeDismissed != Helpers.todayStr()) Notice(readiness)
            if (showMonthly) app.monthlyReport?.let { MonthlyCard(it) }
            if (showReview) app.weeklyReview?.let { WeeklyCard(it) }
            // sync status lives in Settings; Today only speaks up when it fails
            app.syncInfo?.takeIf { it.state == "error" }?.let { T("Sync error — ${it.message ?: ""}", Theme.meta(12.5f), Theme.red) }
        }
    }
    quickKind?.let { kind ->
        QuickCardioSheet(kind, onDismiss = { quickKind = null }) { k, time, dist, rpe, date -> app.logQuickCardio(k, time, dist, rpe, date) }
    }
}

@Composable
private fun SmallGo(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    Row(
        Modifier.alpha(if (enabled) 1f else 0.5f).clip(RoundedCornerShape(Theme.radiusSm)).background(Theme.bgHigh).clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        CapsText(text, Theme.text, 15f)
        Icon(sf("arrow.right"), null, tint = Theme.text, modifier = Modifier.size(14.dp))
    }
}

@Composable
private fun PlanCard(app: AppState, t: Session) {
    val p = t.plan
    val total = t.log.sumOf { it.size }
    val done = t.log.sumOf { r -> r.count { it.done } }
    val load = Dashboard.projectedLoad(p, app.history)
    val meta = listOfNotNull(
        if (p.estTimeMin > 0) "${p.estTimeMin} min" else null,
        Dashboard.averageRPE(p)?.let { "RPE ${Helpers.fmtKg(it)}" },
        "${p.exercises.size} exercises",
    ).joinToString(" • ")
    CoachCard {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Title(p.title.ifEmpty { p.sessionType }, 26f)
                CapsText(meta, Theme.amberText, 13f)
            }
            IconWell("arrow.up.left.and.arrow.down.right")
        }
        ProgressLine(if (total > 0) done.toDouble() / total else 0.0, if (t.finished) Theme.green else Theme.amber, modifier = Modifier.padding(vertical = 6.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            T(if (load > 0) "Target load: ${kgShort(load)} kg volume" else "$done/$total sets done", Theme.meta(13f), Theme.muted, Modifier.weight(1f))
            SmallGo(if (t.finished) "View" else if (done > 0) "Resume" else "Start", !t.finished) { app.screen = Screen.Workout }
        }
    }
}

/** No plan yet, but the library has a workout on today's weekday. */
@Composable
private fun SavedCard(app: AppState, w: SavedWorkout, more: Int, addOns: List<SavedWorkout>) {
    val scope = rememberCoroutineScope()
    CoachCard {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                CapsText("Scheduled today" + if (w.source == "trainer") " · ${w.trainer.ifEmpty { "trainer" }}'s workout" else "", Theme.amberText, 12f)
                Title(w.name, 26f)
                T("${w.exercises.size} exercises · ${if (w.adapt) "coach adapts it to today" else "kept as written"}" +
                    if (addOns.isEmpty()) "" else " · + " + addOns.joinToString(", ") { it.name }, Theme.meta(13f), Theme.muted)
            }
            IconWell("list.bullet.clipboard")
        }
        ExerciseSummary(w.exercises, 4, Modifier.padding(vertical = 4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButtonC(if (more > 0) "$more more scheduled today" else "All my workouts", style = Theme.body(13.5f)) { app.openWorkouts(Screen.Home) }
            Fill()
            SmallGo("Start") { scope.launch { app.startSavedWorkout(w.id) } }
        }
    }
}

@Composable
private fun Notice(r: Dashboard.Readiness) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.radius)).background(Theme.bgPill).padding(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        IconWell(if (r.tone == Dashboard.Tone.Low) "exclamationmark.triangle" else "checkmark.shield", toneColor(r.tone), 32.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            CapsText(when (r.tone) { Dashboard.Tone.Low -> "Go easier today"; Dashboard.Tone.Good -> "Recovery looks good"; else -> "Normal recovery" }, toneColor(r.tone), 12f)
            T(r.note, Theme.body(14f), Theme.textBody, maxLines = 3)
        }
        Box(
            Modifier.size(28.dp).clickable { Cloud.setState("noticeDismissed", JSONValue.Str(Helpers.todayStr())) }.semantics { contentDescription = "Dismiss" },
            contentAlignment = Alignment.Center,
        ) { Icon(sf("xmark"), null, tint = Theme.muted, modifier = Modifier.size(16.dp)) }
    }
}

@Composable
private fun MonthlyCard(r: MonthlyReportCache) = CoachCard {
    SectionHead("Monthly report", "${r.sum.count} sessions")
    ExpandableText(r.text)
}

@Composable
private fun WeeklyCard(r: WeeklyReviewCache) = CoachCard {
    SectionHead("Weekly review", "${r.count} sessions")
    ExpandableText(r.text)
}

/** The exercises of a saved workout as compact rows. */
@Composable
fun ExerciseSummary(exercises: List<SavedWorkout.Exercise>, max: Int = 99, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (e in exercises.take(max)) {
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.radiusSm)).background(Theme.bgPill).padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                T(e.name, Theme.body(14f), modifier = Modifier.weight(1f), maxLines = 1)
                CapsText("${e.sets} × ${e.reps}${if (e.weight.isEmpty()) "" else " · ${e.weight}"}", Theme.amberText, 13f)
            }
        }
        if (exercises.size > max) T("+${exercises.size - max} more", Theme.meta(12.5f), Theme.muted)
    }
}
