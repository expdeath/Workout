import SwiftUI

/// Settings → COACH Pro (port of src/screens/Pro.jsx). Shows the
/// subscription when active; otherwise the offer with everything App
/// Review needs on a paywall (guideline 3.1.2): price and period, the
/// free trial, that it auto-renews, Restore Purchases, Terms and Privacy.
struct ProSectionView: View {
    @Environment(AppState.self) private var appState
    @State private var offer: Subscriptions.Offer?
    @State private var loading = true
    @State private var busy = false
    @State private var msg = ""

    static let features = [
        "The AI coach with no API key to set up",
        "Session plans, check-ins, coach chat, reviews and “Build with coach”",
        "Up to 60 coach requests a day",
        "Everything else in COACH stays free",
    ]

    var body: some View {
        _ = appState.stateTick // Pro status changes arrive from the server
        return VStack(alignment: .leading, spacing: 12) {
            if Cloud.shared.proActive { active } else { pitch }
        }
        .task {
            loading = true
            offer = try? await Subscriptions.monthlyOffer()
            loading = false
        }
    }

    private var active: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusPill(text: Cloud.shared.proTrial ? "Pro · free trial" : "Pro", color: Theme.green)
                if !Cloud.shared.proStore.isEmpty {
                    Text(Cloud.shared.proStore == "app_store" ? "via App Store" : "via the website").capsLabel(Theme.muted, size: 11)
                }
            }
            Text("The AI coach runs on COACH's server — no key needed."
                 + (Cloud.shared.proExpires.map { " \(Cloud.shared.proWillRenew ? "Renews" : "Ends") \($0.formatted(date: .long, time: .omitted))." } ?? ""))
                .font(Theme.body(14.5))
            Text("Up to 60 coach requests a day.").font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
            if Cloud.shared.proStore == "app_store" {
                Button("Manage or cancel") { Task { await Subscriptions.manage() } }.buttonStyle(OutlineButtonStyle())
            } else {
                Text("Bought on the website — manage it there (Settings → COACH Pro).").font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("COACH Pro").font(Theme.head(26, weight: .bold)).textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(offer?.price ?? "$4.99").font(Theme.head(34, weight: .bold)).foregroundStyle(Theme.amberText)
                    Text("/ month").capsLabel()
                    if let trial = offer?.trial ?? (Subscriptions.enabled ? nil : "7 days") {
                        StatusPill(text: "\(trial) free", color: Theme.green, dot: false)
                    }
                }
                ForEach(Self.features, id: \.self) { f in
                    Label(f, systemImage: "checkmark.circle.fill").font(Theme.body(14)).foregroundStyle(Theme.textBody)
                        .symbolRenderingMode(.palette).foregroundStyle(Theme.green, Theme.textBody)
                }
            }
            .padding(14)
            .background(LinearGradient(colors: [Theme.amberBg, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.amber.opacity(0.35)))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))

            if !Subscriptions.enabled {
                Text("Coming soon — you can keep using your own key meanwhile.").font(Theme.body(14)).foregroundStyle(Theme.amberText)
            } else if let offer {
                Button(busy ? "Opening the App Store…" : (offer.trial.map { "Start \($0) free trial" } ?? "Subscribe for \(offer.price)/month")) {
                    Task {
                        busy = true
                        msg = ""
                        do {
                            if try await Subscriptions.purchase(offer) {
                                LocalStore.shared.logEvent(type: "pro_purchased", data: ["via": .string("app_store")])
                                msg = "Welcome to COACH Pro!"
                            }
                        } catch {
                            msg = "The purchase didn't go through — you weren't charged."
                        }
                        busy = false
                    }
                }
                .buttonStyle(BigButtonStyle()).disabled(busy)
                Text("\(offer.trial.map { "Free for \($0), then " } ?? "")\(offer.price) a month. Renews automatically until you cancel in Settings → Apple ID → Subscriptions, at least 24 hours before the period ends\(offer.trial == nil ? "" : " — cancel during the trial and you won't be charged").")
                    .font(Theme.meta(12)).foregroundStyle(Theme.muted)
            } else if loading {
                ProgressView().tint(Theme.amber)
            } else {
                Text("COACH Pro isn't available right now — try again later.").font(Theme.body(14)).foregroundStyle(Theme.muted)
            }
            if !msg.isEmpty { Text(msg).font(Theme.body(14)).foregroundStyle(Theme.amberText) }
            HStack(spacing: 16) {
                if Subscriptions.enabled {
                    Button("Restore purchases") {
                        Task {
                            busy = true
                            do { try await Subscriptions.restore(); msg = Cloud.shared.proActive ? "Restored — you're on Pro." : "No COACH Pro subscription found for this Apple ID." }
                            catch { msg = "Couldn't reach the App Store — try again." }
                            busy = false
                        }
                    }
                }
                Link("Terms", destination: Subscriptions.termsURL)
                Link("Privacy", destination: Subscriptions.privacyURL)
            }
            .font(Theme.body(13.5)).foregroundStyle(Theme.amberText)
        }
    }
}
