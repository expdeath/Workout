package com.expdeath.coach.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.expdeath.coach.stats.fmt
import com.expdeath.coach.stats.formatted
import com.expdeath.coach.stats.rounded
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.pow

// Ports src/components/Charts.jsx (Charts.swift): 2px lines with round caps
// and a light area wash, ≤24px columns, hairline gridlines, labels in ink
// colours, tap/drag to read a value. Drawn on a Canvas — no chart library.

data class ChartPoint(val label: String, val value: Double)

/** "Nice" gridline values covering lo…hi. */
private fun niceTicks(lo: Double, hi: Double, count: Int = 4): List<Double> {
    if (hi <= lo) return listOf(lo)
    val raw = (hi - lo) / count
    val mag = 10.0.pow(floor(log10(raw)))
    val step = listOf(1.0, 2.0, 2.5, 5.0, 10.0).map { it * mag }.first { it >= raw }
    val start = ceil(lo / step) * step
    val out = ArrayList<Double>()
    var v = start
    while (v <= hi + 1e-9) { out.add(v); v += step }
    return out
}

private fun fmtVal(v: Double): String = if (v.rounded() == v) v.toLong().toString() else fmt("%.1f", v)

/** Single-series line chart (exercise trends, recovery). */
@Composable
fun LineChartView(points: List<ChartPoint>, unit: String = "", color: Color = Theme.amber, height: Dp = 180.dp) {
    var selected by remember(points) { mutableStateOf<Int?>(null) }
    val measurer = rememberTextMeasurer()
    val labelStyle = Theme.meta(10f).copy(color = Theme.muted)
    val annStyle = Theme.head(13f, FontWeight.Bold).copy(color = Theme.text)
    val values = points.map { it.value }
    val lo0 = values.minOrNull() ?: 0.0
    val hi0 = values.maxOrNull() ?: 1.0
    val pad = if (hi0 - lo0 < 1e-9) max(abs(hi0) * 0.1, 1.0) else (hi0 - lo0) * 0.15
    val lo = lo0 - pad
    val hi = hi0 + pad
    val ticks = niceTicks(lo, hi)
    val desc = points.joinToString(", ") { "${it.label}: ${fmtVal(it.value)}$unit" }

    Canvas(
        Modifier.fillMaxWidth().height(height).semantics { contentDescription = desc }
            .pointerInput(points) {
                detectTapGestures { o -> selected = nearest(o.x, 34.dp.toPx(), size.width.toFloat(), points.size) }
            }
            .pointerInput(points) {
                detectDragGestures { change, _ -> selected = nearest(change.position.x, 34.dp.toPx(), size.width.toFloat(), points.size) }
            },
    ) {
        if (points.isEmpty()) return@Canvas
        val left = 34.dp.toPx()
        val bottom = 18.dp.toPx()
        val top = 22.dp.toPx()
        val w = size.width - left - 6.dp.toPx()
        val h = size.height - bottom - top
        fun x(i: Int) = left + if (points.size == 1) w / 2 else w * i / (points.size - 1)
        fun y(v: Double) = top + h * (1 - ((v - lo) / (hi - lo)).toFloat())

        // gridlines + y labels
        for (t in ticks) {
            val yy = y(t)
            drawLine(Theme.border, Offset(left, yy), Offset(size.width, yy), 1f)
            val m = measurer.measure(fmtVal(t), labelStyle)
            drawText(m, topLeft = Offset(left - m.size.width - 6.dp.toPx(), yy - m.size.height / 2))
        }
        // smooth path (catmull-rom → cubic)
        val pts = points.indices.map { Offset(x(it), y(points[it].value)) }
        val line = Path().apply {
            moveTo(pts[0].x, pts[0].y)
            for (i in 0 until pts.size - 1) {
                val p0 = pts[maxOf(i - 1, 0)]; val p1 = pts[i]; val p2 = pts[i + 1]; val p3 = pts[minOf(i + 2, pts.size - 1)]
                cubicTo(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6, p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6, p2.x, p2.y)
            }
        }
        val area = Path().apply {
            addPath(line)
            lineTo(pts.last().x, top + h); lineTo(pts.first().x, top + h); close()
        }
        drawPath(area, Brush.verticalGradient(listOf(color.copy(alpha = 0.35f), color.copy(alpha = 0f)), startY = top, endY = top + h))
        drawPath(line, color, style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))

        // x labels: first, middle, last
        val xs = if (points.size > 3) listOf(0, points.size / 2, points.size - 1) else points.indices.toList()
        for (i in xs) {
            val m = measurer.measure(points[i].label, labelStyle)
            val cx = (x(i) - m.size.width / 2).coerceIn(left - 10, size.width - m.size.width)
            drawText(m, topLeft = Offset(cx, size.height - m.size.height))
        }
        // the latest point (and the selected one) with its value
        val marks = listOfNotNull(points.size - 1, selected).distinct()
        for (i in marks) {
            drawCircle(color, 4.5.dp.toPx(), pts[i])
            annotate(measurer.measure("${fmtVal(points[i].value)}$unit", annStyle), pts[i])
        }
    }
}

private fun DrawScope.annotate(m: androidx.compose.ui.text.TextLayoutResult, at: Offset) {
    val padX = 6.dp.toPx(); val padY = 2.dp.toPx()
    val w = m.size.width + padX * 2; val h = m.size.height + padY * 2
    val left = (at.x - w / 2).coerceIn(0f, size.width - w)
    val top = (at.y - h - 6.dp.toPx()).coerceAtLeast(0f)
    drawRoundRect(Theme.bgHigh, Offset(left, top), Size(w, h), CornerRadius(h / 2))
    drawText(m, topLeft = Offset(left + padX, top + padY))
}

private fun nearest(x: Float, left: Float, width: Float, n: Int): Int? {
    if (n == 0) return null
    val frac = ((x - left) / (width - left)).coerceIn(0f, 1f)
    return Math.round(frac * (n - 1)).coerceIn(0, n - 1)
}

/** Single-series bar chart (weekly volume / sessions). */
@Composable
fun BarChartView(bars: List<ChartPoint>, unit: String = "", color: Color = Theme.chartAmber) {
    var selected by remember(bars) { mutableStateOf<Int?>(null) }
    val measurer = rememberTextMeasurer()
    val labelStyle = Theme.meta(10f).copy(color = Theme.muted)
    val annStyle = Theme.meta(11f).copy(color = Theme.text)
    val hi = maxOf(bars.maxOfOrNull { it.value } ?: 0.0, 1.0)
    val ticks = niceTicks(0.0, hi * 1.1)
    val top = ticks.last().coerceAtLeast(hi)
    Canvas(
        Modifier.fillMaxWidth().height(180.dp)
            .semantics { contentDescription = bars.joinToString(", ") { "${it.label}: ${fmtN(it.value)}$unit" } }
            .pointerInput(bars) {
                detectTapGestures { o ->
                    val left = 40.dp.toPx()
                    val slot = (size.width - left) / maxOf(bars.size, 1)
                    val i = ((o.x - left) / slot).toInt()
                    selected = if (i in bars.indices) i else null
                }
            },
    ) {
        if (bars.isEmpty()) return@Canvas
        val left = 40.dp.toPx()
        val bottom = 18.dp.toPx()
        val topPad = 16.dp.toPx()
        val h = size.height - bottom - topPad
        val slot = (size.width - left) / bars.size
        val bw = minOf(22.dp.toPx(), slot * 0.7f)
        fun y(v: Double) = topPad + h * (1 - (v / top).toFloat())
        for (t in ticks) {
            drawLine(Theme.border, Offset(left, y(t)), Offset(size.width, y(t)), 1f)
            val m = measurer.measure(fmtN(t), labelStyle)
            drawText(m, topLeft = Offset(left - m.size.width - 6.dp.toPx(), y(t) - m.size.height / 2))
        }
        val every = maxOf(1, ceil(bars.size / 6.0).toInt())
        bars.forEachIndexed { i, b ->
            val cx = left + slot * i + slot / 2
            val yy = y(b.value)
            if (b.value > 0) {
                val r = 4.dp.toPx()
                val path = Path().apply {
                    moveTo(cx - bw / 2, topPad + h); lineTo(cx - bw / 2, yy + r)
                    quadraticTo(cx - bw / 2, yy, cx - bw / 2 + r, yy); lineTo(cx + bw / 2 - r, yy)
                    quadraticTo(cx + bw / 2, yy, cx + bw / 2, yy + r); lineTo(cx + bw / 2, topPad + h); close()
                }
                drawPath(path, color)
            }
            if (i % every == 0 || i == bars.size - 1) {
                val m = measurer.measure(b.label, labelStyle)
                drawText(m, topLeft = Offset((cx - m.size.width / 2).coerceIn(0f, size.width - m.size.width), size.height - m.size.height))
            }
            if (selected == i) annotate(measurer.measure("${fmtN(b.value)}$unit", annStyle), Offset(cx, yy))
        }
    }
}

fun fmtN(n: Double): String = if (n >= 10000) "${(n / 1000).rounded().toInt()}k" else n.toInt().formatted()

/** Training-day heatmap: last `weeks` weeks, Monday on top, deeper amber =
 *  bigger session (TrainingHeatmap in Charts.jsx). Cells fill the width. */
@Composable
fun TrainingHeatmapView(days: Map<String, Int>, weeks: Int = 16) {
    val today = LocalDate.now()
    val thisMonday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val start = thisMonday.minusWeeks((weeks - 1).toLong())
    val maxVol = maxOf(days.values.maxOrNull() ?: 1, 1)
    val gap = if (weeks > 26) 2.dp else 4.dp
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        // cells fill the width, but the grid stays ≤ 220dp tall (centered), like iOS
        val cell = minOf((maxWidth - gap * (weeks - 1)) / weeks, (220.dp - gap * 6) / 7)
        val gridW = cell * weeks + gap * (weeks - 1)
        Canvas(Modifier.fillMaxWidth().height(cell * 7 + gap * 6).semantics { contentDescription = "Training heatmap, last $weeks weeks" }) {
            val g = gap.toPx()
            val c = cell.toPx()
            val left = (size.width - gridW.toPx()) / 2
            val r = minOf(3.dp.toPx(), c / 4)
            for (w in 0 until weeks) for (d in 0 until 7) {
                val date = start.plusDays((w * 7 + d).toLong())
                drawRoundRect(
                    heatColor(days[date.toString()], maxVol, date.isAfter(today)),
                    Offset(left + w * (c + g), d * (c + g)), Size(c, c), CornerRadius(r),
                )
            }
        }
    }
}

fun heatColor(vol: Int?, maxVol: Int, future: Boolean): Color {
    if (future) return Theme.bgInput
    if (vol == null) return Theme.bgHigh
    // logged but no volume (cardio / mobility) → green
    if (vol <= 0) return Theme.chartGreen.copy(alpha = 0.8f)
    return Theme.amber.copy(alpha = (0.35 + 0.65 * vol / maxVol).toFloat())
}

/** LESS ▢▢▢▢ MORE key under a heatmap. */
@Composable
fun HeatLegend() {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        CapsText("Less", Theme.dim, 10.5f)
        for (o in listOf(0.35f, 0.6f, 0.8f, 1f)) Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.dp)).background(Theme.amber.copy(alpha = o)))
        CapsText("More", Theme.dim, 10.5f)
    }
}

/** Ports ReadinessBar.jsx — teal ≥70, amber ≥45, red below. */
@Composable
fun ReadinessBar(value: Int, label: String, modifier: Modifier = Modifier) {
    val color = if (value >= 70) Theme.green else if (value >= 45) Theme.amber else Theme.red
    val frac by animateFloatAsState((value / 100f).coerceIn(0f, 1f), label = "readiness")
    Row(modifier.fillMaxWidth().semantics { contentDescription = "$label $value" }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CapsText(label)
        Box(Modifier.weight(1f).height(6.dp).clip(CircleShape).background(Theme.bgInput)) {
            Box(Modifier.fillMaxWidth(frac).height(6.dp).clip(CircleShape).background(color))
        }
        T("$value", Theme.head(26f, FontWeight.Bold), color, Modifier.widthIn(min = 30.dp))
    }
}
