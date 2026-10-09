package com.expdeath.coach.persistence

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.expdeath.coach.models.AISettings
import com.expdeath.coach.models.Backup
import com.expdeath.coach.models.DeletedId
import com.expdeath.coach.models.Event
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Session
import com.expdeath.coach.stats.nowMs
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.sync.FirestoreCodec
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** `2026-10-07T06:06:52.123Z` — the same shape as JS toISOString(), so
 *  event ids (iso|type) look alike from every app. */
fun isoNow(): String = isoOf(Instant.now())

fun isoOf(i: Instant): String = ISO_MILLIS.format(i)

private val ISO_MILLIS: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

/** The signed-in account's data, in memory, in the same `Backup` shape the
 *  screens and stats read (sessions/health/deletedIds/aiSettings). Cloud
 *  keeps it live from Firestore snapshot listeners (`applyRemote…`), and
 *  every mutation here writes through to Firestore — whose own offline
 *  cache is what persists data on device. The event log is write-only
 *  (Cloud.allEvents fetches it on demand), except with Cloud.offline
 *  (DebugSeed), where everything stays here. Port of LocalStore.swift. */
object LocalStore {
    var backup by mutableStateOf(Backup())
        private set

    private fun now(): Double = nowMs().rounded()

    // ── Local mutations (write through to Firestore) ─────────────

    /** putSession() in db.js: updatedAt makes this the newest copy
     *  (firestore.rules refuse a write older than the stored one). */
    fun upsert(session: Session) {
        val s = session.copy(updatedAt = now())
        val list = backup.sessions.toMutableList()
        val i = list.indexOfFirst { it.id == s.id }
        if (i >= 0) list[i] = s else list.add(s)
        backup = backup.copy(sessions = list)
        Cloud.putSession(s)
    }

    /** Removes the session for real and records a permanent marker, so no
     *  device can bring it back (hardDeleteSession()). */
    fun hardDelete(sessionId: String) {
        val at = now()
        backup = backup.copy(
            sessions = backup.sessions.filter { it.id != sessionId },
            deletedIds = backup.deletedIds.filter { it.id != sessionId } + DeletedId(sessionId, at),
        )
        Cloud.deleteSession(sessionId, at)
    }

    /** "Clear all history" — every session removed and marked deleted. */
    fun clearSessions() {
        val at = now()
        val ids = backup.sessions.map { it.id }
        var dels = backup.deletedIds
        for (id in ids) dels = dels.filter { it.id != id } + DeletedId(id, at)
        backup = backup.copy(sessions = emptyList(), deletedIds = dels)
        Cloud.clearSessions(ids, at)
    }

    fun logEvent(type: String, data: Map<String, JSONValue> = emptyMap()) {
        val e = Event(now(), isoNow(), type, data)
        if (Cloud.offline) backup = backup.copy(events = backup.events + e)
        Cloud.logEvent(e)
    }

    /** setAISettings() in storage.js — patch + stamp updatedAt so
     *  newest-wins holds across devices. */
    fun updateAISettings(patch: (AISettings) -> AISettings) {
        val s = patch(backup.aiSettings).copy(updatedAt = now())
        backup = backup.copy(aiSettings = s)
        Cloud.putAISettings(s)
    }

    /** Patch a day's row without clobbering fields another source wrote
     *  (mergeHealth() in db.js). */
    fun mergeHealth(patch: HealthRow) {
        val list = backup.health.toMutableList()
        val i = list.indexOfFirst { it.date == patch.date }
        val row: HealthRow
        if (i >= 0) {
            var r = list[i].patchedWith(patch)
            if (patch.raw != null) r = r.copy(raw = patch.raw)
            r = r.copy(receivedAt = patch.receivedAt ?: now())
            row = r
            list[i] = row
        } else {
            row = patch.copy(receivedAt = patch.receivedAt ?: now())
            list.add(row)
        }
        backup = backup.copy(health = list)
        Cloud.putHealth(row)
    }

    // ── Remote changes (from Cloud's snapshot listeners) ─────────

    fun resetMirror() { backup = Backup() }

    fun applyRemoteSessions(changes: List<Pair<String, JSONValue?>>) {
        val list = backup.sessions.toMutableList()
        for ((docId, value) in changes) {
            list.removeAll { FirestoreCodec.docId(it.id) == docId }
            value?.let { Session.fromJson(it) }?.let { list.add(it) }
        }
        backup = backup.copy(sessions = list)
    }

    fun applyRemoteHealth(changes: List<Pair<String, JSONValue?>>) {
        val list = backup.health.toMutableList()
        for ((docId, value) in changes) {
            list.removeAll { FirestoreCodec.docId(it.date) == docId }
            value?.let { HealthRow.fromJson(it) }?.let { list.add(it) }
        }
        backup = backup.copy(health = list.sortedBy { it.date })
    }

    fun applyRemoteDeletedIds(changes: List<Pair<String, JSONValue?>>) {
        val list = backup.deletedIds.toMutableList()
        for ((docId, value) in changes) {
            list.removeAll { FirestoreCodec.docId(it.id) == docId }
            value?.let { DeletedId.fromJson(it) }?.let { list.add(it) }
        }
        backup = backup.copy(deletedIds = list)
    }

    fun applyRemoteAISettings(value: JSONValue?) {
        backup = backup.copy(aiSettings = value?.let { AISettings.fromJson(it) } ?: AISettings())
    }

    // ── Debug / sign-out ─────────────────────────────────────────

    /** DebugSeed only: seed rows without a cloud round trip. */
    fun seed(session: Session) { backup = backup.copy(sessions = backup.sessions + session) }

    fun wipe() { backup = Backup() }
}
