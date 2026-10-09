package com.expdeath.coach.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.expdeath.coach.app.AppSheet
import com.expdeath.coach.app.AppState

// Building blocks shared by the screens — the Compose twins of index.css's
// .card, .label-caps, .tab-header, .pill, .chip and friends (CoachUI.swift
// + FormControls.swift).

/** Small tracked uppercase label (`.label-caps`). */
@Composable
fun CapsText(text: String, color: Color = Theme.muted, size: Float = 13f, modifier: Modifier = Modifier, maxLines: Int = 1, align: TextAlign? = null) {
    Text(text.uppercase(), style = Theme.caps(size), color = color, modifier = modifier, maxLines = maxLines, overflow = TextOverflow.Ellipsis, textAlign = align)
}

/** Plain text in one of the theme styles. */
@Composable
fun T(text: String, style: TextStyle, color: Color = Theme.text, modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE, align: TextAlign? = null) {
    Text(text, style = style, color = color, modifier = modifier, maxLines = maxLines, overflow = TextOverflow.Ellipsis, textAlign = align)
}

/** Big uppercase title in the head font. */
@Composable
fun Title(text: String, size: Float, color: Color = Theme.text, modifier: Modifier = Modifier, maxLines: Int = 2, tracking: Float = 0.5f) {
    Text(text.uppercase(), style = Theme.head(size, FontWeight.Bold).copy(letterSpacing = tracking.sp), color = color, modifier = modifier, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

fun Modifier.tap(onClick: () -> Unit): Modifier = this.clickable(interactionSource = MutableInteractionSource(), indication = null, onClick = onClick)

fun Modifier.panel(bg: Color = Theme.bgCard, stroke: Color = Theme.border, radius: Dp = Theme.radius): Modifier =
    this.clip(RoundedCornerShape(radius)).background(bg).border(1.dp, stroke, RoundedCornerShape(radius))

/** `.card` — raised panel. */
@Composable
fun CoachCard(modifier: Modifier = Modifier, stroke: Color = Theme.border, padding: Dp = 16.dp, spacing: Dp = 8.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().panel(stroke = stroke).padding(padding),
        verticalArrangement = Arrangement.spacedBy(spacing),
        content = content,
    )
}

@Composable
fun CardLabel(text: String, color: Color = Theme.muted) = CapsText(text, color)

/** Section label with an optional amber action/annotation on the right. */
@Composable
fun SectionHead(title: String, trailing: String? = null, trailingColor: Color = Theme.amberText, modifier: Modifier = Modifier, action: (() -> Unit)? = null) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        CapsText(title)
        Spacer(Modifier.weight(1f))
        if (trailing != null) {
            CapsText(trailing, trailingColor, 12f, if (action != null) Modifier.clickable(onClick = action).padding(4.dp) else Modifier)
        }
    }
}

/** A 44dp tap target around an icon. */
@Composable
fun CIconButton(icon: String, label: String, color: Color = Theme.muted, size: Dp = 20.dp, enabled: Boolean = true, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier.size(width = 40.dp, height = 44.dp).clip(CircleShape)
            .clickable(enabled = enabled, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(sf(icon), null, tint = if (enabled) color else Theme.dim.copy(alpha = 0.5f), modifier = Modifier.size(size))
    }
}

/** ‹ — the one back affordance every pushed screen uses. */
@Composable
fun BackButton(label: String = "Back", onClick: () -> Unit) {
    Box(
        Modifier.size(width = 36.dp, height = 44.dp).clickable(onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.CenterStart,
    ) { Icon(sf("chevron.left"), null, tint = Theme.muted, modifier = Modifier.size(28.dp)) }
}

/** Top bar of the five tab screens: COACH • TITLE, then search, chat, the
 *  notification bell (with an unread dot) and the profile avatar. */
@Composable
fun TabHeader(app: AppState, title: String) {
    Row(Modifier.fillMaxWidth().padding(bottom = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        CapsText("COACH", Theme.amberText, 13f)
        Box(Modifier.size(4.dp).clip(CircleShape).background(Theme.amber.copy(alpha = 0.5f)))
        Title(title, 24f, maxLines = 1, tracking = 1f, modifier = Modifier.weight(1f))
        CIconButton("magnifyingglass", "Search") { app.sheet = AppSheet.Search }
        CIconButton("bubble.left", "Ask the coach") { app.chatOpen = true }
        val unread = app.unreadNotifications
        Box {
            CIconButton("bell", if (unread > 0) "Notifications, $unread new" else "Notifications") { app.sheet = AppSheet.Notifications }
            if (unread > 0) Box(Modifier.align(Alignment.TopEnd).offset(x = (-11).dp, y = 11.dp).size(7.dp).clip(CircleShape).background(Theme.amber))
        }
        Box(Modifier.clickable { app.sheet = AppSheet.Profile }.semantics { contentDescription = "Profile" }) {
            Avatar(app.displayName, 32.dp)
        }
    }
}

/** Initials in an amber circle. */
@Composable
fun Avatar(name: String, size: Dp = 32.dp) {
    val initials = name.split(" ").filter { it.isNotEmpty() }.take(2).map { it.first().toString() }.joinToString("").uppercase()
    Box(Modifier.size(size).clip(CircleShape).background(Theme.amber), contentAlignment = Alignment.Center) {
        Text(initials.ifEmpty { "?" }, style = Theme.head(size.value * 0.45f, FontWeight.Bold), color = Theme.onAmber)
    }
}

/** Pushed screens: back chevron, uppercase title, optional trailing icon. */
@Composable
fun ScreenHeader(title: String, onBack: (() -> Unit)? = null, trailingIcon: String? = null, trailingLabel: String = "", trailingAction: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null) BackButton(onClick = onBack)
        Title(title, 28f, maxLines = 1, tracking = 0.8f, modifier = Modifier.weight(1f))
        if (trailingIcon != null && trailingAction != null) CIconButton(trailingIcon, trailingLabel, onClick = trailingAction)
    }
}

/** Rounded-square icon well (rows, tiles, record lines). */
@Composable
fun IconWell(icon: String, tint: Color = Theme.amberText, size: Dp = 36.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(Theme.radiusSm)).background(Theme.bgHigh), contentAlignment = Alignment.Center) {
        Icon(sf(icon), null, tint = tint, modifier = Modifier.size(size * 0.5f))
    }
}

/** `.status-pill` — dot + caps text on a tinted capsule. */
@Composable
fun StatusPill(text: String, color: Color = Theme.green, dot: Boolean = true) {
    Row(
        Modifier.clip(CircleShape).background(color.copy(alpha = 0.12f)).padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (dot) Box(Modifier.size(6.dp).clip(CircleShape).background(color))
        CapsText(text, color, 12f)
    }
}

/** Centered big number over a caps label (Today's three stats). */
@Composable
fun StatBlock(value: String, label: String, color: Color = Theme.text, modifier: Modifier = Modifier) {
    Column(modifier.panel().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(value, style = Theme.head(38f, FontWeight.Bold), color = color, maxLines = 1)
        CapsText(label, Theme.muted, 11f)
    }
}

/** Thin rounded progress bar. */
@Composable
fun ProgressLine(fraction: Double, color: Color = Theme.amber, height: Dp = 6.dp, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(height).clip(CircleShape).background(Theme.bgInput)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0.0, 1.0).toFloat()).height(height).clip(CircleShape).background(color))
    }
}

/** 8 WEEKS · 3 MONTHS · YEAR style segmented switch. */
@Composable
fun SegmentedTabs(options: List<Pair<String, String>>, value: String, onChange: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Theme.radiusSm + 2.dp)).background(Theme.bgCard).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for ((v, label) in options) {
            val on = v == value
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(Theme.radiusSm - 2.dp)).background(if (on) Theme.amber else Color.Transparent)
                    .clickable { onChange(v) }.padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) { CapsText(label, if (on) Theme.onAmber else Theme.muted, 12f) }
        }
    }
}

/** Square launcher tile: icon well over a caps label. */
@Composable
fun LaunchTile(icon: String, label: String, tint: Color = Theme.amberText, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(
        modifier.panel().clickable(onClick = onClick).padding(vertical = 12.dp).semantics { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        IconWell(icon, tint)
        CapsText(label, Theme.textBody, 11f)
    }
}

/** `.chip` — small pill button. */
@Composable
fun Chip(title: String, on: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier.clip(CircleShape).background(if (on) Theme.amber else Theme.bgPill).clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    ) { CapsText(title, if (on) Theme.onAmber else Theme.textBody, 12f) }
}

/** A grouped settings row: icon well, title + subtitle, value, chevron. */
@Composable
fun SettingsRow(icon: String, title: String, subtitle: String? = null, tint: Color = Theme.amberText, onClick: (() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        IconWell(icon, tint)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            T(title, Theme.body(16f, FontWeight.Medium), maxLines = 1)
            if (!subtitle.isNullOrEmpty()) T(subtitle, Theme.meta(13f), Theme.muted, maxLines = 1)
        }
        trailing?.invoke()
        if (onClick != null) Icon(sf("chevron.right"), null, tint = Theme.dim, modifier = Modifier.size(18.dp))
    }
}

/** A rounded group of SettingsRows with inset hairlines between them. */
@Composable
fun RowGroup(rows: List<@Composable () -> Unit>) {
    Column(Modifier.fillMaxWidth().panel()) {
        rows.forEachIndexed { i, row ->
            if (i > 0) Box(Modifier.fillMaxWidth().padding(start = 64.dp).height(1.dp).background(Theme.border))
            row()
        }
    }
}

/** `.chat-bubble` (coach, left) / `.chat-bubble--user` (right). */
@Composable
fun ChatBubble(text: String, user: Boolean = false) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (user) Arrangement.End else Arrangement.Start) {
        if (user) Spacer(Modifier.width(40.dp))
        SelectionContainer(Modifier.weight(1f, fill = false)) {
            Text(
                text, style = Theme.body(15f), color = if (user) Theme.onAmber else Theme.textBody,
                modifier = Modifier.clip(RoundedCornerShape(14.dp)).background(if (user) Theme.amber else Theme.bgCard).padding(horizontal = 13.dp, vertical = 10.dp),
            )
        }
        if (!user) Spacer(Modifier.width(40.dp))
    }
}

/** Text input + ↑ send button, used by both chats. */
@Composable
fun ChatInputRow(text: String, onText: (String) -> Unit, placeholder: String, busy: Boolean, send: () -> Unit) {
    val can = !busy && text.isNotBlank()
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        CoachTextField(text, { onText(it.take(500)) }, placeholder, Modifier.weight(1f), imeAction = ImeAction.Send, onIme = { if (can) send() })
        Box(
            Modifier.size(44.dp).clip(CircleShape).background(Theme.amber.copy(alpha = if (can) 1f else 0.5f))
                .clickable(enabled = can, onClick = send).semantics { contentDescription = "Send" },
            contentAlignment = Alignment.Center,
        ) { Icon(sf("arrow.up"), null, tint = Theme.onAmber) }
    }
}

/** `.input` — full-width text field. */
@Composable
fun CoachTextField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String = "",
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    minLines: Int = 1,
    maxLines: Int = if (singleLine) 1 else 12,
    keyboard: KeyboardType = KeyboardType.Text,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
    password: Boolean = false,
    style: TextStyle = Theme.body(15f),
    imeAction: ImeAction = ImeAction.Default,
    onIme: (() -> Unit)? = null,
    radius: Dp = Theme.radiusSm,
    padH: Dp = 14.dp,
    padV: Dp = 13.dp,
    align: TextAlign = TextAlign.Start,
    bordered: Boolean = true,
) {
    BasicTextField(
        value = value,
        onValueChange = onChange,
        singleLine = singleLine,
        minLines = minLines,
        maxLines = maxLines,
        textStyle = style.copy(color = Theme.text, textAlign = align),
        cursorBrush = SolidColor(Theme.amber),
        visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard, capitalization = capitalization, imeAction = imeAction, autoCorrectEnabled = !password && keyboard == KeyboardType.Text),
        keyboardActions = KeyboardActions(onAny = { onIme?.invoke() }),
        modifier = modifier,
        decorationBox = { inner ->
            Box(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(radius)).background(Theme.bgInput)
                    .then(if (bordered) Modifier.border(1.dp, Theme.borderDim, RoundedCornerShape(radius)) else Modifier)
                    .padding(horizontal = padH, vertical = padV),
                contentAlignment = if (align == TextAlign.Center) Alignment.Center else Alignment.CenterStart,
            ) {
                if (value.isEmpty()) Text(placeholder, style = style.copy(textAlign = align), color = Theme.dim, modifier = Modifier.fillMaxWidth())
                inner()
            }
        },
    )
}

/** Number field used for set inputs (kg / reps / min / km). */
@Composable
fun SetField(value: String, placeholder: String, decimal: Boolean = true, size: Float = 19f, modifier: Modifier = Modifier, onChange: (String) -> Unit) {
    CoachTextField(
        value, onChange, placeholder, modifier.widthIn(max = 76.dp),
        keyboard = if (decimal) KeyboardType.Decimal else KeyboardType.Number,
        style = Theme.data(size), padH = 6.dp, padV = 7.dp, align = TextAlign.Center,
    )
}

/** Long coach text clamped to a few lines; tap to read the rest. */
@Composable
fun ExpandableText(text: String, lines: Int = 4) {
    var open by remember { mutableStateOf(false) }
    Text(
        text, style = Theme.body(14.5f), color = Theme.textBody, maxLines = if (open) Int.MAX_VALUE else lines,
        overflow = TextOverflow.Ellipsis, modifier = Modifier.animateContentSize().tap { open = !open },
    )
}

/** `.big-btn` — the amber, full-width, uppercase CTA with a soft glow. */
@Composable
fun BigButton(text: String, modifier: Modifier = Modifier, danger: Boolean = false, icon: String? = null, enabled: Boolean = true, onClick: () -> Unit) {
    val c = if (danger) Theme.red else Theme.amber
    Row(
        modifier.fillMaxWidth().shadow(if (enabled) 10.dp else 0.dp, RoundedCornerShape(Theme.radius), ambientColor = c, spotColor = c)
            .clip(RoundedCornerShape(Theme.radius)).background(c.copy(alpha = if (enabled) 1f else 0.5f))
            .clickable(enabled = enabled, onClick = onClick).padding(vertical = 16.dp, horizontal = 12.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) { Icon(sf(icon), null, tint = if (danger) Color.White else Theme.onAmber, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(10.dp)) }
        Text(text.uppercase(), style = Theme.head(20f, FontWeight.Bold).copy(letterSpacing = 1.4.sp), color = if (danger) Color.White else Theme.onAmber, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A quieter, outlined secondary button (Quick log, Sign out…). */
@Composable
fun OutlineButton(text: String, modifier: Modifier = Modifier, icon: String? = null, color: Color = Theme.amber, trailingIcon: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    Row(
        modifier.clip(RoundedCornerShape(Theme.radiusSm)).border(1.dp, color.copy(alpha = 0.55f), RoundedCornerShape(Theme.radiusSm))
            .clickable(enabled = enabled, onClick = onClick).padding(horizontal = 14.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null && !trailingIcon) Icon(sf(icon), null, tint = color, modifier = Modifier.size(16.dp))
        Text(text.uppercase(), style = Theme.head(15f, FontWeight.Bold).copy(letterSpacing = 1.2.sp), color = color, maxLines = 1)
        if (icon != null && trailingIcon) Icon(sf(icon), null, tint = color, modifier = Modifier.size(16.dp))
    }
}

/** A plain text button (links, "Cancel", "Keep"…). */
@Composable
fun TextButtonC(text: String, color: Color = Theme.amberText, style: TextStyle = Theme.body(14f, FontWeight.Medium), enabled: Boolean = true, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Text(text, style = style, color = if (enabled) color else Theme.dim, modifier = modifier.clip(RoundedCornerShape(6.dp)).clickable(enabled = enabled, onClick = onClick).padding(vertical = 6.dp, horizontal = 4.dp))
}

/** `.q-label` (+ `.q-label__value` on the right). */
@Composable
fun QLabel(text: String, value: String? = null, top: Dp = 20.dp) {
    Row(Modifier.fillMaxWidth().padding(top = top, bottom = 8.dp), verticalAlignment = Alignment.Bottom) {
        CapsText(text)
        Spacer(Modifier.weight(1f))
        if (value != null) Text(value, style = Theme.head(22f, FontWeight.Bold), color = Theme.amberText)
    }
}

/** `.seg-group` — equal-width choices; one row by default, or `columns` per row. */
@Composable
fun SegGroup(options: List<Pair<String, String>>, value: String, columns: Int? = null, onChange: (String) -> Unit) {
    val n = maxOf(columns ?: options.size, 1)
    val wrap = columns != null
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in options.chunked(n)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((v, label) in row) {
                    val on = v == value
                    Box(
                        Modifier.weight(1f).clip(RoundedCornerShape(Theme.radiusSm)).background(if (on) Theme.amberBg else Theme.bgCard)
                            .border(1.dp, if (on) Theme.amber else Theme.border, RoundedCornerShape(Theme.radiusSm))
                            .clickable { onChange(v) }.padding(vertical = if (wrap) 11.dp else 13.dp, horizontal = 6.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(label, style = Theme.body(if (wrap) 14f else 15f, if (on) FontWeight.Bold else FontWeight.Normal), color = if (on) Theme.amberText else Theme.textBody, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                repeat(n - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** `.pill` / `.pill-on` / `.pill-warn` — a full-width toggle row. */
@Composable
fun Pill(on: Boolean, text: String, warn: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val fg = if (on) (if (warn) Theme.red else Theme.amberText) else Theme.text
    val bg = if (on) (if (warn) Theme.redBg else Theme.amberBg) else Theme.bgCard
    val stroke = if (on) (if (warn) Theme.red else Theme.amber) else Theme.border
    Text(
        text, style = Theme.body(15f), color = fg,
        modifier = modifier.fillMaxWidth().panel(bg, stroke).clickable(onClick = onClick).padding(horizontal = 18.dp, vertical = 15.dp),
    )
}

/** `.err-box` — red inline error. */
@Composable
fun ErrorBox(text: String, modifier: Modifier = Modifier) {
    Text(text, style = Theme.body(13.5f), color = Theme.red, modifier = modifier.fillMaxWidth().panel(Theme.redBg, Theme.red).padding(12.dp))
}

/** Amber 1…10 slider (energy, RPE). */
@Composable
fun StepSlider(value: Int, range: IntRange = 1..10, onChange: (Int) -> Unit) {
    Slider(
        value = value.toFloat(), onValueChange = { onChange(Math.round(it)) },
        valueRange = range.first.toFloat()..range.last.toFloat(), steps = range.last - range.first - 1,
        colors = SliderDefaults.colors(thumbColor = Theme.amber, activeTrackColor = Theme.amber, inactiveTrackColor = Theme.bgHigh, activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent),
    )
}

/** A title + subtitle row with a switch on the right (SwiftUI Toggle). */
@Composable
fun ToggleRow(title: String, sub: String?, on: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!on) }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            T(title, Theme.body(15f, FontWeight.Medium))
            if (!sub.isNullOrEmpty()) T(sub, Theme.meta(12.5f), Theme.muted)
        }
        Spacer(Modifier.width(10.dp))
        Switch(on, onChange, colors = SwitchDefaults.colors(checkedTrackColor = Theme.amber, checkedThumbColor = Theme.onAmber, uncheckedTrackColor = Theme.bgHigh, uncheckedThumbColor = Theme.muted, uncheckedBorderColor = Theme.borderDim))
    }
}

/** − n + stepper (SwiftUI Stepper). */
@Composable
fun Stepper(value: Int, range: IntRange, onChange: (Int) -> Unit) {
    Row(Modifier.panel(Theme.bgPill), verticalAlignment = Alignment.CenterVertically) {
        CIconButton("minus", "Decrease", Theme.text, enabled = value > range.first) { onChange(value - 1) }
        Box(Modifier.width(1.dp).height(24.dp).background(Theme.border))
        CIconButton("plus", "Increase", Theme.text, enabled = value < range.last) { onChange(value + 1) }
    }
}

@Composable
fun Hairline(modifier: Modifier = Modifier) = Box(modifier.fillMaxWidth().height(1.dp).background(Theme.border))

/** Chevron that turns when open. */
@Composable
fun Chevron(open: Boolean, color: Color = Theme.muted, size: Dp = 18.dp) {
    Icon(sf("chevron.down"), null, tint = color, modifier = Modifier.size(size).rotate(if (open) 180f else 0f))
}

/** A bottom sheet in the app's colors. `full` opens straight to full height. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CoachSheet(onDismiss: () -> Unit, full: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = full)
    ModalBottomSheet(
        onDismissRequest = onDismiss, sheetState = state, containerColor = Theme.bg, contentColor = Theme.text,
        dragHandle = { Box(Modifier.padding(top = 8.dp).size(width = 40.dp, height = 4.dp).clip(CircleShape).background(Theme.borderDim)) },
    ) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding(), content = content)
    }
}

/** The screen root: dark background, edge-to-edge insets handled. */
@Composable
fun CoachScreen(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxSize().background(Theme.bg).statusBarsPadding()) { content() }
}

@Composable
fun RowScope.Fill() = Spacer(Modifier.weight(1f))

@Composable
fun VGap(h: Dp) = Spacer(Modifier.height(h))

@Composable
fun HGap(w: Dp) = Spacer(Modifier.width(w))

/** A label + icon row (SwiftUI Label). */
@Composable
fun IconLabel(icon: String, text: String, color: Color, style: TextStyle = Theme.body(14f), iconSize: Dp = 16.dp, maxLines: Int = Int.MAX_VALUE) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(sf(icon), null, tint = color, modifier = Modifier.padding(top = 2.dp).size(iconSize))
        T(text, style, color, maxLines = maxLines)
    }
}
