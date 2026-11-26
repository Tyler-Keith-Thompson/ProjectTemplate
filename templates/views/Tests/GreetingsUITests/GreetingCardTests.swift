// The tests run on the Mac; Linux builds this target empty, without the view-test packages.
#if os(macOS)
import Greetings
import SwiftUI
import Testing
import ViewInspector
@testable import GreetingsUI

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct GreetingCardTests {
    @Test func theCardShowsTheGreetingInItsOwnRegister() async throws {
        let expected = "Good day, Ada!"
        let sut = try GreetingCard(greeting: Greeting(name: "Ada").formal().punctuated(with: "!")) // !performance:line
        //| let sut = GreetingCard(greeting: Greeting(name: "Ada").formal().punctuated(with: "!")) // performance:line

        try await ViewHosting.host(sut) {
            try await sut.inspection.inspect { view in
                let actual = try view.find(text: expected).string()

                #expect(actual == expected)
            }
        }
    }

    @Test func tappingFormalSwitchesTheGreetingToTheFormalRegister() async throws {
        let expected = "Good day, Ada!"
        let sut = try GreetingCard(greeting: Greeting(name: "Ada").punctuated(with: "!")) // !performance:line
        //| let sut = GreetingCard(greeting: Greeting(name: "Ada").punctuated(with: "!")) // performance:line

        try await ViewHosting.host(sut) {
            try await sut.inspection.inspect { view in
                try view.find(button: "Formal").tap()
            }

            try await sut.inspection.inspect { view in
                let actual = try view.find(text: expected).string()

                #expect(actual == expected)
            }
        }
    }

    @Test func tappingTheButtonTwiceSwitchesTheGreetingBack() async throws {
        let expected = "Hi, Ada!"
        let sut = try GreetingCard(greeting: Greeting(name: "Ada").punctuated(with: "!")) // !performance:line
        //| let sut = GreetingCard(greeting: Greeting(name: "Ada").punctuated(with: "!")) // performance:line

        try await ViewHosting.host(sut) {
            try await sut.inspection.inspect { view in
                try view.find(button: "Formal").tap()
            }
            try await sut.inspection.inspect { view in
                try view.find(button: "Casual").tap()
            }

            try await sut.inspection.inspect { view in
                let actual = try view.find(text: expected).string()

                #expect(actual == expected)
            }
        }
    }

    @Test func theButtonIsLabelledWithTheRegisterItSwitchesTo() async throws {
        let expected = "Switch to the casual greeting"
        let sut = try GreetingCard(greeting: Greeting(name: "Ada").formal()) // !performance:line
        //| let sut = GreetingCard(greeting: Greeting(name: "Ada").formal()) // performance:line

        try await ViewHosting.host(sut) {
            try await sut.inspection.inspect { view in
                let actual = try view.find(button: "Casual").accessibilityLabel().string()

                #expect(actual == expected)
            }
        }
    }
}
#endif
