import ExampleViews
import Greetings
import Testing

@Suite struct ExampleViewsTests {
    @Test func `The example apps open by greeting the world casually`() throws { // !performance:line
    //| @Test func `The example apps open by greeting the world casually`() { // performance:line
        let expected = "Hi, World!"

        let actual = try Greeting.example().text // !performance:line
        //| let actual = Greeting.example.text // performance:line

        #expect(actual == expected)
    }
}
