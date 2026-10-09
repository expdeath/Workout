package com.expdeath.coach.sync

import java.util.Base64
import com.expdeath.coach.models.Backup
import com.expdeath.coach.models.DeletedId
import com.expdeath.coach.models.Event
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.models.jobj
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.persistence.Prefs
import com.expdeath.coach.persistence.isoNow
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.nowMs
import kotlinx.coroutines.delay
import java.net.URLEncoder
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.max

/** GitHub backup + Watch inbox — port of src/db/sync.js (GitHubSync.swift).
 *
 *  Firestore (Cloud.kt) is the live database and syncs devices on its own.
 *  GitHub keeps two jobs:
 *    1. Backup: the full account as coach-backup.json + a human-readable
 *       README log, in the account's private data repo. Pushed when data
 *       changed (≥10 min apart) or daily.
 *    2. Watch inbox: the Gym Check-in Shortcut PUTs files into
 *       health-inbox/; every sync drains them into Firestore.
 *  The repo + a fine-grained token live in accounts/{id}.github, shared by
 *  every device of the account — and by the web and iPhone apps. */
object GitHubSync {
    data class Config(val token: String, val repo: String)

    private const val API = "https://api.github.com"
    private const val FILE = "coach-backup.json"
    private const val README = "README.md"
    private const val BRANCH = "main"
    private const val INBOX = "health-inbox"
    private const val MIN_GAP_SEC = 10 * 60.0
    private const val DAY_SEC = 24 * 60 * 60.0

    // ── Config (accounts/{id}.github) ────────────────────────────

    fun config(): Config {
        val g = Cloud.github
        return Config(g["token"]?.string ?: "", g["repo"]?.string ?: "")
    }

    fun setConfig(token: String, repo: String) {
        val cleanRepo = repo.trim().replace("https://github.com/", "").trim('/')
        Cloud.updateGithub(mapOf("token" to JSONValue.Str(token.trim()), "repo" to JSONValue.Str(cleanRepo)))
    }

    /** Last backup attempt — shared by every device of the account. */
    data class LastSyncInfo(val at: String, val status: String, val sessions: Int?, val message: String?, val fingerprint: String?)

    fun lastSync(): LastSyncInfo? {
        val o = Cloud.github["lastBackup"]?.obj ?: return null
        return LastSyncInfo(
            o["at"]?.string ?: "", o["status"]?.string ?: "", o["sessions"]?.number?.toInt(),
            o["message"]?.string, o["fingerprint"]?.string,
        )
    }

    private fun setLastSync(info: Map<String, JSONValue>) {
        val cur = LinkedHashMap(Cloud.github["lastBackup"]?.obj ?: emptyMap())
        cur["at"] = JSONValue.Str(isoNow())
        cur.putAll(info)
        Cloud.updateGithub(mapOf("lastBackup" to JSONValue.Obj(cur)))
    }

    data class LastInboxInfo(val at: Double, val files: Int)

    /** When the Watch inbox was last drained — account state `lastInbox`. */
    fun lastInbox(): LastInboxInfo? {
        val o = Cloud.stateValue("lastInbox")?.obj ?: return null
        val at = o["at"]?.number ?: return null
        val files = o["files"]?.number ?: return null
        return LastInboxInfo(at, files.toInt())
    }

    sealed class SyncError(message: String) : Exception(message) {
        class TokenRejected : SyncError("GitHub token rejected — check it in Settings (needs Contents read/write on your data repo).")
        class Http(status: Int, body: String) : SyncError("GitHub error $status: $body")
        class Message(m: String) : SyncError(m)
    }

    // ── GitHub API helpers ──────────────────────────────────────

    private suspend fun request(cfg: Config, path: String, method: String = "GET", body: JSONValue? = null, accept: String = "application/vnd.github+json"): HttpResponse =
        Http.request(
            API + path, method,
            mapOf("Authorization" to "Bearer ${cfg.token}", "Accept" to accept, "X-GitHub-Api-Version" to "2022-11-28"),
            body?.toJsonString()?.toByteArray(),
        )

    /** Blob shas of our files on the remote (backup, readme), or nulls. */
    private suspend fun remoteShas(cfg: Config): Pair<String?, String?> {
        val r = request(cfg, "/repos/${cfg.repo}/git/trees/$BRANCH")
        if (r.status == 404 || r.status == 409) return null to null
        if (r.status != 200) throw SyncError.Http(r.status, r.text)
        val tree = JSONValue.parse(r.text)?.obj?.get("tree")?.array ?: emptyList()
        fun shaOf(p: String) = tree.firstOrNull { it.obj?.get("path")?.string == p }?.obj?.get("sha")?.string
        return shaOf(FILE) to shaOf(README)
    }

    private fun commitMessage(backup: Backup): String {
        val active = backup.sessions.filter { !it.deleted }
        val last = active.lastOrNull() ?: return "sync: no sessions yet"
        return "sync: ${active.size} sessions · latest ${last.date} ${last.plan.sessionType}".trim()
    }

    private fun b64(str: String): String = Base64.getEncoder().encodeToString(str.toByteArray())

    private fun putBody(message: String, content: String, sha: String?): JSONValue = jobj {
        put("message", message); put("content", content); put("branch", BRANCH); putIfPresent("sha", sha)
    }

    /** Overwrite coach-backup.json — Firestore is the truth, so no merge.
     *  A sha race with another device of the account just retries. */
    private suspend fun pushRemote(cfg: Config, backup: Backup) {
        val json = backup.toJson().toJsonString(pretty = true, sortKeys = true)
        repeat(3) {
            val sha = remoteShas(cfg).first
            val r = request(cfg, "/repos/${cfg.repo}/contents/$FILE", "PUT", putBody(commitMessage(backup), b64(json), sha))
            if (r.status == 200 || r.status == 201) return
            if (r.status == 401 || r.status == 403) throw SyncError.TokenRejected()
            if (r.status != 409 && r.status != 422) throw SyncError.Http(r.status, r.text)
            delay(800)
        }
        throw SyncError.Message("Backup conflict — another device is backing up right now. It will retry later.")
    }

    // ── Repo README: human-readable training log for GitHub ────

    fun buildReadme(sessions: List<Session>): String {
        val active = sessions.filter { !it.deleted && it.date.isNotEmpty() }
        val (thisWeek, streak) = Stats.weekStats(active)
        val rows = active.takeLast(20).reversed().joinToString("\n") { s ->
            val vol = Stats.sessionVolume(s)
            val best = s.plan.exercises.mapIndexedNotNull { i, ex ->
                val sets = (s.log.getOrNull(i) ?: emptyList()).filter { it.isLogged }
                val top = sets.maxByOrNull { com.expdeath.coach.models.parseDouble(it.weight) ?: 0.0 } ?: return@mapIndexedNotNull null
                "${ex.name} ${top.weight.ifEmpty { "?" }}×${top.reps.ifEmpty { "?" }}"
            }.joinToString(" · ")
            val volStr = if (vol > 0) "$vol kg" else "—"
            "| ${Helpers.fmtDate(s.date)} | ${s.plan.sessionType.ifEmpty { "?" }} | ${s.fin?.rpe?.toString() ?: "—"} | $volStr | ${best.ifEmpty { "—" }} |"
        }
        val stamp = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm").withZone(ZoneOffset.UTC).format(Instant.now())
        return """
            |# 🏋️ COACH — Training Data
            |
            |Auto-synced by the [COACH app](https://expdeath.github.io/Workout/). Don't edit by hand — the app owns this repo.
            |
            |**${active.size} sessions** · **$thisWeek this week** · **$streak-week streak** (≥3/week)
            |
            |## Recent sessions
            |
            || Date | Session | RPE | Volume | Top sets |
            ||---|---|---|---|---|
            |${rows.ifEmpty { "| — | — | — | — | — |" }}
            |
            |<sub>Full data (including the event log) lives in [`coach-backup.json`](./coach-backup.json). Updated $stamp UTC.</sub>
            |
        """.trimMargin()
    }

    private suspend fun pushReadme(cfg: Config, sessions: List<Session>) {
        try {
            val sha = remoteShas(cfg).second
            request(cfg, "/repos/${cfg.repo}/contents/$README", "PUT", putBody("docs: update training log", b64(buildReadme(sessions)), sha))
        } catch (_: Exception) {
            // cosmetic — never fatal
        }
    }

    // ── Beta feedback (accounts/{id}/feedback in Firestore) ──────

    suspend fun sendFeedback(text: String) {
        val body = text.trim()
        if (body.isEmpty()) throw SyncError.Message("Write something first.")
        try {
            Cloud.sendFeedback(body.take(2000))
        } catch (_: Exception) {
            throw SyncError.Message("Couldn't send — check your connection and try again.")
        }
    }

    // ── Health inbox ─────────────────────────────────────────────
    // The Watch shortcut PUTs one small file per run into health-inbox/.
    // Every sync drains it: parse → merge into the health rows → delete
    // the file. Produces the same rows as the other apps' drain, so it
    // doesn't matter which app gets to a file first.

    private data class InboxNums(var hrv: Double? = null, var rhr: Double? = null, var steps: Double? = null, var sleepH: Double? = null, var weightKg: Double? = null)

    /** File body → (text, structured numbers if the payload was JSON with
     *  recognizable fields). */
    private fun parseInboxFile(body: String): Pair<String, InboxNums?> {
        val t = body.trim()
        if (!t.startsWith("{")) return t to null
        val obj = JSONValue.parse(t)?.obj ?: return t to null
        obj["health"]?.string?.let { return it to null }
        val nums = InboxNums()
        var any = false
        fun num(key: String): Double? = obj[key]?.number?.takeIf { it > 0 }
        num("hrv")?.let { nums.hrv = it; any = true }
        num("rhr")?.let { nums.rhr = it; any = true }
        num("steps")?.let { nums.steps = it; any = true }
        num("sleepH")?.let { nums.sleepH = it; any = true }
        num("weightKg")?.let { nums.weightKg = it; any = true }
        return t to (if (any) nums else null)
    }

    /** Drains health-inbox/ into Firestore, then deletes each file from the
     *  repo. Per-file failures are skipped (retried next sync). Returns the
     *  number of files ingested. */
    suspend fun consumeHealthInbox(cfg: Config = config()): Int {
        if (cfg.token.isEmpty() || cfg.repo.isEmpty()) return 0
        val list = request(cfg, "/repos/${cfg.repo}/contents/$INBOX?ref=$BRANCH")
        if (list.status == 404) return 0 // no inbox folder yet
        if (list.status != 200) throw SyncError.Http(list.status, list.text)
        val files = JSONValue.parse(list.text)?.array ?: return 0

        var ingested = 0
        for (f in files.mapNotNull { it.obj }.filter { it["type"]?.string == "file" }.take(30)) {
            val name = f["name"]?.string ?: continue
            val sha = f["sha"]?.string ?: continue
            val encodedName = URLEncoder.encode(name, "UTF-8").replace("+", "%20")
            try {
                val raw = request(cfg, "/repos/${cfg.repo}/contents/$INBOX/$encodedName?ref=$BRANCH", accept = "application/vnd.github.raw+json")
                if (raw.status != 200) continue
                ingestInboxFile(name, raw.text)
                try {
                    request(cfg, "/repos/${cfg.repo}/contents/$INBOX/$encodedName", "DELETE",
                        jobj { put("message", "chore: ingest $name"); put("sha", sha); put("branch", BRANCH) })
                } catch (_: Exception) {}
                ingested += 1
            } catch (_: Exception) {
                continue // retried next sync
            }
        }
        if (ingested > 0) {
            Cloud.setState("lastInbox", jobj { put("at", nowMs()); put("files", ingested) })
        }
        return ingested
    }

    /** One inbox file → today's check-in text (if it's today's) + the day's
     *  health row. Internal for tests. */
    fun ingestInboxFile(name: String, body: String) {
        val (text, nums) = parseInboxFile(body)
        val date = Regex("""\d{4}-\d{2}-\d{2}""").find(name)?.value ?: Helpers.todayStr()
        val asText = if (nums != null) {
            listOfNotNull(
                nums.hrv?.let { "HRV ${fmtNum(it)} ms" },
                nums.rhr?.let { "RHR ${fmtNum(it)}" },
                nums.sleepH?.let { "Sleep ${fmtNum(it)}h" },
                nums.weightKg?.let { "Weight ${fmtNum(it)}kg" },
                nums.steps?.let { "Steps ${fmtNum(it)}" },
            ).joinToString(" · ")
        } else text
        if (asText.isEmpty()) return
        // today's raw text pre-fills the check-in (healthText-<date>, as on the web)
        if (date == Helpers.todayStr()) Cloud.setState("healthText-$date", JSONValue.Str(asText.take(2000)))
        val n = Stats.parseHealthNumbers(asText)
        var row = HealthRow(
            date = date, hrv = n.hrv, rhr = n.rhr, steps = n.steps, sleepH = n.sleepH,
            respRate = n.respRate, wristC = n.wristC, vo2max = n.vo2max, kcal = n.kcal,
            exerciseMin = n.exerciseMin, distKm = n.distKm, spo2 = n.spo2, raw = asText.take(300),
        )
        // structured payloads may carry fields the text parser doesn't (weightKg)
        if (nums != null) {
            row = row.copy(
                hrv = nums.hrv ?: row.hrv, rhr = nums.rhr ?: row.rhr, steps = nums.steps ?: row.steps,
                sleepH = nums.sleepH ?: row.sleepH, weightKg = nums.weightKg,
            )
        }
        LocalStore.mergeHealth(row)
    }

    /** JS-style number text: 48 not 48.0, 7.5 stays 7.5. */
    private fun fmtNum(n: Double): String = JSONValue.fmtNumber(n)

    // ── Merge ────────────────────────────────────────────────────

    private fun pickSession(local: Session?, remote: Session?): Session? {
        if (remote == null) return local
        if (local == null) return remote
        if (local.updatedAt != remote.updatedAt) return if (local.updatedAt > remote.updatedAt) local else remote
        if (local.finished != remote.finished) return if (local.finished) local else remote
        return local
    }

    private fun eventKey(e: Event) = "${e.iso}|${e.type}"
    private fun workoutId(w: JSONValue) = w.obj?.get("id")?.string ?: ""

    fun mergeBackups(local: Backup, remote: Backup?): Backup {
        if (remote == null) return normalizeBackup(local)

        val byId = LinkedHashMap<String, Session>()
        for (s in remote.sessions) byId[s.id] = s
        for (s in local.sessions) byId[s.id] = pickSession(s, byId[s.id])!!

        val delById = LinkedHashMap<String, Double>()
        for (d in local.deletedIds + remote.deletedIds) if (d.at > (delById[d.id] ?: 0.0)) delById[d.id] = d.at
        val deletedIds = delById.map { DeletedId(it.key, it.value) }

        val seen = HashSet<String>()
        val events = ArrayList<Event>()
        for (e in local.events + remote.events) if (seen.add(eventKey(e))) events.add(e)

        val aiSettings = if (remote.aiSettings.updatedAt > local.aiSettings.updatedAt) remote.aiSettings else local.aiSettings

        val byDate = LinkedHashMap<String, HealthRow>()
        for (h in remote.health) byDate[h.date] = h
        for (h in local.health) {
            val r = byDate[h.date]
            byDate[h.date] = if (r == null || (h.receivedAt ?: 0.0) >= (r.receivedAt ?: 0.0)) h else r
        }

        return normalizeBackup(local.copy(
            sessions = byId.values.toList(), events = events, health = byDate.values.toList(),
            aiSettings = aiSettings, deletedIds = deletedIds,
        ))
    }

    /** Deterministic shape so backups can be compared reliably. */
    fun normalizeBackup(b: Backup): Backup {
        val dels = LinkedHashMap<String, Double>()
        for (d in b.deletedIds) dels[d.id] = d.at
        val sessions = ArrayList<Session>()
        for (s in b.sessions) {
            if (s.date.isEmpty()) continue
            if (s.deleted) {
                if (dels[s.id] == null) dels[s.id] = if (s.updatedAt > 0) s.updatedAt else nowMs()
                continue
            }
            if (dels[s.id] == null) sessions.add(s)
        }
        return Backup(
            app = "coach",
            version = if (b.version > 0) b.version else 1,
            aiSettings = b.aiSettings,
            deletedIds = dels.map { DeletedId(it.key, it.value) }.sortedBy { it.id },
            health = b.health.sortedBy { it.date },
            sessions = sessions.sortedBy { it.date + it.id },
            events = b.events.sortedBy { eventKey(it) },
            workouts = b.workouts.sortedBy { workoutId(it) },
            prefs = b.prefs,
        )
    }

    // ── Sync ─────────────────────────────────────────────────────

    enum class Status { Unconfigured, Ok }

    data class Result(
        val status: Status,
        val changedLocal: Boolean,
        val sessions: Int,
        val inboxFiles: Int = 0,
        val skipped: Boolean = false,
    )

    /** Cheap "did anything change since the last backup" check — the same
     *  string the web app computes, so the apps agree on it. */
    fun fingerprint(): String {
        val b = LocalStore.backup
        val newest = b.sessions.maxOfOrNull { it.updatedAt } ?: 0.0
        return "${b.sessions.size}:${max(0.0, newest).toLong()}:${b.deletedIds.size}"
    }

    private fun parseIso(s: String): Instant? = try { Instant.parse(s) } catch (_: Exception) { null }

    /** Drain the Watch inbox into Firestore, then back the account up to
     *  GitHub if it's due. `force` backs up now. */
    suspend fun syncNow(force: Boolean = false): Result {
        val cfg = config()
        val sessions = LocalStore.backup.sessions.size
        if (Cloud.account == null || cfg.token.isEmpty() || cfg.repo.isEmpty()) {
            return Result(Status.Unconfigured, false, sessions)
        }

        // never fatal — a broken inbox must not block the backup
        val inboxFiles = try { consumeHealthInbox(cfg) } catch (_: Exception) { 0 }

        val last = lastSync()
        val lastAt = last?.let { parseIso(it.at) }
        val since = if (lastAt == null) Double.MAX_VALUE else (System.currentTimeMillis() - lastAt.toEpochMilli()) / 1000.0
        val fp = fingerprint()
        val due = force || last?.status != "ok" || since > DAY_SEC || (fp != last?.fingerprint && since > MIN_GAP_SEC)
        if (!due) return Result(Status.Ok, inboxFiles > 0, sessions, inboxFiles, skipped = true)

        try {
            val b = LocalStore.backup.copy(events = Cloud.allEvents(), workouts = Workouts.rawAll(), prefs = Prefs.raw)
            val backup = normalizeBackup(b)
            pushRemote(cfg, backup)
            pushReadme(cfg, backup.sessions)
            setLastSync(mapOf(
                "status" to JSONValue.Str("ok"), "sessions" to JSONValue.Num(backup.sessions.size.toDouble()),
                "fingerprint" to JSONValue.Str(fp), "message" to JSONValue.Null,
            ))
            return Result(Status.Ok, inboxFiles > 0, backup.sessions.size, inboxFiles)
        } catch (e: Exception) {
            setLastSync(mapOf("status" to JSONValue.Str("error"), "message" to JSONValue.Str(e.message ?: e.toString())))
            throw e
        }
    }
}
