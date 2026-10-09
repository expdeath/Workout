package com.expdeath.coach.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.Screen
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.models.parseInt
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.Chip
import com.expdeath.coach.ui.CoachCard
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.CoachTextField
import com.expdeath.coach.ui.ErrorBox
import com.expdeath.coach.ui.Fill
import com.expdeath.coach.ui.QLabel
import com.expdeath.coach.ui.ScreenHeader
import com.expdeath.coach.ui.SegGroup
import com.expdeath.coach.ui.SetField
import com.expdeath.coach.ui.StepSlider
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.TextButtonC
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.VGap
import com.expdeath.coach.ui.IconLabel
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

private val pastTypes = listOf("Push", "Pull", "Legs", "Full Body", "Core", "Cardio", "Stretch & Mobility")

private data class DraftExercise(val name: String = "", val sets: List<SetLog> = List(3) { SetLog() })

/** Ports AddPast.jsx — log a workout after the fact. No check-in, no AI:
 *  pick the day and type, type in what you did. Saved as a finished
 *  session on that date. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddPastScreen(app: AppState) {
    var date by remember { mutableStateOf(Helpers.daysAgoStr(1)) }
    var sessionType by remember { mutableStateOf("Full Body") }
    var exercises by remember { mutableStateOf(listOf(DraftExercise())) }
    var durationMin by remember { mutableStateOf("") }
    var rpe by remember { mutableIntStateOf(7) }
    var feedback by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var nameFocus by remember { mutableStateOf<Int?>(null) }
    var picking by remember { mutableStateOf(false) }

    fun setEx(i: Int, f: (DraftExercise) -> DraftExercise) { exercises = exercises.mapIndexed { j, e -> if (j == i) f(e) else e } }
    fun setSet(i: Int, s: Int, f: (SetLog) -> SetLog) = setEx(i) { e -> e.copy(sets = e.sets.mapIndexed { k, x -> if (k == s) f(x) else x }) }

    /** Names logged before, most recent first, filtered by what's typed — so
     *  names match and progressions line up (the web's <datalist>). */
    fun suggestions(typed: String): List<String> {
        val seen = HashSet<String>()
        val names = ArrayList<String>()
        for (s in app.history.asReversed()) for (ex in s.plan.exercises) {
            val n = ex.name.trim()
            if (n.isNotEmpty() && seen.add(n.lowercase())) names.add(n)
        }
        val q = typed.trim().lowercase()
        return names.filter { q.isEmpty() || (it.lowercase().contains(q) && it.lowercase() != q) }.take(8)
    }

    /** Most recent session of this type up to the chosen day. */
    val lastOfType: Session? = app.history.asReversed().firstOrNull { it.plan.sessionType == sessionType && it.date <= date && it.plan.exercises.isNotEmpty() }

    fun save() {
        if (date > Helpers.todayStr()) { error = "Pick a day on or before today."; return }
        val plan = ArrayList<Plan.Exercise>()
        val log = ArrayList<List<SetLog>>()
        for (ex in exercises) {
            val name = ex.name.trim().take(60)
            if (name.isEmpty()) continue
            val mode = Stats.logMode(name, sessionType)
            // keep only the fields this kind of exercise logs, and only sets that happened
            val sets = ex.sets.mapNotNull { s ->
                when (mode) {
                    "cardio" -> if (s.time.isEmpty() && s.dist.isEmpty()) null else SetLog(done = true, time = s.time, dist = s.dist)
                    "check" -> if (s.done) SetLog(done = true) else null
                    else -> if (s.weight.isEmpty() && s.reps.isEmpty()) null else SetLog(weight = s.weight, reps = s.reps, done = true)
                }
            }
            if (sets.isEmpty()) continue
            val reps = sets.mapNotNull { parseInt(it.reps) }.filter { it > 0 }
            val repsText = if (reps.isEmpty()) "" else if (reps.min() == reps.max()) "${reps[0]}" else "${reps.min()}-${reps.max()}"
            plan.add(Plan.Exercise(name = name, sets = sets.size, reps = repsText))
            log.add(sets)
        }
        if (plan.isEmpty()) { error = "Add at least one exercise with a logged set."; return }
        val minutes = (parseDouble(durationMin) ?: 0.0).rounded().toInt()
        app.addPastSession(date, sessionType, plan, log, if (minutes > 0) minutes else null, rpe, feedback.trim())
    }

    CoachScreen {
        Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(16.dp)) {
            ScreenHeader("Past workout", onBack = { app.screen = Screen.History })
            QLabel("Day", Helpers.fmtDate(date))
            SegGroup(listOf("1" to "Yesterday", "2" to "2 days ago", "3" to "3 days ago"), listOf("1", "2", "3").firstOrNull { Helpers.daysAgoStr(it.toInt()) == date } ?: "") {
                date = Helpers.daysAgoStr(it.toIntOrNull() ?: 1)
            }
            TextButtonC("Other day…", Theme.muted, Theme.body(15f), modifier = Modifier.padding(top = 8.dp)) { picking = true }

            QLabel("Type")
            SegGroup(pastTypes.map { it to it }, sessionType, 3) { sessionType = it }

            Row(verticalAlignment = Alignment.Bottom) {
                Box(Modifier.weight(1f)) { QLabel("Exercises") }
                if (lastOfType != null) {
                    TextButtonC("Copy last $sessionType", Theme.green, Theme.body(13.5f, FontWeight.Medium), modifier = Modifier.padding(bottom = 4.dp)) {
                        exercises = lastOfType.plan.exercises.mapIndexed { i, ex ->
                            val sets = (lastOfType.log.getOrNull(i) ?: emptyList()).filter { it.isLogged }
                            DraftExercise(ex.name, sets.ifEmpty { listOf(SetLog()) })
                        }
                        error = ""
                    }
                }
            }

            exercises.forEachIndexed { exI, ex ->
                val mode = Stats.logMode(ex.name, sessionType)
                CoachCard(Modifier.padding(bottom = 10.dp)) {
                    CoachTextField(ex.name, { v -> setEx(exI) { it.copy(name = v) } }, "Exercise", Modifier.onFocusChanged { if (it.isFocused) nameFocus = exI })
                    if (nameFocus == exI) {
                        val matches = suggestions(ex.name)
                        if (matches.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            for (n in matches) Chip(n) { setEx(exI) { it.copy(name = n) }; nameFocus = null }
                        }
                    }
                    ex.sets.forEachIndexed { setI, s ->
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            T("${setI + 1}", Theme.meta(13f), Theme.muted, Modifier.width(20.dp))
                            when (mode) {
                                "check" -> Box(
                                    Modifier.size(34.dp).clip(RoundedCornerShape(Theme.radiusSm)).background(if (s.done) Theme.green else Theme.bgPill)
                                        .clickable { setSet(exI, setI) { it.copy(done = !it.done) } }.semantics { contentDescription = if (s.done) "Mark not done" else "Mark done" },
                                    contentAlignment = Alignment.Center,
                                ) { T(if (s.done) "✓" else " ", Theme.meta(14f, FontWeight.Medium), Theme.bg) }
                                "cardio" -> {
                                    SetField(s.time, "min") { v -> setSet(exI, setI) { it.copy(time = Helpers.cleanTime(v)) } }
                                    T("min", Theme.meta(13f), Theme.muted)
                                    SetField(s.dist, "km") { v -> setSet(exI, setI) { it.copy(dist = Helpers.cleanDist(v)) } }
                                    T("km", Theme.meta(13f), Theme.muted)
                                }
                                else -> {
                                    SetField(s.weight, "kg") { v -> setSet(exI, setI) { it.copy(weight = Helpers.cleanWeight(v)) } }
                                    T("×", Theme.meta(13f), Theme.muted)
                                    SetField(s.reps, "reps", decimal = false) { v -> setSet(exI, setI) { it.copy(reps = Helpers.cleanReps(v)) } }
                                }
                            }
                        }
                    }
                    Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        TextButtonC("Add set", Theme.green, Theme.body(13.5f, FontWeight.Medium)) { setEx(exI) { it.copy(sets = it.sets + SetLog()) } }
                        if (ex.sets.size > 1) TextButtonC("Remove set", Theme.green, Theme.body(13.5f, FontWeight.Medium)) { setEx(exI) { it.copy(sets = it.sets.dropLast(1)) } }
                        Fill()
                        if (exercises.size > 1) TextButtonC("Delete", Theme.red, Theme.body(13.5f, FontWeight.Medium)) { exercises = exercises.filterIndexed { j, _ -> j != exI } }
                    }
                }
            }
            Box(Modifier.fillMaxWidth().clickable { exercises = exercises + DraftExercise() }.padding(vertical = 13.dp), contentAlignment = Alignment.Center) {
                IconLabel("plus", "Add exercise", Theme.muted, Theme.body(15f, FontWeight.SemiBold))
            }

            QLabel("Duration")
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SetField(durationMin, "min") { durationMin = Helpers.cleanTime(it) }
                T("min", Theme.meta(13f), Theme.muted)
            }
            QLabel("Effort (RPE)", "$rpe/10")
            StepSlider(rpe) { rpe = it }
            CoachTextField(feedback, { feedback = it }, "Notes", Modifier.padding(top = 8.dp))
            if (error.isNotEmpty()) ErrorBox(error, Modifier.padding(top = 12.dp))
            VGap(18.dp)
            BigButton("Save") { save() }
            VGap(24.dp)
        }
    }

    if (picking) {
        val initial = LocalDate.parse(date).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli()
        val state = rememberDatePickerState(initialSelectedDateMillis = initial, selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long) = Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate() <= LocalDate.now()
        })
        val colors = DatePickerDefaults.colors(containerColor = Theme.bgCard, selectedDayContainerColor = Theme.amber, selectedDayContentColor = Theme.onAmber, todayDateBorderColor = Theme.amber, todayContentColor = Theme.amberText)
        DatePickerDialog(
            onDismissRequest = { picking = false },
            confirmButton = {
                TextButtonC("OK") {
                    state.selectedDateMillis?.let { date = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString() }
                    picking = false
                }
            },
            dismissButton = { TextButtonC("Cancel", Theme.muted) { picking = false } },
            colors = colors,
        ) { DatePicker(state, colors = colors) }
    }
}
