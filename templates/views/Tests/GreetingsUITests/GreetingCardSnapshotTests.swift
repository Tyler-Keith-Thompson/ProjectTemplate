// The tests run on the Mac; Linux builds this target empty, without the view-test packages.
#if os(macOS)
import Greetings
import SnapshotTesting
import SwiftUI
import Testing
@testable import GreetingsUI

// ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the test
// asks for, so a snapshot doesn't depend on the Mac's own appearance or display. macOS doesn't scale
// text with Dynamic Type, so the Mac pins light and dark only.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GreetingCardSnapshotTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func aCasualGreeting(colorScheme: ColorScheme) throws {
        let sut = GreetingCard(greeting: Greeting(name: "Ada").punctuated(with: "!"))
        let renderer = ImageRenderer(content: sut.background(.background).environment(\.colorScheme, colorScheme))
        renderer.scale = 2

        let actual = try #require(renderer.nsImage)

        assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func aFormalGreeting(colorScheme: ColorScheme) throws {
        let sut = GreetingCard(greeting: Greeting(name: "Ada").formal().punctuated(with: "!"))
        let renderer = ImageRenderer(content: sut.background(.background).environment(\.colorScheme, colorScheme))
        renderer.scale = 2

        let actual = try #require(renderer.nsImage)

        assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
    }
}
#endif
