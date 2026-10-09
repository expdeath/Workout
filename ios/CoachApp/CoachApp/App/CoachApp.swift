import SwiftUI

@main
struct CoachApp: App {
    @State private var appState: AppState = {
        #if DEBUG
        DebugSeed.applyIfRequested()
        #endif
        return AppState()
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}
