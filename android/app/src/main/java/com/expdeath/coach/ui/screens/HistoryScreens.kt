package com.expdeath.coach.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.expdeath.coach.ai.Gemini
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.Screen
import com.expdeath.coach.models.FinishInfo
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Calories
import com.expdeath.coach.stats.Dashboard
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.formatted
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.CapsText
import com.expdeath.coach.ui.CardLabel
import com.expdeath.coach.ui.ChatBubble
import com.expdeath.coach.ui.ChatInputRow
import com.expdeath.coach.ui.Chevron
import com.expdeath.coach.ui.Chip
import com.expdeath.coach.ui.CoachCard
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.CoachSheet
import com.expdeath.coach.ui.CoachTextField
import com.expdeath.coach.ui.ErrorBox
import com.expdeath.coach.ui.Fill
import com.expdeath.coach.ui.Hairline
import com.expdeath.coach.ui.IconLabel
import com.expdeath.coach.ui.IconWell
import com.expdeath.coach.ui.OutlineButton
import com.expdeath.coach.ui.ProgressLine
import com.expdeath.coach.ui.QLabel
import com.expdeath.coach.ui.ScreenHeader
import com.expdeath.coach.ui.SetField
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.TabHeader
import com.expdeath.coach.ui.TextButtonC
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.VGap
import com.expdeath.coach.ui.sf
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.IsoFields
import java.util.Locale

/** Every exercise in it is logged as time/distance (quick cardio, a run…). */
fun isCardioSession(h: Session): Boolean =
    h.plan.exercises.isNotEmpty() && h.plan.exercises.all { Stats.logMode(it.name, h.plan.sessionType) == "cardio" }

/** 24kg×11 → "24kg × 11"; a tick-off set → "✓" */
fun setShort(s: SetLog): String =
    if (s.weight.isNotEmpty() || s.reps.isNotEmpty()) "${if (s.weight.isEmpty()) "—" else s.weight + "kg"} × ${s.reps.ifEmpty { "?" }}" else s.formatted

/** Same wording as the web chats. */
fun chatError(e: Exception): String {
    val m = e.message ?: ""
    return if (Regex("status|empty", RegexOption.IGNORE_CASE).containsMatchIn(m)) "The coach didn’t answer — check your API key in Settings, then try again."
    else m.ifEmpty { "The coach is unreachable — try again." }
}

/** Ports History.jsx — every logged session, newest first. Tap → detail;
 *  ⋯ → edit sets & notes in place, or delete for good. */
@Composable
fun HistoryScreen(app: AppState) {
    val scope = rememberCoroutineScope()
    var sheetId by remember { mutableStateOf<String?>(null) }
    var deleting by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf<Session?>(null) }
    var filter by remember { mutableStateOf("all") }
    var weekOffset by remember { mutableIntStateOf(0) }
    var day by remember { mutableStateOf<String?>(null) }
    var expanded by remember { mutableStateOf<Set<String>?>(null) }

    val target = Dashboard.weeklyTarget(LocalStore.backup.aiSettings)
    val rev = app.history.asReversed()
    val shown = rev.filter { h -> (day == null || h.date == day) && (filter == "all" || (filter == "cardio") == isCardioSession(h)) }
    // the three newest sessions start expanded; older ones are folded
    val open = expanded ?: rev.take(3).map { it.id }.toSet()
    val weekStart = LocalDate.parse(Stats.mondayOf(Helpers.todayStr())).plusWeeks(weekOffset.toLong())

    fun toggle(id: String) { expanded = if (id in open) open - id else open + id }

    CoachScreen {
        Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            TabHeader(app, "Log")
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CapsText(weekStart.format(DateTimeFormatter.ofPattern("MMMM yyyy")), Theme.amberText, 14f)
                T("Week ${weekStart.get(IsoFields.WEEK_OF_WEEK_BASED_YEAR)}", Theme.meta(13f), Theme.muted)
                Fill()
                OutlineButton("Log workout", icon = "plus") { app.screen = Screen.AddPast }
            }
            // week strip
            val dates = app.history.map { it.date }.toSet()
            val today = Helpers.todayStr()
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.radius)).background(Theme.bgCard).padding(vertical = 8.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(width = 22.dp, height = 44.dp).clickable { weekOffset -= 1 }.semantics { contentDescription = "Previous week" }, contentAlignment = Alignment.Center) {
                    Icon(sf("chevron.left"), null, tint = Theme.dim)
                }
                for (i in 0 until 7) {
                    val d = weekStart.plusDays(i.toLong())
                    val iso = d.toString()
                    val on = day == iso
                    val future = iso > today
                    Column(Modifier.weight(1f).alpha(if (future) 0.35f else 1f).clickable(enabled = !future) { day = if (on) null else iso }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        CapsText(d.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault()), Theme.dim, 11f)
                        Box(
                            Modifier.size(32.dp).clip(CircleShape).background(if (on) Theme.amber else Color.Transparent)
                                .border(1.dp, if (iso == today && !on) Theme.amber.copy(alpha = 0.6f) else Color.Transparent, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) { T("${d.dayOfMonth}", Theme.head(18f, FontWeight.Bold), if (on) Theme.onAmber else if (iso == today) Theme.amberText else Theme.textBody) }
                        Box(Modifier.size(5.dp).clip(CircleShape).background(if (iso in dates) Theme.amber else Color.Transparent))
                    }
                }
                Box(Modifier.size(width = 22.dp, height = 44.dp).clickable(enabled = weekOffset < 0) { weekOffset = minOf(weekOffset + 1, 0) }.semantics { contentDescription = "Next week" }, contentAlignment = Alignment.Center) {
                    Icon(sf("chevron.right"), null, tint = if (weekOffset < 0) Theme.dim else Color.Transparent)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                for ((v, l) in listOf("all" to "All", "strength" to "Strength", "cardio" to "Cardio")) Chip(l, filter == v) { filter = v }
                Fill()
                if (day != null) Chip("Clear day") { day = null }
            }
            // weekly target
            val done = Stats.weekStats(app.history, target).thisWeek
            val pct = minOf(100, (done.toDouble() / maxOf(target, 1) * 100).rounded().toInt())
            CoachCard(padding = 14.dp) {
                Row { CapsText("Weekly target"); Fill(); CapsText("$pct% complete", if (pct >= 100) Theme.green else Theme.amberText, 12f) }
                ProgressLine(pct / 100.0, if (pct >= 100) Theme.green else Theme.amber, 7.dp)
                Row {
                    T("$done of $target sessions finished", Theme.meta(12.5f), Theme.muted)
                    Fill()
                    T(if (done >= target) "Target hit" else "${target - done} to go", Theme.meta(12.5f), Theme.muted)
                }
            }

            if (shown.isEmpty()) {
                T(if (rev.isEmpty()) "Nothing logged yet." else "No sessions here.", Theme.body(15f), Theme.muted, Modifier.fillMaxWidth().padding(top = 40.dp), align = androidx.compose.ui.text.style.TextAlign.Center)
            }
            for (h in shown) {
                val d = draft
                when {
                    d != null && d.id == h.id -> EditCard(d, onChange = { draft = it }, onCancel = { draft = null }) {
                        // only what this form edits, onto the latest copy — a debrief or
                        // another device's change that arrived while editing must survive
                        val latest = (LocalStore.backup.sessions.firstOrNull { it.id == d.id } ?: d).copy(log = d.log, fin = d.fin)
                        scope.launch { app.updateSession(latest) }
                        draft = null
                    }
                    isCardioSession(h) -> CardioCard(h, { app.detailSession = h; app.screen = Screen.HistoryDetail }) { sheetId = h.id; deleting = false }
                    else -> SessionCard(h, h.id in open, { toggle(h.id) }, { app.detailSession = h; app.screen = Screen.HistoryDetail }) { sheetId = h.id; deleting = false }
                }
            }
        }
    }

    sheetId?.let { id ->
        val h = app.history.firstOrNull { it.id == id }
        CoachSheet({ sheetId = null }) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                T("${h?.plan?.sessionType ?: "Session"} · ${Helpers.fmtDate(h?.date ?: "")}", Theme.head(20f, FontWeight.Bold), modifier = Modifier.padding(bottom = 8.dp))
                if (!deleting) {
                    MenuRow("Edit", "pencil") { draft = h; sheetId = null }
                    MenuRow("Delete", "trash", Theme.red) { deleting = true }
                } else {
                    T("Delete for good? It's removed from your log, stats and the coach's memory.", Theme.body(14f), Theme.muted)
                    VGap(8.dp)
                    BigButton("Delete", danger = true) {
                        sheetId = null
                        if (h != null) scope.launch { app.deleteSession(h) }
                    }
                }
                VGap(16.dp)
            }
        }
    }
}

@Composable
fun MenuRow(title: String, icon: String, color: Color = Theme.text, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 11.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(sf(icon), null, tint = color, modifier = Modifier.size(22.dp))
        T(title, Theme.body(16f), color)
    }
}

@Composable
private fun RoundIcon(icon: String, label: String, bg: Color = Color.Transparent, content: @Composable () -> Unit = {}, onClick: () -> Unit) {
    Box(Modifier.size(30.dp).clip(CircleShape).background(bg).clickable(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        content()
        if (icon.isNotEmpty()) Icon(sf(icon), null, tint = Theme.muted, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun SessionCard(h: Session, open: Boolean, onToggle: () -> Unit, onOpen: () -> Unit, onMenu: () -> Unit) {
    val sets = h.log.flatMap { r -> r.filter { it.isLogged } }
    Column(Modifier.clickable(onClick = onOpen)) {
        CoachCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconWell("dumbbell.fill")
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    T(h.plan.sessionType, Theme.body(17f, FontWeight.Bold), maxLines = 1)
                    T(listOfNotNull(Helpers.fmtDate(h.date), h.durationMin?.let { "$it min" }).joinToString(" · "), Theme.meta(13f), Theme.muted)
                }
                RoundIcon("", if (open) "Collapse" else "Expand", Theme.bgHigh, { Chevron(open, size = 18.dp) }, onToggle)
                RoundIcon("ellipsis", "Session options", onClick = onMenu)
            }
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.radiusSm)).background(Theme.bgInput).padding(vertical = 8.dp)) {
                HStat("Volume", "${Stats.sessionVolume(h).formatted()} kg", Modifier.weight(1f))
                HStat("Sets", "${sets.size}", Modifier.weight(1f))
                HStat("Effort", h.fin?.let { "RPE ${it.rpe}" } ?: "—", Modifier.weight(1f), Theme.amberText)
            }
            if (open) {
                h.plan.exercises.forEachIndexed { exI, ex ->
                    val logged = (h.log.getOrNull(exI) ?: emptyList()).filter { it.isLogged }
                    val all = if (logged.isEmpty()) "—" else logged.joinToString("  ") { it.formatted }
                    val best = logged.maxByOrNull { parseDouble(it.weight) ?: 0.0 }
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.radiusSm)).background(Theme.bgPill).padding(horizontal = 10.dp, vertical = 8.dp).semantics { contentDescription = "${ex.name}: $all" },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Box(Modifier.size(6.dp).clip(CircleShape).background(Theme.amber))
                        T(ex.name, Theme.body(14.5f), Theme.textBody, Modifier.weight(1f), maxLines = 1)
                        T(best?.let { setShort(it) } ?: "—", Theme.head(17f, FontWeight.Bold), Theme.amberText)
                    }
                }
            }
        }
    }
}

@Composable
private fun HStat(label: String, value: String, modifier: Modifier, color: Color = Theme.text) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        CapsText(label, Theme.dim, 10.5f)
        T(value, Theme.head(17f, FontWeight.Bold), color, maxLines = 1)
    }
}

@Composable
private fun CardioCard(h: Session, onOpen: () -> Unit, onMenu: () -> Unit) {
    val sets = h.log.flatMap { r -> r.filter { it.isLogged } }
    val km = sets.mapNotNull { parseDouble(it.dist) }.sum()
    val min = sets.mapNotNull { parseDouble(it.time) }.sum()
    val name = (h.plan.exercises.firstOrNull()?.name ?: "").lowercase()
    val icon = when {
        "cycl" in name || "ride" in name || "bike" in name -> "bicycle"
        "hike" in name -> "figure.hiking"
        "walk" in name -> "figure.walk"
        else -> "figure.run"
    }
    Column(Modifier.clickable(onClick = onOpen)) {
        CoachCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconWell(icon, Theme.green)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    T(h.plan.exercises.firstOrNull()?.name ?: h.plan.sessionType, Theme.body(17f, FontWeight.Bold), maxLines = 1)
                    T(listOfNotNull(Helpers.fmtDate(h.date), if (min > 0) "${Helpers.fmtKg(min)} min" else null).joinToString(" · "), Theme.meta(13f), Theme.muted)
                }
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    T(if (km > 0) "${Helpers.fmtKg(km)} km" else "${Helpers.fmtKg(min)} min", Theme.head(20f, FontWeight.Bold))
                    h.fin?.let { CapsText("RPE ${it.rpe}", Theme.green, 11f) }
                }
                RoundIcon("ellipsis", "Session options", onClick = onMenu)
            }
        }
    }
}

@Composable
private fun EditCard(d: Session, onChange: (Session) -> Unit, onCancel: () -> Unit, onSave: () -> Unit) {
    fun edit(exI: Int, setI: Int, f: (SetLog) -> SetLog) {
        if (exI >= d.log.size || setI >= d.log[exI].size) return
        onChange(d.copy(log = d.log.mapIndexed { i, r -> if (i == exI) r.mapIndexed { j, s -> if (j == setI) f(s) else s } else r }))
    }
    fun fin(f: (FinishInfo) -> FinishInfo) = onChange(d.copy(fin = f(d.fin ?: FinishInfo())))
    CoachCard {
        Row {
            T(d.plan.sessionType, Theme.head(18f, FontWeight.Bold))
            Fill()
            T(Helpers.fmtDate(d.date), Theme.meta(13f), Theme.muted)
        }
        d.plan.exercises.forEachIndexed { exI, ex ->
            T(ex.name, Theme.body(14f, FontWeight.SemiBold), Theme.textBody, Modifier.padding(top = 8.dp))
            val mode = Stats.logMode(ex.name, d.plan.sessionType)
            (d.log.getOrNull(exI) ?: emptyList()).forEachIndexed { setI, s ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    T("${setI + 1}", Theme.meta(13f), Theme.muted, Modifier.width(20.dp))
                    when (mode) {
                        "check" -> T(if (s.done) "Done" else "Skipped", Theme.body(13f), Theme.muted)
                        "cardio" -> {
                            SetField(s.time, "min") { v -> edit(exI, setI) { it.copy(time = Helpers.cleanTime(v)) } }
                            T("min", Theme.meta(13f), Theme.muted)
                            SetField(s.dist, "km") { v -> edit(exI, setI) { it.copy(dist = Helpers.cleanDist(v)) } }
                            T("km", Theme.meta(13f), Theme.muted)
                        }
                        else -> {
                            SetField(s.weight, "kg") { v -> edit(exI, setI) { it.copy(weight = Helpers.cleanWeight(v)) } }
                            T("×", Theme.meta(13f), Theme.muted)
                            SetField(s.reps, "reps", decimal = false) { v -> edit(exI, setI) { it.copy(reps = Helpers.cleanReps(v)) } }
                        }
                    }
                }
            }
        }
        T("Session RPE", Theme.meta(13f), Theme.muted, Modifier.padding(top = 10.dp))
        SetField(d.fin?.rpe?.toString() ?: "", "1-10", decimal = false) { v ->
            val n = v.filter { it.isDigit() }.toIntOrNull() ?: 0
            fin { it.copy(rpe = n.coerceIn(1, 10)) }
        }
        CoachTextField(d.fin?.pain ?: "", { v -> fin { it.copy(pain = v) } }, "Pain (empty = none)")
        CoachTextField(d.fin?.feedback ?: "", { v -> fin { it.copy(feedback = v) } }, "Feedback")
        Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BigButton("Save changes", Modifier.weight(1f), onClick = onSave)
            TextButtonC("CANCEL", Theme.muted, Theme.head(15f, FontWeight.SemiBold), onClick = onCancel)
        }
    }
}

/** Ports HistoryDetail.jsx — one logged session in full, with a coach chat
 *  scoped to just it (ephemeral, like the web app's). */
@Composable
fun HistoryDetailScreen(app: AppState) {
    val s = app.detailSession
    if (s == null) {
        LaunchedEffect(Unit) { app.screen = Screen.History }
        CoachScreen {}
        return
    }
    val scope = rememberCoroutineScope()
    var messages by remember { mutableStateOf(listOf<Gemini.ChatMessage>()) }
    var input by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    val scroll = rememberScrollState()
    LaunchedEffect(messages.size) { scroll.animateScrollTo(scroll.maxValue) }

    val health = LocalStore.backup.health
    val kcal = Calories.estimate(s, Calories.latestBodyWeightKg(health))
    val exercises = s.plan.exercises.mapIndexedNotNull { exI, ex ->
        val sets = (s.log.getOrNull(exI) ?: emptyList()).filter { it.isLogged }
        if (sets.isEmpty()) null else ex.name to sets
    }

    fun send() {
        val text = input.trim()
        if (text.isEmpty() || busy) return
        val next = messages + Gemini.ChatMessage("user", text)
        messages = next; input = ""; error = ""; busy = true
        scope.launch {
            try {
                val reply = Gemini.askCoach(next, app.history, healthLog = LocalStore.backup.health, focusSession = s)
                messages = next + Gemini.ChatMessage("coach", reply)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                error = chatError(e)
            }
            busy = false
        }
    }

    CoachScreen {
        Column(Modifier.fillMaxSize().imePadding().verticalScroll(scroll).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            ScreenHeader(s.plan.sessionType, onBack = { app.screen = Screen.History })
            T((listOf(Helpers.fmtDate(s.date)) + listOfNotNull(s.durationMin?.let { "$it min" }, if (kcal > 0) "~${kcal.formatted()} kcal" else null, s.fin?.let { "RPE ${it.rpe}" })).joinToString(" · "), Theme.meta(14f), Theme.muted)
            s.fin?.pain?.takeIf { it.isNotEmpty() }?.let { IconLabel("bandage", it, Theme.amber) }
            // every exercise in one card: name, then its sets on one line
            if (exercises.isNotEmpty()) CoachCard {
                exercises.forEachIndexed { i, (name, sets) ->
                    if (i > 0) Hairline(Modifier.padding(vertical = 4.dp))
                    T(name, Theme.body(15f, FontWeight.SemiBold))
                    T(sets.joinToString("  ·  ") { it.formatted }, Theme.meta(13.5f), Theme.muted)
                }
            }
            val fb = s.fin?.feedback ?: ""
            if (exercises.isEmpty()) T(fb.ifEmpty { "No sets were logged for this session." }, Theme.body(13.5f), Theme.muted)
            else if (fb.isNotEmpty()) T("\"$fb\"", Theme.body(13.5f), Theme.muted)
            s.debrief?.takeIf { it.isNotEmpty() }?.let { d ->
                CoachCard { CardLabel("Coach debrief"); T(d, Theme.body(14.5f), Theme.textBody) }
            }
            Hairline(Modifier.padding(top = 12.dp))
            QLabel("Ask about this session")
            for (m in messages) ChatBubble(m.text, m.role == "user")
            if (busy) ChatBubble("…")
            if (error.isNotEmpty()) ErrorBox(error)
            ChatInputRow(input, { input = it }, "Ask about this session…", busy) { send() }
            VGap(24.dp)
        }
    }
}
