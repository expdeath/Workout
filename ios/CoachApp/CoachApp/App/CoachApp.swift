import SwiftUI
import GoogleSignIn

@main
struct CoachApp: App {
    @State private var appState: AppState = {
        Cloud.configure()
        #if DEBUG
        DebugSeed.applyIfRequested()
        #endif
        return AppState()
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                // Google sign-in hands control back through this URL
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
