package com.expdeath.coach.sync

import com.expdeath.coach.models.Event
import com.expdeath.coach.models.JSONValue
import kotlin.math.abs

/** Values ⇄ Firestore document data — a port of src/db/firestoreCodec.js
 *  (and FirestoreCodec.swift), so every app reads and writes identical
 *  documents (schema: docs/firestore.md). Pure Kotlin: no Firebase types,
 *  so it's unit tested without the SDK.
 *
 *  Firestore can't hold an array directly inside an array (a session's
 *  `log` is [[set]]) and reserves some field names, so:
 *    an array inside an array  → { "__a": [...] }
 *    an object with a key Firestore can't hold ("" or "__…")
 *                              → { "__m": [{ "k": key, "v": value }, …] }
 *  Lossless for any JSON value. */
object FirestoreCodec {
    private const val ARR = "__a"
    private const val MAP = "__m"

    private fun badKey(k: String) = k.isEmpty() || k.startsWith("__")

    // ── JSONValue → Firestore value ──────────────────────────────

    fun encode(v: JSONValue, inArray: Boolean = false): Any? = when (v) {
        is JSONValue.Arr -> {
            val out = v.v.map { encode(it, true) }
            if (inArray) mapOf(ARR to out) else out
        }
        is JSONValue.Obj -> {
            if (v.v.keys.any(::badKey)) {
                mapOf(MAP to v.v.keys.sorted().map { mapOf("k" to it, "v" to encode(v.v.getValue(it))) })
            } else {
                LinkedHashMap<String, Any?>().also { m -> v.v.forEach { (k, x) -> m[k] = encode(x) } }
            }
        }
        is JSONValue.Str -> v.v
        is JSONValue.Bool -> v.v
        is JSONValue.Null -> null
        // whole numbers go out as integers, like the web SDK writes JS
        // numbers (ms timestamps, counts) — doubles otherwise
        is JSONValue.Num -> if (v.v == Math.rint(v.v) && abs(v.v) < 9_007_199_254_740_992.0) v.v.toLong() else v.v
    }

    // ── Firestore value → JSONValue ──────────────────────────────

    fun decode(any: Any?): JSONValue = when (any) {
        is Boolean -> JSONValue.Bool(any)
        is Number -> JSONValue.Num(any.toDouble())
        is String -> JSONValue.Str(any)
        is List<*> -> JSONValue.Arr(any.map { decode(it) })
        is Map<*, *> -> {
            val inner = any[ARR]
            val pairs = any[MAP]
            when {
                any.size == 1 && inner is List<*> -> JSONValue.Arr(inner.map { decode(it) })
                any.size == 1 && pairs is List<*> && pairs.all { it is Map<*, *> } -> {
                    val out = LinkedHashMap<String, JSONValue>()
                    for (p in pairs) {
                        val m = p as Map<*, *>
                        val k = m["k"] as? String ?: continue
                        out[k] = decode(m["v"])
                    }
                    JSONValue.Obj(out)
                }
                else -> JSONValue.Obj(LinkedHashMap<String, JSONValue>().also { m ->
                    any.forEach { (k, x) -> if (k is String) m[k] = decode(x) }
                })
            }
        }
        else -> JSONValue.Null // null, or a Firestore type this app never writes
    }

    // ── Documents ────────────────────────────────────────────────

    /** A model's JSON → the data to write as one document. */
    @Suppress("UNCHECKED_CAST")
    fun document(v: JSONValue): Map<String, Any?> =
        encode(v) as? Map<String, Any?> ?: throw IllegalArgumentException("a document must be an object")

    /** Document ids can't contain "/" or be "." / ".." / "__…__"; the real
     *  key always also lives inside the document, so ids are just lookups. */
    fun docId(raw: String): String {
        val esc = raw.replace("%", "%25").replace("/", "%2F")
        if (esc.isEmpty() || esc == "." || esc == ".." || (esc.startsWith("__") && esc.endsWith("__") && esc.length >= 4)) {
            return "%$esc"
        }
        return esc
    }

    /** Same key the merge dedupes the event log by (src/db/backupShape.js). */
    fun eventDocId(e: Event): String = docId("${e.iso}|${e.type}")
}
