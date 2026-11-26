import ExampleViews
import Greetings
import SwiftUI

/// The Apple example app, one source for every Apple platform: the composition root, which hands
/// the screen what it shows.
@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            // !performance:begin
            if let greeting = try? Greeting.example() {
                ExampleView(greeting: greeting)
            }
            // !performance:end
            //| ExampleView(greeting: .example) // performance:line
        }
    }
}
