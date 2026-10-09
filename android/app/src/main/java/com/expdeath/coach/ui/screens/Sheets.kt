package com.expdeath.coach.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.expdeath.coach.account.Account
import com.expdeath.coach.ai.Gemini
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.Screen
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Dashboard
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.ui.Avatar
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.CIconButton
import com.expdeath.coach.ui.CapsText
import com.expdeath.coach.ui.ChatBubble
import com.expdeath.coach.ui.ChatInputRow
import com.expdeath.coach.ui.CoachSheet
import com.expdeath.coach.ui.CoachTextField
import com.expdeath.coach.ui.ErrorBox
import com.expdeath.coach.ui.IconWell
import com.expdeath.coach.ui.QLabel
import com.expdeath.coach.ui.StatusPill
import com.expdeath.coach.ui.Stepper
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.Title
import com.expdeath.coach.ui.VGap
import com.expdeath.coach.ui.sf
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private const val CHAT_PREFIX = "chat-"
private val starters = listOf("Shoulder feels off — what do I swap?", "Too tired for legs. Alternatives?", "How heavy should warm-up sets be?")

/** Ports Coach.jsx — the coach chat as a bottom sheet, reachable from any
 *  screen. Today's chat is account state (`chat-<date>`, same key and shape
 *  as the other apps), so a conversation continues across devices. */
@Composable
fun CoachChatSheet(app: AppState, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val key = CHAT_PREFIX + Helpers.todayStr()
    var messages by remember {
        mutableStateOf((Cloud.stateValue(key)?.array ?: emptyList()).mapNotNull { v ->
            val o = v.obj ?: return@mapNotNull null
            val role = o["role"]?.string ?: return@mapNotNull null
            val text = o["text"]?.string ?: return@mapNotNull null
            Gemini.ChatMessage(role, text)
        })
    }
    var input by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    val scroll = rememberScrollState()
    LaunchedEffect(messages.size, busy) { scroll.animateScrollTo(scroll.maxValue) }

    fun save(msgs: List<Gemini.ChatMessage>) {
        // today's chat only — yesterday's questions rarely matter tomorrow
        for (k in Cloud.stateKeys()) if (k.startsWith(CHAT_PREFIX) && k != key) Cloud.setState(k, null)
        Cloud.setState(key, JSONValue.Arr(msgs.takeLast(30).map { JSONValue.obj("role" to JSONValue.Str(it.role), "text" to JSONValue.Str(it.text)) }))
    }

    fun send() {
        val text = input.trim()
        if (text.isEmpty() || busy) return
        val next = messages + Gemini.ChatMessage("user", text)
        messages = next; save(next); input = ""; error = ""; busy = true
        scope.launch {
            try {
                val reply = Gemini.askCoach(next, app.history, app.todayPlan, LocalStore.backup.health)
                val done = next + Gemini.ChatMessage("coach", reply)
                messages = done
                save(done)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                error = chatError(e)
            }
            busy = false
        }
    }

    CoachSheet(onClose) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.85f).imePadding()) {
            Row(Modifier.padding(horizontal = 16.dp).padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                T("Coach", Theme.head(26f, FontWeight.Bold), modifier = Modifier.weight(1f))
                CIconButton("xmark", "Close chat", onClick = onClose)
            }
            Column(Modifier.weight(1f).verticalScroll(scroll).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (messages.isEmpty()) {
                    // tap a starter instead of reading a paragraph of examples
                    for (q in starters) {
                        T(q, Theme.body(14.5f), Theme.textBody, Modifier.clip(RoundedCornerShape(14.dp)).border(1.dp, Theme.borderDim, RoundedCornerShape(14.dp)).clickable { input = q }.padding(horizontal = 13.dp, vertical = 10.dp))
                    }
                }
                for (m in messages) ChatBubble(m.text, m.role == "user")
                if (busy) ChatBubble("…")
                if (error.isNotEmpty()) ErrorBox(error)
            }
            Box(Modifier.padding(16.dp)) { ChatInputRow(input, { input = it }, "Ask the coach…", busy) { send() } }
        }
    }
}

/** "2h", "3d", "Sep 12" */
fun ago(ms: Double): String {
    val s = (System.currentTimeMillis() - ms) / 1000
    if (s < 3600) return "${maxOf((s / 60).toInt(), 1)}m"
    if (s < 86400) return "${(s / 3600).toInt()}h"
    if (s < 7 * 86400) return "${(s / 86400).toInt()}d"
    return DateTimeFormatter.ofPattern("MMM d").withZone(ZoneId.systemDefault()).format(Instant.ofEpochMilli(ms.toLong()))
}

/** The bell's inbox — reviews, new records, milestones and deload warnings
 *  (Dashboard.notifications), newest first. Opening it marks everything
 *  read; tapping one jumps to where it lives. */
@Composable
fun NotificationsSheet(app: AppState, onClose: () -> Unit) {
    var seenBefore by remember { mutableDoubleStateOf(app.notifSeenAt) }
    LaunchedEffect(Unit) {
        seenBefore = app.notifSeenAt
        app.markNotificationsSeen()
    }
    val items = app.notifications
    CoachSheet(onClose) {
        Row(Modifier.padding(horizontal = 16.dp).padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Title("Notifications", 26f, tracking = 0.6f, modifier = Modifier.weight(1f))
            CIconButton("xmark", "Close", onClick = onClose)
        }
        if (items.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(sf("bell.slash"), null, tint = Theme.dim, modifier = Modifier.size(28.dp))
                T("Nothing yet — reviews, records and milestones show up here.", Theme.body(14f), Theme.muted, align = TextAlign.Center)
            }
        } else {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (n in items) {
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.radius)).background(Theme.bgCard).clickable { onClose(); app.screen = n.screen }.padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        IconWell(n.icon, if (n.icon.startsWith("exclamation")) Theme.red else Theme.amberText, 34.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                T(n.title, Theme.body(15f, FontWeight.Medium), modifier = Modifier.weight(1f), maxLines = 1)
                                T(ago(n.at), Theme.meta(12f), Theme.dim)
                            }
                            T(n.body, Theme.body(13.5f), Theme.muted, maxLines = 2)
                        }
                        if (n.at > seenBefore) Box(Modifier.padding(top = 6.dp).size(7.dp).clip(CircleShape).background(Theme.amber))
                    }
                }
            }
        }
    }
}

/** Edit profile — the name the app greets you by (state `displayName`,
 *  shared with the other apps) and your weekly session target. Google still
 *  owns the sign-in email. */
@Composable
fun ProfileSheet(app: AppState, onClose: () -> Unit) {
    val account = Account.current()
    var name by remember { mutableStateOf(app.displayNameOverride ?: account?.name ?: "") }
    var target by remember { mutableIntStateOf(Dashboard.weeklyTarget(LocalStore.backup.aiSettings)) }
    CoachSheet(onClose, full = true) {
        Column(Modifier.imePadding().verticalScroll(rememberScrollState()).padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Title("Profile", 26f, tracking = 0.6f, modifier = Modifier.weight(1f))
                CIconButton("xmark", "Close", onClick = onClose)
            }
            Row(Modifier.padding(vertical = 18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Avatar(name.ifEmpty { app.displayName }, 56.dp)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    T(name.ifEmpty { app.displayName }, Theme.body(18f, FontWeight.Bold), maxLines = 1)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        StatusPill(if (account?.admin == true) "Admin" else "Member", Theme.amberText, dot = false)
                        T(account?.email ?: "", Theme.meta(12.5f), Theme.muted, maxLines = 1)
                    }
                }
            }
            QLabel("Display name")
            CoachTextField(name, { name = it }, account?.name ?: "Your name", capitalization = KeyboardCapitalization.Words)
            QLabel("Weekly target", "$target / week")
            Row(verticalAlignment = Alignment.CenterVertically) {
                T("Sessions per week", Theme.body(15f), Theme.textBody, Modifier.weight(1f))
                Stepper(target, 1..14) { target = it }
            }
            T("Sets your streak, consistency and the weekly target bar.", Theme.body(13f), Theme.muted, Modifier.padding(top = 4.dp))
            VGap(24.dp)
            BigButton("Save") {
                app.setDisplayName(name)
                LocalStore.updateAISettings { it.copy(weeklyTarget = target) }
                onClose()
            }
        }
    }
}

/** Search across the account — ports Search.jsx: exercises (→ their
 *  record), saved workouts (→ the editor) and logged sessions (→ the session). */
@Composable
fun SearchSheet(app: AppState, onClose: () -> Unit) {
    var q by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { try { focus.requestFocus() } catch (_: Exception) {} }
    val term = q.trim().lowercase()
    fun has(s: String) = s.lowercase().contains(term)
    val history = app.history
    fun sessionName(s: com.expdeath.coach.models.Session): String =
        if (isCardioSession(s)) s.plan.exercises.firstOrNull()?.name ?: s.plan.sessionType else s.plan.title.ifEmpty { s.plan.sessionType }
    val seen = HashSet<String>()
    val names = history.flatMap { h -> h.plan.exercises.map { it.name.trim() } }.filter { it.isNotEmpty() && seen.add(it.lowercase()) }
    val records = Stats.prRecords(history)
    val exercises = if (term.length < 2) emptyList() else names.filter { has(it) }
        .map { n -> n to records.firstOrNull { it.name.lowercase() == n.lowercase() } }.sortedByDescending { it.second?.count ?: 0 }.take(5)
    val workouts = if (term.length < 2) emptyList() else Workouts.list().filter { w -> has(w.name) || has(w.trainer) || w.exercises.any { has(it.name) } }.take(4)
    val sessions = if (term.length < 2) emptyList() else history.asReversed().filter { s ->
        has(sessionName(s)) || has(s.plan.sessionType) || has(s.date) || has(Helpers.fmtDate(s.date)) || has(s.fin?.feedback ?: "") || s.plan.exercises.any { has(it.name) }
    }.take(6)

    CoachSheet(onClose, full = true) {
        Row(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            T("Search", Theme.head(22f, FontWeight.Bold), modifier = Modifier.weight(1f))
            T("Done", Theme.body(15f, FontWeight.Medium), Theme.amberText, Modifier.clickable(onClick = onClose).padding(8.dp))
        }
        Column(Modifier.imePadding().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            CoachTextField(q, { q = it }, "Exercise, workout or date…", Modifier.focusRequester(focus).padding(bottom = 8.dp), capitalization = KeyboardCapitalization.None)
            when {
                term.length < 2 -> T("Search exercises, workouts and your log — e.g. “squat”, “push”, “Sept”.", Theme.body(13.5f), Theme.muted)
                exercises.isEmpty() && workouts.isEmpty() && sessions.isEmpty() -> T("Nothing matches.", Theme.body(13.5f), Theme.muted)
            }
            if (exercises.isNotEmpty()) GroupTitle("Exercises")
            for ((name, rec) in exercises) {
                SearchRow("trophy", name, Stats.muscleGroupOf(name) + (rec?.let { " · ${it.count} sets logged" } ?: ""),
                    rec?.weight?.let { "${Helpers.fmtKg(it.w)} kg × ${it.reps.ifEmpty { "?" }}" }) { onClose(); app.openRecord(name) }
            }
            if (workouts.isNotEmpty()) GroupTitle("My workouts")
            for (w in workouts) {
                SearchRow("list.bullet.clipboard", w.name,
                    listOf(if (w.source == "trainer") w.trainer.ifEmpty { "Trainer" } else "Mine", Workouts.daysLabel(w), "${w.exercises.size} exercises").filter { it.isNotEmpty() }.joinToString(" · "),
                ) { onClose(); app.openWorkouts(id = w.id) }
            }
            if (sessions.isNotEmpty()) GroupTitle("Sessions")
            for (s in sessions) {
                SearchRow("dumbbell", sessionName(s), listOfNotNull(Helpers.fmtDate(s.date), s.durationMin?.let { "$it min" }, s.fin?.let { "RPE ${it.rpe}" }).joinToString(" · ")) {
                    onClose()
                    app.detailSession = s
                    app.screen = Screen.HistoryDetail
                }
            }
        }
    }
}

@Composable
private fun GroupTitle(t: String) = CapsText(t, Theme.dim, 11f, Modifier.padding(top = 10.dp, bottom = 2.dp))

@Composable
private fun SearchRow(icon: String, title: String, sub: String, value: String? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        IconWell(icon, size = 32.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            T(title, Theme.body(15f, FontWeight.SemiBold), maxLines = 1)
            T(sub, Theme.meta(12.5f), Theme.muted, maxLines = 1)
        }
        if (value != null) CapsText(value, Theme.amberText, 13f)
    }
}
