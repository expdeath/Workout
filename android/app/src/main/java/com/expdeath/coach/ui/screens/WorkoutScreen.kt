package com.expdeath.coach.ui.screens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.MediaController
import android.widget.VideoView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.expdeath.coach.ai.Gemini
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.MainActivity
import com.expdeath.coach.app.RestNotifier
import com.expdeath.coach.app.Screen
import com.expdeath.coach.models.FinishInfo
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.persistence.MediaStore
import com.expdeath.coach.persistence.Prefs
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.fmt
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.CIconButton
import com.expdeath.coach.ui.BackButton
import com.expdeath.coach.ui.CapsText
import com.expdeath.coach.ui.CardLabel
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.CoachSheet
import com.expdeath.coach.ui.CoachTextField
import com.expdeath.coach.ui.ExpandableText
import com.expdeath.coach.ui.Fill
import com.expdeath.coach.ui.HGap
import com.expdeath.coach.ui.IconLabel
import com.expdeath.coach.ui.ReadinessBar
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.TextButtonC
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.VGap
import com.expdeath.coach.ui.openUrl
import com.expdeath.coach.ui.panel
import com.expdeath.coach.ui.sf
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.net.URLEncoder
import kotlin.math.ceil

private val efforts = listOf("", "easy", "good", "grind")

/** "90s" → 90 · "2min" → 120 · "1-2min" → 120 · fallback 90 (parseRestSeconds). */
fun parseRestSeconds(rest: String): Double {
    val g = Stats.firstMatch("""(\d+)(?:\s*-\s*(\d+))?\s*(s|sec|m|min)?""", rest) ?: return 90.0
    val first = g.getOrNull(1) ?: return 90.0
    val n = parseDouble(g.getOrNull(2) ?: first) ?: return 90.0
    val unit = (g.getOrNull(3) ?: "s").lowercase()
    val secs = if (unit.startsWith("m")) n * 60 else n
    return secs.coerceIn(15.0, 600.0)
}

private data class RestTimer(val endsAt: Long, val total: Double, val exName: String)
private data class SheetState(val exI: Int, val mode: String) // menu | swap | remove
private data class HarderState(val loading: Boolean = false, val caution: String? = null, val options: List<Gemini.IntensifyOption> = emptyList(), val applied: Set<Int> = emptySet(), val error: String? = null)

/** Per-exercise context: logging mode, last time, suggestion, plate target. */
private data class ExMeta(val ex: Plan.Exercise, val exI: Int, val mode: String, val lastPerf: Stats.LastPerformance?, val suggest: Double?, val plateTarget: Double?)

private fun cueKey(name: String) = name.trim().lowercase()

/** Ports Workout.jsx — the guided session: set logging (strength kg×reps ·
 *  cardio min/km · tick-off), rest timer, superset flow, plate math,
 *  last-time hints, cue notes + form photo/clip, the per-exercise ⋯ menu and
 *  "make it harder". Every edit goes through AppState (→ Firestore). */
@Composable
fun WorkoutScreen(app: AppState) {
    val t = app.todayPlan
    if (t == null) {
        LaunchedEffect(Unit) { app.screen = Screen.Home }
        CoachScreen {}
        return
    }
    val ctx = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    var sheet by remember { mutableStateOf<SheetState?>(null) }
    var swapDraft by remember { mutableStateOf("") }
    var confirmCancel by remember { mutableStateOf(false) }
    var platesFor by remember { mutableStateOf<Int?>(null) }
    var editingCue by remember { mutableStateOf<Int?>(null) }
    var cueDraft by remember { mutableStateOf("") }
    var harder by remember { mutableStateOf<HarderState?>(null) }
    var timer by remember { mutableStateOf<RestTimer?>(null) }
    var restJob by remember { mutableStateOf<Job?>(null) }
    var mediaVersion by remember { mutableIntStateOf(0) } // bump to re-read thumbnails
    var viewer by remember { mutableStateOf<MediaStore.Item?>(null) }
    var pickFor by remember { mutableStateOf<String?>(null) } // exercise name awaiting a photo/clip

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        val name = pickFor
        pickFor = null
        if (uri != null && name != null) {
            val isVideo = ctx.contentResolver.getType(uri)?.startsWith("video") == true
            try { MediaStore.put(cueKey(name), uri, isVideo) } catch (_: Exception) {}
            mediaVersion += 1
        }
    }

    fun stopTimer() {
        restJob?.cancel()
        restJob = null
        timer = null
        view.keepScreenOn = false
        RestNotifier.cancel(ctx)
    }

    fun startTimer(seconds: Double, exName: String) {
        stopTimer()
        timer = RestTimer(System.currentTimeMillis() + (seconds * 1000).toLong(), seconds, exName)
        // Settings → Alerts & reports decides which of these happen
        val sound = Prefs.isOn("restSound"); val buzz = Prefs.isOn("restVibrate")
        if (Prefs.isOn("keepAwake")) view.keepScreenOn = true // screen stays on while resting
        restJob = scope.launch {
            // a real notification: fires even with the phone locked or in another app
            if (Prefs.isOn("restNotify") && (MainActivity.current?.askNotifications() ?: RestNotifier.canNotify(ctx))) {
                val left = (timer?.endsAt ?: 0L) - System.currentTimeMillis()
                if (left > 0) RestNotifier.schedule(ctx, left / 1000.0, exName, sound)
            }
            val left = (timer?.endsAt ?: 0L) - System.currentTimeMillis()
            if (left > 0) delay(left)
            if (buzz) RestNotifier.buzz(ctx)
            if (sound) RestNotifier.beep()
            delay(4000)
            timer = null
            view.keepScreenOn = false
        }
    }

    DisposableEffect(Unit) { onDispose { restJob?.cancel(); view.keepScreenOn = false; RestNotifier.cancel(ctx) } }

    fun toggleSet(exI: Int, setI: Int, set: SetLog) {
        val turningOn = !set.done
        app.updateSet(exI, setI, done = turningOn)
        RestNotifier.tick(ctx)
        val ex = t.plan.exercises.getOrNull(exI) ?: return
        if (turningOn) startTimer(parseRestSeconds(ex.rest), ex.name)
    }

    fun exMeta(exI: Int): ExMeta {
        val ex = t.plan.exercises[exI]
        val mode = Stats.logMode(ex.name, t.plan.sessionType)
        val lastPerf = Stats.lastPerformance(app.history, ex.name)
        val suggest = if (mode != "strength") null else Stats.suggestNextWeight(lastPerf, ex.reps)
        val typed = t.log.getOrNull(exI)?.reversed()?.mapNotNull { parseDouble(it.weight) }?.firstOrNull { it > 0 }
        // parseFloat("24kg") → 24, like JS
        val leading = Stats.firstMatch("""^\s*(\d+(?:\.\d+)?)""", ex.suggestedWeight)?.getOrNull(1)?.let { parseDouble(it) }
        val plateTarget = if (mode != "strength") null else typed ?: suggest ?: leading
        return ExMeta(ex, exI, mode, lastPerf, suggest, plateTarget)
    }

    @Composable
    fun PlateLine(target: Double) {
        val gym = LocalStore.backup.aiSettings
        val info = Helpers.plateBreakdown(target, gym.barKg ?: Helpers.defaultBarKg, Helpers.parsePlates(gym.plates) ?: Helpers.defaultPlates) ?: return
        val kg = Helpers::fmtKg
        var s = if (info.perSide.isEmpty())
            "${kg(target)}kg → bar only (${kg(info.bar)}kg${if (target < info.bar) " — lighter than the bar" else ""})"
        else "${kg(target)}kg → ${kg(info.bar)}kg bar + ${info.perSide.joinToString(" + ") { kg(it) }} per side"
        if (info.perSide.isNotEmpty() && !info.exact) s += " · closest load ${kg(info.loaded)}kg"
        T(s, Theme.meta(13f), Theme.amber)
    }

    @Composable
    fun ExHeader(m: ExMeta, dot: Color?, paired: Boolean) {
        val ex = m.ex
        val key = cueKey(ex.name)
        val cue = LocalStore.backup.aiSettings.cueNotes[key]
        val media = remember(key, mediaVersion) { MediaStore.get(key) }
        val tryWeight = m.suggest?.let { "${Helpers.fmtKg(it)}kg" } ?: if (m.mode == "strength" && ex.suggestedWeight.isNotEmpty()) ex.suggestedWeight else null
        // one line of prescription, one line of guidance — everything else is in ⋯
        val prescription = listOf("${ex.sets} × ${ex.reps}", if (ex.rpe.isEmpty()) "" else "RPE ${ex.rpe}", if (ex.rest.isEmpty()) "" else "${ex.rest} rest").filter { it.isNotEmpty() }.joinToString(" · ")
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (dot != null) { Box(Modifier.size(8.dp).clip(CircleShape).background(dot)); HGap(6.dp) }
                T(ex.name, Theme.head(20f, FontWeight.Bold), modifier = Modifier.weight(1f))
                Box(Modifier.size(width = 36.dp, height = 28.dp).clickable { sheet = SheetState(m.exI, "menu") }.semantics { contentDescription = "Options for ${ex.name}" }, contentAlignment = Alignment.Center) {
                    Icon(sf("ellipsis"), null, tint = Theme.muted)
                }
            }
            T(prescription, Theme.meta(13.5f), Theme.textBody)
            if (tryWeight != null || m.lastPerf != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (tryWeight != null) T("Try $tryWeight${if (m.suggest != null && m.lastPerf != null) " ↑" else ""}", Theme.meta(13f, FontWeight.SemiBold), Theme.amber)
                    m.lastPerf?.let { lp -> T("Last ${lp.sets.joinToString(", ") { it.formatted }}", Theme.meta(13f), Theme.muted, Modifier.weight(1f, fill = false), maxLines = 1) }
                    if (m.plateTarget != null) {
                        Fill()
                        Box(Modifier.size(28.dp).clickable { platesFor = if (platesFor == m.exI) null else m.exI }.semantics { contentDescription = "Plate breakdown for ${Helpers.fmtKg(m.plateTarget)}kg" }, contentAlignment = Alignment.Center) {
                            Icon(sf("scalemass"), null, tint = if (platesFor == m.exI) Theme.amber else Theme.green, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            if (platesFor == m.exI && m.plateTarget != null) PlateLine(m.plateTarget)
            if (!paired && ex.superset.isNotEmpty()) T("Superset ${ex.superset}", Theme.meta(12.5f, FontWeight.Medium), Theme.green)
            if (ex.notes.isNotEmpty()) T(ex.notes, Theme.body(13.5f), Theme.muted, maxLines = 2)
            if (editingCue == m.exI) {
                Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    CoachTextField(cueDraft, { cueDraft = it }, "Note to self, e.g. seat height 4", singleLine = false, minLines = 2, maxLines = 5)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SmallChip("Save", on = true) {
                            val text = cueDraft.trim().take(200)
                            LocalStore.updateAISettings { s -> s.copy(cueNotes = if (text.isEmpty()) s.cueNotes - key else s.cueNotes + (key to text)) }
                            editingCue = null
                        }
                        SmallChip(if (media != null) "Replace photo" else "Add photo") {
                            pickFor = ex.name
                            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                        }
                        if (media != null) SmallChip("Remove photo") { MediaStore.remove(key); mediaVersion += 1 }
                        SmallChip("Cancel") { editingCue = null }
                    }
                    T("Photos stay on this device.", Theme.meta(12f), Theme.dim)
                }
            } else if (cue != null) {
                Box(Modifier.clickable { cueDraft = cue; editingCue = m.exI }) { IconLabel("pencil", cue, Theme.amber, Theme.body(13.5f)) }
            }
            if (media != null && editingCue != m.exI) {
                Box(Modifier.padding(top = 6.dp).clickable { viewer = media }.semantics { contentDescription = "Form reference for ${ex.name}" }) { MediaThumb(media) }
            }
        }
    }

    @Composable
    fun SetRow(m: ExMeta, setI: Int, dot: Color?) {
        val exists = t.log.getOrNull(m.exI)?.getOrNull(setI)
        val set = exists ?: SetLog()
        val last = m.lastPerf?.sets?.getOrNull(setI)
        Row(Modifier.alpha(if (exists != null) 1f else 0f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (dot != null) Box(Modifier.size(8.dp).clip(CircleShape).background(dot))
            Box(
                Modifier.size(34.dp).clip(RoundedCornerShape(Theme.radiusSm)).background(if (set.done) Theme.green else Theme.bgPill)
                    .clickable(enabled = exists != null) { toggleSet(m.exI, setI, set) }
                    .semantics { contentDescription = if (set.done) "Set ${setI + 1} done" else "Set ${setI + 1}" },
                contentAlignment = Alignment.Center,
            ) { T(if (set.done) "✓" else "${setI + 1}", Theme.meta(14f, FontWeight.Medium), if (set.done) Theme.bg else Theme.text) }
            when (m.mode) {
                "check" -> T(m.ex.reps, Theme.body(13.5f), Theme.textBody, Modifier.weight(1f).clickable(enabled = exists != null) { toggleSet(m.exI, setI, set) })
                "cardio" -> {
                    NumField(set.time, last?.time?.ifEmpty { null } ?: "min") { app.updateSet(m.exI, setI, time = it) }
                    T("min", Theme.meta(13f), Theme.muted)
                    NumField(set.dist, last?.dist?.ifEmpty { null } ?: "km") { app.updateSet(m.exI, setI, dist = it) }
                    T("km", Theme.meta(13f), Theme.muted)
                }
                else -> {
                    NumField(set.weight, m.suggest?.let { Helpers.fmtKg(it) } ?: last?.weight?.ifEmpty { null } ?: "kg") { app.updateSet(m.exI, setI, weight = it) }
                    T("×", Theme.meta(13f), Theme.muted)
                    NumField(set.reps, last?.reps?.ifEmpty { null } ?: "reps", decimal = false) { app.updateSet(m.exI, setI, reps = it) }
                }
            }
            if (m.mode != "check") {
                Fill()
                // the effort tag only appears once the set is ticked (its space stays reserved)
                val show = set.done || set.effort.isNotEmpty()
                val color = when (set.effort) { "easy" -> Theme.green; "good" -> Theme.amber; "grind" -> Theme.red; else -> Theme.dim }
                T(set.effort.ifEmpty { "rate" }, Theme.meta(12.5f, FontWeight.Medium), color,
                    Modifier.widthIn(min = 44.dp).alpha(if (show) 1f else 0f)
                        .clickable(enabled = show) { app.updateSet(m.exI, setI, effort = efforts[(efforts.indexOf(set.effort).coerceAtLeast(0) + 1) % efforts.size]) }
                        .padding(vertical = 8.dp)
                        .semantics { contentDescription = "Effort for set ${setI + 1}: ${set.effort.ifEmpty { "not rated" }}" },
                    align = TextAlign.Center)
            }
        }
    }

    val p = t.plan
    Box(Modifier.fillMaxSize()) {
        CoachScreen {
            Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(16.dp)) {
                // header
                val total = t.log.sumOf { it.size }
                val done = t.log.sumOf { r -> r.count { it.done } }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BackButton("Home") { app.screen = Screen.Home }
                    Fill()
                    CapsText("$done/$total sets", if (done == total && total > 0) Theme.green else Theme.muted, 15f)
                    Fill()
                    CIconButton("bubble.left", "Ask the coach") { app.chatOpen = true }
                    CIconButton("xmark", "Cancel this session") { confirmCancel = !confirmCancel }
                }
                if (confirmCancel) {
                    val anyLogged = t.log.any { r -> r.any { it.isLogged } }
                    Row(Modifier.padding(top = 10.dp).fillMaxWidth().clip(RoundedCornerShape(Theme.radiusSm)).background(Theme.redBg).padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        T("Discard this session entirely?${if (anyLogged) " Your logged sets will be lost." else ""}", Theme.body(13.5f), Theme.textBody, Modifier.weight(1f))
                        TextButtonC("Discard", Theme.red, Theme.head(14f, FontWeight.Bold)) { stopTimer(); app.cancelSession() }
                        TextButtonC("Keep", Theme.muted, Theme.head(14f, FontWeight.Bold)) { confirmCancel = false }
                    }
                }
                T(p.sessionType.uppercase(), Theme.head(40f, FontWeight.Bold), Theme.amber, Modifier.padding(top = 4.dp))
                T(listOf(p.title, if (p.estTimeMin > 0) "~${p.estTimeMin} min" else "").filter { it.isNotEmpty() }.joinToString(" · "), Theme.body(15f), Theme.muted)
                ReadinessBar(p.recoveryScore ?: 50, "Recovery", Modifier.padding(top = 14.dp))

                // why + warm-up in one quiet card; the reasoning folds to 2 lines
                WCard {
                    if (p.reasoning.isNotEmpty()) ExpandableText(p.reasoning, 2)
                    if (p.concerns.isNotEmpty()) IconLabel("exclamationmark.triangle.fill", p.concerns, Theme.amber)
                    if (p.warmup.isNotEmpty()) T("Warm-up  " + p.warmup.joinToString(" · "), Theme.body(14f), Theme.textBody)
                }

                // superset flow: two exercises sharing a letter merge into one card, rows A1 B1 A2 B2
                for (g in groupedExercises(p.exercises)) {
                    if (g.size == 2) {
                        val a = exMeta(g[0]); val b = exMeta(g[1])
                        WCard {
                            CapsText("Superset ${a.ex.superset}", Theme.green, 12f, Modifier.padding(bottom = 6.dp))
                            ExHeader(a, Theme.green, true)
                            VGap(12.dp)
                            ExHeader(b, Theme.amber, true)
                            val rounds = maxOf(t.log.getOrNull(a.exI)?.size ?: 0, t.log.getOrNull(b.exI)?.size ?: 0)
                            Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (r in 0 until rounds) { SetRow(a, r, Theme.green); SetRow(b, r, Theme.amber) }
                            }
                        }
                    } else {
                        val m = exMeta(g[0])
                        WCard {
                            ExHeader(m, null, false)
                            Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (s in 0 until (t.log.getOrNull(m.exI)?.size ?: 0)) SetRow(m, s, null)
                            }
                        }
                    }
                }

                p.cardio?.takeIf { it.desc.isNotEmpty() || it.duration.isNotEmpty() }?.let { c ->
                    WCard { CardLabel("Cardio"); T(listOf(c.desc, c.duration).filter { it.isNotEmpty() }.joinToString(" · "), Theme.body(14.5f)) }
                }
                if (p.cooldown.isNotEmpty()) WCard { CardLabel("Cool-down"); T(p.cooldown.joinToString(" · "), Theme.body(14.5f)) }

                // make it harder
                val h = harder
                if (h != null) {
                    WCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CardLabel("Push harder"); Fill()
                            CIconButton("xmark", "Close") { harder = null }
                        }
                        h.caution?.let { T(it, Theme.body(13.5f), Theme.amber) }
                        if (h.loading) T("Picking upgrades…", Theme.body(14f), Theme.muted)
                        h.error?.let { T(it, Theme.body(14f), Theme.amber) }
                        h.options.forEachIndexed { i, o ->
                            val applied = i in h.applied
                            Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.Top) {
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    T(harderLabel(o), Theme.body(14.5f))
                                    if (o.why.isNotEmpty()) T(o.why, Theme.meta(12f), Theme.muted)
                                }
                                TextButtonC(if (applied) "✓ In" else "Apply", if (applied) Theme.muted else Theme.green, Theme.head(14f, FontWeight.Bold), enabled = !applied) {
                                    if (app.applyHarder(o)) harder = harder?.copy(applied = (harder?.applied ?: emptySet()) + i)
                                }
                            }
                        }
                        if (!h.loading && h.error == null && h.options.isEmpty()) T("Nothing to add today — finish strong.", Theme.body(14f), Theme.muted)
                    }
                } else {
                    Box(
                        Modifier.padding(top = 14.dp).fillMaxWidth().clip(RoundedCornerShape(Theme.radius))
                            .drawBehind {
                                drawRoundRect(Theme.amber.copy(alpha = 0.5f), cornerRadius = CornerRadius(Theme.radius.toPx()),
                                    style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 5.dp.toPx()))))
                            }
                            .clickable {
                                scope.launch {
                                    val health = LocalStore.backup.health
                                    // gentle data-driven reminder, shown instantly while the AI thinks
                                    val caution = Stats.recoveryCaution(t.checkin, app.history, health)
                                    harder = HarderState(loading = true, caution = caution)
                                    harder = try {
                                        val res = Gemini.intensifyWorkout(t, app.history, health)
                                        HarderState(caution = caution ?: res.note.ifEmpty { null }, options = res.options)
                                    } catch (e: Exception) {
                                        if (e is kotlinx.coroutines.CancellationException) throw e
                                        HarderState(caution = caution, error = "Couldn’t reach the coach — try again in a moment.")
                                    }
                                }
                            }.padding(vertical = 14.dp),
                        contentAlignment = Alignment.Center,
                    ) { T("Make it harder", Theme.head(15f, FontWeight.SemiBold), Theme.amber) }
                }

                VGap(18.dp)
                BigButton("Finish session") {
                    app.fin = FinishInfo()
                    app.screen = Screen.Finish
                }
                VGap(if (timer == null) 24.dp else 96.dp)
            }
        }
        timer?.let { RestBar(it, Modifier.align(Alignment.BottomCenter)) { stopTimer() } }
    }

    // ── ⋯ menu (bottom sheet) ──
    sheet?.let { s ->
        val ex = t.plan.exercises.getOrNull(s.exI)
        val rows = t.log.getOrNull(s.exI) ?: emptyList()
        val canDrop = rows.size > 1 && rows.lastOrNull()?.isLogged == false
        CoachSheet({ sheet = null }) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                T(ex?.name ?: "", Theme.head(20f, FontWeight.Bold), modifier = Modifier.padding(bottom = 8.dp))
                when (s.mode) {
                    "menu" -> {
                        if (ex != null && ex.alt.isNotEmpty()) SheetItem("Swap to ${ex.alt}", "arrow.left.arrow.right", Theme.green) { sheet = null; app.swapExercise(s.exI) }
                        SheetItem("Did something else…", "pencil.line", Theme.green) { swapDraft = ""; sheet = SheetState(s.exI, "swap") }
                        SheetItem("How-to video", "play.rectangle") {
                            sheet = null
                            openUrl(ctx, "https://www.youtube.com/results?search_query=" + URLEncoder.encode("how to ${ex?.name ?: ""} proper form", "UTF-8"))
                        }
                        SheetItem("Add set", "plus") { sheet = null; app.adjustSets(s.exI, 1) }
                        SheetItem("Remove set", "minus", enabled = canDrop) { sheet = null; app.adjustSets(s.exI, -1) }
                        val cue = LocalStore.backup.aiSettings.cueNotes[cueKey(ex?.name ?: "")]
                        SheetItem(if (cue == null) "Note or photo" else "Edit note", "note.text") { cueDraft = cue ?: ""; editingCue = s.exI; sheet = null }
                        SheetItem("Remove exercise", "trash", Theme.red) { sheet = SheetState(s.exI, "remove") }
                    }
                    "swap" -> {
                        T("What did you do instead?", Theme.body(14f), Theme.muted)
                        val save = {
                            val name = swapDraft.trim()
                            if (name.isNotEmpty()) app.renameExercise(s.exI, name)
                            sheet = null
                        }
                        CoachTextField(swapDraft, { swapDraft = it.take(60) }, "e.g. Running", onIme = save)
                        VGap(8.dp)
                        BigButton("Swap it in", enabled = swapDraft.isNotBlank()) { save() }
                    }
                    else -> {
                        T("Skip it today?${if (rows.any { it.isLogged }) " Logged sets will be lost." else ""}", Theme.body(14f), Theme.muted)
                        VGap(8.dp)
                        BigButton("Remove exercise", danger = true) { sheet = null; app.removeExercise(s.exI) }
                    }
                }
                VGap(12.dp)
            }
        }
    }

    viewer?.let { MediaViewer(it) { viewer = null } }
}

/** [[i]] or [[i, partner]] in plan order — like the web's renderedIdx walk. */
private fun groupedExercises(exs: List<Plan.Exercise>): List<List<Int>> {
    val seen = HashSet<Int>()
    val out = ArrayList<List<Int>>()
    exs.forEachIndexed { i, ex ->
        if (i in seen) return@forEachIndexed
        val partner = if (ex.superset.isEmpty()) null else exs.indices.firstOrNull { it != i && exs[it].superset == ex.superset }
        if (partner != null && partner > i) { seen.add(i); seen.add(partner); out.add(listOf(i, partner)) }
        else { seen.add(i); out.add(listOf(i)) }
    }
    return out
}

private fun harderLabel(o: Gemini.IntensifyOption): String {
    fun w(ex: Plan.Exercise) = if (ex.suggestedWeight.isEmpty()) "" else " @ ${ex.suggestedWeight}"
    return when (o.kind) {
        "add" -> o.exercise?.let { "Add ${it.name} — ${it.sets}×${it.reps}${w(it)}" } ?: "Add an exercise"
        "extraSet" -> "One more set of ${o.target}"
        else -> o.exercise?.let { "Swap ${o.target} → ${it.name} — ${it.sets}×${it.reps}${w(it)}" } ?: "Swap ${o.target}"
    }
}

@Composable
private fun WCard(content: @Composable () -> Unit) {
    Column(Modifier.padding(top = 12.dp).fillMaxWidth().panel().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) { content() }
}

@Composable
private fun NumField(value: String, placeholder: String, decimal: Boolean = true, onChange: (String) -> Unit) {
    com.expdeath.coach.ui.SetField(value, placeholder, decimal, 15f, Modifier.width(76.dp), onChange)
}

@Composable
private fun SmallChip(title: String, on: Boolean = false, onClick: () -> Unit) {
    T(title, Theme.body(13f, if (on) FontWeight.SemiBold else FontWeight.Normal), if (on) Theme.bg else Theme.text,
        Modifier.clip(CircleShape).background(if (on) Theme.green else Theme.bgPill).clickable(onClick = onClick).padding(horizontal = 11.dp, vertical = 7.dp))
}

@Composable
private fun SheetItem(title: String, icon: String, color: Color = Theme.text, enabled: Boolean = true, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(vertical = 11.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(sf(icon), null, tint = if (enabled) color else Theme.dim, modifier = Modifier.size(22.dp))
        T(title, Theme.body(16f), if (enabled) color else Theme.dim)
    }
}

private fun loadBitmap(f: File, maxSide: Int): Bitmap? = try {
    val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(f.path, o)
    var sample = 1
    while (maxOf(o.outWidth, o.outHeight) / sample > maxSide) sample *= 2
    BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = sample })
} catch (_: Exception) { null }

@Composable
private fun MediaThumb(m: MediaStore.Item) {
    val bmp = remember(m.file.path, m.file.lastModified()) { if (m.isVideo) null else loadBitmap(m.file, 300) }
    Box(Modifier.size(width = 96.dp, height = 72.dp).clip(RoundedCornerShape(Theme.radiusSm)).background(Theme.bgPill), contentAlignment = Alignment.Center) {
        if (bmp != null) Image(bmp.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        T(if (m.isVideo) "▶" else "🔍", Theme.body(20f), Color.White)
    }
}

@Composable
private fun MediaViewer(m: MediaStore.Item, onClose: () -> Unit) {
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (m.isVideo) {
                AndroidView({ c ->
                    VideoView(c).apply {
                        setVideoPath(m.file.path)
                        setMediaController(MediaController(c).also { it.setAnchorView(this) })
                        setOnPreparedListener { it.isLooping = true; start() }
                    }
                }, Modifier.fillMaxSize().align(Alignment.Center))
            } else {
                val bmp = remember(m.file.path) { loadBitmap(m.file, 2048) }
                if (bmp != null) Image(bmp.asImageBitmap(), null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
            }
            T("✕", Theme.head(22f, FontWeight.Bold), Color.White, Modifier.align(Alignment.TopEnd).padding(top = 36.dp, end = 12.dp).clickable(onClick = onClose).padding(12.dp))
        }
    }
}

@Composable
private fun RestBar(timer: RestTimer, modifier: Modifier, onSkip: () -> Unit) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(timer) { while (true) { now = System.currentTimeMillis(); delay(250) } }
    val remaining = ceil((timer.endsAt - now) / 1000.0).toInt()
    val frac = (remaining / timer.total).coerceIn(0.0, 1.0).toFloat()
    val over = remaining <= 0
    Box(modifier.fillMaxWidth().height(64.dp).background(Theme.bgCard).semantics { contentDescription = "Rest timer" }) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(frac).background((if (over) Theme.green else Theme.amber).copy(alpha = 0.25f)))
        Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.border))
        Row(Modifier.fillMaxSize().padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val r = maxOf(remaining, 0)
            T(if (over) "GO" else fmt("%d:%02d", r / 60, r % 60), Theme.data(22f), if (over) Theme.green else Theme.text)
            T(if (over) "Next set · ${timer.exName}" else timer.exName, Theme.body(14f), Theme.muted, Modifier.weight(1f), maxLines = 1)
            TextButtonC("SKIP", Theme.muted, Theme.head(15f, FontWeight.SemiBold), onClick = onSkip)
        }
    }
}
