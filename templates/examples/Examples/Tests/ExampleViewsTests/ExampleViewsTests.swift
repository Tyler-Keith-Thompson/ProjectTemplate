import ExampleViews
import Greetings
import Testing

@Suite struct ExampleViewsTests {
    @Test func `The example apps open by greeting the world casually`() {
        let expected = "Hi, World!"

        let actual = Greeting.example.text

        #expect(actual == expected)
    }
}
