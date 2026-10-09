package com.expdeath.coach.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.expdeath.coach.app.AppSheet
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.Screen
import com.expdeath.coach.ui.screens.AIConsentScreen
import com.expdeath.coach.ui.screens.AddPastScreen
import com.expdeath.coach.ui.screens.CheckInScreen
import com.expdeath.coach.ui.screens.CoachChatSheet
import com.expdeath.coach.ui.screens.FinishScreen
import com.expdeath.coach.ui.screens.GeneratingScreen
import com.expdeath.coach.ui.screens.HistoryDetailScreen
import com.expdeath.coach.ui.screens.HistoryScreen
import com.expdeath.coach.ui.screens.HomeScreen
import com.expdeath.coach.ui.screens.LoginScreen
import com.expdeath.coach.ui.screens.NotificationsSheet
import com.expdeath.coach.ui.screens.ProfileSheet
import com.expdeath.coach.ui.screens.ProgressScreen
import com.expdeath.coach.ui.screens.RecordsScreen
import com.expdeath.coach.ui.screens.SearchSheet
import com.expdeath.coach.ui.screens.SettingsScreen
import com.expdeath.coach.ui.screens.WorkoutScreen
import com.expdeath.coach.ui.screens.WorkoutsScreen
import java.io.File

/** Switches on AppState.screen (RootView.swift), with the bottom tab bar
 *  on the five top-level screens and the app-wide sheets. */
@Composable
fun RootScreen(app: AppState) {
    MaterialTheme(colorScheme = darkColorScheme(primary = Theme.amber, background = Theme.bg, surface = Theme.bg, onSurface = Theme.text)) {
        CompositionLocalProvider(LocalContentColor provides Theme.text) {
            val tab = TabBar.tabs.any { it.screen == app.screen }
            Column(Modifier.fillMaxSize().background(Theme.bg)) {
                Box(Modifier.weight(1f)) {
                    when (app.screen) {
                        Screen.Loading -> CoachScreen {
                            CircularProgressIndicator(color = Theme.amber, modifier = Modifier.align(Alignment.Center))
                        }
                        Screen.Login -> LoginScreen(app)
                        Screen.Home -> HomeScreen(app)
                        Screen.CheckIn -> CheckInScreen(app)
                        Screen.Generating -> GeneratingScreen(app)
                        Screen.Workout -> WorkoutScreen(app)
                        Screen.Finish -> FinishScreen(app)
                        Screen.History -> HistoryScreen(app)
                        Screen.HistoryDetail -> HistoryDetailScreen(app)
                        Screen.AddPast -> AddPastScreen(app)
                        Screen.Settings -> SettingsScreen(app)
                        Screen.Records -> RecordsScreen(app)
                        Screen.Progress -> ProgressScreen(app)
                        Screen.AIConsent -> AIConsentScreen(app)
                        Screen.Workouts -> androidx.compose.runtime.key(app.workoutsOpenId ?: "list") { WorkoutsScreen(app, app.workoutsOpenId) }
                    }
                }
                if (tab) TabBar(app) else Box(Modifier.navigationBarsPadding())
            }

            // system back: pushed screens return where they came from; tabs go to Today
            val back: Screen? = when (app.screen) {
                Screen.CheckIn, Screen.Workout, Screen.History, Screen.Progress, Screen.Records, Screen.Settings -> Screen.Home
                Screen.Finish -> Screen.Workout
                Screen.HistoryDetail, Screen.AddPast -> Screen.History
                Screen.Workouts -> app.workoutsFrom
                else -> null
            }
            BackHandler(enabled = back != null) { app.screen = back!! }

            if (app.chatOpen) CoachChatSheet(app) { app.chatOpen = false }
            when (app.sheet) {
                AppSheet.Notifications -> NotificationsSheet(app) { app.sheet = null }
                AppSheet.Profile -> ProfileSheet(app) { app.sheet = null }
                AppSheet.Search -> SearchSheet(app) { app.sheet = null }
                null -> {}
            }
        }
    }
}

/** The bottom tab bar on the five top-level screens. */
object TabBar {
    data class Tab(val screen: Screen, val icon: String, val label: String)

    val tabs = listOf(
        Tab(Screen.Home, "bolt", "Today"),
        Tab(Screen.History, "calendar", "Log"),
        Tab(Screen.Progress, "chart.bar.xaxis", "Progress"),
        Tab(Screen.Records, "trophy", "Records"),
        Tab(Screen.Settings, "slider.horizontal.3", "Settings"),
    )

    @Composable
    operator fun invoke(app: AppState) {
        Column(Modifier.fillMaxWidth().background(Theme.bgCard)) {
            Hairline()
            Row(Modifier.fillMaxWidth().navigationBarsPadding()) {
                for (t in tabs) {
                    val on = app.screen == t.screen
                    val c = if (on) Theme.amberText else Theme.dim
                    Column(
                        Modifier.weight(1f).clickable { app.screen = t.screen }.padding(top = 9.dp, bottom = 6.dp)
                            .semantics { contentDescription = t.label; selected = on },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Icon(sf(if (on && t.icon == "trophy") "trophy.fill" else t.icon), null, tint = c, modifier = Modifier.size(22.dp))
                        CapsText(t.label, c, 11f)
                    }
                }
            }
        }
    }
}

// ── Platform helpers (share sheet, links) ───────────────────────────

fun openUrl(ctx: Context, url: String) {
    try { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
}

fun shareText(ctx: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    ctx.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** Where exported files go before the share sheet hands them on. */
fun exportsDir(ctx: Context): File = File(ctx.cacheDir, "exports").also { it.mkdirs() }

fun shareFile(ctx: Context, file: File, mime: String) {
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", file)
    val send = Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    ctx.startActivity(Intent.createChooser(send, file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
