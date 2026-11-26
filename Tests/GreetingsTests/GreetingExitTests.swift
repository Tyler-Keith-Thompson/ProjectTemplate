// Exit tests, in a file of their own: each runs its body in a child process, which some platforms // wasm:line
// (WASI) cannot start, and those builds leave out every file holding one. // wasm:line
//| // Exit tests, in a file of their own: each runs its body in a child process. // !wasm:line
// performance:begin
//|
//| import Greetings
//| import ProjectNameTestSupport
//| import Testing
//|
//| @Suite("Greeting: traps")
//| struct GreetingExitTests {
//|     @Test("The plain spelling traps on an empty name", .tags(.precondition))
//|     func plainEmptyNameTraps() async {
//|         await #expect(processExitsWith: .failure) {
//|             _ = Greeting(name: "")
//|         }
//|     }
//| }
// performance:end
