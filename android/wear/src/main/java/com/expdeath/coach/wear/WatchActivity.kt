package com.expdeath.coach.wear

import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.itemsIndexed
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import com.expdeath.coach.watchlink.WExercise
import com.expdeath.coach.watchlink.WRest
import com.expdeath.coach.watchlink.WSet
import com.expdeath.coach.watchlink.WatchCommand
import com.expdeath.coach.watchlink.WatchState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.roundToLong

/** COACH on the wrist: only what you'd otherwise reach for the phone for
 *  between sets — what's next, log it, rest, rate it, finish. Planning,
 *  check-ins, history and the AI all stay on the phone. */
class WatchActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PhoneLink.init(this)
        debugSeed(intent)
        setContent { CoachWatch() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        debugSeed(intent)
    }

    override fun onResume() {
        super.onResume()
        lifecycleScope.launch { PhoneLink.refresh() }
    }

    /** Debug builds: a canned workout, no phone needed (emulator screenshots).
     *  adb shell am start -n com.expdeath.coach/com.expdeath.coach.wear.WatchActivity --es COACH_DEBUG_SEED workout|rest|idle */
    private fun debugSeed(intent: Intent?) {
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        val seed = intent?.getStringExtra("COACH_DEBUG_SEED") ?: return
        PhoneLink.debugShow(DebugStates.state(seed))
    }
}

// ── Look ─────────────────────────────────────────────────────────

private object W {
    val bg = Color(0xFF000000)
    val card = Color(0xFF131B2E)
    val pill = Color(0xFF1A1F2B)
    val text = Color(0xFFF8FAFC)
    val muted = Color(0xFF8391A7)
    val dim = Color(0xFF4E5869)
    val amber = Color(0xFFF59E0B)
    val green = Color(0xFF56E5A9)
    val red = Color(0xFFF26D5B)
    val data = FontFamily(Font(R.font.barlow_condensed_bold, FontWeight.Bold), Font(R.font.barlow_condensed_semibold, FontWeight.SemiBold))
    val head = FontFamily(Font(R.font.space_grotesk_bold, FontWeight.Bold), Font(R.font.space_grotesk_medium, FontWeight.Medium))
}

private fun num(size: Int, color: Color = W.text) = TextStyle(fontFamily = W.data, fontWeight = FontWeight.Bold, fontSize = size.sp, color = color)
private fun head(size: Int, color: Color = W.text, weight: FontWeight = FontWeight.Bold) = TextStyle(fontFamily = W.head, fontWeight = weight, fontSize = size.sp, color = color)

private enum class Page { Set, List, Finish }

/** A set just logged here — its effort can be tapped in during the rest. */
private data class Logged(val ex: Int, val set: Int, val name: String)

@Composable
private fun CoachWatch() {
    val s by PhoneLink.state.collectAsState()
    val hr by WorkoutService.heartRate.collectAsState()
    val reachable by PhoneLink.phoneReachable.collectAsState()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(250) } }

    var page by remember { mutableStateOf(Page.Set) }
    var picked by remember { mutableStateOf<Int?>(null) } // exercise chosen from the list; null = follow the plan
    var logged by remember { mutableStateOf<Logged?>(null) }

    // Workout running → heart rate + rest buzz in the foreground service (asks for sensors once)
    val ctx = androidx.compose.ui.platform.LocalContext.current
    var asked by remember { mutableStateOf(false) }
    val perms = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { WorkoutService.start(ctx) }
    LaunchedEffect(s.active) {
        if (!s.active) { page = Page.Set; picked = null; logged = null; return@LaunchedEffect }
        if (WorkoutService.running) return@LaunchedEffect
        val wanted = buildList {
            add(WorkoutService.sensorPermission); add(Manifest.permission.ACTIVITY_RECOGNITION)
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }.filter { androidx.core.content.ContextCompat.checkSelfPermission(ctx, it) != android.content.pm.PackageManager.PERMISSION_GRANTED }
        if (wanted.isNotEmpty() && !asked) { asked = true; perms.launch(wanted.toTypedArray()) } else WorkoutService.start(ctx)
    }

    MaterialTheme {
        Box(Modifier.fillMaxSize().background(W.bg), contentAlignment = Alignment.Center) {
            val rest = s.rest?.takeIf { now < it.endsAt + 4_000 }
            when {
                !s.active && s.finished -> DoneScreen(s)
                !s.active -> IdleScreen(reachable)
                page == Page.List -> ListScreen(s, hr, now, onPick = { picked = it; page = Page.Set }, onFinish = { page = Page.Finish }, onBack = { page = Page.Set })
                page == Page.Finish -> FinishScreen(onSave = { rpe -> PhoneLink.send(WatchCommand.FINISH, rpe = rpe) }, onBack = { page = Page.List })
                rest != null -> RestScreen(s, rest, now, logged)
                else -> SetScreen(s, hr, now, picked,
                    onList = { page = Page.List },
                    onLogged = { l, finishedExercise -> logged = l; if (finishedExercise) picked = null },
                    onNext = { picked = null })
            }
        }
    }
}

// ── Top line: heart rate · elapsed · sets ────────────────────────

@Composable
private fun TopLine(s: WatchState, hr: Int?, now: Long) {
    val mins = if (s.startedAt > 0) ((now - s.startedAt) / 60_000).coerceAtLeast(0) else 0
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (hr != null) Text("♥ $hr", style = num(15, W.red))
        Text(if (mins >= 60) "${mins / 60}h${(mins % 60).toString().padStart(2, '0')}" else "${mins}m", style = num(15, W.muted))
        Text("${s.doneSets}/${s.totalSets}", style = num(15, if (s.doneSets == s.totalSets) W.green else W.muted))
    }
}

// ── Set ──────────────────────────────────────────────────────────

@Composable
private fun SetScreen(s: WatchState, hr: Int?, now: Long, picked: Int?, onList: () -> Unit, onLogged: (Logged, Boolean) -> Unit, onNext: () -> Unit) {
    val focus = s.next()
    val exI = picked?.takeIf { it in s.exercises.indices } ?: focus?.ex
    if (exI == null) {
        // every set done
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(18.dp)) {
            TopLine(s, hr, now)
            Text("All sets done", style = head(18, W.green), textAlign = TextAlign.Center)
            Pill("Finish workout", W.green, W.bg, Modifier.fillMaxWidth(0.8f)) { onList() }
        }
        return
    }
    val ex = s.exercises[exI]
    val setI = s.nextSet(exI)
    val haptic = LocalHapticFeedback.current

    Column(Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        TopLine(s, hr, now)
        Text(
            ex.name, style = head(16), textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 2.dp).fillMaxWidth(0.86f).clickable(onClick = onList).semantics { contentDescription = "${ex.name}. Tap for all exercises" },
        )
        if (setI == null) {
            Text("${ex.sets.size}/${ex.sets.size} sets ✓", style = num(16, W.green), modifier = Modifier.padding(top = 4.dp))
            Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Pill("+ Set", W.pill, W.text) { PhoneLink.send(WatchCommand.ADD_SET, ex = exI, name = ex.name) }
                Pill("Next", W.green, W.bg) { onNext() }
            }
            return@Column
        }
        val partner = if (ex.superset.isNotEmpty()) " · ${ex.superset}${setI + 1}" else ""
        Text("SET ${setI + 1} OF ${ex.sets.size}$partner", style = head(12, W.amber, FontWeight.Medium))

        val pre = s.prefill(exI, setI)
        // what's on the dials, reset whenever the set changes
        val key = "${s.id}/$exI/$setI"
        var a by remember(key) { mutableStateOf(if (ex.mode == "cardio") pre.t else pre.w) }
        var b by remember(key) { mutableStateOf(if (ex.mode == "cardio") pre.d else pre.r) }
        var sel by remember(key) { mutableIntStateOf(0) }

        if (ex.mode != "check") {
            val cardio = ex.mode == "cardio"
            // minutes in 1s, km in 0.1s · kg by weightStep, reps in 1s
            fun bump(dir: Int) {
                if (sel == 0) a = step(a, dir * (if (cardio) 1.0 else weightStep(a)), if (cardio) 0 else 1)
                else b = step(b, dir * (if (cardio) 0.1 else 1.0), if (cardio) 1 else 0)
                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            }
            val focusRequester = remember { FocusRequester() }
            var acc by remember { mutableFloatStateOf(0f) }
            LaunchedEffect(key) { try { focusRequester.requestFocus() } catch (_: Exception) {} }
            Row(
                Modifier.padding(top = 6.dp)
                    .onRotaryScrollEvent { e ->
                        acc += e.verticalScrollPixels
                        while (abs(acc) >= 40f) { bump(if (acc > 0) 1 else -1); acc -= 40f * (if (acc > 0) 1 else -1) }
                        true
                    }
                    .focusRequester(focusRequester).focusable(),
                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
            ) {
                // − and + change whichever dial is selected; so does the crown / bezel
                Round("−", "Less") { bump(-1) }
                Dial(a.ifEmpty { "–" }, if (cardio) "min" else "kg", sel == 0) { sel = 0 }
                Dial(b.ifEmpty { "–" }, if (cardio) "km" else "reps", sel == 1) { sel = 1 }
                Round("+", "More") { bump(1) }
            }
        } else {
            Text(ex.reps, style = head(14, W.muted, FontWeight.Medium), modifier = Modifier.padding(top = 6.dp), textAlign = TextAlign.Center, maxLines = 2)
        }
        if (ex.last.isNotEmpty() && ex.mode != "check") {
            Text("Last ${ex.last}", style = head(11, W.muted, FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp).fillMaxWidth(0.8f), textAlign = TextAlign.Center)
        }
        Pill("DONE", W.green, W.bg, Modifier.padding(top = 6.dp).fillMaxWidth(0.62f).height(42.dp)) {
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            when (ex.mode) {
                "cardio" -> PhoneLink.send(WatchCommand.LOG_SET, ex = exI, name = ex.name, set = setI, t = a, d = b)
                "check" -> PhoneLink.send(WatchCommand.LOG_SET, ex = exI, name = ex.name, set = setI)
                else -> PhoneLink.send(WatchCommand.LOG_SET, ex = exI, name = ex.name, set = setI, w = a, r = b)
            }
            onLogged(Logged(exI, setI, ex.name), setI == ex.sets.lastIndex || ex.sets.withIndex().all { (j, x) -> x.done || j == setI })
        }
    }
}

/** Plates move in 2.5s on a bar, dumbbells in 1s up to 20. */
private fun weightStep(v: String) = if ((v.toDoubleOrNull() ?: 0.0) < 20) 1.0 else 2.5

private fun step(v: String, by: Double, decimals: Int): String {
    val n = ((v.toDoubleOrNull() ?: 0.0) + by).coerceAtLeast(0.0)
    val rounded = if (decimals == 0) n.roundToLong().toDouble() else (n * 10).roundToLong() / 10.0
    return if (rounded == 0.0 && by < 0) "" else fmtNum(rounded)
}

private fun fmtNum(n: Double) = if (n == n.roundToLong().toDouble()) n.roundToLong().toString() else n.toString()

@Composable
private fun Dial(value: String, unit: String, selected: Boolean, onClick: () -> Unit) {
    Column(
        Modifier.width(58.dp).clip(RoundedCornerShape(12.dp)).background(W.card)
            .border(2.dp, if (selected) W.amber else Color.Transparent, RoundedCornerShape(12.dp))
            .clickable(onClick = onClick).padding(vertical = 4.dp)
            .semantics { contentDescription = "$value $unit" + if (selected) ", selected — turn the crown to change" else "" },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value, style = num(26, if (selected) W.text else W.muted), maxLines = 1)
        Text(unit, style = head(10, W.muted, FontWeight.Medium))
    }
}

@Composable
private fun Round(label: String, desc: String, onClick: () -> Unit) {
    Box(Modifier.size(30.dp).clip(CircleShape).background(W.pill).clickable(onClick = onClick).semantics { contentDescription = desc }, contentAlignment = Alignment.Center) {
        Text(label, style = num(22))
    }
}

@Composable
private fun Pill(label: String, bg: Color, fg: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(modifier.clip(RoundedCornerShape(50)).background(bg).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 9.dp), contentAlignment = Alignment.Center) {
        Text(label, style = head(14, fg), maxLines = 1)
    }
}

// ── Rest ─────────────────────────────────────────────────────────

@Composable
private fun RestScreen(s: WatchState, rest: WRest, now: Long, logged: Logged?) {
    val left = ceil((rest.endsAt - now) / 1000.0).toInt()
    val over = left <= 0
    val frac = if (rest.total > 0) (left.toFloat() / rest.total).coerceIn(0f, 1f) else 0f
    val next = s.next()?.let { f -> s.exercises.getOrNull(f.ex)?.let { "${it.name} · set ${f.set + 1}" } }
    // effort for the set just logged here (the phone shows the same tag)
    val ratable = logged?.let { l -> s.exercises.getOrNull(l.ex)?.takeIf { it.name == l.name && it.mode != "check" }?.sets?.getOrNull(l.set) }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize().padding(4.dp)) {
            val stroke = 6.dp.toPx()
            val d = size.minDimension - stroke
            val tl = Offset((size.width - d) / 2, (size.height - d) / 2)
            drawArc(W.pill, 0f, 360f, false, tl, Size(d, d), style = Stroke(stroke))
            drawArc(if (over) W.green else W.amber, -90f, 360f * frac, false, tl, Size(d, d), style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(22.dp)) {
            Text(if (over) "GO" else "REST", style = head(12, if (over) W.green else W.muted, FontWeight.Medium))
            val l = left.coerceAtLeast(0)
            Text(if (over) "GO" else "${l / 60}:${(l % 60).toString().padStart(2, '0')}", style = num(44, if (over) W.green else W.text),
                modifier = Modifier.semantics { contentDescription = if (over) "Rest over" else "$l seconds of rest left" })
            if (next != null) Text("Next: $next", style = head(11, W.muted, FontWeight.Medium), maxLines = 2, textAlign = TextAlign.Center, overflow = TextOverflow.Ellipsis)
            if (ratable != null && logged != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for ((e, c) in listOf("easy" to W.green, "good" to W.amber, "grind" to W.red)) {
                        val on = ratable.e == e
                        Text(e, style = head(11, if (on) W.bg else c, FontWeight.Medium),
                            modifier = Modifier.clip(RoundedCornerShape(50)).background(if (on) c else W.pill)
                                .clickable { PhoneLink.send(WatchCommand.EFFORT, ex = logged.ex, name = logged.name, set = logged.set, effort = if (on) "" else e) }
                                .padding(horizontal = 8.dp, vertical = 5.dp))
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (!over) Pill("+15s", W.pill, W.text) { PhoneLink.send(WatchCommand.REST_ADD, sec = 15) }
                Pill(if (over) "Next set" else "Skip", if (over) W.green else W.pill, if (over) W.bg else W.text) { PhoneLink.send(WatchCommand.REST_SKIP) }
            }
        }
    }
}

// ── All exercises + finish ───────────────────────────────────────

@Composable
private fun ListScreen(s: WatchState, hr: Int?, now: Long, onPick: (Int) -> Unit, onFinish: () -> Unit, onBack: () -> Unit) {
    ScalingLazyColumn(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        item { TopLine(s, hr, now) }
        item { Text(s.title.ifEmpty { s.type }.uppercase(), style = head(13, W.amber), maxLines = 1) }
        itemsIndexed(s.exercises) { i, ex -> ExerciseRow(ex) { onPick(i) } }
        item { Pill("Finish workout", W.amber, W.bg, Modifier.padding(top = 6.dp).fillMaxWidth(0.8f), onFinish) }
        item { Pill("Back", W.pill, W.text, Modifier.fillMaxWidth(0.6f), onBack) }
    }
}

@Composable
private fun ExerciseRow(ex: WExercise, onClick: () -> Unit) {
    val done = ex.sets.isNotEmpty() && ex.doneSets == ex.sets.size
    Row(
        Modifier.fillMaxWidth(0.9f).clip(RoundedCornerShape(14.dp)).background(W.card).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(ex.name, style = head(13, if (done) W.muted else W.text, FontWeight.Medium), maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Text(if (done) "✓" else "${ex.doneSets}/${ex.sets.size}", style = num(16, if (done) W.green else W.muted))
    }
}

@Composable
private fun FinishScreen(onSave: (Int) -> Unit, onBack: () -> Unit) {
    var rpe by remember { mutableIntStateOf(7) }
    val focusRequester = remember { FocusRequester() }
    var acc by remember { mutableFloatStateOf(0f) }
    val haptic = LocalHapticFeedback.current
    LaunchedEffect(Unit) { try { focusRequester.requestFocus() } catch (_: Exception) {} }
    fun bump(d: Int) { rpe = (rpe + d).coerceIn(1, 10); haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
    Column(
        Modifier.fillMaxSize().padding(16.dp)
            .onRotaryScrollEvent { e ->
                acc += e.verticalScrollPixels
                while (abs(acc) >= 60f) { bump(if (acc > 0) 1 else -1); acc -= 60f * (if (acc > 0) 1 else -1) }
                true
            }.focusRequester(focusRequester).focusable(),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        Text("HOW HARD?", style = head(12, W.muted, FontWeight.Medium))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Round("−", "Easier") { bump(-1) }
            Text("$rpe", style = num(48, W.amber), modifier = Modifier.semantics { contentDescription = "Session effort $rpe out of 10" })
            Round("+", "Harder") { bump(1) }
        }
        Text(rpeLabel(rpe), style = head(11, W.muted, FontWeight.Medium))
        Pill("Save workout", W.green, W.bg, Modifier.fillMaxWidth(0.75f)) { onSave(rpe) }
        Pill("Back", W.pill, W.text, onClick = onBack)
    }
}

private fun rpeLabel(r: Int) = when {
    r <= 3 -> "Easy"; r <= 5 -> "Moderate"; r <= 7 -> "Hard"; r <= 9 -> "Very hard"; else -> "All out"
}

// ── No workout / just finished ───────────────────────────────────

@Composable
private fun IdleScreen(reachable: Boolean?) {
    val scope = rememberCoroutineScope()
    var msg by remember { mutableStateOf<String?>(null) }
    Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("COACH", style = head(20, W.amber))
        Text(
            if (reachable == false) "Phone not connected. Start your workout in COACH on your phone — it shows up here."
            else "Start today's workout on your phone. Sets, rest and finish show up here.",
            style = head(13, W.muted, FontWeight.Medium), textAlign = TextAlign.Center,
        )
        Pill("Open on phone", W.pill, W.text) {
            scope.launch { msg = if (PhoneLink.openOnPhone()) "Check your phone" else "Couldn't reach your phone" }
        }
        msg?.let { Text(it, style = head(11, W.muted, FontWeight.Medium)) }
    }
}

@Composable
private fun DoneScreen(s: WatchState) {
    Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("✓", style = num(40, W.green))
        Text("Workout saved", style = head(16))
        Text(s.title.ifEmpty { s.type }, style = head(12, W.muted, FontWeight.Medium), textAlign = TextAlign.Center, maxLines = 2)
        Text("The details are on your phone.", style = head(11, W.dim, FontWeight.Medium), textAlign = TextAlign.Center)
    }
}

// ── Debug states (debug builds only) ─────────────────────────────

internal object DebugStates {
    fun state(kind: String): WatchState {
        val now = System.currentTimeMillis()
        val ex = listOf(
            WExercise("Bench Press", reps = "6-8", restSec = 120, target = "62.5", last = "60kg×8, 60kg×8, 60kg×7",
                sets = listOf(WSet("60", "8", done = true, e = "good", pw = "62.5", pr = "8"), WSet(pw = "62.5", pr = "8"), WSet(pw = "62.5", pr = "7"))),
            WExercise("Incline Dumbbell Press", reps = "8-10", restSec = 90, target = "22", superset = "", sets = List(3) { WSet(pw = "22", pr = "10") }),
            WExercise("Cable Fly", reps = "12-15", restSec = 60, sets = List(3) { WSet() }),
            WExercise("Plank", mode = "check", reps = "3 × 45s", restSec = 45, sets = List(2) { WSet() }),
        )
        return when (kind) {
            "idle" -> WatchState(sentAt = now)
            "done" -> WatchState(finished = true, title = "Push — strength", sentAt = now)
            "rest" -> WatchState(true, "dbg", "Push", "Push — strength", now - 23 * 60_000, ex, WRest(now + 74_000, 120, "Bench Press"), sentAt = now)
            else -> WatchState(true, "dbg", "Push", "Push — strength", now - 23 * 60_000, ex, sentAt = now)
        }
    }
}
