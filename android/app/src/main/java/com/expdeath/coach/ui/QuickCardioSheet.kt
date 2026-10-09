package com.expdeath.coach.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.expdeath.coach.stats.Helpers

/** Ports QuickCardioSheet.jsx — a run/ride/walk/hike logged straight to
 *  history in a few taps, bypassing check-in + AI entirely. */
@Composable
fun QuickCardioSheet(kind: String, onDismiss: () -> Unit, onSave: (kind: String, time: String, dist: String, rpe: Int, date: String) -> Unit) {
    var time by remember { mutableStateOf("") }
    var dist by remember { mutableStateOf("") }
    var rpe by remember { mutableIntStateOf(6) }
    var daysAgo by remember { mutableStateOf("0") } // forgot to log it yesterday → backdate
    val (label, verb, icon) = when (kind) {
        "cycle" -> Triple("Log a ride", "ride", "🚴")
        "walk" -> Triple("Log a walk", "walk", "🚶")
        "hike" -> Triple("Log a hike", "hike", "🥾")
        else -> Triple("Log a run", "run", "🏃")
    }
    val canSave = time.isNotEmpty() || dist.isNotEmpty()

    CoachSheet(onDismiss) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            T(label, Theme.head(24f, FontWeight.Bold))
            SegGroup(listOf("0" to "Today", "1" to "Yesterday", "2" to "2 days ago"), daysAgo) { daysAgo = it }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CoachTextField(time, { time = Helpers.cleanTime(it) }, "min", Modifier.width(78.dp), keyboard = KeyboardType.Decimal, style = Theme.data(15f), padH = 10.dp, padV = 10.dp, align = TextAlign.Center)
                T("min", Theme.meta(13f), Theme.dim)
                CoachTextField(dist, { dist = Helpers.cleanDist(it) }, "km", Modifier.width(78.dp), keyboard = KeyboardType.Decimal, style = Theme.data(15f), padH = 10.dp, padV = 10.dp, align = TextAlign.Center)
                T("km", Theme.meta(13f), Theme.dim)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                T("Effort", Theme.body(14f, FontWeight.SemiBold), Theme.muted)
                Fill()
                T("$rpe/10", Theme.head(20f, FontWeight.Bold), Theme.amber)
            }
            StepSlider(rpe) { rpe = it }
            Box(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.radiusSm)).background(Theme.green.copy(alpha = if (canSave) 1f else 0.4f))
                    .clickable(enabled = canSave) {
                        onSave(kind, time, dist, rpe, Helpers.daysAgoStr(daysAgo.toIntOrNull() ?: 0))
                        onDismiss()
                    }.padding(vertical = 15.dp),
                contentAlignment = Alignment.Center,
            ) { T("$icon Save $verb", Theme.body(16f, FontWeight.Medium), Theme.bg) }
        }
    }
}
