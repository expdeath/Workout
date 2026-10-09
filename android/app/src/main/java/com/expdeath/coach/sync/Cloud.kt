package com.expdeath.coach.sync

import android.app.Activity
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import com.expdeath.coach.app.CoachApplication
import com.expdeath.coach.models.Backup
import com.expdeath.coach.models.Event
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.AISettings
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.toJson
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.nowMs
import com.expdeath.coach.stats.rounded
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.AuthCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.auth.OAuthProvider
import com.google.firebase.auth.UserProfileChangeRequest
import com.google.firebase.firestore.AggregateSource
import com.google.firebase.firestore.DocumentChange
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import com.google.firebase.firestore.Source
import com.google.firebase.firestore.WriteBatch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/** Cloud Firestore — the live database, shared with the web and iPhone
 *  apps (port of src/db/cloud.js and Cloud.swift; schema + rules:
 *  docs/firestore.md).
 *
 *  Signing in with Google proves an email; allowlist/{email} maps it to
 *  one account (a Google account's first sign-in creates its own). That
 *  account's documents are mirrored into LocalStore by snapshot listeners
 *  (so screens read LocalStore synchronously), and every LocalStore
 *  mutation writes through here in the background — Firestore queues
 *  writes offline, so logging a set never waits on the network. */
object Cloud {
    private const val TAG = "COACH"

    /** OAuth web client of the heath-9a322 project — Credential Manager
     *  asks Google for an ID token minted for it, which Firebase accepts. */
    const val WEB_CLIENT_ID = "204447158862-1q03247j9e4l4ifcpb872491mksp52ku.apps.googleusercontent.com"

    data class AccountInfo(
        val accountId: String,
        val name: String,
        val admin: Boolean,
        val email: String,
        /** Signed itself up (not added by the owner): uses its own Gemini key. */
        val selfServe: Boolean = false,
    )

    sealed class CloudError(message: String) : Exception(message) {
        class Blocked(email: String) : CloudError("$email has been turned off on COACH. Ask Abhi if that's a mistake.")
        class NoPresenter : CloudError("Couldn't show the Google sign-in screen — try again.")
        class SignInFailed(m: String) : CloudError(m)
        /** The user closed Google's / Apple's sheet. */
        class Cancelled : CloudError("Cancelled.")
    }

    var account by mutableStateOf<AccountInfo?>(null)
        private set
    /** accounts/{id} — name, github { repo, token, lastBackup }, … */
    var accountDoc by mutableStateOf<Map<String, JSONValue>>(emptyMap())
        private set
    /** entitlements/{id} — COACH Pro, written only by the server */
    var pro by mutableStateOf<Map<String, JSONValue>>(emptyMap())
        private set
    /** config/shared — { geminiKey } (invited accounts only) */
    var shared by mutableStateOf<Map<String, JSONValue>>(emptyMap())
        private set
    /** accounts/{id}/state/… other than aiSettings (today, weeklyReview, …) */
    var state by mutableStateOf<Map<String, JSONValue>>(emptyMap())
        private set

    /** Called on the main thread with what changed: "sessions" | "health"
     *  | "state" | "account" | "shared" | "pro". */
    var onChange: ((String) -> Unit)? = null

    /** DebugSeed / tests: no Firebase at all, LocalStore only. */
    var offline = false

    private val listeners = ArrayList<ListenerRegistration>()
    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()
    private val auth: FirebaseAuth get() = FirebaseAuth.getInstance()

    // ── Setup ────────────────────────────────────────────────────

    private var configured = false

    /** google-services.json when the app was built with one; otherwise the
     *  same public project settings the web app uses (src/db/cloud.js). */
    fun configure() {
        if (configured) return
        configured = true
        val ctx = CoachApplication.context
        if (FirebaseApp.initializeApp(ctx) == null) {
            FirebaseApp.initializeApp(ctx, FirebaseOptions.Builder()
                .setApiKey("AIzaSyDE2zTvTacbQn2vgSTDY0LvHB-Gr7xAhec")
                .setApplicationId("1:204447158862:web:5c8b43f5e9e902f19e291f")
                .setProjectId("heath-9a322")
                .setStorageBucket("heath-9a322.firebasestorage.app")
                .setGcmSenderId("204447158862")
                .build())
        }
    }

    /** Invited accounts share the owner's key; self-serve ones bring their own. */
    val geminiKey: String
        get() = (if (account?.selfServe == true) accountDoc else shared)["geminiKey"]?.string ?: ""

    // ── COACH Pro (functions/index.js; docs/subscriptions.md) ──

    const val functionsBase = "https://europe-west2-heath-9a322.cloudfunctions.net"

    val proActive: Boolean
        get() {
            if (pro["pro"]?.bool != true) return false
            val exp = pro["expiresAt"]?.number ?: return true
            return exp > nowMs()
        }
    val proTrial: Boolean get() = pro["trial"]?.bool ?: false
    val proWillRenew: Boolean get() = pro["willRenew"]?.bool ?: false
    val proStore: String get() = pro["store"]?.string ?: ""
    val proExpires: Double? get() = pro["expiresAt"]?.number

    /** Can the AI coach run? A key (own or shared), or COACH Pro. */
    val aiReady: Boolean get() = geminiKey.isNotEmpty() || proActive

    /** Tests: a stand-in ID token (no Firebase behind it). */
    var debugIdToken: String? = null

    suspend fun idToken(): String {
        debugIdToken?.let { return it }
        val user = auth.currentUser ?: throw CloudError.SignInFailed("Not signed in.")
        return user.getIdToken(false).await().token ?: throw CloudError.SignInFailed("Not signed in.")
    }

    /** Ask the server to re-read the subscription now (right after a purchase). */
    suspend fun refreshPro() {
        if (offline) return
        val token = try { idToken() } catch (_: Exception) { return }
        val r = try {
            Http.request("$functionsBase/refreshPro", "POST", mapOf("Authorization" to "Bearer $token"))
        } catch (_: Exception) { return }
        if (r.status != 200) return
        val o = JSONValue.parse(r.text)?.obj ?: return
        pro = o
        onChange?.invoke("pro")
    }

    /** The owner (shared key) or a self-serve account (its own) can change it. */
    val canSetGeminiKey: Boolean get() = account?.admin == true || account?.selfServe == true

    val github: Map<String, JSONValue> get() = accountDoc["github"]?.obj ?: emptyMap()

    private fun path(vararg parts: String): String = (listOf("accounts", account?.accountId ?: "_") + parts).joinToString("/")

    // ── Auth ─────────────────────────────────────────────────────

    /** The Firebase user restored from disk, if any. */
    val signedInUser: FirebaseUser? get() = if (offline) null else auth.currentUser

    suspend fun signInWithGoogle(activity: Activity): FirebaseUser =
        auth.signInWithCredential(googleCredential(activity)).await().user
            ?: throw CloudError.SignInFailed("Google didn't return an identity — try again.")

    /** Google's account picker (Credential Manager) → a Firebase credential. */
    private suspend fun googleCredential(activity: Activity): AuthCredential {
        val option = GetSignInWithGoogleOption.Builder(WEB_CLIENT_ID).build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val result = try {
            CredentialManager.create(activity).getCredential(activity, request)
        } catch (e: androidx.credentials.exceptions.GetCredentialCancellationException) {
            throw CloudError.Cancelled()
        } catch (e: androidx.credentials.exceptions.GetCredentialException) {
            throw CloudError.SignInFailed("Google sign-in failed: ${e.message ?: e.type}")
        }
        val cred = result.credential
        if (cred !is CustomCredential || cred.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            throw CloudError.SignInFailed("Google didn't return an identity — try again.")
        }
        val idToken = GoogleIdTokenCredential.createFrom(cred.data).idToken
        return GoogleAuthProvider.getCredential(idToken, null)
    }

    /** Sign in with Apple through Firebase's web flow (AppleSignIn.kt).
     *  Apple sends the name only on the very first sign-in, so it's kept
     *  on the Firebase user. */
    suspend fun signInWithApple(activity: Activity): FirebaseUser {
        val provider = OAuthProvider.newBuilder("apple.com").setScopes(listOf("email", "name")).build()
        val result = try {
            auth.startActivityForSignInWithProvider(activity, provider).await()
        } catch (e: Exception) {
            if (e.message?.contains("cancel", ignoreCase = true) == true) throw CloudError.Cancelled()
            throw e
        }
        val user = result.user ?: throw CloudError.SignInFailed("Apple didn't return an identity — try again.")
        if (user.displayName.isNullOrEmpty()) {
            val name = (result.additionalUserInfo?.profile?.get("name") as? Map<*, *>)
                ?.let { listOfNotNull(it["firstName"] as? String, it["lastName"] as? String).joinToString(" ") }
            if (!name.isNullOrEmpty()) {
                try { user.updateProfile(UserProfileChangeRequest.Builder().setDisplayName(name).build()).await() } catch (_: Exception) {}
            }
        }
        return user
    }

    /** Settings → Delete account (port of cloudDeleteAccount in cloud.js).
     *  Proves it's really you first — Firebase only deletes a sign-in made
     *  moments ago — then deletes every document of the account, the
     *  account itself, your allowlist entry (last: the rules check it until
     *  then) and the sign-in. The GitHub backup repo is the user's and is left. */
    suspend fun deleteAccount(activity: Activity) {
        val user = auth.currentUser ?: throw CloudError.SignInFailed("Not signed in.")
        val acct = account ?: throw CloudError.SignInFailed("Not signed in.")
        if (user.providerData.any { it.providerId == "apple.com" }) {
            val provider = OAuthProvider.newBuilder("apple.com").build()
            try {
                user.startActivityForReauthenticateWithProvider(activity, provider).await()
            } catch (e: Exception) {
                if (e.message?.contains("cancel", ignoreCase = true) == true) throw CloudError.Cancelled()
                throw e
            }
        } else {
            user.reauthenticate(googleCredential(activity)).await()
        }

        val refs = ArrayList<DocumentReference>()
        for (name in listOf("sessions", "health", "deletedIds", "events", "state", "feedback")) {
            refs += db.collection(path(name)).get().await().documents.map { it.reference }
        }
        for (chunk in refs.chunked(450)) {
            val batch = db.batch()
            chunk.forEach { batch.delete(it) }
            batch.commit().await()
        }
        db.document(path()).delete().await()
        db.collection("allowlist").document(acct.email).delete().await()
        stop()
        user.delete().await()
        clearCredentials()
        try { db.terminate().await(); db.clearPersistence().await() } catch (_: Exception) {}
    }

    /** True once every write made on this device has reached the server,
     *  waiting at most `timeoutSec` (false when offline). */
    suspend fun flushWrites(timeoutSec: Long = 8): Boolean {
        if (offline || account == null) return true
        return withTimeoutOrNull(timeoutSec * 1000) {
            try { db.waitForPendingWrites().await(); true } catch (_: Exception) { false }
        } ?: false
    }

    private suspend fun clearCredentials() {
        try { CredentialManager.create(CoachApplication.context).clearCredentialState(ClearCredentialStateRequest()) } catch (_: Exception) {}
    }

    /** Sign out and drop this device's offline copy of the account. */
    suspend fun signOut() {
        stop()
        auth.signOut()
        clearCredentials()
        try { db.terminate().await(); db.clearPersistence().await() } catch (_: Exception) {}
    }

    // ── Session: allowlist → account → live listeners ────────────

    /** First sign-in of an email the owner didn't add: it gets its own
     *  empty account, keyed by the Firebase uid (the only shape the rules
     *  accept — never admin, never another account). */
    private suspend fun signUp(user: FirebaseUser, email: String): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val name = user.displayName?.takeIf { it.isNotEmpty() } ?: email.substringBefore("@")
        val entry = mapOf("accountId" to user.uid, "name" to name, "admin" to false, "selfServe" to true, "createdAt" to now)
        val batch = db.batch()
        batch.set(db.collection("allowlist").document(email), entry)
        batch.set(db.collection("accounts").document(user.uid), mapOf("name" to name, "createdAt" to now))
        batch.commit().await()
        return entry
    }

    /** Opens the user's account and resolves once every listener has
     *  delivered its first snapshot (from the offline cache when there's no
     *  network), so the app renders real data at once. */
    suspend fun start(user: FirebaseUser): AccountInfo {
        stop()
        val email = (user.email ?: "").lowercase()
        // throws offline (unless cached) → the login screen's "check your connection"
        val ref = db.collection("allowlist").document(email)
        var snap = ref.get().await()
        // the offline cache can remember "missing": only sign up on the server's word
        if (!snap.exists()) snap = ref.get(Source.SERVER).await()
        val data: Map<String, Any?> = if (snap.exists()) snap.data ?: emptyMap() else signUp(user, email)
        val accountId = data["accountId"] as? String ?: throw CloudError.SignInFailed("Your account entry is damaged — ask Abhi.")
        if (data["blocked"] == true) throw CloudError.Blocked(email)
        val info = AccountInfo(
            accountId = accountId,
            name = data["name"] as? String ?: "",
            admin = data["admin"] as? Boolean ?: false,
            email = email,
            selfServe = data["selfServe"] as? Boolean ?: false,
        )
        account = info
        LocalStore.resetMirror()

        suspendCancellableCoroutine { done ->
            val pending = PendingCount(if (info.selfServe) 6 else 7) { if (done.isActive) done.resume(Unit) }
            watchDoc(path(), "account", pending) { accountDoc = it }
            watchDoc("entitlements/$accountId", "pro", pending) { pro = it }
            // the shared key is for invited accounts; self-serve ones bring their own
            if (!info.selfServe) watchDoc("config/shared", "shared", pending) { shared = it }
            watchCollection(path("sessions"), "sessions", pending) { LocalStore.applyRemoteSessions(it) }
            watchCollection(path("health"), "health", pending) { LocalStore.applyRemoteHealth(it) }
            watchCollection(path("deletedIds"), "deletedIds", pending) { LocalStore.applyRemoteDeletedIds(it) }
            watchCollection(path("state"), "state", pending) { changes ->
                val s = LinkedHashMap(state)
                for ((id, value) in changes) {
                    if (id == "aiSettings") {
                        LocalStore.applyRemoteAISettings(value)
                    } else {
                        val o = value?.obj
                        if (o != null) s[id] = o["value"] ?: JSONValue.Null else s.remove(id)
                    }
                }
                state = s
            }
        }
        return info
    }

    fun stop() {
        listeners.forEach { it.remove() }
        listeners.clear()
        account = null
        accountDoc = emptyMap()
        pro = emptyMap()
        shared = emptyMap()
        state = emptyMap()
    }

    /** Resolves the start() wait once all first snapshots are in. */
    private class PendingCount(private var left: Int, private val done: () -> Unit) {
        fun one() { left -= 1; if (left == 0) done() }
    }

    private fun watchDoc(p: String, label: String, pending: PendingCount, apply: (Map<String, JSONValue>) -> Unit) {
        var first = true
        listeners.add(db.document(p).addSnapshotListener { snap, err ->
            if (snap != null) {
                FirestoreCodec.decode(snap.data ?: emptyMap<String, Any?>()).obj?.let(apply)
            } else if (err != null) {
                Log.w(TAG, "listener $label failed: ${err.message}")
            }
            if (first) { first = false; pending.one() }
            onChange?.invoke(label)
        })
    }

    /** Delivers (documentId, decoded value or null when removed) per change. */
    private fun watchCollection(p: String, label: String, pending: PendingCount, apply: (List<Pair<String, JSONValue?>>) -> Unit) {
        var first = true
        listeners.add(db.collection(p).addSnapshotListener { snap, err ->
            if (snap != null) {
                apply(snap.documentChanges.map { ch ->
                    ch.document.id to (if (ch.type == DocumentChange.Type.REMOVED) null else FirestoreCodec.decode(ch.document.data))
                })
            } else if (err != null) {
                Log.w(TAG, "listener $label failed: ${err.message}")
            }
            if (first) { first = false; pending.one() }
            onChange?.invoke(label)
        })
    }

    /** Tests: Pro status with no Firebase behind it. */
    fun debugSetPro(p: Map<String, JSONValue>) { pro = p }

    /** DebugSeed: a signed-in-looking state with no Firebase behind it. */
    fun debugActivate(account: AccountInfo, geminiKey: String) {
        offline = true
        this.account = account
        shared = mapOf("geminiKey" to JSONValue.Str(geminiKey))
    }

    // ── Writes (background; failures are logged, the next snapshot
    //    puts the mirror back in line). Handed to the SDK synchronously,
    //    so Firestore applies them in exactly the order they were made. ──

    private val active: Boolean get() = !offline && account != null

    private fun logged(what: String): (Exception?) -> Unit = { e ->
        if (e != null) Log.w(TAG, "cloud write failed ($what): ${e.message}")
    }

    private fun com.google.android.gms.tasks.Task<Void>.log(what: String) {
        addOnCompleteListener { logged(what)(it.exception) }
    }

    fun putSession(s: Session) {
        if (!active) return
        db.document(path("sessions", FirestoreCodec.docId(s.id))).set(FirestoreCodec.document(s.toJson())).log("session")
    }

    private fun marker(id: String, at: Double) = mapOf("id" to id, "at" to FirestoreCodec.encode(JSONValue.Num(at)))

    /** Delete for real + permanent marker, atomically. */
    fun deleteSession(id: String, at: Double) {
        if (!active) return
        val batch = db.batch()
        batch.set(db.document(path("deletedIds", FirestoreCodec.docId(id))), marker(id, at))
        batch.delete(db.document(path("sessions", FirestoreCodec.docId(id))))
        batch.commit().log("delete session")
    }

    /** "Clear all history": every session removed AND marked deleted. */
    fun clearSessions(ids: List<String>, at: Double) {
        if (!active || ids.isEmpty()) return
        for (chunk in ids.chunked(225)) {
            val batch = db.batch()
            for (id in chunk) {
                batch.set(db.document(path("deletedIds", FirestoreCodec.docId(id))), marker(id, at))
                batch.delete(db.document(path("sessions", FirestoreCodec.docId(id))))
            }
            batch.commit().log("clear history")
        }
    }

    fun putHealth(row: HealthRow) {
        if (!active) return
        db.document(path("health", FirestoreCodec.docId(row.date))).set(FirestoreCodec.document(row.toJson())).log("health")
    }

    fun putAISettings(settings: AISettings) {
        if (!active) return
        db.document(path("state", "aiSettings")).set(FirestoreCodec.document(settings.toJson())).log("aiSettings")
    }

    fun logEvent(e: Event) {
        if (!active) return
        db.document(path("events", FirestoreCodec.eventDocId(e))).set(FirestoreCodec.document(e.toJson())).log("event")
    }

    /** Account state other than aiSettings; null deletes the key. */
    fun stateValue(key: String): JSONValue? = state[key]

    fun setState(key: String, value: JSONValue?) {
        val s = LinkedHashMap(state)
        if (value != null) s[key] = value else s.remove(key)
        state = s
        if (offline || account == null) return
        onChange?.invoke("state")
        val ref = db.document(path("state", FirestoreCodec.docId(key)))
        if (value == null) { ref.delete().log("state $key"); return }
        ref.set(mapOf(
            "value" to FirestoreCodec.encode(value),
            "updatedAt" to FirestoreCodec.encode(JSONValue.Num(nowMs().rounded())),
        )).log("state $key")
    }

    fun stateKeys(): List<String> = state.keys.toList()

    /** Patch accounts/{id}.github ({ repo, token, lastBackup }). */
    fun updateGithub(patch: Map<String, JSONValue>) {
        val g = LinkedHashMap(github)
        g.putAll(patch)
        accountDoc = accountDoc + ("github" to JSONValue.Obj(g))
        onChange?.invoke("account")
        if (!active) return
        db.document(path()).update("github", FirestoreCodec.encode(JSONValue.Obj(g))).log("github settings")
    }

    /** Owner only — the rules reject anyone else. */
    fun setSharedGeminiKey(key: String) {
        shared = shared + ("geminiKey" to JSONValue.Str(key))
        onChange?.invoke("shared")
        if (!active || account?.admin != true) return
        db.document("config/shared").set(mapOf("geminiKey" to key), SetOptions.merge()).log("shared key")
    }

    /** Self-serve accounts: their own Gemini key, on accounts/{id}. */
    fun setOwnGeminiKey(key: String) {
        accountDoc = accountDoc + ("geminiKey" to JSONValue.Str(key))
        onChange?.invoke("account")
        if (!active || account?.selfServe != true) return
        db.document(path()).update("geminiKey", key).log("own key")
    }

    /** Awaited: the user is told it was sent. */
    suspend fun sendFeedback(text: String) {
        val acct = account
        if (!active || acct == null) throw CloudError.SignInFailed("Not signed in.")
        db.collection(path("feedback")).document().set(mapOf(
            "text" to text, "name" to acct.name, "email" to acct.email,
            "at" to FirestoreCodec.encode(JSONValue.Num(nowMs().rounded())),
        )).await()
    }

    /** "Import backup": make the account's sessions/health match a
     *  (normalized) backup and add its events + deletion markers — the
     *  web's cloudReplaceData. Sessions the rules would refuse (an older
     *  copy than the stored one, or a deleted id) are skipped, since one
     *  refused write fails its whole batch. Returns how many were skipped. */
    suspend fun replaceData(b: Backup): Int {
        if (!active) return 0
        val ops = ArrayList<(WriteBatch) -> Unit>()
        val mirror = LocalStore.backup
        val keepIds = b.sessions.map { it.id }.toSet()
        val keepDates = b.health.map { it.date }.toSet()
        for (s in mirror.sessions) if (s.id !in keepIds) {
            val ref = db.document(path("sessions", FirestoreCodec.docId(s.id)))
            ops.add { it.delete(ref) }
        }
        for (h in mirror.health) if (h.date !in keepDates) {
            val ref = db.document(path("health", FirestoreCodec.docId(h.date)))
            ops.add { it.delete(ref) }
        }
        for (d in b.deletedIds) {
            val ref = db.document(path("deletedIds", FirestoreCodec.docId(d.id)))
            val data = marker(d.id, d.at)
            ops.add { it.set(ref, data) }
        }
        val deleted = (mirror.deletedIds.map { it.id } + b.deletedIds.map { it.id }).toSet()
        var skipped = 0
        for (s in b.sessions) {
            if (s.id in deleted || (mirror.sessions.firstOrNull { it.id == s.id }?.updatedAt ?: 0.0) > s.updatedAt) {
                skipped += 1
                continue
            }
            val ref = db.document(path("sessions", FirestoreCodec.docId(s.id)))
            val data = FirestoreCodec.document(s.toJson())
            ops.add { it.set(ref, data) }
        }
        for (h in b.health) {
            val ref = db.document(path("health", FirestoreCodec.docId(h.date)))
            val data = FirestoreCodec.document(h.toJson())
            ops.add { it.set(ref, data) }
        }
        for (e in b.events) {
            val ref = db.document(path("events", FirestoreCodec.eventDocId(e)))
            val data = FirestoreCodec.document(e.toJson())
            ops.add { it.set(ref, data) }
        }
        for (chunk in ops.chunked(450)) {
            val batch = db.batch()
            chunk.forEach { it(batch) }
            batch.commit().await()
        }
        return skipped
    }

    // ── On-demand reads ──────────────────────────────────────────

    /** The whole event log (write-only otherwise) — for the GitHub backup. */
    suspend fun allEvents(): List<Event> {
        if (!active) return LocalStore.backup.events
        return db.collection(path("events")).get().await().documents.mapNotNull { Event.fromJson(FirestoreCodec.decode(it.data)) }
    }

    suspend fun countEvents(): Int {
        if (!active) return LocalStore.backup.events.size
        return try { db.collection(path("events")).count().get(AggregateSource.SERVER).await().count.toInt() } catch (_: Exception) { 0 }
    }
}
