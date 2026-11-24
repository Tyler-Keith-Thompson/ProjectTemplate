import SwiftUI

/// The app the simulator tests run inside. UIKit needs a running application to give windows a
/// scene, and a snapshot test draws its view in a window; this one shows nothing of its own.
@main
struct TestHostApp: App {
    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
    }
}
