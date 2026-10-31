// Exit tests, in a file of their own: each runs its body in a child process, which some platforms
// (WASI) cannot start, and those builds leave out every file holding one.

import Greetings
import ProjectNameTestSupport
import Testing

@Suite("Greeting: traps")
struct GreetingExitTests {
    @Test("The plain spelling traps on an empty name", .tags(.precondition))
    func plainEmptyNameTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Greeting(name: "")
        }
    }
}
