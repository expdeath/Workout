package com.expdeath.coach.sync

import android.content.Intent
import android.net.Uri
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.expdeath.coach.app.AppState
import com.expdeath.coach.app.CoachApplication
import com.expdeath.coach.app.MainActivity
import com.expdeath.coach.app.Screen
import com.expdeath.coach.app.WatchSync
import com.expdeath.coach.watchlink.WatchCommand
import com.expdeath.coach.watchlink.WatchPaths
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit

/** Wear OS transport for [WatchSync] — the Data Layer, the Android twin of
 *  WatchConnectivity on the iPhone. The phone writes the latest WatchState
 *  to one data item (/coach/state); the watch writes each command as its
 *  own item (/coach/cmd/<id>), which Google Play services queues while the
 *  watch is out of range and delivers to [WatchListenerService] — even
 *  with COACH closed on the phone. Every call tolerates phones without
 *  Wear OS (the Tasks just fail). */
object WearBridge {
    private val ctx get() = CoachApplication.context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun start() {
        WatchSync.sender = { json -> send(json) }
        WatchSync.opener = { openOnWatch() }
    }

    private fun send(json: String) {
        scope.launch {
            gms {
                val req = PutDataMapRequest.create(WatchPaths.STATE).apply {
                    dataMap.putString("json", json)
                }.asPutDataRequest().setUrgent()
                Wearable.getDataClient(ctx).putDataItem(req)
            }
        }
    }

    /** A Play services call, off the main thread and capped at 5 s: on a
     *  phone without Wear OS, the Wearable clients can block the calling
     *  thread instead of failing (it froze Settings → Watch). */
    private suspend fun <T> gms(call: () -> Task<T>): T? = withContext(Dispatchers.IO) {
        try { Tasks.await(call(), 5, TimeUnit.SECONDS) } catch (_: Exception) { null }
    }

    /** Watches in range with COACH installed. */
    suspend fun watchesWithApp(): List<Node> =
        gms { Wearable.getCapabilityClient(ctx).getCapability(WatchPaths.WATCH_CAPABILITY, CapabilityClient.FILTER_REACHABLE) }?.nodes?.toList() ?: emptyList()

    /** Every watch connected to this phone, COACH or not. */
    suspend fun connectedWatches(): List<Node> = gms { Wearable.getNodeClient(ctx).connectedNodes } ?: emptyList()

    /** Opens COACH's workout screen on each watch that has it. */
    fun openOnWatch() {
        scope.launch {
            val nodes = watchesWithApp()
            if (nodes.isEmpty()) return@launch
            val helper = RemoteActivityHelper(ctx)
            val intent = Intent(Intent.ACTION_VIEW).addCategory(Intent.CATEGORY_BROWSABLE).setData(Uri.parse("coach://workout"))
            for (n in nodes) try { helper.startRemoteActivity(intent, n.id) } catch (_: Exception) {}
        }
    }

    /** The one AppState, created (and signed in) if the phone app wasn't running. */
    suspend fun appState(): AppState? {
        val app = MainActivity.state ?: AppState().also { MainActivity.state = it }
        withTimeoutOrNull(20_000) { while (app.screen == Screen.Loading) delay(100) }
        return if (Cloud.account != null || Cloud.offline) app else null
    }
}

/** Commands from the watch. Runs when they arrive, whether or not COACH is open. */
class WatchListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        // read everything out before the buffer is released
        val cmds = events.mapNotNull { e ->
            val item = e.dataItem
            if (e.type != DataEvent.TYPE_CHANGED || item.uri.path?.startsWith(WatchPaths.COMMAND + "/") != true) return@mapNotNull null
            val json = DataMapItem.fromDataItem(item).dataMap.getString("json") ?: return@mapNotNull null
            WatchCommand.fromJson(json)?.let { it to item.uri }
        }.sortedBy { it.first.at }
        if (cmds.isEmpty()) return
        val client = Wearable.getDataClient(this)
        runBlocking {
            withTimeoutOrNull(30_000) {
                withContext(Dispatchers.Main) {
                    val app = WearBridge.appState() ?: return@withContext
                    for ((cmd, _) in cmds) WatchSync.handle(app, cmd)
                }
            }
            // handled (or not deliverable): either way, don't redeliver
            for ((_, uri) in cmds) try { Tasks.await(client.deleteDataItems(uri), 5, TimeUnit.SECONDS) } catch (_: Exception) {}
        }
    }
}
