package com.expdeath.coach.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.expdeath.coach.app.AppState
import com.expdeath.coach.models.AISettings
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.Session
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Calories
import com.expdeath.coach.stats.Dashboard
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.ui.BarChartView
import com.expdeath.coach.ui.CapsText
import com.expdeath.coach.ui.CardLabel
import com.expdeath.coach.ui.ChartPoint
import com.expdeath.coach.ui.Chip
import com.expdeath.coach.ui.CoachCard
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.Fill
import com.expdeath.coach.ui.HeatLegend
import com.expdeath.coach.ui.LineChartView
import com.expdeath.coach.ui.ProgressLine
import com.expdeath.coach.ui.SectionHead
import com.expdeath.coach.ui.SegmentedTabs
import com.expdeath.coach.ui.StatusPill
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.TabHeader
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.Title
import com.expdeath.coach.ui.TrainingHeatmapView
import com.expdeath.coach.ui.panel
import com.expdeath.coach.ui.sf

private data class RecMode(val key: String, val label: String, val points: List<ChartPoint>, val unit: String, val color: Color, val desc: String)

/** Ports Progress.jsx — a range switch (8 weeks · 3 months · year) over the
 *  summary, consistency heatmap, lift progression, weekly training, muscle
 *  balance, goals and recovery (HRV / RHR / sleep / body weight). */
@Composable
fun ProgressScreen(app: AppState) {
    var range by remember { mutableStateOf("8w") }
    var exIdx by remember { mutableIntStateOf(0) }
    var exMetric by remember { mutableStateOf("w") } // w = best set weight · e = est. 1RM
    var weekMode by remember { mutableStateOf("volume") }
    var recMode by remember { mutableStateOf("hrv") }

    val days = when (range) { "8w" -> 56; "3m" -> 91; else -> 364 }
    val weeks = days / 7
    val all = app.history
    val start = Helpers.daysAgoStr(days - 1)
    val history = all.filter { it.date >= start }
    val health = LocalStore.backup.health.sortedBy { it.date }
    val recModes = recoveryModes(health.filter { it.date >= start }).filter { it.points.size >= 2 }
    val settings = LocalStore.backup.aiSettings
    val target = Dashboard.weeklyTarget(settings)

    CoachScreen {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            TabHeader(app, "Progress")
            SegmentedTabs(listOf("8w" to "8 Weeks", "3m" to "3 Months", "1y" to "Year"), range) { range = it }
            if (all.size < 2 && recModes.isEmpty()) {
                T("Log two sessions to unlock charts.", Theme.body(15f), Theme.muted, Modifier.fillMaxWidth().padding(top = 60.dp), align = TextAlign.Center)
            } else {
                Summary(all, health, target, days)
                Consistency(all, target, weeks)
                ExerciseCard(history, exIdx, { exIdx = it }, exMetric) { exMetric = it }
                WeeklyCard(all, weeks, weekMode) { weekMode = it }
                BalanceCard(all)
                GoalsCard(all, settings)
                if (recModes.isNotEmpty()) RecoveryCard(recModes, recMode, { recMode = it }, all, health)
                else T("Recovery charts appear after two days of Health data.", Theme.body(13.5f), Theme.muted)
            }
        }
    }
}

@Composable
private fun Summary(all: List<Session>, health: List<HealthRow>, target: Int, days: Int) {
    val r = Dashboard.rangeSummary(all, days, Calories.latestBodyWeightKg(health))
    val delta = Dashboard.deltaPercent(r.sessions, r.prevSessions)
    val streak = Stats.weekStats(all, target).streak
    Row(Modifier.fillMaxWidth().panel().padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        SummaryCol("Sessions", "${r.sessions}", delta?.let { "${if (it >= 0) "↗ +" else "↘ "}$it%" } ?: "Logged",
            if (delta == null) Theme.muted else if (delta >= 0) Theme.green else Theme.red, Modifier.weight(1f))
        Box(Modifier.width(1.dp).height(52.dp).background(Theme.border))
        SummaryCol("Volume", if (r.volume >= 10000) "${r.volume / 1000}T" else "${Helpers.fmtKg(r.volume / 1000.0)}T", "Lifted", Theme.muted, Modifier.weight(1f))
        Box(Modifier.width(1.dp).height(52.dp).background(Theme.border))
        SummaryCol("Streak", "${streak}wk", if (streak > 0) "Active" else "—", if (streak > 0) Theme.amberText else Theme.muted, Modifier.weight(1f))
    }
}

@Composable
private fun SummaryCol(label: String, value: String, sub: String?, subColor: Color, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        CapsText(label, Theme.muted, 11f)
        T(value, Theme.head(30f, FontWeight.Bold), maxLines = 1)
        if (sub != null) CapsText(sub, subColor, 11f)
    }
}

@Composable
private fun Consistency(all: List<Session>, target: Int, weeks: Int) {
    val pct = Dashboard.compliance(all, weeks, target)
    CoachCard {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Title("Consistency", 22f)
                T("Daily training frequency", Theme.meta(12.5f), Theme.muted)
            }
            StatusPill("$pct% compliance", if (pct >= 80) Theme.green else Theme.amberText)
        }
        val byDay = HashMap<String, Int>()
        for (s in all) byDay.merge(s.date, Stats.sessionVolume(s), Int::plus)
        Box(Modifier.padding(vertical = 6.dp)) { TrainingHeatmapView(byDay, weeks) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            T("Target: $target sessions/wk", Theme.meta(12.5f), Theme.muted)
            Fill()
            HeatLegend()
        }
    }
}

@Composable
private fun ExerciseCard(history: List<Session>, exIdx: Int, setIdx: (Int) -> Unit, exMetric: String, setMetric: (String) -> Unit) {
    val chartable = Stats.exerciseSeries(history).filter { it.points.size >= 2 }.take(10)
    if (chartable.isEmpty()) return
    val sel = chartable[minOf(exIdx, chartable.size - 1)]
    val e1 = sel.points.filter { it.e != null }
    val showE1 = e1.size >= 2
    val metric = if (exMetric == "e" && showE1) "e" else "w"
    val pts = if (metric == "e") e1 else sel.points
    val vals = pts.map { if (metric == "e") it.e ?: it.w else it.w }
    val latest = vals.lastOrNull() ?: 0.0
    val first = vals.firstOrNull() ?: 0.0
    val isPR = latest >= (vals.maxOrNull() ?: 0.0) && latest > first
    CoachCard {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (isPR) StatusPill("New PR", Theme.amberText, dot = false)
                    CapsText("Lift progression")
                }
                Title(sel.name, 22f)
            }
            if (showE1) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Chip("Weight", metric == "w") { setMetric("w") }
                Chip("1RM", metric == "e") { setMetric("e") }
            }
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            T(Helpers.fmtKg(latest), Theme.head(36f, FontWeight.Bold), Theme.amberText)
            CapsText("kg", Theme.amberText, 15f, Modifier.padding(bottom = 6.dp))
            val d = latest - first
            CapsText("${if (d >= 0) "+" else ""}${Helpers.fmtKg(d)} kg progression", if (d >= 0) Theme.green else Theme.red, 12f, Modifier.padding(bottom = 7.dp))
        }
        LineChartView(pts.map { ChartPoint(shortDate(it.date), if (metric == "e") it.e ?: it.w else it.w) }, "kg", Theme.amber, 170.dp)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            chartable.forEachIndexed { i, s -> Chip(s.name, s.name == sel.name) { setIdx(i) } }
        }
    }
}

@Composable
private fun WeeklyCard(all: List<Session>, weeks: Int, mode: String, setMode: (String) -> Unit) {
    CoachCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CardLabel("Weekly training")
            Fill()
            Chip("Volume", mode == "volume") { setMode("volume") }
            Chip("Sessions", mode == "sessions") { setMode("sessions") }
        }
        val buckets = Stats.weeklyBuckets(all, minOf(weeks, 12))
        if (mode == "volume") BarChartView(buckets.map { ChartPoint(shortDate(it.start), it.volume.toDouble()) }, "kg")
        else BarChartView(buckets.map { ChartPoint(shortDate(it.start), it.count.toDouble()) }, color = Theme.chartGreen)
    }
}

@Composable
private fun BalanceCard(all: List<Session>) {
    val balance = Stats.muscleBalance(all)
    if (balance.isEmpty()) return
    CoachCard {
        SectionHead("Muscle balance", "14 days", Theme.muted)
        val maxSets = maxOf(balance.maxOf { it.sets }, 1)
        for (b in balance) {
            val gap = (b.lastDaysAgo ?: 0) >= 10
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                T(b.group, Theme.body(13.5f), Theme.textBody, Modifier.width(84.dp))
                ProgressLine(maxOf(b.sets.toDouble() / maxSets, if (b.sets > 0) 0.06 else 0.0), if (gap) Theme.red else Theme.amber, 7.dp, Modifier.weight(1f))
                T(if (b.sets > 0) "${b.sets} sets" else "${b.lastDaysAgo?.toString() ?: "—"}d ago", Theme.meta(12.5f), if (gap) Theme.red else Theme.muted, Modifier.width(64.dp), align = TextAlign.End)
            }
        }
    }
}

@Composable
private fun GoalsCard(all: List<Session>, settings: AISettings) {
    val goals = Stats.goalProgress(all, settings.goals)
    if (goals.isEmpty()) return
    CoachCard {
        CardLabel("Goals")
        for (g in goals) {
            Column(Modifier.padding(top = 2.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    T(g.text, Theme.body(14f), modifier = Modifier.weight(1f))
                    if (g.target != null && g.current != null) T("${Helpers.fmtKg(g.current)} / ${Helpers.fmtKg(g.target)}${g.unit}", Theme.head(15f, FontWeight.Bold), Theme.amberText)
                }
                if (g.target != null && g.current != null && g.target > 0) ProgressLine(g.current / g.target, if (g.current >= g.target) Theme.green else Theme.amber, 7.dp)
            }
        }
    }
}

private fun recoveryModes(health: List<HealthRow>): List<RecMode> {
    fun pts(f: (HealthRow) -> Double?) = health.mapNotNull { h -> f(h)?.takeIf { it > 0 }?.let { ChartPoint(shortDate(h.date), it) } }
    return listOf(
        RecMode("hrv", "HRV", pts { it.hrv }, "ms", Theme.green, "Higher and steady is good."),
        RecMode("rhr", "Resting HR", pts { it.rhr }, "bpm", Theme.amber, "Lower and steady is good."),
        RecMode("sleep", "Sleep", pts { it.sleepH }, "h", Theme.green, "Under ~6h, the coach eases off."),
        RecMode("weight", "Body wt", pts { it.weightKg }, "kg", Theme.amber, "Watch the trend, not the day."),
    )
}

@Composable
private fun RecoveryCard(modes: List<RecMode>, recMode: String, setMode: (String) -> Unit, history: List<Session>, health: List<HealthRow>) {
    val active = modes.firstOrNull { it.key == recMode } ?: modes[0]
    val latest = active.points.lastOrNull()?.value ?: 0.0
    val prior = active.points.dropLast(1).takeLast(7).map { it.value }
    val avg = if (prior.isEmpty()) null else prior.average()
    val readiness = Dashboard.readiness(history, health)
    CoachCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(sf("heart.text.square"), null, tint = Theme.green, modifier = Modifier.size(18.dp))
            CapsText("Recovery & ${active.label}")
            Fill()
            readiness?.let { r ->
                StatusPill(
                    when (r.tone) { Dashboard.Tone.Good -> "Optimal recovery"; Dashboard.Tone.Ok -> "Steady"; else -> "Strained" },
                    when (r.tone) { Dashboard.Tone.Good -> Theme.green; Dashboard.Tone.Ok -> Theme.amberText; else -> Theme.red },
                )
            }
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            T(Helpers.fmtKg((latest * 10).rounded() / 10), Theme.head(38f, FontWeight.Bold))
            CapsText(active.unit, Theme.muted, 14f, Modifier.padding(bottom = 7.dp))
            Fill()
            if (avg != null) {
                val d = latest - avg
                CapsText("${if (d >= 0) "+" else ""}${Helpers.fmtKg((d * 10).rounded() / 10)}${active.unit} vs 7d avg", Theme.green, 11f, Modifier.padding(bottom = 8.dp))
            }
        }
        LineChartView(active.points, active.unit, active.color, 140.dp)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (m in modes) Chip(m.label, m.key == active.key) { setMode(m.key) }
        }
        T(active.desc, Theme.body(13f), Theme.muted)
    }
}
