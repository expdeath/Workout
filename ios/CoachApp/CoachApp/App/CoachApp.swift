import SwiftUI
import GoogleSignIn

@main
struct CoachApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
                // back in the foreground: Apple Health + Watch inbox + backup
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, Cloud.shared.account != nil { appState.maybeSyncOnForeground() }
                }
        }
    }
}
