package com.expdeath.coach.app

import android.app.Activity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.expdeath.coach.account.Account
import com.expdeath.coach.account.Subscriptions
import com.expdeath.coach.ai.Gemini
import com.expdeath.coach.models.Backup
import com.expdeath.coach.models.Checkin
import com.expdeath.coach.models.FinishInfo
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.MonthlyReportCache
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.models.WeeklyReviewCache
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.models.parseInt
import com.expdeath.coach.models.toJson
import com.expdeath.coach.persistence.AIConsent
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.persistence.Prefs
import com.expdeath.coach.persistence.isoNow
import com.expdeath.coach.stats.Dashboard
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.fmt
import com.expdeath.coach.stats.nowMs
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.stats.safe
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.sync.GitHubSync
import com.expdeath.coach.sync.HealthConnectSync
import com.expdeath.coach.sync.HealthIngest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.time.DayOfWeek
import java.time.LocalDate
import kotlin.coroutines.cancellation.CancellationException

/** The screen state machine in src/App.jsx — one case per screen. */
enum class Screen {
    Loading, Login, Home, CheckIn, Generating, Workout, Finish, History, HistoryDetail,
    AddPast, Records, Progress, Settings, Workouts, AIConsent,
}

/** App-wide sheets opened from the tab header. */
enum class AppSheet { Notifications, Profile, Search }

data class SyncInfo(val state: String, val at: Long? = null, val sessions: Int? = null, val message: String? = null)

/** Root app state — ports the state + effects in src/App.jsx (and
 *  AppState.swift) onto one observable object driving RootScreen's screen
 *  switch: the daily check-in → AI plan → workout → finish loop, sync
 *  orchestration, weekly/monthly report generation. Every mutation runs
 *  on the main thread — an AI reply finishing must never race a Firestore
 *  snapshot updating the same session list. */
class AppState(private val debugStart: Screen? = null) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var screen by mutableStateOf(Screen.Loading)
    var history by mutableStateOf<List<Session>>(emptyList())
    var todayPlan by mutableStateOf<Session?>(null)
    var chatOpen by mutableStateOf(false)
    var sheet by mutableStateOf<AppSheet?>(null)
    /** When the notification inbox was last opened (ms) — state `notifSeenAt`. */
    var notifSeenAt by mutableStateOf(0.0)
    /** Name chosen in Edit profile — state `displayName` (shared with the
     *  other apps); falls back to the Google account name. */
    var displayNameOverride by mutableStateOf<String?>(null)
    var detailSession by mutableStateOf<Session?>(null)
    var error by mutableStateOf("")
    var statusMsg by mutableStateOf("")
    var syncInfo by mutableStateOf<SyncInfo?>(null)
    var weeklyReview by mutableStateOf<WeeklyReviewCache?>(null)
    var monthlyReport by mutableStateOf<MonthlyReportCache?>(null)
    var loginError by mutableStateOf("")
    /** Bumped when account state changes (another device saved a workout…). */
    var stateTick by mutableIntStateOf(0)
    /** My workouts: where its back button returns to, and a workout to open straight away. */
    var workoutsFrom by mutableStateOf(Screen.Home)
    var workoutsOpenId by mutableStateOf<String?>(null)
    /** Search → Records: the exercise to select (changes each time). */
    var recordPick by mutableStateOf<RecordPick?>(null)
    data class RecordPick(val name: String, val at: Long = System.currentTimeMillis())

    var ci by mutableStateOf(Checkin())
    var fin by mutableStateOf(FinishInfo())

    val muscleGap: Stats.MuscleGap? get() = Stats.biggestMuscleGap(history)

    private var lastSyncAt = 0L
    private var periodicSync: Job? = null
    private var syncJob: Job? = null

    init {
        scope.launch { start() }
    }

    // ── Sign-in + boot ───────────────────────────────────────────────

    /** Restores the Google session and opens the account, or shows Login. */
    private suspend fun start() {
        if (Cloud.offline) { boot(); return }
        try {
            if (Account.resume() != null) boot() else screen = Screen.Login
        } catch (e: Exception) {
            if (e is Cloud.CloudError.Blocked) Cloud.signOut()
            loginError = message(e)
            screen = Screen.Login
        }
    }

    /** Login screen → Google → allowlist (sign-up on first visit) → account. */
    fun signIn(activity: Activity) = scope.launch {
        loginError = ""
        try {
            Account.signIn(activity)
            screen = Screen.Loading
            boot()
        } catch (e: Exception) {
            if (e is Cloud.CloudError.Cancelled || e is CancellationException) return@launch // closing Google's sheet isn't an error
            loginError = message(e)
        }
    }

    /** The Sign in with Apple button. */
    fun signInWithApple(activity: Activity) = scope.launch {
        loginError = ""
        try {
            Account.signInWithApple(activity)
            screen = Screen.Loading
            boot()
        } catch (e: Exception) {
            if (e is Cloud.CloudError.Cancelled || e is CancellationException) return@launch
            loginError = message(e)
        }
    }

    /** Settings → Delete account. Returns why it failed (nothing deleted
     *  when the re-sign-in is cancelled), or null — then we're at Login. */
    suspend fun deleteAccount(activity: Activity): String? {
        try {
            Subscriptions.stop()
            Account.deleteAccount(activity)
        } catch (e: Exception) {
            if (e is Cloud.CloudError.Cancelled) return "Cancelled — nothing was deleted."
            if (e is com.google.firebase.auth.FirebaseAuthInvalidUserException || e.message?.contains("USER_MISMATCH") == true) {
                return "That was a different account — sign in as the one you want to delete."
            }
            return e.message ?: e.toString()
        }
        history = emptyList()
        todayPlan = null
        weeklyReview = null
        monthlyReport = null
        screen = Screen.Login
        return null
    }

    /** The consent screen was answered — on to the app. */
    fun aiConsentAnswered(allowed: Boolean) {
        AIConsent.set(allowed)
        LocalStore.logEvent("ai_consent", mapOf("allowed" to JSONValue.Bool(allowed)))
        screen = if (Cloud.aiReady) Screen.Home else Screen.Settings
    }

    /** Signs out only once everything logged on this device is in the cloud
     *  — signing out clears the device's offline copy, so unsynced changes
     *  would be lost. Returns why it refused, or null. */
    suspend fun signOut(): String? {
        LocalStore.logEvent("signed_out")
        if (!Cloud.flushWrites()) {
            return "Some changes haven't reached the cloud yet (no connection?). Connect to the internet and try again — signing out now would lose them."
        }
        Subscriptions.stop()
        Account.signOut()
        history = emptyList()
        todayPlan = null
        weeklyReview = null
        monthlyReport = null
        screen = Screen.Login
        return null
    }

    private fun message(e: Exception): String =
        if (e is Cloud.CloudError) e.message ?: "" else "Couldn't open your account — check your connection and try again."

    suspend fun boot() {
        Account.current()?.accountId?.let { acct -> scope.launch { Subscriptions.start(acct) } }
        Cloud.onChange = { what -> cloudChanged(what) }
        loadActive()
        loadStateFromCloud()
        pruneOldHealthText()
        LocalStore.logEvent("app_open", mapOf("sessions" to JSONValue.Num(history.size.toDouble())))
        HealthIngest.reparseRows() // parser upgrades backfill old rows
        scope.launch {
            HealthConnectSync.sync() // today + any missing days of the last week
            runSync()
        }
        // and every 5 minutes while the app stays open (throttled like a foreground return)
        periodicSync?.cancel()
        periodicSync = scope.launch {
            while (true) {
                delay(5 * 60_000L)
                if (MainActivity.inForeground && Cloud.account != null) maybeSyncOnForeground()
            }
        }
        scope.launch { maybeWeeklyReview() }
        scope.launch { maybeMonthlyReport() }
        // asked once per account before anything goes to Gemini; then, with
        // no API key yet, Settings first
        screen = if (!AIConsent.answered) Screen.AIConsent else if (Cloud.aiReady) Screen.Home else Screen.Settings
        if (debugStart != null) {
            ci = buildDefaultCheckin() // what Home's "Start check-in" tap does
            screen = debugStart
        }
    }

    /** Deleted sessions are already excluded — LocalStore.hardDelete removes
     *  the row for real. */
    private fun loadActive() {
        history = LocalStore.backup.sessions.sortedBy { it.date + it.id }
    }

    private fun persistToday(t: Session?) {
        todayPlan = t
        Cloud.setState("today", t?.toJson())
    }

    // ── Cloud state (shared with the other apps, same keys) ──────────

    /** A field of a state object without decoding the whole thing — so a
     *  report another app wrote is recognised even if a field's type differs. */
    private fun stateField(key: String, field: String): String? = Cloud.stateValue(key)?.obj?.get(field)?.string

    private fun loadStateFromCloud() {
        val t = Cloud.stateValue("today")?.let { Session.fromJson(it) }
        todayPlan = if (t?.date == Helpers.todayStr()) t else null
        weeklyReview = Cloud.stateValue("weeklyReview")?.let { WeeklyReviewCache.fromJson(it) }
        monthlyReport = Cloud.stateValue("monthlyReport")?.let { MonthlyReportCache.fromJson(it) }
        Cloud.stateValue("notifSeenAt")?.number?.let { notifSeenAt = it }
        val n = Cloud.stateValue("displayName")?.string
        displayNameOverride = if (!n.isNullOrEmpty()) n else null
    }

    // ── Profile + notifications ──────────────────────────────────────

    val displayName: String
        get() = displayNameOverride ?: Account.current()?.let { it.name.ifEmpty { it.email } } ?: ""

    val firstName: String? get() = displayName.split(" ").firstOrNull { it.isNotEmpty() }

    fun setDisplayName(name: String) {
        val n = name.trim().take(40)
        displayNameOverride = n.ifEmpty { null }
        Cloud.setState("displayName", if (n.isEmpty()) null else JSONValue.Str(n))
    }

    val notifications: List<Dashboard.Notice> get() = Dashboard.notifications(history, weeklyReview, monthlyReport)

    val unreadNotifications: Int get() = notifications.count { it.at > notifSeenAt }

    fun markNotificationsSeen() {
        notifSeenAt = nowMs().rounded()
        Cloud.setState("notifSeenAt", JSONValue.Num(notifSeenAt))
    }

    /** Another device (or this one) changed the account. */
    private fun cloudChanged(what: String) {
        when (what) {
            "sessions" -> loadActive()
            "state" -> { loadStateFromCloud(); stateTick += 1 }
            "pro" -> stateTick += 1
        }
    }

    /** Drop single-use Watch text from earlier days (pruneOldHealth on the web). */
    private fun pruneOldHealthText() {
        val today = "healthText-${Helpers.todayStr()}"
        for (k in Cloud.stateKeys()) if (k.startsWith("healthText-") && k != today) Cloud.setState(k, null)
    }

    // ── Sync ─────────────────────────────────────────────────────────

    suspend fun runSync(replaceRemote: Boolean = false): GitHubSync.Result? {
        lastSyncAt = System.currentTimeMillis()
        syncInfo = SyncInfo("syncing")
        return try {
            val r = GitHubSync.syncNow(replaceRemote)
            if (r.status == GitHubSync.Status.Unconfigured) {
                syncInfo = null
                return r
            }
            if (r.changedLocal) loadActive()
            syncInfo = SyncInfo("ok", System.currentTimeMillis(), r.sessions)
            r
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            val msg = e.message ?: e.toString()
            LocalStore.logEvent("sync_failed", mapOf("message" to JSONValue.Str(msg)))
            syncInfo = SyncInfo("error", message = msg)
            syncJob?.cancel()
            syncJob = scope.launch {
                delay(20_000)
                runSync()
            }
            null
        }
    }

    /** Call when the app comes back to the foreground — throttled to 20s. */
    fun maybeSyncOnForeground() {
        if (System.currentTimeMillis() - lastSyncAt < 20_000) return
        scope.launch {
            HealthConnectSync.sync() // Health Connect → today's row (no-op until connected)
            runSync()
        }
    }

    /** Home's Start check-in / Quick start: fresh Health Connect numbers for
     *  today first, so the check-in is pre-filled with them. */
    suspend fun prepareCheckin(): Checkin {
        HealthConnectSync.sync(1)
        // nothing for today yet: Watch data copied to the clipboard fills it in
        // (the button tap that got us here is the user gesture, as on the web)
        if (todaysHealth().isNullOrEmpty()) {
            val clip = try {
                val cm = CoachApplication.context.getSystemService(android.content.ClipboardManager::class.java)
                cm?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(CoachApplication.context)?.toString()
            } catch (_: Exception) { null }
            if (HealthIngest.looksLikeHealthData(clip)) {
                val t = HealthIngest.storeToday(clip!!)
                LocalStore.logEvent("health_pasted_auto", mapOf("chars" to JSONValue.Num(t.length.toDouble())))
            }
        }
        return buildDefaultCheckin()
    }

    // ── Check-in defaults ────────────────────────────────────────────

    fun buildDefaultCheckin(): Checkin {
        // the saved-workout library: today's scheduled workout + add-ons
        val today = Workouts.scheduledFor()
        return Checkin(
            health = todaysHealth(),
            templateId = today.sessions.firstOrNull()?.id ?: "",
            addOnIds = today.addOns.map { it.id },
        )
    }

    // ── My workouts ──────────────────────────────────────────────────

    fun openWorkouts(from: Screen? = null, id: String? = null) {
        val f = from ?: screen
        workoutsFrom = if (f in listOf(Screen.Home, Screen.History, Screen.Progress, Screen.Records, Screen.Settings, Screen.CheckIn)) f else Screen.Home
        workoutsOpenId = id
        screen = Screen.Workouts
    }

    /** Start a saved workout: the check-in, with it already picked. */
    suspend fun startSavedWorkout(id: String) {
        val c = prepareCheckin().copy(templateId = id)
        ci = c
        error = ""
        screen = Screen.CheckIn
    }

    fun openRecord(name: String) {
        recordPick = RecordPick(name)
        screen = Screen.Records
    }

    /** Today's health row (Health Connect / the Watch-shortcut inbox)
     *  formatted for the check-in — todaysHealth() in healthIngest.js. */
    private fun todaysHealth(): String? {
        Cloud.stateValue("healthText-${Helpers.todayStr()}")?.string?.takeIf { it.isNotEmpty() }?.let { return it }
        return LocalStore.backup.health.firstOrNull { it.date == Helpers.todayStr() }?.raw
    }

    // ── AI plan generation ───────────────────────────────────────────

    fun generateWorkout(checkin: Checkin) = scope.launch {
        screen = Screen.Generating
        error = ""
        statusMsg = ""
        LocalStore.logEvent("checkin_submitted")

        val bodyKg = parseDouble(checkin.bodyKg)
        if (bodyKg != null && bodyKg > 20 && bodyKg < 300) {
            LocalStore.mergeHealth(HealthRow(date = Helpers.todayStr(), weightKg = bodyKg))
        }

        // a saved workout (yours or your trainer's) and today's add-ons
        val template = Workouts.get(checkin.templateId)
        val addOns = checkin.addOnIds.mapNotNull { Workouts.get(it) }

        try {
            var plan: Plan
            try {
                plan = Gemini.generateWorkoutPlan(checkin, history, template) { msg -> scope.launch { statusMsg = msg } }
                if (template != null && !template.adapt) plan = Workouts.enforceExact(plan, template, history)
                else if (template != null) plan = plan.copy(fromWorkout = Workouts.fromWorkout(template, true))
            } catch (e: Exception) {
                if (e is CancellationException || template == null) throw e
                // the coach is unreachable — a saved workout still runs, as written
                LocalStore.logEvent("generation_failed", mapOf("message" to JSONValue.Str(e.message ?: ""), "fallback" to JSONValue.Str("saved workout")))
                plan = Workouts.templateToPlan(template, history).copy(concerns = "Coach unavailable — weights are from your history.")
            }
            plan = Workouts.appendAddOns(plan, addOns, history)
            LocalStore.logEvent("plan_generated", mapOf(
                "sessionType" to JSONValue.Str(plan.sessionType), "title" to JSONValue.Str(plan.title),
                "estTimeMin" to JSONValue.Num(plan.estTimeMin.toDouble()),
                "workout" to (template?.let { JSONValue.Str(it.id) } ?: JSONValue.Null), "addOns" to JSONValue.Num(addOns.size.toDouble()),
            ))
            val log = plan.exercises.map { ex -> List(if (ex.sets > 0) ex.sets else 3) { SetLog() } }
            val now = System.currentTimeMillis()
            val t = Session(
                id = "${Helpers.todayStr()}#$now", date = Helpers.todayStr(), startedAt = now.toDouble(),
                checkin = checkin, plan = plan, log = log, finished = false,
            )
            persistToday(t)
            screen = Screen.Workout
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            LocalStore.logEvent("generation_failed", mapOf("message" to JSONValue.Str(e.message ?: "")))
            error = e.message?.takeIf { it.isNotEmpty() } ?: "Couldn't build today's session. Check Settings for your API key, then try again."
            screen = Screen.CheckIn
        }
    }

    // ── Weekly / monthly reports ─────────────────────────────────────

    private suspend fun maybeWeeklyReview() {
        if (!Prefs.isOn("weeklyReview")) return // switched off in Settings
        if (LocalDate.now(Helpers.zone).dayOfWeek != DayOfWeek.SUNDAY) return // Sundays only
        val thisMonday = Stats.mondayOf(Helpers.todayStr())
        if (stateField("weeklyReview", "week") == thisMonday) return // already done this week
        val summary = Stats.lastWeekSummary(history) ?: return
        if (!Cloud.aiReady) return
        val text = try { Gemini.generateWeeklyReview(summary) } catch (_: Exception) { return }
        val review = WeeklyReviewCache(thisMonday, nowMs().rounded(), text, summary.count, summary.progressions)
        Cloud.setState("weeklyReview", review.toJson())
        weeklyReview = review
    }

    private suspend fun maybeMonthlyReport() {
        if (!Prefs.isOn("monthlyReport")) return // switched off in Settings
        val now = LocalDate.now(Helpers.zone)
        if (now.dayOfMonth > 7) return // first week of the month only
        val prev = now.minusMonths(1)
        val ym = "${prev.year}-${fmt("%02d", prev.monthValue)}"
        if (stateField("monthlyReport", "month") == ym) return // already generated
        if (!Cloud.aiReady) return
        val sum = Stats.monthSummary(history, LocalStore.backup.health, ym) ?: return
        val text = try { Gemini.generateMonthlyReport(sum) } catch (_: Exception) { return }
        val report = MonthlyReportCache(ym, nowMs().rounded(), text, sum)
        Cloud.setState("monthlyReport", report.toJson())
        monthlyReport = report
    }

    // ── Mid-workout plan edits ───────────────────────────────────────

    private inline fun editToday(f: (Session) -> Session?) {
        val t = todayPlan ?: return
        val n = f(t) ?: return
        persistToday(n)
    }

    private fun <T> List<T>.replace(i: Int, f: (T) -> T): List<T> = mapIndexed { j, x -> if (j == i) f(x) else x }

    fun swapExercise(exI: Int) = editToday { t ->
        val ex = t.plan.exercises.safe(exI) ?: return@editToday null
        if (ex.alt.isEmpty()) return@editToday null
        LocalStore.logEvent("exercise_swapped", mapOf("from" to JSONValue.Str(ex.name), "to" to JSONValue.Str(ex.alt)))
        t.copy(plan = t.plan.copy(exercises = t.plan.exercises.replace(exI) { it.copy(name = ex.alt, alt = ex.name) }))
    }

    fun renameExercise(exI: Int, name: String) = editToday { t ->
        val ex = t.plan.exercises.safe(exI) ?: return@editToday null
        val clean = name.trim().take(60)
        if (clean.isEmpty() || clean.lowercase() == ex.name.trim().lowercase()) return@editToday null
        LocalStore.logEvent("exercise_swapped_custom", mapOf("from" to JSONValue.Str(ex.name), "to" to JSONValue.Str(clean)))
        t.copy(plan = t.plan.copy(exercises = t.plan.exercises.replace(exI) { it.copy(name = clean, alt = ex.name, suggestedWeight = "") }))
    }

    fun removeExercise(exI: Int) = editToday { t ->
        val ex = t.plan.exercises.safe(exI) ?: return@editToday null
        LocalStore.logEvent("exercise_removed", mapOf("name" to JSONValue.Str(ex.name)))
        t.copy(
            plan = t.plan.copy(
                exercises = t.plan.exercises.filterIndexed { i, _ -> i != exI },
                estTimeMin = maxOf(t.plan.estTimeMin - 6, 15),
            ),
            log = if (exI < t.log.size) t.log.filterIndexed { i, _ -> i != exI } else t.log,
        )
    }

    /** Removing only pops the last row while it's still empty — logged work
     *  can't be deleted this way. */
    fun adjustSets(exI: Int, delta: Int) = editToday { t ->
        var rows = t.log.safe(exI) ?: return@editToday null
        if (rows.isEmpty()) return@editToday null
        rows = when {
            delta < 0 && rows.size > 1 && !rows.last().isLogged -> rows.dropLast(1)
            delta > 0 -> rows + SetLog()
            else -> return@editToday null
        }
        LocalStore.logEvent("sets_adjusted", mapOf("delta" to JSONValue.Num(delta.toDouble()), "sets" to JSONValue.Num(rows.size.toDouble())))
        val n = rows.size
        t.copy(
            log = t.log.replace(exI) { rows },
            plan = if (exI < t.plan.exercises.size) t.plan.copy(exercises = t.plan.exercises.replace(exI) { it.copy(sets = n) }) else t.plan,
        )
    }

    fun updateSet(exI: Int, setI: Int, weight: String? = null, reps: String? = null, time: String? = null, dist: String? = null, done: Boolean? = null, effort: String? = null) =
        editToday { t ->
            val row = t.log.safe(exI) ?: return@editToday null
            var s = row.safe(setI) ?: return@editToday null
            // clamp, don't reject — same sanitation as the web app's updateSet
            if (weight != null) s = s.copy(weight = Helpers.cleanWeight(weight))
            if (reps != null) s = s.copy(reps = Helpers.cleanReps(reps))
            if (time != null) s = s.copy(time = Helpers.cleanTime(time))
            if (dist != null) s = s.copy(dist = Helpers.cleanDist(dist))
            if (done != null) s = s.copy(done = done)
            if (effort != null) s = s.copy(effort = effort)
            val ns = s
            t.copy(log = t.log.replace(exI) { r -> r.replace(setI) { ns } })
        }

    /** AI "make it harder" upgrade applied to today's plan.
     *  add = new exercise · extraSet = +1 set · replace = harder variation */
    fun applyHarder(opt: Gemini.IntensifyOption): Boolean {
        var t = todayPlan ?: return false
        fun findIndex(name: String) = t.plan.exercises.indexOfFirst { it.name.trim().lowercase() == name.trim().lowercase() }.takeIf { it >= 0 }
        when (opt.kind) {
            "add" -> {
                val ex = opt.exercise?.takeIf { it.name.isNotEmpty() } ?: return false
                t = t.copy(plan = t.plan.copy(exercises = t.plan.exercises + ex), log = t.log + listOf(List(if (ex.sets > 0) ex.sets else 3) { SetLog() }))
            }
            "extraSet" -> {
                val i = findIndex(opt.target) ?: return false
                val sets = maxOf(t.plan.exercises[i].sets, t.log.safe(i)?.size ?: 0) + 1
                t = t.copy(
                    plan = t.plan.copy(exercises = t.plan.exercises.replace(i) { it.copy(sets = sets) }),
                    log = t.log.replace(i) { it + SetLog() },
                )
            }
            "replace" -> {
                val ex = opt.exercise?.takeIf { it.name.isNotEmpty() } ?: return false
                val i = findIndex(opt.target) ?: return false
                val kept = (t.log.safe(i) ?: emptyList()).filter { it.isLogged }
                val n = maxOf(if (ex.sets > 0) ex.sets else 3, kept.size)
                t = t.copy(
                    plan = t.plan.copy(exercises = t.plan.exercises.replace(i) { ex }),
                    log = t.log.replace(i) { kept + List(n - kept.size) { SetLog() } },
                )
            }
            else -> return false
        }
        t = t.copy(plan = t.plan.copy(estTimeMin = t.plan.estTimeMin + if (opt.kind == "extraSet") 3 else 6))
        LocalStore.logEvent("plan_intensified", mapOf("kind" to JSONValue.Str(opt.kind), "target" to JSONValue.Str(opt.target)))
        persistToday(t)
        return true
    }

    // ── Finish / cancel ──────────────────────────────────────────────

    fun finishSession() = scope.launch {
        var t = todayPlan ?: return@launch
        val durationMin: Int? = if (t.startedAt > 0) minOf(((nowMs() - t.startedAt) / 60000).rounded().toInt(), 240) else null
        t = t.copy(
            finished = true,
            fin = fin,
            durationMin = if (durationMin != null && durationMin >= 10) durationMin else t.durationMin,
            log = t.log.map { ex -> ex.map { s -> if (s.weight.isNotEmpty() || s.reps.isNotEmpty() || s.time.isNotEmpty() || s.dist.isNotEmpty()) s.copy(done = true) else s } },
        )
        val prior = history.filter { it.id != t.id }
        val prs = Stats.detectPRs(t, prior)
        if (prs.isNotEmpty()) t = t.copy(prs = prs)

        history = prior + t
        LocalStore.upsert(t)
        persistToday(t)
        LocalStore.logEvent("session_finished", mapOf(
            "date" to JSONValue.Str(t.date), "sessionType" to JSONValue.Str(t.plan.sessionType),
            "rpe" to JSONValue.Num(fin.rpe.toDouble()), "prs" to JSONValue.Num(prs.size.toDouble()),
        ))
        screen = Screen.Home
        scope.launch { runSync() }

        // Background: coach debrief on the finished session (unless switched off)
        if (!Prefs.isOn("debrief")) return@launch
        val text = try { Gemini.generateDebrief(t, prior) } catch (_: Exception) { return@launch }
        // the session may have been edited (or deleted) while the AI was
        // writing — attach the debrief to the latest copy only
        val latest = LocalStore.backup.sessions.firstOrNull { it.id == t.id }?.copy(debrief = text) ?: return@launch
        LocalStore.upsert(latest)
        if (todayPlan?.id == latest.id) persistToday(latest)
        val i = history.indexOfFirst { it.id == latest.id }
        if (i >= 0) history = history.replace(i) { latest }
        scope.launch { runSync() }
    }

    fun cancelSession() {
        LocalStore.logEvent("session_cancelled")
        persistToday(null)
        screen = Screen.Home
    }

    // ── Quick cardio (bypasses check-in and the AI entirely) ─────────

    /** `date` backdates the log (forgot to log yesterday's run); null = today. */
    fun logQuickCardio(kind: String, time: String, dist: String, rpe: Int, date: String? = null) {
        val day = date ?: Helpers.todayStr()
        val (sessionType, name) = when (kind) {
            "run" -> "Run" to "Running"
            "cycle" -> "Cycle" to "Cycling"
            "walk" -> "Walk" to "Brisk walk"
            "hike" -> "Hike" to "Hike"
            else -> return
        }
        val durationMin = parseInt(time)
        val plan = Plan(
            sessionType = sessionType,
            title = if (dist.isNotEmpty()) "${dist}km ${sessionType.lowercase()}" else sessionType,
            recoveryScore = null,
            reasoning = "Logged directly from Home — not part of an AI-generated plan.",
            exercises = listOf(Plan.Exercise(name = name, sets = 1, rpe = if (rpe > 0) rpe.toString() else "")),
            estTimeMin = durationMin ?: 0,
        )
        val now = System.currentTimeMillis()
        val t = Session(
            id = "$day#$now", date = day, startedAt = now.toDouble(),
            checkin = null, plan = plan, log = listOf(listOf(SetLog(done = true, time = time, dist = dist))),
            finished = true, fin = FinishInfo(rpe = if (rpe > 0) rpe else 6), durationMin = durationMin,
        )
        // may be backdated — keep history in date order
        history = (history + t).sortedBy { it.date + it.id }
        LocalStore.upsert(t)
        LocalStore.logEvent("quick_cardio_logged", mapOf("kind" to JSONValue.Str(kind), "date" to JSONValue.Str(day)))
        scope.launch { runSync() }
    }

    // ── Backup export / import (Settings → Your data) ────────────────

    /** exportAll() in src/db/db.js: the account as one JSON file. */
    suspend fun exportBackupFile(dir: File): File {
        val b = LocalStore.backup.copy(
            events = Cloud.allEvents(), workouts = Workouts.rawAll(), prefs = Prefs.raw,
            version = 4,
        ).let { it.copy(sessions = it.sessions.sortedBy { s -> s.date + s.id }, health = it.health.sortedBy { h -> h.date }) }
        val o = LinkedHashMap(b.toJson().v)
        o["exportedAt"] = JSONValue.Str(isoNow())
        val f = File(dir, "coach-backup-${Helpers.todayStr()}.json")
        f.writeText(JSONValue.Obj(o).toJsonString())
        LocalStore.logEvent("data_exported", mapOf("sessions" to JSONValue.Num(b.sessions.size.toDouble())))
        return f
    }

    /** The spreadsheet-friendly export: one row per logged set. */
    fun exportCsvFile(dir: File): File {
        fun esc(v: String) = if (v.any { it == ',' || it == '"' || it == '\n' }) "\"${v.replace("\"", "\"\"")}\"" else v
        val rows = mutableListOf(listOf("date", "session_type", "exercise", "set", "weight_kg", "reps", "effort", "session_rpe", "pain", "duration_min"))
        for (s in history) {
            s.plan.exercises.forEachIndexed { i, ex ->
                (s.log.safe(i) ?: emptyList()).forEachIndexed { si, set ->
                    if (set.done || set.weight.isNotEmpty() || set.reps.isNotEmpty()) {
                        rows.add(listOf(s.date, s.plan.sessionType, ex.name, "${si + 1}", set.weight, set.reps, set.effort,
                            s.fin?.rpe?.toString() ?: "", s.fin?.pain ?: "", s.durationMin?.toString() ?: ""))
                    }
                }
            }
        }
        val f = File(dir, "coach-sessions-${Helpers.todayStr()}.csv")
        f.writeText(rows.joinToString("\n") { r -> r.joinToString(",") { esc(it) } })
        LocalStore.logEvent("data_exported_csv", mapOf("rows" to JSONValue.Num((rows.size - 1).toDouble())))
        return f
    }

    /** importAll() in src/db/db.js: the backup becomes the account's data
     *  (sessions/health replaced, events + deletions added, AI settings only
     *  if the backup's are newer), then GitHub is backed up. */
    suspend fun importBackup(text: String): String {
        val root = JSONValue.parse(text)?.obj
        if (root == null || root["sessions"] !is JSONValue.Arr) throw IllegalArgumentException("Not a valid COACH backup file.")
        val b = GitHubSync.normalizeBackup(Backup.fromJson(JSONValue.Obj(root)) ?: throw IllegalArgumentException("Not a valid COACH backup file."))
        val skipped = Cloud.replaceData(b)
        if (b.aiSettings.updatedAt > LocalStore.backup.aiSettings.updatedAt) Cloud.putAISettings(b.aiSettings)
        // saved workouts: add missing ones, newer copies win (replaceAll in src/db/db.js)
        for (raw in b.workouts) {
            val o = raw.obj ?: continue
            val id = o["id"]?.string?.takeIf { it.isNotEmpty() } ?: continue
            val mine = Cloud.stateValue("workout-$id")?.obj?.get("updatedAt")?.number ?: -1.0
            val theirs = o["updatedAt"]?.number ?: 0.0
            if (theirs > mine) Cloud.setState("workout-$id", raw)
        }
        if (b.prefs != null && Prefs.raw == null) Cloud.setState("prefs", b.prefs)
        LocalStore.logEvent("data_imported", mapOf("sessions" to JSONValue.Num(b.sessions.size.toDouble()), "events" to JSONValue.Num(b.events.size.toDouble())))
        scope.launch { runSync(replaceRemote = true) } // restored backup becomes the GitHub copy too
        return "Restored ${b.sessions.size} sessions from backup${if (skipped > 0) " ($skipped kept: newer or deleted here)" else ""}."
    }

    // ── Past workout (typed in after the fact) ───────────────────────

    /** addPastSession() in src/App.jsx: a finished session dated the day it
     *  happened — no check-in, no AI — with PRs vs. what was logged before. */
    fun addPastSession(date: String, sessionType: String, exercises: List<Plan.Exercise>, log: List<List<SetLog>>, durationMin: Int?, rpe: Int, feedback: String) {
        val plan = Plan(
            sessionType = sessionType, title = sessionType, recoveryScore = null,
            reasoning = "Added afterwards from the Log — not part of an AI-generated plan.",
            exercises = exercises, estTimeMin = durationMin ?: 0,
        )
        var t = Session(
            id = "$date#${System.currentTimeMillis()}", date = date, startedAt = 0.0,
            checkin = null, plan = plan, log = log, finished = true,
            fin = FinishInfo(rpe, "", feedback), durationMin = durationMin, backfilled = true,
        )
        val prs = Stats.detectPRs(t, history.filter { it.date < date })
        if (prs.isNotEmpty()) t = t.copy(prs = prs)
        history = (history + t).sortedBy { it.date + it.id }
        LocalStore.upsert(t)
        LocalStore.logEvent("past_session_added", mapOf(
            "date" to JSONValue.Str(date), "sessionType" to JSONValue.Str(sessionType),
            "exercises" to JSONValue.Num(exercises.size.toDouble()),
            "setsDone" to JSONValue.Num(log.flatten().size.toDouble()), "prs" to JSONValue.Num(prs.size.toDouble()),
        ))
        screen = Screen.History
        scope.launch { runSync() }
    }

    // ── History management ───────────────────────────────────────────

    suspend fun clearHistory() {
        history = emptyList()
        persistToday(null)
        LocalStore.clearSessions()
        LocalStore.logEvent("history_cleared")
        // back up now so the GitHub copy matches right away
        runSync(replaceRemote = true)
    }

    suspend fun deleteSession(s: Session) {
        LocalStore.hardDelete(s.id)
        history = history.filter { it.id != s.id }
        if (todayPlan?.id == s.id) persistToday(null)
        LocalStore.logEvent("session_deleted", mapOf("id" to JSONValue.Str(s.id)))
        runSync()
    }

    suspend fun updateSession(s: Session) {
        LocalStore.upsert(s)
        val i = history.indexOfFirst { it.id == s.id }
        if (i >= 0) history = history.replace(i) { s }
        if (todayPlan?.id == s.id) persistToday(s)
        LocalStore.logEvent("session_edited", mapOf("id" to JSONValue.Str(s.id)))
        runSync()
    }

    fun reloadFromDb() = loadActive()
}
