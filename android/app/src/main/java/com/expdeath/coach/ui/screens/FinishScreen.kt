package com.expdeath.coach.ui.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.RestNotifier
import com.expdeath.coach.app.Screen
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.CoachTextField
import com.expdeath.coach.ui.QLabel
import com.expdeath.coach.ui.ScreenHeader
import com.expdeath.coach.ui.StepSlider
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.VGap
import com.expdeath.coach.ui.panel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Ports Finish.jsx — 20-second post-session log: session RPE, pain, too
 *  easy/hard, with a PR celebration when today beat an all-time record.
 *  Save → AppState.finishSession (Firestore + debrief). */
@Composable
fun FinishScreen(app: AppState) {
    val ctx = LocalContext.current
    var saving by remember { mutableStateOf(false) }
    var confetti by remember { mutableStateOf(false) }
    // all-time records beaten today, vs everything before this session
    val prs = app.todayPlan?.let { t -> Stats.detectPRs(t, app.history.filter { it.id != t.id }) } ?: emptyList()
    LaunchedEffect(Unit) {
        if (prs.isEmpty()) return@LaunchedEffect
        confetti = true
        RestNotifier.buzz(ctx)
        delay(3200)
        confetti = false
    }
    Box(Modifier.fillMaxSize()) {
        CoachScreen {
            Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(16.dp)) {
                ScreenHeader("How did it go?", onBack = { app.screen = Screen.Workout })
                if (prs.isNotEmpty()) {
                    Column(Modifier.padding(top = 14.dp).fillMaxWidth().panel(Theme.amberBg, Theme.amber).padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        T("🏆 New record${if (prs.size > 1) "s" else ""}", Theme.head(17f, FontWeight.Bold), Theme.amber)
                        for (p in prs) T("${p.name} · ${if (p.kind == "weight") "" else "e1RM "}${Helpers.fmtKg(p.from)} → ${Helpers.fmtKg(p.to)}kg", Theme.meta(14f))
                    }
                }
                QLabel("Effort (RPE)", "${app.fin.rpe}/10")
                StepSlider(app.fin.rpe) { app.fin = app.fin.copy(rpe = it) }
                QLabel("Any pain?")
                CoachTextField(app.fin.pain, { app.fin = app.fin.copy(pain = it) }, "None")
                QLabel("Too easy or too hard?")
                CoachTextField(app.fin.feedback, { app.fin = app.fin.copy(feedback = it) }, "e.g. curls felt brutal")
                VGap(28.dp)
                BigButton(if (saving) "Saving…" else "Save session", enabled = !saving) {
                    saving = true
                    app.finishSession()
                }
                VGap(24.dp)
            }
        }
        if (confetti) ConfettiBurst()
    }
}

/** One burst of falling pieces — the web app's .confetti-burst. */
@Composable
private fun ConfettiBurst() {
    val colors = listOf(Theme.amber, Theme.green, Theme.red, Color(0xFF7EA6F5), Color(0xFFE4C1F9))
    val progress = remember { List(28) { Animatable(0f) } }
    LaunchedEffect(Unit) {
        progress.forEachIndexed { i, a ->
            launch {
                delay((i % 7) * 120L)
                a.animateTo(1f, tween((2000 + (i * 13 % 10) * 100), easing = LinearEasing))
            }
        }
    }
    Canvas(Modifier.fillMaxSize()) {
        progress.forEachIndexed { i, a ->
            val f = a.value
            val x = size.width * ((i * 37 + 13) % 100) / 100f
            val y = -20f + (size.height + 40f) * f * f
            rotate((i * 47 % 360 + 360 * f), Offset(x, y)) {
                drawRoundRect(colors[i % colors.size], Offset(x - 4.dp.toPx(), y - 6.dp.toPx()), Size(8.dp.toPx(), 12.dp.toPx()), CornerRadius(2.dp.toPx()))
            }
        }
    }
}
