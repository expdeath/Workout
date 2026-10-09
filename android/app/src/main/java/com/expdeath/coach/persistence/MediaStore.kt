package com.expdeath.coach.persistence

import android.net.Uri
import com.expdeath.coach.app.CoachApplication
import java.io.File
import java.net.URLEncoder

/** Per-exercise form photo or short clip — device-local only, never synced
 *  (same as the web's IndexedDB `media` store and MediaStore.swift: far too
 *  big for the database). Keyed like cue notes: the lowercased exercise name. */
object MediaStore {
    data class Item(val file: File, val isVideo: Boolean)

    private val dir: File
        get() = File(CoachApplication.context.filesDir, "CoachMedia").also { it.mkdirs() }

    /** File-safe name for a key ("Incline DB Press" → "incline+db+press"). */
    private fun base(key: String): String = URLEncoder.encode(key, "UTF-8").replace("*", "%2A")

    fun get(key: String): Item? {
        for ((ext, video) in listOf("jpg" to false, "mp4" to true)) {
            val f = File(dir, "${base(key)}.$ext")
            if (f.exists()) return Item(f, video)
        }
        return null
    }

    /** Replaces whatever was stored for this key with a picked photo or clip. */
    fun put(key: String, uri: Uri, isVideo: Boolean) {
        remove(key)
        val out = File(dir, "${base(key)}.${if (isVideo) "mp4" else "jpg"}")
        CoachApplication.context.contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { input.copyTo(it) }
        } ?: throw IllegalStateException("Couldn't read that file.")
    }

    fun remove(key: String) {
        for (ext in listOf("jpg", "mp4")) File(dir, "${base(key)}.$ext").delete()
    }

    /** Everything on sign-out (wipeLocal). */
    fun removeAll() { dir.deleteRecursively() }
}
