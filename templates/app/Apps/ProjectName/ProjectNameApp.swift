import GreetingFeature
import SwiftUI

/// The app: the composition root, where production registers what it swaps in for a module's
/// default (`Container.x.register { … }` in `init()`, before the first view resolves it).
@main
struct ProjectNameApp: App {
    var body: some Scene {
        WindowGroup {
            GreetingView()
        }
    }
}
