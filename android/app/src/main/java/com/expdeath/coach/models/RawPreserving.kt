package com.expdeath.coach.models

// ── Lossless round trips for synced documents ─────────────────────
// Sessions, health rows, events and AI settings come from JSON that
// other clients wrote (the web app, the iPhone app, older versions). The
// typed Kotlin models only know some of those keys, and decode some
// values loosely (a number where a String is expected, defaults for
// missing keys). Re-encoding just the typed fields would silently drop or
// rewrite everything else — and since every write goes back to the
// shared database, that loss would reach every device.
//
// So a document decoded from JSON remembers that JSON (`raw`) and what
// its typed fields encoded to right after decoding (`base`). Encoding it
// again starts from `raw` and applies only the fields whose typed value
// has actually changed since (base → current). Untouched keys — known or
// not — go back out as they came in. (Port of RawPreserving.swift.)

/** The JSON a document was decoded from. Deliberately ignored by `==`:
 *  two sessions with the same typed content are the same session. */
class RawSource(val raw: JSONValue, val base: JSONValue) {
    override fun equals(other: Any?): Boolean = other is RawSource
    override fun hashCode(): Int = 0
}

/** A model that can encode just its typed fields, and remembers the JSON
 *  it was decoded from. */
interface RawPreserving {
    val source: RawSource?
    fun encodeKnown(): JSONValue.Obj
}

/** The body of every RawPreserving type's encoding. */
fun RawPreserving.toJson(): JSONValue {
    val s = source ?: return encodeKnown()
    return s.raw.applying(s.base, encodeKnown())
}

/** Call at the end of decoding, after every typed field is set. */
fun rememberSource(raw: JSONValue, decoded: RawPreserving): RawSource = RawSource(raw, decoded.encodeKnown())
