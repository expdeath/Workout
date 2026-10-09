package com.expdeath.coach.account

import android.app.Activity
import com.expdeath.coach.persistence.Defaults
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.persistence.MediaStore
import com.expdeath.coach.sync.Cloud

/** Accounts: Google sign-in + the Firestore allowlist (port of
 *  src/utils/account.js / Account.swift). Anyone can sign in: a Google
 *  account's first sign-in creates its own allowlist entry and empty
 *  account (selfServe; it brings its own Gemini key). Entries the owner adds
 *  are "invited" and share the owner's key. The same Google account opens
 *  the same account on any device — web, iPhone or Android; blocked: true
 *  turns one off. */
object Account {
    /** The signed-in account, or null. */
    fun current(): Cloud.AccountInfo? = Cloud.account

    /** Boot: the Firebase user restored from disk → their account. null when
     *  nobody is signed in; throws CloudError.Blocked for an account the
     *  owner turned off. */
    suspend fun resume(): Cloud.AccountInfo? {
        val user = Cloud.signedInUser ?: return null
        return Cloud.start(user)
    }

    /** The Login screen's button. */
    suspend fun signIn(activity: Activity): Cloud.AccountInfo {
        val user = Cloud.signInWithGoogle(activity)
        return try {
            Cloud.start(user)
        } catch (e: Exception) {
            Cloud.signOut() // blocked / couldn't open → don't stay half signed in
            throw e
        }
    }

    /** The Login screen's Sign in with Apple button. */
    suspend fun signInWithApple(activity: Activity): Cloud.AccountInfo {
        val user = Cloud.signInWithApple(activity)
        return try {
            Cloud.start(user)
        } catch (e: Exception) {
            Cloud.signOut()
            throw e
        }
    }

    /** Delete the account and everything in it, then this device's copy. */
    suspend fun deleteAccount(activity: Activity) {
        Cloud.deleteAccount(activity)
        wipeLocal()
    }

    /** Clears everything this device kept (settings, the in-memory mirror,
     *  form media). */
    fun wipeLocal() {
        Defaults.removeAll()
        LocalStore.wipe()
        MediaStore.removeAll() // form photos/clips live only on this device
    }

    /** Sign out: this device forgets the account (data stays in the cloud). */
    suspend fun signOut() {
        Cloud.signOut()
        wipeLocal()
    }
}

/** Sign in with Apple → Firebase (Firebase's web flow on Android). Built
 *  but off, exactly like the iPhone app: it needs the Apple provider set
 *  up in Firebase first (docs/app-store.md). Flip `enabled` once it is. */
object AppleSignIn {
    const val enabled = false
}
