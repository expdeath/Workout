import Foundation
import RevenueCat

/// COACH Pro on iPhone — App Store subscriptions through RevenueCat
/// (the website sells the same entitlement through RevenueCat Web Billing).
/// RevenueCat knows each customer by the COACH account id, so a purchase
/// here and one on the web are the same `pro` entitlement; the server
/// (functions/index.js) writes entitlements/{accountId} from it and the
/// AI requests check that — never this device's say-so.
/// Off until RevenueCat is set up: docs/subscriptions.md.
enum Subscriptions {
    /// RevenueCat public Apple API key ("appl_…") — a public key, safe in the app.
    static let appleAPIKey = ""
    static var enabled: Bool { !appleAPIKey.isEmpty }

    static let termsURL = URL(string: "https://expdeath.github.io/Workout/terms.html")!
    static let privacyURL = URL(string: "https://expdeath.github.io/Workout/privacy.html")!

    /// After sign-in: tie RevenueCat to this COACH account.
    static func start(accountId: String) async {
        guard enabled else { return }
        if Purchases.isConfigured {
            _ = try? await Purchases.shared.logIn(accountId)
        } else {
            Purchases.configure(withAPIKey: appleAPIKey, appUserID: accountId)
        }
    }

    /// Sign out / delete account: forget the customer on this device.
    static func stop() async {
        guard enabled, Purchases.isConfigured, !Purchases.shared.isAnonymous else { return }
        _ = try? await Purchases.shared.logOut()
    }

    struct Offer {
        var package: Package
        /// "$4.99" in the customer's own currency, from the App Store.
        var price: String
        /// "1 week" when the App Store offers a free trial to this customer.
        var trial: String?
    }

    static func monthlyOffer() async throws -> Offer? {
        guard enabled else { return nil }
        let offerings = try await Purchases.shared.offerings()
        guard let pkg = offerings.current?.monthly ?? offerings.current?.availablePackages.first else { return nil }
        let product = pkg.storeProduct
        var trial: String?
        if let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial {
            let p = intro.subscriptionPeriod
            trial = p.unit == .day && p.value == 7 ? "7 days" : "\(p.value) \(p.unit == .week ? "week" : p.unit == .month ? "month" : "day")\(p.value == 1 ? "" : "s")"
        }
        return Offer(package: pkg, price: product.localizedPriceString, trial: trial)
    }

    /// true = bought (the server is then asked to refresh); false = cancelled.
    static func purchase(_ offer: Offer) async throws -> Bool {
        let result = try await Purchases.shared.purchase(package: offer.package)
        if result.userCancelled { return false }
        await Cloud.shared.refreshPro()
        return true
    }

    /// Apple requires a Restore button: finds an existing App Store subscription.
    static func restore() async throws {
        _ = try await Purchases.shared.restorePurchases()
        await Cloud.shared.refreshPro()
    }

    @MainActor
    static func manage() async {
        try? await Purchases.shared.showManageSubscriptions()
    }
}
