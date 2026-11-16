// https://github.com/nalexn/ViewInspector/blob/0.10.5/guide.md#approach-2
#if canImport(SwiftUI)
import Combine
import SwiftUI

/// Lets ViewInspector read a view after SwiftUI has updated it: a test sends a line number, and the
/// view hands itself to the callback registered for it.
final class Inspection<V>: @unchecked Sendable {
    let notice = PassthroughSubject<UInt, Never>()
    var callbacks = [UInt: (V) -> Void]()

    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) {
            callback(view)
        }
    }
}
#endif
