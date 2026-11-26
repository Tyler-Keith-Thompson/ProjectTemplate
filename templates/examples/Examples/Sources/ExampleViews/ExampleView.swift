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
    // !performance:begin
    /// The greeting the example apps open with.
    ///
    /// - Throws: `EmptyName`, as `Greeting(name:)` does, though its name, "World", isn't empty.
    public static func example() throws(EmptyName) -> Greeting {
        try Greeting(name: "World").casual().punctuated(with: "!")
    }
    // !performance:end
    // performance:begin
    //| /// The greeting the example apps open with.
    //| public static let example = Greeting(name: "World").casual().punctuated(with: "!")
    // performance:end
}
