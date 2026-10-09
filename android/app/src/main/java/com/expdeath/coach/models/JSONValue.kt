package com.expdeath.coach.models

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlin.math.abs

/**
 * Arbitrary JSON payload — the Kotlin twin of JSONValue.swift. Every
 * synced document passes through this tree so both apps (and the web)
 * read and write identical shapes. Numbers are always doubles, like JS
 * (and the Swift enum): 7 and 7.0 are the same value.
 */
sealed class JSONValue {
    data class Str(val v: String) : JSONValue()
    data class Num(val v: Double) : JSONValue()
    data class Bool(val v: Boolean) : JSONValue()
    data class Arr(val v: List<JSONValue>) : JSONValue()
    data class Obj(val v: Map<String, JSONValue>) : JSONValue()
    data object Null : JSONValue()

    val string: String? get() = (this as? Str)?.v
    val number: Double? get() = (this as? Num)?.v
    val bool: Boolean? get() = (this as? Bool)?.v
    val array: List<JSONValue>? get() = (this as? Arr)?.v
    val obj: Map<String, JSONValue>? get() = (this as? Obj)?.v

    /** `self` with the edits that turn `base` into `current` applied —
     *  recursing into objects and arrays so an edit to one set of one
     *  exercise leaves every other key of the session untouched
     *  (RawPreserving.swift). */
    fun applying(base: JSONValue?, current: JSONValue): JSONValue {
        if (base == current) return this
        val raw = this
        if (raw is Obj && base is Obj && current is Obj) {
            val out = LinkedHashMap(raw.v)
            for ((k, cv) in current.v) {
                if (base.v[k] != cv) {
                    val r = raw.v[k]
                    out[k] = r?.applying(base.v[k], cv) ?: cv
                }
            }
            for (k in base.v.keys) if (!current.v.containsKey(k)) out.remove(k)
            return Obj(out)
        }
        if (raw is Arr && base is Arr && current is Arr) {
            return Arr(current.v.indices.map { i ->
                if (i < raw.v.size && i < base.v.size) raw.v[i].applying(base.v[i], current.v[i]) else current.v[i]
            })
        }
        return current
    }

    /** Compact JSON text (pretty = 2-space indent, like JSON.stringify(v, null, 2)). */
    fun toJsonString(pretty: Boolean = false, sortKeys: Boolean = false): String {
        val sb = StringBuilder()
        write(sb, pretty, sortKeys, 0)
        return sb.toString()
    }

    private fun write(sb: StringBuilder, pretty: Boolean, sortKeys: Boolean, depth: Int) {
        when (this) {
            is Str -> quote(sb, v)
            is Num -> sb.append(fmtNumber(v))
            is Bool -> sb.append(if (v) "true" else "false")
            is Null -> sb.append("null")
            is Arr -> {
                if (v.isEmpty()) { sb.append("[]"); return }
                sb.append('[')
                v.forEachIndexed { i, e ->
                    if (i > 0) sb.append(',')
                    if (pretty) { sb.append('\n'); indent(sb, depth + 1) }
                    e.write(sb, pretty, sortKeys, depth + 1)
                }
                if (pretty) { sb.append('\n'); indent(sb, depth) }
                sb.append(']')
            }
            is Obj -> {
                if (v.isEmpty()) { sb.append("{}"); return }
                sb.append('{')
                val keys = if (sortKeys) v.keys.sorted() else v.keys.toList()
                keys.forEachIndexed { i, k ->
                    if (i > 0) sb.append(',')
                    if (pretty) { sb.append('\n'); indent(sb, depth + 1) }
                    quote(sb, k)
                    sb.append(if (pretty) ": " else ":")
                    v.getValue(k).write(sb, pretty, sortKeys, depth + 1)
                }
                if (pretty) { sb.append('\n'); indent(sb, depth) }
                sb.append('}')
            }
        }
    }

    companion object {
        fun obj(vararg pairs: Pair<String, JSONValue>): Obj = Obj(linkedMapOf(*pairs))
        fun str(s: String?): JSONValue = if (s == null) Null else Str(s)
        fun num(n: Number?): JSONValue = if (n == null) Null else Num(n.toDouble())

        /** Parses JSON text; null when it isn't valid JSON. */
        fun parse(text: String): JSONValue? =
            try { from(Json.parseToJsonElement(text)) } catch (_: Exception) { null }

        fun from(e: JsonElement): JSONValue = when (e) {
            is JsonNull -> Null
            is JsonObject -> Obj(LinkedHashMap<String, JSONValue>().also { m -> e.forEach { (k, v) -> m[k] = from(v) } })
            is JsonArray -> Arr(e.map { from(it) })
            is JsonPrimitive -> when {
                e.isString -> Str(e.content)
                e.booleanOrNull != null -> Bool(e.booleanOrNull!!)
                else -> e.content.toDoubleOrNull()?.let { Num(it) } ?: Str(e.content)
            }
        }

        /** JS-style number text: 48 not 48.0, 7.5 stays 7.5. */
        fun fmtNumber(n: Double): String = when {
            n.isNaN() || n.isInfinite() -> "null"
            n == Math.rint(n) && abs(n) < 1e15 -> n.toLong().toString()
            else -> n.toString()
        }

        private fun indent(sb: StringBuilder, depth: Int) { repeat(depth) { sb.append("  ") } }

        private fun quote(sb: StringBuilder, s: String) {
            sb.append('"')
            for (c in s) {
                when (c) {
                    '"' -> sb.append("\\\"")
                    '\\' -> sb.append("\\\\")
                    '\n' -> sb.append("\\n")
                    '\r' -> sb.append("\\r")
                    '\t' -> sb.append("\\t")
                    '\b' -> sb.append("\\b")
                    '\u000C' -> sb.append("\\f")
                    else -> if (c < ' ') sb.append(String.format("\\u%04x", c.code)) else sb.append(c)
                }
            }
            sb.append('"')
        }
    }
}

// ── Lenient field decoding ───────────────────────────────────────
// Real synced data mixes types for the same field (the AI returns `rpe`
// as a number some days and a string on others; hand-entered values
// arrive as strings). These never throw on a type mismatch — they
// coerce, or return null so the caller's default applies.

typealias JObj = Map<String, JSONValue>

private fun JObj.json(key: String): JSONValue? {
    val v = this[key] ?: return null
    return if (v is JSONValue.Null) null else v
}

/** Swift `Double(String)`: a plain decimal number, nothing else. */
fun parseDouble(s: String?): Double? {
    if (s == null) return null
    if (!NUMBER.matches(s)) return null
    return s.toDoubleOrNull()
}

private val NUMBER = Regex("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?$")

/** Swift `Int(String)`: digits with an optional sign. */
fun parseInt(s: String?): Int? {
    if (s == null || !Regex("^[+-]?\\d+$").matches(s)) return null
    return s.toIntOrNull()
}

fun JObj.lenientString(key: String): String? = when (val v = json(key)) {
    is JSONValue.Str -> v.v
    is JSONValue.Num -> JSONValue.fmtNumber(v.v)
    is JSONValue.Bool -> if (v.v) "true" else "false"
    else -> null
}

fun JObj.lenientDouble(key: String): Double? = when (val v = json(key)) {
    is JSONValue.Num -> v.v
    is JSONValue.Str -> parseDouble(v.v.trim(' '))
    is JSONValue.Bool -> if (v.v) 1.0 else 0.0
    else -> null
}

fun JObj.lenientInt(key: String): Int? {
    val d = lenientDouble(key) ?: return null
    if (!d.isFinite() || abs(d) >= 1e15) return null
    return Math.round(d).toInt()
}

fun JObj.lenientBool(key: String): Boolean? = when (val v = json(key)) {
    is JSONValue.Bool -> v.v
    is JSONValue.Num -> v.v != 0.0
    is JSONValue.Str -> v.v.lowercase() in setOf("true", "1", "yes")
    else -> null
}

fun JObj.lenientStrings(key: String): List<String>? {
    val a = (json(key) as? JSONValue.Arr)?.v ?: return null
    return a.mapNotNull {
        when (it) {
            is JSONValue.Str -> it.v
            is JSONValue.Num -> JSONValue.fmtNumber(it.v)
            else -> null
        }
    }
}

fun JObj.lenientObj(key: String): JObj? = (json(key) as? JSONValue.Obj)?.v

/** A nested value decoded by `decode`, null instead of failing when it's malformed. */
fun <T> JObj.lenient(key: String, decode: (JSONValue) -> T?): T? {
    val v = json(key) ?: return null
    return try { decode(v) } catch (_: Exception) { null }
}

/** An array whose every element must decode (Swift `[T].self`): null if any doesn't. */
fun <T> JObj.lenientList(key: String, decode: (JSONValue) -> T?): List<T>? {
    val a = (json(key) as? JSONValue.Arr)?.v ?: return null
    val out = ArrayList<T>(a.size)
    for (e in a) out.add(decode(e) ?: return null)
    return out
}

/** Decodes an array element by element, keeping (as raw JSON) any element
 *  that doesn't fit the model — so one odd row can neither fail the
 *  whole array nor be dropped on the next write (LossyArray). */
class LossyArray<T>(val items: List<T>, val unparsed: List<JSONValue>) {
    companion object {
        fun <T> decode(v: JSONValue, decode: (JSONValue) -> T?): LossyArray<T>? {
            val a = (v as? JSONValue.Arr)?.v ?: return null
            val items = ArrayList<T>()
            val unparsed = ArrayList<JSONValue>()
            for (e in a) {
                val item = try { decode(e) } catch (_: Exception) { null }
                if (item != null) items.add(item) else unparsed.add(e)
            }
            return LossyArray(items, unparsed)
        }
    }
}

// ── Building objects ─────────────────────────────────────────────

/** Ordered object builder for encodeKnown(). */
class JBuilder {
    val map = LinkedHashMap<String, JSONValue>()
    fun put(k: String, v: String) { map[k] = JSONValue.Str(v) }
    fun put(k: String, v: Double) { map[k] = JSONValue.Num(v) }
    fun put(k: String, v: Int) { map[k] = JSONValue.Num(v.toDouble()) }
    fun put(k: String, v: Boolean) { map[k] = JSONValue.Bool(v) }
    fun put(k: String, v: JSONValue) { map[k] = v }
    fun putIfPresent(k: String, v: String?) { if (v != null) put(k, v) }
    fun putIfPresent(k: String, v: Double?) { if (v != null) put(k, v) }
    fun putIfPresent(k: String, v: Int?) { if (v != null) put(k, v) }
    fun putIfPresent(k: String, v: Boolean?) { if (v != null) put(k, v) }
    fun putIfPresent(k: String, v: JSONValue?) { if (v != null) put(k, v) }
    fun build(): JSONValue.Obj = JSONValue.Obj(map)
}

inline fun jobj(block: JBuilder.() -> Unit): JSONValue.Obj = JBuilder().apply(block).build()

fun strings(list: List<String>): JSONValue = JSONValue.Arr(list.map { JSONValue.Str(it) })
