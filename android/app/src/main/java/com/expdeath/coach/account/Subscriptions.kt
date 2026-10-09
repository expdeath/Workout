package com.expdeath.coach.account

import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.expdeath.coach.app.CoachApplication
import com.expdeath.coach.sync.Cloud
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitLogIn
import com.revenuecat.purchases.awaitLogOut
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.models.Period

/** COACH Pro on Android — Google Play subscriptions through RevenueCat
 *  (the website sells the same entitlement through RevenueCat Web Billing,
 *  the iPhone app through the App Store). RevenueCat knows each customer by
 *  the COACH account id, so a purchase anywhere is the same `pro`
 *  entitlement; the server (functions/index.js) writes
 *  entitlements/{accountId} from it and the AI requests check that — never
 *  this device's say-so. Off until RevenueCat is set up: docs/subscriptions.md. */
object Subscriptions {
    /** RevenueCat public Google API key ("goog_…") — a public key, safe in the app. */
    const val googleAPIKey = ""
    val enabled: Boolean get() = googleAPIKey.isNotEmpty()

    const val termsURL = "https://expdeath.github.io/Workout/terms.html"
    const val privacyURL = "https://expdeath.github.io/Workout/privacy.html"

    /** After sign-in: tie RevenueCat to this COACH account. */
    suspend fun start(accountId: String) {
        if (!enabled) return
        if (Purchases.isConfigured) {
            try { Purchases.sharedInstance.awaitLogIn(accountId) } catch (_: Exception) {}
        } else {
            Purchases.configure(PurchasesConfiguration.Builder(CoachApplication.context, googleAPIKey).appUserID(accountId).build())
        }
    }

    /** Sign out / delete account: forget the customer on this device. */
    suspend fun stop() {
        if (!enabled || !Purchases.isConfigured || Purchases.sharedInstance.isAnonymous) return
        try { Purchases.sharedInstance.awaitLogOut() } catch (_: Exception) {}
    }

    data class Offer(
        val pkg: Package,
        /** "$4.99" in the customer's own currency, from Google Play. */
        val price: String,
        /** "7 days" when Play offers a free trial to this customer. */
        val trial: String?,
    )

    suspend fun monthlyOffer(): Offer? {
        if (!enabled) return null
        val offerings = Purchases.sharedInstance.awaitOfferings()
        val pkg = offerings.current?.monthly ?: offerings.current?.availablePackages?.firstOrNull() ?: return null
        val product = pkg.product
        val trial = product.defaultOption?.freePhase?.billingPeriod?.let { p ->
            val unit = when (p.unit) {
                Period.Unit.DAY -> "day"; Period.Unit.WEEK -> "week"; Period.Unit.MONTH -> "month"; Period.Unit.YEAR -> "year"; else -> "day"
            }
            if (p.unit == Period.Unit.DAY && p.value == 7) "7 days" else "${p.value} $unit${if (p.value == 1) "" else "s"}"
        }
        return Offer(pkg, product.price.formatted, trial)
    }

    /** true = bought (the server is then asked to refresh); false = cancelled. */
    suspend fun purchase(activity: Activity, offer: Offer): Boolean {
        try {
            Purchases.sharedInstance.awaitPurchase(PurchaseParams.Builder(activity, offer.pkg).build())
        } catch (e: PurchasesTransactionException) {
            if (e.userCancelled) return false
            throw e
        }
        Cloud.refreshPro()
        return true
    }

    /** Finds an existing Play subscription. */
    suspend fun restore() {
        Purchases.sharedInstance.awaitRestore()
        Cloud.refreshPro()
    }

    /** Google Play's subscription center. */
    fun manage(activity: Activity) {
        activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(
            "https://play.google.com/store/account/subscriptions?package=${activity.packageName}"
        )))
    }
}
