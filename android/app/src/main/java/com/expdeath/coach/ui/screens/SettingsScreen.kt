package com.expdeath.coach.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.expdeath.coach.BuildConfig
import com.expdeath.coach.account.Account
import com.expdeath.coach.account.Subscriptions
import com.expdeath.coach.app.AppSheet
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.CoachApplication
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.persistence.AIConsent
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.persistence.Prefs
import com.expdeath.coach.stats.Dashboard
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.sync.GitHubSync
import com.expdeath.coach.sync.HealthConnectSync
import com.expdeath.coach.ui.Avatar
import com.expdeath.coach.ui.BigButton
import com.expdeath.coach.ui.CIconButton
import com.expdeath.coach.ui.CapsText
import com.expdeath.coach.ui.Chevron
import com.expdeath.coach.ui.Chip
import com.expdeath.coach.ui.CoachScreen
import com.expdeath.coach.ui.CoachSheet
import com.expdeath.coach.ui.CoachTextField
import com.expdeath.coach.ui.ErrorBox
import com.expdeath.coach.ui.Fill
import com.expdeath.coach.ui.OutlineButton
import com.expdeath.coach.ui.QLabel
import com.expdeath.coach.ui.RowGroup
import com.expdeath.coach.ui.SectionHead
import com.expdeath.coach.ui.SettingsRow
import com.expdeath.coach.ui.StatusPill
import com.expdeath.coach.ui.Stepper
import com.expdeath.coach.ui.T
import com.expdeath.coach.ui.TabHeader
import com.expdeath.coach.ui.TextButtonC
import com.expdeath.coach.ui.Theme
import com.expdeath.coach.ui.Title
import com.expdeath.coach.ui.ToggleRow
import com.expdeath.coach.ui.VGap
import com.expdeath.coach.ui.exportsDir
import com.expdeath.coach.ui.openUrl
import com.expdeath.coach.ui.panel
import com.expdeath.coach.ui.sf
import com.expdeath.coach.ui.shareFile
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

private val titles = mapOf(
    "coach" to "AI Coach", "target" to "Weekly target", "watch" to "Health Connect", "gym" to "Plates & Bar",
    "sync" to "Cloud backup", "data" to "Your data", "account" to "Feedback", "about" to "About", "alerts" to "Alerts & reports",
    "delete" to "Delete account", "pro" to "COACH Pro",
)

private data class PrefRow(val key: String, val title: String, val sub: String)

private val prefRows = listOf(
    "Rest timer" to listOf(
        PrefRow("restSound", "Sound", "A chime when the rest ends"),
        PrefRow("restVibrate", "Vibration", "A buzz when the rest ends"),
        PrefRow("restNotify", "Notification", "Alert when the phone is locked or you're in another app"),
    ),
    "During a workout" to listOf(PrefRow("keepAwake", "Keep screen awake", "The screen stays on while you rest")),
    "AI reports" to listOf(
        PrefRow("weeklyReview", "Weekly review", "Written every Sunday from your week"),
        PrefRow("monthlyReport", "Monthly report", "Written in the first week of a new month"),
        PrefRow("debrief", "Post-workout debrief", "Two sentences from the coach after each session"),
    ),
)

/** Ports Settings.jsx — a profile card, then grouped rows (preferences,
 *  devices, data & account); each row opens its form in a sheet. Sign out
 *  and Delete account at the end. */
@Composable
fun SettingsScreen(app: AppState) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val account = Account.current()
    var detail by remember { mutableStateOf<String?>(null) }
    var confirmOut by remember { mutableStateOf(false) }
    var signOutMsg by remember { mutableStateOf("") }
    var eventCount by remember { mutableStateOf<Int?>(null) }
    var healthRequested by remember { mutableStateOf(HealthConnectSync.requested) }
    LaunchedEffect(Unit) {
        if (!Cloud.aiReady) detail = "coach"
        eventCount = Cloud.countEvents()
    }
    val settings = LocalStore.backup.aiSettings

    val coachStatus = when {
        !AIConsent.allowed -> "Off — nothing is sent to Google Gemini"
        Cloud.proActive -> "Ready · COACH Pro"
        Cloud.geminiKey.isEmpty() -> if (Cloud.canSetGeminiKey) "No API key yet — add one to start" else "No API key yet — ask Abhi"
        else -> if (settings.profile.isEmpty()) "Ready · add your profile" else "Ready · profile set"
    }
    val watchStatus = when {
        LocalStore.backup.health.any { it.date == Helpers.todayStr() } -> "Synced today"
        healthRequested -> "Connected · nothing today yet"
        else -> "Not connected"
    }
    val plateSummary = (Helpers.parsePlates(settings.plates) ?: Helpers.defaultPlates).joinToString(" / ") { Helpers.fmtKg(it) } + " kg plates"
    val alertsOn = prefRows.flatMap { it.second }.count { Prefs.isOn(it.key) }

    CoachScreen {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            TabHeader(app, "Settings")
            if (account != null) {
                Row(Modifier.fillMaxWidth().panel().clickable { app.sheet = AppSheet.Profile }.padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Box {
                        Avatar(app.displayName, 54.dp)
                        Box(Modifier.align(Alignment.BottomEnd).size(14.dp).clip(CircleShape).background(Theme.bgCard).padding(2.dp).clip(CircleShape).background(Theme.green))
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            T(app.displayName, Theme.body(18f, FontWeight.Bold), maxLines = 1)
                            if (account.admin) Icon(sf("checkmark.seal.fill"), null, tint = Theme.amberText, modifier = Modifier.size(16.dp))
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            StatusPill(if (account.admin) "Admin" else "Member", Theme.amberText, dot = false)
                            T(account.email, Theme.meta(12.5f), Theme.muted, maxLines = 1)
                        }
                    }
                    Box(Modifier.size(38.dp).clip(CircleShape).background(Theme.bgHigh), contentAlignment = Alignment.Center) {
                        Icon(sf("pencil"), null, tint = Theme.muted, modifier = Modifier.size(18.dp))
                    }
                }
            }
            Group("Preferences", "Coach logic") {
                RowGroup(listOf(
                    { SettingsRow("crown", "COACH Pro", if (Cloud.proActive) (if (Cloud.proTrial) "Active · free trial" else "Active") else "AI coach with no key to set up · 7 days free", if (Cloud.proActive) Theme.green else Theme.amberText, { detail = "pro" }) },
                    { SettingsRow("brain.head.profile", "AI Coach", coachStatus, onClick = { detail = "coach" }) },
                    { SettingsRow("bell.badge", "Alerts & reports", "$alertsOn of 7 on · rest timer, screen, AI reports", onClick = { detail = "alerts" }) },
                    { SettingsRow("target", "Weekly target", "Streak, consistency and the target bar", Theme.green, { detail = "target" }) { CapsText("${Dashboard.weeklyTarget(settings)}/wk", Theme.amberText, 14f) } },
                ))
            }
            Group("Devices & sensors", if (watchStatus.startsWith("Synced")) "All synced" else null) {
                RowGroup(listOf(
                    { SettingsRow("applewatch", "Watch & Health Connect", watchStatus, Theme.green, { detail = "watch" }) },
                    { SettingsRow("scalemass", "Barbell & plate setup", plateSummary, onClick = { detail = "gym" }) { CapsText("${Helpers.fmtKg(settings.barKg ?: Helpers.defaultBarKg)}kg bar", Theme.textBody, 13f) } },
                ))
            }
            Group("Data & account", "Cloud vault") {
                val rows = mutableListOf<@Composable () -> Unit>(
                    { SettingsRow("icloud", "Cloud backup", backupStatus(), Theme.green, { detail = "sync" }) },
                    { SettingsRow("square.and.arrow.up", "Export workout log", "CSV · JSON backup · import", onClick = { detail = "data" }) },
                )
                if (account != null) rows.add { SettingsRow("bubble.left.and.text.bubble.right", "Send feedback", "Straight to Abhi", onClick = { detail = "account" }) }
                rows.add { SettingsRow("info.circle", "About COACH", null, Theme.muted, { detail = "about" }) }
                RowGroup(rows)
            }
            if (account != null) {
                OutlineButton(if (confirmOut) "Tap again — this wipes this device" else "Sign out", Modifier.fillMaxWidth(), "rectangle.portrait.and.arrow.right", Theme.red) {
                    if (confirmOut) scope.launch {
                        val refusal = app.signOut()
                        if (refusal != null) { signOutMsg = refusal; confirmOut = false }
                    } else confirmOut = true
                }
                if (signOutMsg.isNotEmpty()) T(signOutMsg, Theme.body(13.5f), Theme.amberText)
                T("Signing out clears this device, including exercise photos. Your log stays in the cloud.", Theme.body(12.5f), Theme.dim)
                Row(Modifier.clickable { detail = "delete" }.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(sf("trash"), null, tint = Theme.red, modifier = Modifier.size(16.dp))
                    T("Delete account", Theme.body(14f, FontWeight.Medium), Theme.red)
                }
            }
            CapsText("COACH · v${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", Theme.dim, 11f, Modifier.fillMaxWidth(), align = TextAlign.Center)
        }
    }

    detail?.let { id ->
        CoachSheet({ detail = null }, full = true) {
            Row(Modifier.padding(horizontal = 20.dp).padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Title(titles[id] ?: "", 26f, tracking = 0.6f, modifier = Modifier.weight(1f))
                CIconButton("xmark", "Close") { detail = null }
            }
            Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                when (id) {
                    "coach" -> CoachSection()
                    "target" -> TargetSection { detail = null }
                    "watch" -> WatchSection(watchStatus) { healthRequested = HealthConnectSync.requested }
                    "gym" -> GymSection()
                    "sync" -> BackupSection()
                    "data" -> DataSection(app, eventCount)
                    "account" -> FeedbackSection()
                    "alerts" -> AlertsSection()
                    "delete" -> DeleteSection(app) { detail = null }
                    "pro" -> ProSection()
                    else -> {
                        T("COACH plans each session with Google Gemini from your check-in, history and recovery data. Your log lives in Firestore, backed up to your GitHub repo.", Theme.body(14f), Theme.muted)
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            TextButtonC("Privacy policy") { openUrl(ctx, Subscriptions.privacyURL) }
                            TextButtonC("Terms of service") { openUrl(ctx, Subscriptions.termsURL) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Group(title: String, note: String?, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHead(title, note, if (note == "All synced") Theme.green else Theme.muted, Modifier.padding(horizontal = 4.dp))
        content()
    }
}

private fun backupStatus(): String {
    val last = GitHubSync.lastSync()
    val cfg = GitHubSync.config()
    if (last?.status == "ok") {
        val at = try { Instant.parse(last.at) } catch (_: Exception) { null }
        if (at != null) return "Live sync · backed up " + DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withZone(ZoneId.systemDefault()).format(at)
    }
    if (last?.status == "error") return "Backup failed: ${last.message ?: ""}"
    return if (cfg.repo.isEmpty() || cfg.token.isEmpty()) "Live sync · no GitHub backup" else "Live sync · backup pending"
}

/** "✓ Saved" for two seconds. */
@Composable
private fun rememberFlash(): Pair<Boolean, () -> Unit> {
    var on by remember { mutableStateOf(false) }
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(tick) { if (tick > 0) { on = true; delay(2000); on = false } }
    return on to { tick += 1 }
}

@Composable
private fun SecretField(value: String, onChange: (String) -> Unit, placeholder: String) {
    var show by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        CoachTextField(value, onChange, placeholder, Modifier.weight(1f), password = !show, capitalization = KeyboardCapitalization.None, keyboard = if (show) KeyboardType.Ascii else KeyboardType.Password)
        TextButtonC(if (show) "Hide" else "Show", Theme.muted, Theme.meta(13f)) { show = !show }
    }
}

@Composable
private fun ColumnScope.CoachSection() {
    val account = Account.current()
    var key by remember { mutableStateOf(Cloud.geminiKey) }
    var ai by remember { mutableStateOf(LocalStore.backup.aiSettings) }
    var whatShared by remember { mutableStateOf(false) }
    val (saved, flash) = rememberFlash()
    ToggleRow(
        "Use the AI coach (Google Gemini)",
        if (AIConsent.allowed) "Sends your workouts, check-ins, chats and Health data to Google Gemini to plan sessions."
        else "Off — nothing goes to Gemini. You can still log workouts and run saved ones as written.",
        AIConsent.allowed,
    ) { on ->
        AIConsent.set(on)
        LocalStore.logEvent("ai_consent", mapOf("allowed" to JSONValue.Bool(on), "from" to JSONValue.Str("settings")))
    }
    if (AIConsent.allowed) {
        Row(Modifier.clickable { whatShared = !whatShared }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            T("What's shared", Theme.body(13.5f), Theme.amberText)
            Chevron(whatShared, Theme.amberText, 16.dp)
        }
        if (whatShared) for ((_, title, sub) in aiShared) T("$title — $sub", Theme.meta(12.5f), Theme.muted)
    }
    if (Cloud.proActive) {
        T("You're on COACH Pro — no key needed; the coach runs on COACH's server.", Theme.meta(12.5f), Theme.muted)
    }
    if (Cloud.canSetGeminiKey && !Cloud.proActive) {
        QLabel(if (account?.selfServe == true) "Your Gemini API key" else "Gemini API key (shared)")
        SecretField(key, { key = it }, "AIzaSy…")
        T("${if (account?.selfServe == true) "Only your account uses it." else "Shared by everyone you invited."} Free at aistudio.google.com/apikey.", Theme.body(13f), Theme.muted)
    }
    QLabel("About you")
    CoachTextField(ai.profile, { ai = ai.copy(profile = it.take(1500)) }, "e.g. Desk job, lower back gets tight", singleLine = false, minLines = 3)
    QLabel("Goals (one per line)")
    CoachTextField(ai.goals, { ai = ai.copy(goals = it.take(600)) }, "e.g.\nBench Press 80kg\n4 sessions a week", singleLine = false, minLines = 3)
    QLabel("Equipment")
    CoachTextField(ai.equipment, { ai = ai.copy(equipment = it.take(600)) }, "e.g. no cable tower, dumbbells to 40kg", singleLine = false, minLines = 3)
    QLabel("Base routine")
    CoachTextField(ai.routine, { ai = ai.copy(routine = it.take(4000)) }, "Empty = built-in Push/Pull/Legs", singleLine = false, minLines = 3)
    VGap(10.dp)
    BigButton(if (saved) "✓ Saved" else "Save coach setup") {
        val newKey = key.trim()
        if (Cloud.canSetGeminiKey && !Cloud.proActive && newKey != Cloud.geminiKey) {
            if (account?.selfServe == true) Cloud.setOwnGeminiKey(newKey) else Cloud.setSharedGeminiKey(newKey)
            LocalStore.logEvent("api_key_saved")
        }
        LocalStore.updateAISettings { s -> s.copy(profile = ai.profile.trim(), goals = ai.goals.trim(), equipment = ai.equipment.trim(), routine = ai.routine.trim()) }
        LocalStore.logEvent("ai_settings_saved")
        flash()
    }
}

@Composable
private fun ColumnScope.TargetSection(close: () -> Unit) {
    var target by remember { mutableIntStateOf(Dashboard.weeklyTarget(LocalStore.backup.aiSettings)) }
    QLabel("Sessions per week", "$target")
    Stepper(target, 1..14) { target = it }
    T("Your streak counts weeks that hit this, and Progress measures consistency against it.", Theme.body(13.5f), Theme.muted)
    VGap(10.dp)
    BigButton("Save target") {
        LocalStore.updateAISettings { it.copy(weeklyTarget = target) }
        LocalStore.logEvent("weekly_target_saved", mapOf("target" to JSONValue.Num(target.toDouble())))
        close()
    }
}

@Composable
private fun ColumnScope.WatchSection(watchStatus: String, onChanged: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf("") }
    T(watchStatus, Theme.meta(13.5f), if (watchStatus == "Synced today") Theme.green else Theme.muted)
    Cloud.stateValue("healthText-${Helpers.todayStr()}")?.string?.let { text ->
        val line = Stats.fmtHealthLine(Stats.parseHealthNumbers(text))
        T("Today: ${line.ifEmpty { text }}", Theme.body(14f), Theme.green)
    }
    GitHubSync.lastInbox()?.let { inbox ->
        T("Last delivery " + DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withZone(ZoneId.systemDefault()).format(Instant.ofEpochMilli(inbox.at.toLong())),
            Theme.meta(13f), Theme.muted)
    }
    when {
        HealthConnectSync.needsUpdate -> {
            T("Health Connect needs an update before COACH can read it.", Theme.body(13f), Theme.muted)
            BigButton("Update Health Connect") { openUrl(ctx, "market://details?id=com.google.android.apps.healthdata") }
        }
        !HealthConnectSync.isAvailable -> {
            T("Health Connect isn't available on this device. Install it from Google Play to read your watch data.", Theme.body(13f), Theme.muted)
            BigButton("Get Health Connect") { openUrl(ctx, "market://details?id=com.google.android.apps.healthdata") }
        }
        else -> {
            T(if (HealthConnectSync.requested) "Reads HRV, resting HR, sleep and more each time the app opens. Change access in Health Connect → App permissions."
              else "Read-only. COACH never writes to Health Connect. Your watch's app (Fitbit, Samsung Health, Garmin…) needs to share with Health Connect too.",
                Theme.body(13f), Theme.muted)
            BigButton(if (busy) "Reading Health Connect…" else if (HealthConnectSync.requested) "Read Health Connect now" else "Connect Health Connect", enabled = !busy) {
                scope.launch {
                    busy = true; msg = ""
                    try {
                        if (HealthConnectSync.grantedCount() == 0) HealthConnectSync.requestAccess()
                        HealthConnectSync.requested = true
                        onChanged()
                        val n = HealthConnectSync.sync()
                        msg = if (n > 0) "✓ Read $n day${if (n == 1) "" else "s"} from Health Connect."
                        else "Nothing new in Health Connect — if that's unexpected, check Health Connect → App permissions → COACH, and that your watch app shares its data."
                    } catch (e: Exception) {
                        msg = "Couldn't open Health Connect: ${e.message}"
                    }
                    busy = false
                }
            }
            if (msg.isNotEmpty()) T(msg, Theme.body(13.5f), Theme.amber)
        }
    }
}

@Composable
private fun ColumnScope.GymSection() {
    val s = LocalStore.backup.aiSettings
    var barKg by remember { mutableStateOf(Helpers.fmtKg(s.barKg ?: Helpers.defaultBarKg)) }
    var plates by remember { mutableStateOf(s.plates ?: Helpers.defaultPlates.joinToString(", ") { Helpers.fmtKg(it) }) }
    val (saved, flash) = rememberFlash()
    QLabel("Bar weight (kg)")
    CoachTextField(barKg, { v -> barKg = v.filter { it.isDigit() || it == '.' } }, keyboard = KeyboardType.Decimal)
    QLabel("Plates (kg, per pair)")
    CoachTextField(plates, { plates = it }, Helpers.defaultPlates.joinToString(", ") { Helpers.fmtKg(it) })
    VGap(10.dp)
    BigButton(if (saved) "✓ Saved" else "Save gym setup") {
        LocalStore.updateAISettings { it.copy(barKg = (parseDouble(barKg) ?: Helpers.defaultBarKg).coerceIn(0.0, 40.0), plates = plates.trim()) }
        LocalStore.logEvent("gym_settings_saved")
        flash()
    }
}

@Composable
private fun ColumnScope.BackupSection() {
    val scope = rememberCoroutineScope()
    val cfg = GitHubSync.config()
    var repo by remember { mutableStateOf(cfg.repo) }
    var token by remember { mutableStateOf(cfg.token) }
    var msg by remember { mutableStateOf("") }
    var syncing by remember { mutableStateOf(false) }
    val (saved, flash) = rememberFlash()
    T(backupStatus(), Theme.meta(13.5f), Theme.green)
    QLabel("GitHub backup")
    CoachTextField(repo, { repo = it }, "your-username/workout-data", capitalization = KeyboardCapitalization.None, keyboard = KeyboardType.Uri)
    SecretField(token, { token = it }, "github_pat_…")
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        BigButton(if (saved) "✓ Saved" else "Save settings", Modifier.weight(1f)) {
            GitHubSync.setConfig(token, repo)
            LocalStore.logEvent("sync_config_saved", mapOf("repo" to JSONValue.Str(repo)))
            flash()
        }
        BigButton(if (syncing) "Backing up…" else "Back up now", Modifier.weight(1f), enabled = !syncing) {
            scope.launch {
                syncing = true; msg = "Backing up…"
                msg = try {
                    val r = GitHubSync.syncNow(force = true)
                    if (r.status == GitHubSync.Status.Unconfigured) "Add your token and repo first, then Save." else "✓ Backed up — ${r.sessions} sessions on GitHub"
                } catch (e: Exception) { "Backup failed: ${e.message}" }
                syncing = false
            }
        }
    }
    if (msg.isNotEmpty()) T(msg, Theme.body(13.5f), Theme.amber)
    T("Fine-grained token, your data repo only, Contents: read & write.", Theme.body(13f), Theme.muted)
}

@Composable
private fun ColumnScope.DataSection(app: AppState, eventCount: Int?) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var msg by remember { mutableStateOf("") }
    var confirmClear by remember { mutableStateOf(false) }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            msg = try {
                val text = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) } ?: throw IllegalStateException("Couldn't read that file.")
                app.importBackup(text)
            } catch (e: Exception) { "Import failed: ${e.message}" }
        }
    }
    QLabel("Your data")
    T("${app.history.size} sessions · ${eventCount?.toString() ?: "…"} events", Theme.meta(13f), Theme.muted)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip("Export") { scope.launch { try { shareFile(ctx, app.exportBackupFile(exportsDir(ctx)), "application/json") } catch (e: Exception) { msg = "Export failed: ${e.message}" } } }
        Chip("Import") { importer.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) }
        Chip("Export CSV") { try { shareFile(ctx, app.exportCsvFile(exportsDir(ctx)), "text/csv") } catch (e: Exception) { msg = "Export failed: ${e.message}" } }
    }
    if (msg.isNotEmpty()) T(msg, Theme.body(13.5f), Theme.amber)
    VGap(6.dp)
    BigButton(if (confirmClear) "Tap again to confirm" else "Clear all history", danger = true) {
        if (confirmClear) { confirmClear = false; scope.launch { app.clearHistory() } } else confirmClear = true
    }
}

@Composable
private fun ColumnScope.FeedbackSection() {
    val scope = rememberCoroutineScope()
    var feedback by remember { mutableStateOf("") }
    var msg by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    QLabel("Send feedback to Abhi")
    CoachTextField(feedback, { feedback = it.take(2000) }, "Bugs, ideas, anything…", singleLine = false, minLines = 3, maxLines = 8)
    BigButton(if (sending) "Sending…" else "Send feedback", enabled = !sending && feedback.isNotBlank()) {
        scope.launch {
            sending = true; msg = ""
            try {
                GitHubSync.sendFeedback(feedback)
                LocalStore.logEvent("feedback_sent", mapOf("chars" to JSONValue.Num(feedback.length.toDouble())))
                feedback = ""
                msg = "✓ Sent — thank you!"
            } catch (e: Exception) { msg = e.message ?: "" }
            sending = false
        }
    }
    if (msg.isNotEmpty()) T(msg, Theme.body(13.5f), Theme.amberText)
}

@Composable
private fun ColumnScope.AlertsSection() {
    for ((group, rows) in prefRows) {
        QLabel(group)
        for (r in rows) {
            ToggleRow(r.title, r.sub, Prefs.isOn(r.key)) { on ->
                Prefs.set(r.key, on)
                LocalStore.logEvent("pref_changed", mapOf("key" to JSONValue.Str(r.key), "on" to JSONValue.Bool(on)))
            }
        }
    }
}

@Composable
private fun ColumnScope.DeleteSection(app: AppState, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    var typed by remember { mutableStateOf("") }
    var deleting by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf("") }
    T("This permanently deletes your COACH account and everything in it:", Theme.body(14.5f))
    for (line in listOf(
        "every logged session, set and personal record",
        "Health Connect / watch data, check-ins, coach chats and reports",
        "saved workouts, settings, your Gemini key and GitHub token",
        "your sign-in — signing in again starts a brand-new, empty account",
    )) T("• $line", Theme.meta(13f), Theme.muted)
    T("Your GitHub backup repository is yours and isn't touched — delete it on github.com if you want it gone too. You'll sign in once more to confirm it's you.", Theme.meta(12.5f), Theme.dim)
    QLabel("Type DELETE to confirm")
    CoachTextField(typed, { typed = it }, capitalization = KeyboardCapitalization.Characters)
    if (msg.isNotEmpty()) ErrorBox(msg)
    BigButton(if (deleting) "Deleting…" else "Delete my account", danger = true, enabled = !deleting && typed.trim() == "DELETE") {
        val act = CoachApplication.activity ?: return@BigButton
        scope.launch {
            deleting = true; msg = ""
            val err = app.deleteAccount(act)
            if (err != null) msg = err else close()
            deleting = false
        }
    }
}

private val proFeatures = listOf(
    "The AI coach with no API key to set up",
    "Session plans, check-ins, coach chat, reviews and “Build with coach”",
    "Up to 60 coach requests a day",
    "Everything else in COACH stays free",
)

/** Settings → COACH Pro (port of Pro.jsx / ProView.swift). Shows the
 *  subscription when active; otherwise the offer with price, free trial,
 *  auto-renewal, Restore, Terms and Privacy. */
@Composable
private fun ColumnScope.ProSection() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var offer by remember { mutableStateOf<Subscriptions.Offer?>(null) }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        offer = try { Subscriptions.monthlyOffer() } catch (_: Exception) { null }
        loading = false
    }
    if (Cloud.proActive) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            StatusPill(if (Cloud.proTrial) "Pro · free trial" else "Pro", Theme.green)
            if (Cloud.proStore.isNotEmpty()) CapsText(when (Cloud.proStore) { "play_store" -> "via Google Play"; "app_store" -> "via App Store"; else -> "via the website" }, Theme.muted, 11f)
        }
        val exp = Cloud.proExpires?.let { DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withZone(ZoneId.systemDefault()).format(Instant.ofEpochMilli(it.toLong())) }
        T("The AI coach runs on COACH's server — no key needed." + (exp?.let { " ${if (Cloud.proWillRenew) "Renews" else "Ends"} $it." } ?: ""), Theme.body(14.5f))
        T("Up to 60 coach requests a day.", Theme.meta(12.5f), Theme.muted)
        when (Cloud.proStore) {
            "play_store" -> OutlineButton("Manage or cancel") { CoachApplication.activity?.let { Subscriptions.manage(it) } }
            "app_store" -> T("Bought on the App Store — manage it on your iPhone (Settings → Apple ID → Subscriptions).", Theme.meta(12.5f), Theme.muted)
            else -> T("Bought on the website — manage it there (Settings → COACH Pro).", Theme.meta(12.5f), Theme.muted)
        }
        return
    }
    Column(
        Modifier.fillMaxWidth().clip(androidx.compose.foundation.shape.RoundedCornerShape(Theme.radius))
            .background(androidx.compose.ui.graphics.Brush.linearGradient(listOf(Theme.amberBg, androidx.compose.ui.graphics.Color.Transparent)))
            .border(1.dp, Theme.amber.copy(alpha = 0.35f), androidx.compose.foundation.shape.RoundedCornerShape(Theme.radius)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Title("COACH Pro", 26f)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            T(offer?.price ?: "$4.99", Theme.head(34f, FontWeight.Bold), Theme.amberText)
            CapsText("/ month", modifier = Modifier.padding(bottom = 6.dp))
            (offer?.trial ?: if (Subscriptions.enabled) null else "7 days")?.let { Box(Modifier.offset(y = (-4).dp)) { StatusPill("$it free", Theme.green, dot = false) } }
        }
        for (f in proFeatures) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(sf("checkmark.circle.fill"), null, tint = Theme.green, modifier = Modifier.size(18.dp))
            T(f, Theme.body(14f), Theme.textBody)
        }
    }
    val o = offer
    when {
        !Subscriptions.enabled -> T("Coming soon — you can keep using your own key meanwhile.", Theme.body(14f), Theme.amberText)
        o != null -> {
            BigButton(if (busy) "Opening Google Play…" else o.trial?.let { "Start $it free trial" } ?: "Subscribe for ${o.price}/month", enabled = !busy) {
                val act = CoachApplication.activity ?: return@BigButton
                scope.launch {
                    busy = true; msg = ""
                    try {
                        if (Subscriptions.purchase(act, o)) {
                            LocalStore.logEvent("pro_purchased", mapOf("via" to JSONValue.Str("play_store")))
                            msg = "Welcome to COACH Pro!"
                        }
                    } catch (_: Exception) { msg = "The purchase didn't go through — you weren't charged." }
                    busy = false
                }
            }
            T("${o.trial?.let { "Free for $it, then " } ?: ""}${o.price} a month. Renews automatically until you cancel in Google Play → Payments & subscriptions${if (o.trial == null) "" else " — cancel during the trial and you won't be charged"}.", Theme.meta(12f), Theme.muted)
        }
        loading -> androidx.compose.material3.CircularProgressIndicator(color = Theme.amber)
        else -> T("COACH Pro isn't available right now — try again later.", Theme.body(14f), Theme.muted)
    }
    if (msg.isNotEmpty()) T(msg, Theme.body(14f), Theme.amberText)
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        if (Subscriptions.enabled) TextButtonC("Restore purchases", style = Theme.body(13.5f)) {
            scope.launch {
                busy = true
                msg = try { Subscriptions.restore(); if (Cloud.proActive) "Restored — you're on Pro." else "No COACH Pro subscription found for this Google account." }
                catch (_: Exception) { "Couldn't reach Google Play — try again." }
                busy = false
            }
        }
        TextButtonC("Terms", style = Theme.body(13.5f)) { openUrl(ctx, Subscriptions.termsURL) }
        TextButtonC("Privacy", style = Theme.body(13.5f)) { openUrl(ctx, Subscriptions.privacyURL) }
    }
}
