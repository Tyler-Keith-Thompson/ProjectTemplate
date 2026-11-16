import DebugDrawer
import SwiftUI

extension View {
    /// Opens and closes the debug drawer on Control-D (a hardware keyboard, or the simulator's) or a
    /// shake (a device, or the simulator's Device › Shake). Release builds leave the view as it is.
    func debugDrawerTrigger() -> some View {
        #if DEBUG
            background {
                Button("Debug drawer") { DebugDrawer.shared.toggle() }
                    .keyboardShortcut("d", modifiers: .control)
                    .accessibilityLabel("Debug drawer, open or close")
                    .hidden()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                DebugDrawer.shared.toggle()
            }
        #else
            self
        #endif
    }
}

#if DEBUG
    extension Notification.Name {
        fileprivate static let deviceDidShake = Notification.Name("ProjectName.deviceDidShake")
    }

    // SwiftUI has no shake event, so every window reports one. Debug builds only, and the drawer is
    // the one listener.
    extension UIWindow {
        override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if motion == .motionShake {
                NotificationCenter.default.post(name: .deviceDidShake, object: nil)
            }
            super.motionEnded(motion, with: event)
        }
    }
#endif
