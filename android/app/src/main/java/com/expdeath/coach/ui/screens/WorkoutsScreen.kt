package com.expdeath.coach.ui.screens

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.expdeath.coach.ai.Gemini
import com.expdeath.coach.app.AppState
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.SavedWorkout
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.CIconButton
import com.expdeath.coach.ui.CapsText
import com.expdeath.coach.ui.Chip
import com.expdeath.coach.ui.CoachCard
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.CoachTextField
import com.expdeath.coach.ui.ErrorBox
import com.expdeath.coach.ui.Fill
import com.expdeath.coach.ui.Hairline
import com.expdeath.coach.ui.IconLabel
import com.expdeath.coach.ui.IconWell
import com.expdeath.coach.ui.OutlineButton
import com.expdeath.coach.ui.QLabel
import com.expdeath.coach.ui.ScreenHeader
import com.expdeath.coach.ui.SectionHead
import com.expdeath.coach.ui.SegGroup
import com.expdeath.coach.ui.StatusPill
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.TextButtonC
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.Title
import com.expdeath.coach.ui.ToggleRow
import com.expdeath.coach.ui.panel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.time.LocalDate

/** My workouts — ports Workouts.jsx: the saved-workout library (yours and
 *  your trainer's), the weekday schedule, daily add-ons, and the coach that
 *  builds them from a program, a photo of one, or a description. Everything
 *  is account state in Firestore, shared with the other apps. */
@Composable
fun WorkoutsScreen(app: AppState, openId: String?) {
    val opened = remember(openId) { openId?.let { Workouts.get(it) } }
    var mode by remember { mutableStateOf(if (opened != null) "edit" else "list") }
    var draft by remember { mutableStateOf(opened ?: SavedWorkout()) }
    var drafts by remember { mutableStateOf(listOf<SavedWorkout>()) }
    var coachMsg by remember { mutableStateOf("") }
    var confirmDel by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun back() = when (mode) {
        "list" -> app.screen = app.workoutsFrom
        "review" -> mode = "build"
        else -> mode = "list"
    }

    fun save() {
        val saved = Workouts.save(draft)
        LocalStore.logEvent("workout_saved", mapOf(
            "id" to JSONValue.Str(saved.id), "kind" to JSONValue.Str(saved.kind), "source" to JSONValue.Str(saved.source),
            "exercises" to JSONValue.Num(saved.exercises.size.toDouble()), "days" to JSONValue.Num(saved.days.size.toDouble()),
        ))
        mode = "list"
    }

    CoachScreen {
        Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            when (mode) {
                "edit" -> WorkoutEditor(draft, { draft = it }, ::save) { mode = "list" }
                "build" -> WorkoutBuilder(app.history, { mode = "list" }) { res ->
                    drafts = res.workouts
                    coachMsg = res.message
                    mode = "review"
                }
                "review" -> {
                    ScreenHeader("Review", onBack = ::back)
                    if (coachMsg.isNotEmpty()) Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.radius)).background(Theme.bgCard).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        IconWell("brain.head.profile", size = 32.dp)
                        T(coachMsg, Theme.body(14f), Theme.textBody)
                    }
                    drafts.forEachIndexed { i, w ->
                        CoachCard {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                CoachTextField(w.name, { v -> drafts = drafts.mapIndexed { j, d -> if (j == i) d.copy(name = v) else d } }, modifier = Modifier.weight(1f), style = Theme.body(16f, FontWeight.SemiBold))
                                CIconButton("xmark", "Remove") { drafts = drafts.filterIndexed { j, _ -> j != i } }
                            }
                            KindAndDays(w) { nw -> drafts = drafts.mapIndexed { j, d -> if (j == i) nw else d } }
                            ExerciseSummary(w.exercises)
                        }
                    }
                    BigButton(if (drafts.size > 1) "Save all ${drafts.size}" else "Save workout", enabled = drafts.isNotEmpty()) {
                        drafts.forEach { Workouts.save(it) }
                        LocalStore.logEvent("workouts_imported", mapOf("count" to JSONValue.Num(drafts.size.toDouble()), "source" to JSONValue.Str(drafts.firstOrNull()?.source ?: "")))
                        drafts = emptyList()
                        mode = "list"
                    }
                    T("You can change anything later — open a workout and edit it.", Theme.meta(12.5f), Theme.dim)
                }
                else -> {
                    val all = Workouts.list()
                    ScreenHeader("My workouts", onBack = ::back)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        BigButton("Build with coach", Modifier.weight(1f), icon = "brain.head.profile") { mode = "build" }
                        OutlineButton("New", Modifier.width(96.dp), "plus") { draft = SavedWorkout(exercises = listOf(SavedWorkout.Exercise())); mode = "edit" }
                    }
                    if (all.any { it.days.isNotEmpty() || it.isAddOn }) WeekPlan(all)
                    if (all.isEmpty()) CoachCard {
                        Title("No saved workouts yet", 22f)
                        T("Snap a photo of your trainer's program, paste it, or tell the coach what you want — it turns it into workouts you can schedule and start in one tap.", Theme.body(14f), Theme.muted)
                    }
                    val sessions = all.filter { !it.isAddOn }
                    val addOns = all.filter { it.isAddOn }
                    if (sessions.isNotEmpty()) SectionHead("Workouts")
                    for (w in sessions) LibraryCard(w, confirmDel == w.id, { draft = w; mode = "edit" }, { confirmDel = w.id }, { Workouts.delete(w.id); confirmDel = null }) {
                        scope.launch { app.startSavedWorkout(w.id) }
                    }
                    if (addOns.isNotEmpty()) SectionHead("Add-ons", "On their days", Theme.muted)
                    for (w in addOns) LibraryCard(w, confirmDel == w.id, { draft = w; mode = "edit" }, { confirmDel = w.id }, { Workouts.delete(w.id); confirmDel = null }, null)
                }
            }
        }
    }
}

@Composable
private fun LibraryCard(w: SavedWorkout, confirming: Boolean, onEdit: () -> Unit, onAskDelete: () -> Unit, onDelete: () -> Unit, onStart: (() -> Unit)?) {
    CoachCard {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Title(w.name, 22f)
                WorkoutBadges(w)
            }
            if (onStart != null) OutlineButton("Start", icon = "arrow.right", trailingIcon = true, onClick = onStart)
        }
        ExerciseSummary(w.exercises, 4)
        Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.clickable(onClick = onEdit)) { IconLabel("pencil", "Edit", Theme.muted, Theme.body(13.5f)) }
            if (confirming) TextButtonC("Tap again to delete", Theme.red, Theme.body(13.5f), onClick = onDelete)
            else Box(Modifier.clickable(onClick = onAskDelete)) { IconLabel("trash", "Delete", Theme.muted, Theme.body(13.5f)) }
        }
    }
}

/** Trainer · Kept exact / Coach adapts · Mon · Wed */
@Composable
fun WorkoutBadges(w: SavedWorkout) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        if (w.source == "trainer") StatusPill(if (w.trainer.isEmpty()) "Trainer" else "Trainer · ${w.trainer}", Theme.green, dot = false)
        if (!w.isAddOn) StatusPill(if (w.adapt) "Coach adapts" else "Kept exact", Theme.amberText, dot = false)
        val days = Workouts.daysLabel(w)
        CapsText(days.ifEmpty { "Not scheduled" }, if (days.isEmpty()) Theme.dim else Theme.textBody, 11f)
    }
}

/** Mon–Sun: what's scheduled each day (add-ons as a green dot). */
@Composable
private fun WeekPlan(all: List<SavedWorkout>) {
    val today = LocalDate.now().dayOfWeek.value % 7
    Row(Modifier.fillMaxWidth().panel().padding(8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for (d in Workouts.weekOrder) {
            val s = all.filter { !it.isAddOn && d in it.days }
            val a = all.filter { it.isAddOn && (it.days.isEmpty() || d in it.days) }
            Column(
                Modifier.weight(1f).clip(RoundedCornerShape(Theme.radiusSm)).background(if (d == today) Theme.amberBg else Color.Transparent).padding(vertical = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                CapsText(Workouts.weekdays[d], if (d == today) Theme.amberText else Theme.muted, 11f)
                for (w in s) T(w.name, Theme.body(11f, FontWeight.SemiBold), align = TextAlign.Center, maxLines = 2)
                if (a.isNotEmpty()) Box(Modifier.size(6.dp).clip(CircleShape).background(Theme.green))
                if (s.isEmpty() && a.isEmpty()) T("—", Theme.meta(12f), Theme.dim)
            }
        }
    }
}

/** Workout / daily add-on, and the weekdays it's on. */
@Composable
private fun KindAndDays(w: SavedWorkout, onChange: (SavedWorkout) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SegGroup(listOf("session" to "Workout", "addon" to "Daily add-on"), w.kind) { onChange(w.copy(kind = it)) }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (d in Workouts.weekOrder) {
                val on = d in w.days
                Box(
                    Modifier.weight(1f).clip(CircleShape).background(if (on) Theme.amber else Theme.bgPill)
                        .clickable { onChange(w.copy(days = if (on) w.days - d else w.days + d)) }.padding(vertical = 7.dp),
                    contentAlignment = Alignment.Center,
                ) { CapsText(Workouts.weekdays[d], if (on) Theme.onAmber else Theme.textBody, 11f) }
            }
        }
        T(
            if (w.isAddOn) (if (w.days.isEmpty()) "No days picked = added to every session." else "Added to your session on these days.")
            else (if (w.days.isEmpty()) "Not scheduled — start it from here or the check-in whenever you like." else "Ready to start on these days — Today shows it."),
            Theme.meta(12.5f), Theme.muted,
        )
    }
}

@Composable
private fun WorkoutEditor(draft: SavedWorkout, onChange: (SavedWorkout) -> Unit, onSave: () -> Unit, onCancel: () -> Unit) {
    fun setEx(i: Int, f: (SavedWorkout.Exercise) -> SavedWorkout.Exercise) = onChange(draft.copy(exercises = draft.exercises.mapIndexed { j, e -> if (j == i) f(e) else e }))
    fun move(i: Int, dir: Int) {
        val j = i + dir
        if (j !in draft.exercises.indices) return
        val l = draft.exercises.toMutableList()
        val tmp = l[i]; l[i] = l[j]; l[j] = tmp
        onChange(draft.copy(exercises = l))
    }
    ScreenHeader(if (draft.id.isEmpty()) "New workout" else "Edit workout", onBack = onCancel)
    CoachCard {
        QLabel("Name", top = 0.dp)
        CoachTextField(draft.name, { onChange(draft.copy(name = it)) }, "e.g. Upper A, Leg day, Daily core", capitalization = KeyboardCapitalization.Words)
        Box(Modifier.padding(top = 4.dp)) { KindAndDays(draft, onChange) }
        QLabel("Who wrote it?")
        SegGroup(listOf("me" to "Me", "trainer" to "My trainer"), draft.source) { onChange(draft.copy(source = it)) }
        if (draft.source == "trainer") CoachTextField(draft.trainer, { onChange(draft.copy(trainer = it)) }, "Trainer's name (optional)", capitalization = KeyboardCapitalization.Words)
        if (!draft.isAddOn) Box(Modifier.padding(top = 10.dp)) {
            ToggleRow(
                "Let the coach adapt it",
                if (draft.adapt) "On a tired or sore day the coach may ease or trim it, and tells you what changed."
                else "Off: kept exactly as written — the coach only fills in weights and flags recovery.",
                draft.adapt,
            ) { onChange(draft.copy(adapt = it)) }
        }
        QLabel("Notes")
        CoachTextField(draft.notes, { onChange(draft.copy(notes = it)) }, "Tempo, warm-up, the trainer's instructions…", singleLine = false, minLines = 2, maxLines = 5)
    }
    CoachCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CapsText("Exercises"); Fill(); CapsText("Weight empty = from history", Theme.dim, 10.5f)
        }
        draft.exercises.forEachIndexed { i, e ->
            if (i > 0) Hairline(Modifier.padding(vertical = 4.dp))
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    CapsText("${i + 1}", Theme.amberText, modifier = Modifier.width(20.dp))
                    CoachTextField(e.name, { v -> setEx(i) { it.copy(name = v) } }, "Exercise", Modifier.weight(1f), capitalization = KeyboardCapitalization.Words)
                    CIconButton("chevron.up", "Move up", enabled = i > 0, modifier = Modifier.width(32.dp)) { move(i, -1) }
                    CIconButton("chevron.down", "Move down", enabled = i < draft.exercises.size - 1, modifier = Modifier.width(32.dp)) { move(i, 1) }
                    CIconButton("xmark", "Remove exercise", modifier = Modifier.width(32.dp)) { onChange(draft.copy(exercises = draft.exercises.filterIndexed { j, _ -> j != i })) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Small("Sets", e.sets.toString(), "3", Modifier.weight(1f), KeyboardType.Number) { v -> setEx(i) { it.copy(sets = v.filter { c -> c.isDigit() }.take(2).toIntOrNull() ?: 3) } }
                    Small("Reps", e.reps, "8-10", Modifier.weight(1f)) { v -> setEx(i) { it.copy(reps = v) } }
                    Small("Weight", e.weight, "auto", Modifier.weight(1f)) { v -> setEx(i) { it.copy(weight = v) } }
                    Small("Rest", e.rest, "90s", Modifier.weight(1f)) { v -> setEx(i) { it.copy(rest = v) } }
                }
                CoachTextField(e.notes, { v -> setEx(i) { it.copy(notes = v) } }, "Cue or note (optional)", style = Theme.body(14f), padH = 10.dp, padV = 8.dp, bordered = false)
            }
        }
        OutlineButton("Add exercise", Modifier.fillMaxWidth().padding(top = 6.dp), "plus") { onChange(draft.copy(exercises = draft.exercises + SavedWorkout.Exercise())) }
    }
    BigButton("Save workout", enabled = draft.name.isNotBlank() && draft.exercises.any { it.name.isNotBlank() }, onClick = onSave)
}

@Composable
private fun Small(label: String, value: String, placeholder: String, modifier: Modifier, keyboard: KeyboardType = KeyboardType.Text, onChange: (String) -> Unit) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        CapsText(label, Theme.dim, 10.5f)
        CoachTextField(value, onChange, placeholder, keyboard = keyboard, capitalization = KeyboardCapitalization.None, style = Theme.body(14f), padH = 10.dp, padV = 8.dp, bordered = false)
    }
}

/** ≤1600px JPEG — only sent to Gemini to read, never stored. */
private fun jpeg(bmp: Bitmap): ByteArray {
    val scale = minOf(1f, 1600f / maxOf(bmp.width, bmp.height))
    val b = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true) else bmp
    return ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
}

/** Paste a program, add a photo of it, or describe what you want. */
@Composable
private fun WorkoutBuilder(history: List<Session>, onBack: () -> Unit, onBuilt: (Gemini.BuiltWorkouts) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var source by remember { mutableStateOf("trainer") }
    var trainer by remember { mutableStateOf("") }
    var text by remember { mutableStateOf("") }
    var photo by remember { mutableStateOf<Bitmap?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        if (uri != null) scope.launch {
            photo = withContext(Dispatchers.IO) {
                try { ImageDecoder.decodeBitmap(ImageDecoder.createSource(ctx.contentResolver, uri)) { d, _, _ -> d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE } } catch (_: Exception) { null }
            }
        }
    }
    ScreenHeader("Build with coach", onBack = onBack)
    CoachCard {
        SegGroup(listOf("trainer" to "From my trainer", "me" to "Describe it"), source) { source = it }
        T(if (source == "trainer") "Paste the program your trainer sent, or add a photo of it. The coach copies it exactly — every exercise, set and rep — and splits a multi-day plan into separate workouts."
          else "Tell the coach what you want, e.g. “15 minutes of core every day” or “upper body with dumbbells, 45 min, Mon and Thu”. It builds it around your goals, equipment and history.",
            Theme.body(13.5f), Theme.muted)
        if (source == "trainer") CoachTextField(trainer, { trainer = it }, "Trainer's name (optional)", capitalization = KeyboardCapitalization.Words)
        CoachTextField(text, { text = it }, if (source == "trainer") "Day A — Mon\nBench press 4x6 @ 70kg, rest 2 min\n…" else "What do you want to do, and when?", singleLine = false, minLines = 5, maxLines = 12)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlineButton(if (photo == null) "Add a photo" else "Change photo", icon = "photo") {
                picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }
            photo?.let { p ->
                Image(p.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.size(44.dp).clip(RoundedCornerShape(Theme.radiusSm)))
                TextButtonC("Remove", Theme.muted, Theme.body(13.5f)) { photo = null }
            }
        }
        T("The photo is only sent to the coach to read — it isn't stored.", Theme.meta(12f), Theme.dim)
        if (error.isNotEmpty()) ErrorBox(error)
        BigButton(if (busy) "The coach is reading it…" else "Build my workouts", Modifier.alpha(if (busy) 0.6f else 1f), enabled = !busy && (text.isNotBlank() || photo != null)) {
            scope.launch {
                busy = true; error = ""
                try {
                    val img = photo?.let { withContext(Dispatchers.Default) { jpeg(it) } }
                    val res = Gemini.buildWorkouts(text, img, source, history)
                    onBuilt(res.copy(workouts = res.workouts.map { it.copy(source = source, trainer = if (source == "trainer") trainer else "") }))
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    error = e.message?.ifEmpty { null } ?: "The coach couldn't build that — try again."
                }
                busy = false
            }
        }
    }
}
