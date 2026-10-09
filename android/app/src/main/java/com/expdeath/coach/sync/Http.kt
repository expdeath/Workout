package com.expdeath.coach.sync

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** One HTTP response, body fully read. */
class HttpResponse(val status: Int, val body: ByteArray) {
    val text: String get() = String(body, Charsets.UTF_8)
}

/** Tiny suspend wrapper over OkHttp — every network call in the app (Gemini,
 *  GitHub, the COACH server) goes through here. No HTTP cache: GitHub's
 *  max-age=60 would otherwise hide another device's push for a minute. */
object Http {
    private val client = OkHttpClient.Builder()
        .cache(null)
        .connectTimeout(20, TimeUnit.SECONDS)
        .build()

    /** Tests: answer requests without the network (the iOS tests' URLProtocol stubs). */
    var stub: ((url: String, method: String, headers: Map<String, String>, body: ByteArray?) -> HttpResponse)? = null

    suspend fun request(
        url: String,
        method: String = "GET",
        headers: Map<String, String> = emptyMap(),
        body: ByteArray? = null,
        contentType: String = "application/json",
        timeoutSec: Long = 30,
    ): HttpResponse {
        stub?.let { return it(url, method, headers, body) }
        return send(url, method, headers, body, contentType, timeoutSec)
    }

    private suspend fun send(url: String, method: String, headers: Map<String, String>, body: ByteArray?, contentType: String, timeoutSec: Long): HttpResponse = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url).apply {
            headers.forEach { (k, v) -> header(k, v) }
            header("Cache-Control", "no-cache")
            val b = body ?: if (method in setOf("POST", "PUT", "PATCH")) ByteArray(0) else null
            method(method, b?.toRequestBody(contentType.toMediaType()))
        }.build()
        val call = client.newBuilder().callTimeout(timeoutSec, TimeUnit.SECONDS).build().newCall(req)
        suspendCancellableCoroutine { cont ->
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) { cont.resumeWithException(e) }
                override fun onResponse(call: Call, response: Response) {
                    val r = response.use { HttpResponse(it.code, it.body?.bytes() ?: ByteArray(0)) }
                    cont.resume(r)
                }
            })
        }
    }
}
