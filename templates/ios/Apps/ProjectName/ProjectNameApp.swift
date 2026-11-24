import Greetings
import SwiftUI

/// The iOS app: the composition root, where production registers what it swaps in for a module's
/// default before the first view resolves it. Screens live in modules of their own (IOS_MODULES in
/// scripts/modules.py), which tests reach; this greeting stands in for the first of them.
@main
struct ProjectNameApp: App {
    var body: some Scene {
        WindowGroup {
            Text(Greeting(name: "World").text)
        }
    }
}
