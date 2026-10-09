package com.expdeath.coach.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.automirrored.outlined.FeaturedPlayList
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.AddAlert
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.CloudDone
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.EmojiEvents
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.material.icons.outlined.Feedback
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.outlined.GppGood
import androidx.compose.material.icons.outlined.Healing
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.ManageSearch
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.OpenInFull
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Scale
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.SmartDisplay
import androidx.compose.material.icons.outlined.TableChart
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.TrackChanges
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.Upload
import androidx.compose.material.icons.outlined.Watch
import androidx.compose.material.icons.outlined.WorkspacePremium
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.expdeath.coach.R

/** Visual design system — the same tokens as the :root custom properties
 *  in src/index.css (and Theme.swift), so all three apps look identical.
 *  Dark only, like the web app. */
object Theme {
    // ── Colors ──
    val bg = Color(0xFF0B0F17)          // page background (surface-base)
    val bgCard = Color(0xFF131B2E)      // raised card (surface-elevated)
    val bgInput = Color(0xFF0A0E16)     // inset fields and wells
    val bgPill = Color(0xFF1A1F2B)      // tiles and rows inside a card
    val bgHigh = Color(0xFF262A33)      // pressed / selected surface
    val border = Color.White.copy(alpha = 0.07f)
    val borderDim = Color(0xFF2B3140)
    val text = Color(0xFFF8FAFC)
    val textBody = Color(0xFFDFE2EE)
    val muted = Color(0xFF8391A7)
    val dim = Color(0xFF4E5869)
    val amber = Color(0xFFF59E0B)
    val amberText = Color(0xFFFBBF24)
    val amberBg = Color(0xFFF59E0B).copy(alpha = 0.12f)
    val green = Color(0xFF56E5A9)
    val greenBg = Color(0xFF56E5A9).copy(alpha = 0.12f)
    val red = Color(0xFFF26D5B)
    val redBg = Color(0xFFF26D5B).copy(alpha = 0.12f)
    val onAmber = Color(0xFF080B11)
    val chartAmber = Color(0xFFD48A0A)
    val chartGreen = Color(0xFF30C88F)

    // ── Fonts: Barlow Condensed (titles, numbers, caps labels) +
    //    Space Grotesk (everything you read) ──
    private val barlow = FontFamily(
        Font(R.font.barlow_condensed_medium, FontWeight.Medium),
        Font(R.font.barlow_condensed_semibold, FontWeight.SemiBold),
        Font(R.font.barlow_condensed_bold, FontWeight.Bold),
    )
    private val grotesk = FontFamily(
        Font(R.font.space_grotesk_regular, FontWeight.Normal),
        Font(R.font.space_grotesk_medium, FontWeight.Medium),
        Font(R.font.space_grotesk_bold, FontWeight.Bold),
    )

    fun head(size: Float, weight: FontWeight = FontWeight.SemiBold) = TextStyle(
        fontFamily = barlow,
        fontWeight = if (weight >= FontWeight.Bold) FontWeight.Bold else if (weight <= FontWeight.Medium) FontWeight.Medium else FontWeight.SemiBold,
        fontSize = size.sp,
    )

    fun body(size: Float, weight: FontWeight = FontWeight.Normal) = TextStyle(
        fontFamily = grotesk,
        fontWeight = if (weight >= FontWeight.SemiBold) FontWeight.Bold else if (weight == FontWeight.Medium) FontWeight.Medium else FontWeight.Normal,
        fontSize = size.sp,
    )

    /** Secondary text with tabular digits so numbers line up. */
    fun meta(size: Float, weight: FontWeight = FontWeight.Normal) = body(size, weight).copy(fontFeatureSettings = "tnum")

    /** Numbers you type or watch tick (set inputs, the rest timer). */
    fun data(size: Float) = head(size, FontWeight.Bold).copy(fontFeatureSettings = "tnum")

    /** Small tracked uppercase label (`.label-caps`). */
    fun caps(size: Float = 13f) = head(size, FontWeight.Bold).copy(letterSpacing = 1.6.sp)

    val link = TextStyle(textDecoration = TextDecoration.None)

    val radius = 12.dp
    val radiusSm = 9.dp
}

/** SF Symbol names used across the shared logic (Dashboard icons) and the
 *  screens → their Material equivalents. */
fun sf(name: String): ImageVector = when (name) {
    "calendar" -> Icons.Outlined.CalendarMonth
    "flame.fill" -> Icons.Filled.LocalFireDepartment
    "scalemass.fill", "scalemass" -> Icons.Outlined.Scale
    "medal.fill" -> Icons.Filled.MilitaryTech
    "medal" -> Icons.Filled.MilitaryTech
    "trophy.fill" -> Icons.Filled.EmojiEvents
    "trophy" -> Icons.Outlined.EmojiEvents
    "rosette" -> Icons.Filled.Verified
    "doc.text.magnifyingglass" -> Icons.Outlined.ManageSearch
    "exclamationmark.triangle.fill", "exclamationmark.triangle" -> Icons.Filled.Warning
    "checkmark.shield" -> Icons.Outlined.GppGood
    "bolt" -> Icons.Filled.Bolt
    "chart.bar.xaxis" -> Icons.Outlined.BarChart
    "slider.horizontal.3" -> Icons.Outlined.Tune
    "magnifyingglass" -> Icons.Outlined.Search
    "bubble.left" -> Icons.AutoMirrored.Outlined.Chat
    "bell" -> Icons.Outlined.Notifications
    "bell.slash" -> Icons.Outlined.NotificationsOff
    "bell.badge" -> Icons.Outlined.AddAlert
    "chevron.left" -> Icons.Outlined.ChevronLeft
    "chevron.right" -> Icons.Outlined.ChevronRight
    "chevron.down" -> Icons.Filled.ExpandMore
    "chevron.up" -> Icons.Filled.ExpandLess
    "xmark" -> Icons.Filled.Close
    "timer" -> Icons.Outlined.Timer
    "figure.run" -> Icons.AutoMirrored.Filled.DirectionsRun
    "bicycle" -> Icons.Filled.DirectionsBike
    "figure.walk" -> Icons.AutoMirrored.Filled.DirectionsWalk
    "figure.hiking" -> Icons.Filled.Hiking
    "play.fill" -> Icons.Filled.PlayArrow
    "arrow.right" -> Icons.AutoMirrored.Filled.ArrowForward
    "arrow.up" -> Icons.Filled.ArrowUpward
    "arrow.up.left.and.arrow.down.right" -> Icons.Outlined.OpenInFull
    "list.bullet.clipboard" -> Icons.AutoMirrored.Outlined.ListAlt
    "dumbbell", "dumbbell.fill" -> Icons.Outlined.FitnessCenter
    "ellipsis" -> Icons.Filled.MoreHoriz
    "plus" -> Icons.Filled.Add
    "minus" -> Icons.Filled.Remove
    "trash" -> Icons.Outlined.Delete
    "pencil" -> Icons.Outlined.Edit
    "pencil.line" -> Icons.Outlined.EditNote
    "note.text" -> Icons.AutoMirrored.Filled.Notes
    "arrow.left.arrow.right" -> Icons.Filled.SwapHoriz
    "play.rectangle" -> Icons.Outlined.SmartDisplay
    "star.fill" -> Icons.Filled.Star
    "checkmark.circle.fill" -> Icons.Filled.CheckCircle
    "checkmark.seal.fill" -> Icons.Filled.Verified
    "square.and.arrow.up" -> Icons.Outlined.Share
    "tablecells" -> Icons.Outlined.TableChart
    "heart.text.square" -> Icons.Outlined.MonitorHeart
    "brain.head.profile" -> Icons.Outlined.Psychology
    "crown" -> Icons.Outlined.WorkspacePremium
    "target" -> Icons.Outlined.TrackChanges
    "applewatch" -> Icons.Outlined.Watch
    "icloud" -> Icons.Outlined.CloudDone
    "bubble.left.and.text.bubble.right" -> Icons.Outlined.Feedback
    "info.circle" -> Icons.Outlined.Info
    "rectangle.portrait.and.arrow.right" -> Icons.AutoMirrored.Filled.Logout
    "photo" -> Icons.Outlined.Image
    "bandage" -> Icons.Outlined.Healing
    "square.and.pencil" -> Icons.Outlined.Edit
    "heart" -> Icons.Outlined.Favorite
    "upload" -> Icons.Outlined.Upload
    "back" -> Icons.AutoMirrored.Filled.ArrowBack
    "external" -> Icons.AutoMirrored.Filled.OpenInNew
    "list" -> Icons.AutoMirrored.Outlined.FeaturedPlayList
    else -> Icons.Filled.FitnessCenter
}
