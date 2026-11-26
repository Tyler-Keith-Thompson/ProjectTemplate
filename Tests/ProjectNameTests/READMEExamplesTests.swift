// The README's examples, verbatim, so the README cannot drift from the code.

import ProjectName
import Testing

@Suite("README examples")
struct READMEExamplesTests {
    @Test("Usage")
    // !performance:begin
    func usage() throws {
        let greeting = try Greeting(name: "Ada").formal().punctuated(with: "!")
    // !performance:end
    // performance:begin
    //| func usage() {
    //|     let greeting = Greeting(name: "Ada").formal().punctuated(with: "!")
    // performance:end
        #expect(greeting.text == "Good day, Ada!")
    }
}
