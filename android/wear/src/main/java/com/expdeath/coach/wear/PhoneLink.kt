package com.expdeath.coach.wear

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.expdeath.coach.watchlink.WatchCommand
import com.expdeath.coach.watchlink.WatchPaths
import com.expdeath.coach.watchlink.WatchState
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.tasks.await
import java.util.UUID

/** The watch's view of the phone's workout (docs/watch.md). Holds the
 *  phone's last [WatchState] plus the commands sent since, and shows the
 *  two combined — so a tap on the wrist shows up instantly, works out of
 *  Bluetooth range (the Data Layer queues the command), and is replaced by
 *  the phone's real answer when it arrives. Both halves are kept on disk:
 *  the watch app can be killed between sets. */
object PhoneLink {
    private lateinit var ctx: Context
    private var phone = WatchState()
    private var pending = listOf<WatchCommand>()

    private val _state = MutableStateFlow(WatchState())
    /** What to show: the phone's state with this watch's pending commands applied. */
    val state: StateFlow<WatchState> = _state

    /** Is the phone in range with COACH on it? null = not checked yet. */
    val phoneReachable = MutableStateFlow<Boolean?>(null)

    private val prefs get() = ctx.getSharedPreferences("phonelink", Context.MODE_PRIVATE)

    @Synchronized fun init(context: Context) {
        if (::ctx.isInitialized) return
        ctx = context.applicationContext
        phone = prefs.getString("phone", null)?.let { WatchState.fromJson(it) } ?: WatchState()
        pending = prefs.getStringSet("pending", emptySet())!!.mapNotNull { WatchCommand.fromJson(it) }.sortedBy { it.at }
        publish()
    }

    @Synchronized private fun publish() {
        val cutoff = System.currentTimeMillis() - 30 * 60_000L
        // applied by the phone, or too old to still matter
        pending = pending.filter { it.id !in phone.acks && it.at > cutoff }
        prefs.edit()
            .putString("phone", phone.toJson())
            .putStringSet("pending", pending.map { it.toJson() }.toSet())
            .apply()
        _state.value = phone.withPending(pending)
    }

    /** A state snapshot from the phone. */
    @Synchronized fun receive(json: String) {
        val s = WatchState.fromJson(json) ?: return
        if (s.sentAt in 1 until phone.sentAt) return // an older copy arriving late
        phone = s
        phoneReachable.value = true
        publish()
    }

    /** Applies a command here at once and sends it to the phone. */
    fun send(cmd: String, ex: Int = -1, name: String = "", set: Int = -1, w: String = "", r: String = "", t: String = "", d: String = "",
             effort: String = "", sec: Int = 0, rpe: Int = 0, workout: com.expdeath.coach.watchlink.WorkoutSummary? = null) {
        val c = WatchCommand(
            id = UUID.randomUUID().toString(), at = System.currentTimeMillis(), cmd = cmd, session = _state.value.id,
            ex = ex, name = name, set = set, w = w, r = r, t = t, d = d, effort = effort, sec = sec, rpe = rpe, workout = workout,
        )
        if (cmd != WatchCommand.SYNC && cmd != WatchCommand.WORKOUT) synchronized(this) {
            pending = pending + c
            publish()
        }
        try {
            val req = PutDataMapRequest.create("${WatchPaths.COMMAND}/${c.id}").apply {
                dataMap.putString("json", c.toJson())
            }.asPutDataRequest().setUrgent()
            Wearable.getDataClient(ctx).putDataItem(req)
        } catch (_: Exception) {}
    }

    /** On launch: the latest state the Data Layer holds, then ask the phone for a fresh one. */
    suspend fun refresh() {
        try {
            val items = Wearable.getDataClient(ctx).getDataItems(Uri.Builder().scheme(PutDataRequest.WEAR_URI_SCHEME).path(WatchPaths.STATE).build()).await()
            items.use { buf -> buf.forEach { item -> DataMapItem.fromDataItem(item).dataMap.getString("json")?.let { receive(it) } } }
        } catch (_: Exception) {}
        phoneReachable.value = try {
            Wearable.getCapabilityClient(ctx).getCapability(WatchPaths.PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE).await().nodes.isNotEmpty()
        } catch (_: Exception) { false }
        send(WatchCommand.SYNC)
    }

    /** "Start on your phone": opens COACH there. */
    suspend fun openOnPhone(): Boolean = try {
        val node = Wearable.getCapabilityClient(ctx).getCapability(WatchPaths.PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE).await().nodes.firstOrNull()
            ?: Wearable.getNodeClient(ctx).connectedNodes.await().firstOrNull()
        if (node == null) false else {
            val intent = Intent(Intent.ACTION_VIEW).addCategory(Intent.CATEGORY_BROWSABLE).setData(Uri.parse("coach://open"))
            RemoteActivityHelper(ctx).startRemoteActivity(intent, node.id)
            true
        }
    } catch (_: Exception) { false }

    /** Debug builds: show a canned workout without a phone (emulator screenshots). */
    fun debugShow(s: WatchState) {
        synchronized(this) { phone = s; pending = emptyList() }
        publish()
    }
}

/** The phone's state updates, delivered even while the watch app is closed. */
class PhoneListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        PhoneLink.init(this)
        for (e in events) {
            if (e.type != DataEvent.TYPE_CHANGED || e.dataItem.uri.path != WatchPaths.STATE) continue
            DataMapItem.fromDataItem(e.dataItem).dataMap.getString("json")?.let { PhoneLink.receive(it) }
        }
    }
}
