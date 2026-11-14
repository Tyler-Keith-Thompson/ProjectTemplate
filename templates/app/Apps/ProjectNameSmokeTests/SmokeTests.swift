// XCUITest is the one place XCTest is used: only it drives the built app in the simulator.
import XCTest

final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTypingANameShowsItsGreeting() {
        let app = XCUIApplication()
        app.launch()

        let nameField = app.textFields["Name to greet"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 30))
        nameField.tap()
        nameField.typeText("Ada")

        XCTAssertTrue(app.staticTexts["Good day, Ada!"].waitForExistence(timeout: 30))
    }
}
