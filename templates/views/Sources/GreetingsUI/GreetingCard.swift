// SwiftUI is on Apple platforms alone; on Linux this module builds empty, so the package still does.
#if canImport(SwiftUI)
import Greetings
import SwiftUI

/// A greeting, with a button that switches it between the casual and the formal register.
public struct GreetingCard: View {
    private let greeting: Greeting
    @State private var register: Greeting.Register
    @ScaledMetric(relativeTo: .title) private var spacing = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // ViewInspector reads the view after it updates through this (its guide's "approach 2"): the one
    // hook production code carries for tests, since a SwiftUI view can't be inspected otherwise.
    let inspection = Inspection<Self>()

    /// A card showing `greeting`, starting in the greeting's own register.
    ///
    /// - Parameter greeting: The greeting to show.
    public init(greeting: Greeting) {
        self.greeting = greeting
        _register = State(initialValue: greeting.register)
    }

    public var body: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                Image(systemName: "hand.wave")
                    .accessibilityHidden(true)
                Text(greeting.in(register).text)
            }
            .font(.title)
            .accessibilityElement(children: .combine)

            Button(register.other.title) {
                withAnimation(reduceMotion ? nil : .smooth) {
                    register = register.other
                }
            }
            .accessibilityLabel("Switch to the \(register.other.title.lowercased()) greeting")
        }
        .padding(spacing * 2)
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }
}

extension Greeting {
    fileprivate func `in`(_ register: Register) -> Greeting {
        switch register {
        case .casual: casual()
        case .formal: formal()
        }
    }
}

extension Greeting.Register {
    fileprivate var other: Self {
        switch self {
        case .casual: .formal
        case .formal: .casual
        }
    }

    fileprivate var title: String {
        switch self {
        case .casual: "Casual"
        case .formal: "Formal"
        }
    }
}
#endif
