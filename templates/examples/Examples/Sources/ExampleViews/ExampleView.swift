import Greetings

#if canImport(SwiftUI)
import SwiftUI

/// The screen every example app shows: a greeting for a name.
public struct ExampleView: View {
    private let greeting: Greeting

    /// A screen showing `greeting`.
    public init(greeting: Greeting) {
        self.greeting = greeting
    }

    public var body: some View {
        Text(greeting.text)
            .font(.title)
            .padding()
    }
}
#endif

extension Greeting {
    /// The greeting the example apps open with.
    public static let example = Greeting(name: "World").casual().punctuated(with: "!")
}
