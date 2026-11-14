import Afluent
import DependencyInjection
import Foundation
import Greetings
import Mockable

/// Greets a name: the seam between the greeting screen and wherever its greetings come from.
@Mockable
public protocol GreetingService: Sendable {
    /// The greeting for `name`, as work that runs when it is executed.
    ///
    /// - Parameter name: The name to greet; spaces around it are dropped.
    /// - Returns: Work that yields the formal greeting, or throws ``/Greetings/EmptyName`` when
    ///   `name` holds nothing but spaces.
    func greeting(for name: String) -> any AsynchronousUnitOfWork<Greeting>
}

// The service a real app's screen asks would reach a server here. This one composes the greeting
// itself, which keeps the seam the screen's tests replace with a mock.
struct _GreetingService: GreetingService {
    func greeting(for name: String) -> any AsynchronousUnitOfWork<Greeting> {
        DeferredTask {
            try Greeting(checkedName: name.trimmingCharacters(in: .whitespaces))
                .formal()
                .punctuated(with: "!")
        }
    }
}

extension Container {
    /// The greeting service every screen resolves.
    public static let greetingService = Factory { _GreetingService() as GreetingService }
}
