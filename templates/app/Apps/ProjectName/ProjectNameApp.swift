import DebugDrawer
import DebugDrawerAppInfoPlugin
import DebugDrawerConsolePlugin
import DebugDrawerPerformancePlugin
import DebugDrawerUserDefaultsPlugin
import GreetingFeature
import SwiftUI

/// The app: the composition root, where production registers what it swaps in for a module's
/// default (`Container.x.register { … }` in `init()`, before the first view resolves it).
@main
struct ProjectNameApp: App {
    init() {
        // Debug builds only: release builds have no install calls, and DebugDrawer's own API
        // compiles to no-ops there.
        #if DEBUG
            DebugDrawer.shared.installAppInfo()
            DebugDrawer.shared.installConsole()
            DebugDrawer.shared.installPerformance()
            DebugDrawer.shared.installUserDefaults()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            GreetingView()
                .debugDrawer()
                .debugDrawerTrigger()
        }
    }
}
