import Afluent
import DependencyInjection
import Greetings
import GreetingService
import Testing

@Suite(.timeLimit(.minutes(1)))
struct GreetingServiceTests {
    @Test func theServiceGreetsANameFormally() async throws {
        try await withTestContainer {
            Container.greetingService.useProduction()
            let expected = "Good day, Ada!"

            let sut = Container.greetingService()
            let actual = try await sut.greeting(for: "Ada").execute()

            #expect(actual.text == expected)
        }
    }

    @Test func theServiceDropsSpacesAroundTheName() async throws {
        try await withTestContainer {
            Container.greetingService.useProduction()
            let expected = "Good day, Ada!"

            let sut = Container.greetingService()
            let actual = try await sut.greeting(for: "  Ada  ").execute()

            #expect(actual.text == expected)
        }
    }

    @Test func theServiceThrowsEmptyNameForANameOfOnlySpaces() async {
        await withTestContainer {
            Container.greetingService.useProduction()

            let sut = Container.greetingService()

            await #expect(throws: EmptyName.self) {
                try await sut.greeting(for: "   ").execute()
            }
        }
    }
}
