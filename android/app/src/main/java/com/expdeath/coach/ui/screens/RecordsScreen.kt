package com.expdeath.coach.ui.screens

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.expdeath.coach.app.AppState
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Session
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Dashboard
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.fmt
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.ui.CapsText
import com.expdeath.coach.ui.ChartPoint
import com.expdeath.coach.ui.Chevron
import com.expdeath.coach.ui.CoachCard
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.IconLabel
import com.expdeath.coach.ui.IconWell
import com.expdeath.coach.ui.LineChartView
import com.expdeath.coach.ui.OutlineButton
import com.expdeath.coach.ui.ProgressLine
import com.expdeath.coach.ui.SectionHead
import com.expdeath.coach.ui.StatusPill
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.TabHeader
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.Title
import com.expdeath.coach.ui.exportsDir
import com.expdeath.coach.ui.panel
import com.expdeath.coach.ui.sf
import com.expdeath.coach.ui.shareFile
import com.expdeath.coach.ui.shareText
import kotlinx.coroutines.launch
import java.io.File

/** "2026-08-30" → "30/8", like the web's toLocaleDateString day/month. */
fun shortDate(iso: String): String = Helpers.parseDate(iso)?.let { "${it.dayOfMonth}/${it.monthValue}" } ?: iso

/** Ports Records.jsx — the honor roll (milestones unlocked), lifetime stats,
 *  the milestone grid with progress, personal records (tap one for its
 *  est. 1RM trend) and the next benchmark in reach. */
@Composable
fun RecordsScreen(app: AppState) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var openEx by remember { mutableStateOf<String?>(null) }
    var showAll by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val rowY = remember { mutableStateMapOf<String, Float>() }

    val history = app.history
    val records = Stats.prRecords(history).filter { it.weight != null }.sortedByDescending { it.weight?.date ?: "" }
    val series = Stats.exerciseSeries(history)
    val totalVolume = history.sumOf { Stats.sessionVolume(it) }
    val streak = Stats.weekStats(history, Dashboard.weeklyTarget(LocalStore.backup.aiSettings)).streak
    val milestones = Dashboard.milestones(history)
    val earned = milestones.count { it.earned }

    // opened from search: open that lift's row and bring it into view
    LaunchedEffect(app.recordPick) {
        val pick = app.recordPick ?: return@LaunchedEffect
        if (System.currentTimeMillis() - pick.at > 5000) return@LaunchedEffect
        openEx = pick.name
        showAll = true
        kotlinx.coroutines.delay(150)
        rowY["pr-${pick.name.lowercase()}"]?.let { scroll.animateScrollTo(maxOf(0, it.toInt() - 200)) }
    }

    CoachScreen {
        Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            TabHeader(app, "Records")
            // honor roll
            CoachCard(stroke = Theme.amber.copy(alpha = 0.35f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        StatusPill("Honor roll", Theme.amberText, dot = false)
                        Title("$earned milestone${if (earned == 1) "" else "s"} unlocked", 28f)
                        T("${records.size} personal record${if (records.size == 1) "" else "s"} on the board", Theme.meta(13f), Theme.green)
                    }
                    Box(Modifier.size(64.dp).clip(RoundedCornerShape(Theme.radius)).background(Theme.amberBg), contentAlignment = Alignment.Center) {
                        Icon(sf("trophy.fill"), null, tint = Theme.amberText, modifier = Modifier.size(30.dp))
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTile("Sessions", "${history.size}", sub = if (history.isEmpty()) null else "Active", subColor = Theme.green, modifier = Modifier.weight(1f))
                StatTile("Lifted", if (totalVolume >= 10000) "${(totalVolume / 1000.0).rounded().toInt()}" else fmt("%.1f", totalVolume / 1000.0), "t", "Lifetime", modifier = Modifier.weight(1f))
                StatTile("Streak", "$streak", "wks", if (streak >= 2) "Hot" else null, Theme.amberText, Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlineButton("Share", icon = "square.and.arrow.up") { shareText(ctx, shareRecordsText(history)) }
                OutlineButton("Export CSV", icon = "tablecells") {
                    scope.launch { try { shareFile(ctx, recordsCsv(history, exportsDir(ctx)), "text/csv") } catch (_: Exception) {} }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionHead("Key milestones", "$earned of ${milestones.size} complete", Theme.muted)
                for (row in Dashboard.keyMilestones(history).chunked(2)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (m in row) MilestoneTile(m, Modifier.weight(1f))
                        if (row.size == 1) Box(Modifier.weight(1f))
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionHead("Personal records", if (records.size > 6) (if (showAll) "Top 6" else "All PRs") else null) { showAll = !showAll }
                if (records.isEmpty()) T("Log weighted sets to see records.", Theme.body(14f), Theme.muted)
                for (r in if (showAll) records else records.take(6)) {
                    val key = "pr-${r.name.lowercase()}"
                    Box(Modifier.onGloballyPositioned { rowY[key] = it.positionInParent().y }) {
                        RecordRow(r, series.firstOrNull { it.name == r.name }?.points ?: emptyList(), openEx?.lowercase() == r.name.lowercase()) {
                            openEx = if (openEx?.lowercase() == r.name.lowercase()) null else r.name
                        }
                    }
                }
            }
            Dashboard.nextBenchmark(history)?.let { next ->
                Row(Modifier.fillMaxWidth().panel().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconWell("flame.fill", Theme.amberText, 34.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        T("Next benchmark in reach", Theme.body(15f, FontWeight.Medium))
                        T("${next.goal - next.value} more to unlock ${next.title.lowercase()}", Theme.meta(13f), Theme.muted)
                    }
                }
            }
        }
    }
}

// ── Share / export (shareRecords / exportRecordsCsv in Records.jsx) ──

private fun shareRecordsText(history: List<Session>): String {
    val records = Stats.prRecords(history).filter { it.weight != null }.sortedByDescending { it.e1rm?.v ?: it.weight!!.w }
    val earned = Dashboard.milestones(history).filter { it.earned }
    val lines = mutableListOf("My training records — ${history.size} sessions, ${records.size} PRs, ${earned.size} milestones")
    lines += records.take(6).map { r ->
        "• ${r.name}: ${Helpers.fmtKg(r.weight!!.w)} kg × ${r.weight!!.reps.ifEmpty { "?" }}" + (r.e1rm?.let { " (est. 1RM ${Helpers.fmtKg(it.v)} kg)" } ?: "")
    }
    earned.lastOrNull()?.let { lines.add("Latest milestone: ${it.title}") }
    return lines.joinToString("\n")
}

private fun recordsCsv(history: List<Session>, dir: File): File {
    fun esc(v: String) = if (v.any { it == ',' || it == '"' || it == '\n' }) "\"${v.replace("\"", "\"\"")}\"" else v
    val rows = mutableListOf("Exercise,Muscle group,Best weight (kg),Reps,Best set date,Est. 1RM (kg),Est. 1RM date,Sets logged")
    for (r in Stats.prRecords(history)) {
        val w = r.weight ?: continue
        rows.add(listOf(r.name, Stats.muscleGroupOf(r.name), Helpers.fmtKg(w.w), w.reps, w.date, r.e1rm?.let { Helpers.fmtKg(it.v) } ?: "", r.e1rm?.date ?: "", "${r.count}").joinToString(",") { esc(it) })
    }
    val f = File(dir, "coach-records-${Helpers.todayStr()}.csv")
    f.writeText(rows.joinToString("\n"))
    LocalStore.logEvent("records_exported", mapOf("records" to JSONValue.Num((rows.size - 1).toDouble())))
    return f
}

@Composable
private fun MilestoneTile(m: Dashboard.Milestone, modifier: Modifier) {
    Row(
        modifier.heightIn(min = 74.dp).panel(stroke = if (m.earned) Theme.amber.copy(alpha = 0.35f) else Theme.border).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        IconWell(m.icon, if (m.earned) Theme.amberText else Theme.dim, 32.dp)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            T(m.title, Theme.body(14f, FontWeight.Medium), if (m.earned) Theme.text else Theme.muted, maxLines = 1)
            if (m.earned) IconLabel("checkmark.circle.fill", "Unlocked", Theme.green, Theme.meta(11.5f), 13.dp)
            else {
                ProgressLine(m.value.toDouble() / m.goal, height = 4.dp)
                T("${m.value} / ${m.goal}", Theme.meta(11f), Theme.dim)
            }
        }
    }
}

@Composable
private fun RecordRow(r: Stats.ExercisePR, points: List<Stats.ExercisePoint>, isOpen: Boolean, onTap: () -> Unit) {
    val isNew = (r.weight?.date ?: "") >= Helpers.daysAgoStr(6)
    Column(Modifier.fillMaxWidth().panel().clickable(onClick = onTap).padding(12.dp).animateContentSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconWell(if (isNew) "star.fill" else "medal", if (isNew) Theme.amberText else Theme.muted, 34.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                T(r.name, Theme.body(15f, FontWeight.Medium), maxLines = 1)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (isNew) CapsText("New", Theme.amberText, 11f)
                    T(listOfNotNull(Stats.muscleGroupOf(r.name), r.e1rm?.let { "e1RM ${Helpers.fmtKg(it.v)}kg" }).joinToString(" · "), Theme.meta(12.5f), Theme.muted, maxLines = 1)
                }
            }
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                T(Helpers.fmtKg(r.weight!!.w), Theme.head(22f, FontWeight.Bold), Theme.amberText)
                CapsText("kg × ${r.weight!!.reps.ifEmpty { "?" }}", Theme.muted, 11f, Modifier.padding(bottom = 3.dp))
            }
            Chevron(isOpen, Theme.dim, 16.dp)
        }
        if (isOpen) {
            if (points.size >= 2) LineChartView(points.map { ChartPoint(shortDate(it.date), it.e ?: it.w) }, "kg", height = 150.dp)
            else T("One more session unlocks the trend.", Theme.meta(13f), Theme.dim)
        }
    }
}

/** `.stat-tile` — caps label, big number, optional caps note. */
@Composable
fun StatTile(label: String, value: String, unit: String = "", sub: String? = null, subColor: Color = Theme.muted, modifier: Modifier = Modifier) {
    Column(modifier.panel().padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        CapsText(label, Theme.muted, 11f)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            T(value, Theme.head(30f, FontWeight.Bold), maxLines = 1)
            if (unit.isNotEmpty()) CapsText(unit, Theme.muted, 12f, Modifier.padding(bottom = 5.dp))
        }
        if (sub != null) CapsText(sub, subColor, 10.5f)
    }
}
