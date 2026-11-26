import Afluent
import Clocks
import ConcurrencyExtras
import DependencyInjection
import Greetings
import GreetingService
import Mockable
import SwiftUI
import Testing
import ViewInspector
@testable import GreetingFeature

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct GreetingViewTests {
    @Test func theScreenPromptsForANameBeforeAnythingIsTyped() async throws {
        try await withMainSerialExecutor {
            try await withTestContainer {
                let mockGreetingService = MockGreetingService()
                Container.greetingService.register { mockGreetingService }
                Container.clock.register { AnyClock(TestClock()) }

                let sut = GreetingView()
                try await ViewHosting.host(sut) {
                    try await sut.inspection.inspect { view in
                        _ = try view.find(ViewType.ContentUnavailableView.self)
                    }
                }

                verify(mockGreetingService).greeting(for: .any).called(.never)
            }
        }
    }

    @Test func theScreenShowsTheGreetingOnceTypingPausesFor300Milliseconds() async throws {
        try await withMainSerialExecutor {
            try await withTestContainer {
                let clock = TestClock()
                let mockGreetingService = MockGreetingService()
                given(mockGreetingService)
                    .greeting(for: .value("Ada"))
                    .willReturn(DeferredTask { try Greeting(name: "Ada").formal().punctuated(with: "!") })
                Container.greetingService.register { mockGreetingService }
                Container.clock.register { AnyClock(clock) }

                let sut = GreetingView()
                try await ViewHosting.host(sut) {
                    try await sut.inspection.inspect { view in
                        try view.find(ViewType.TextField.self).setInput("Ada")
                    }
                    await clock.advance(by: .milliseconds(300))

                    try await sut.inspection.inspect { view in
                        _ = try view.find(text: "Good day, Ada!")
                    }
                }

                verify(mockGreetingService).greeting(for: .value("Ada")).called(.once)
            }
        }
    }

    @Test func theScreenAsksForNoGreetingWhileTypingContinues() async throws {
        try await withMainSerialExecutor {
            try await withTestContainer {
                let clock = TestClock()
                let mockGreetingService = MockGreetingService()
                given(mockGreetingService)
                    .greeting(for: .value("Ada"))
                    .willReturn(DeferredTask { try Greeting(name: "Ada").formal().punctuated(with: "!") })
                Container.greetingService.register { mockGreetingService }
                Container.clock.register { AnyClock(clock) }

                let sut = GreetingView()
                try await ViewHosting.host(sut) {
                    try await sut.inspection.inspect { view in
                        try view.find(ViewType.TextField.self).setInput("Ad")
                    }
                    await clock.advance(by: .milliseconds(200))
                    try await sut.inspection.inspect { view in
                        try view.find(ViewType.TextField.self).setInput("Ada")
                    }
                    await clock.advance(by: .milliseconds(200))

                    try await sut.inspection.inspect { view in
                        _ = try view.find(ViewType.ContentUnavailableView.self)
                    }
                }

                verify(mockGreetingService).greeting(for: .any).called(.never)
            }
        }
    }

    @Test func theScreenPromptsAgainWithoutAskingWhenTheNameIsOnlySpaces() async throws {
        try await withMainSerialExecutor {
            try await withTestContainer {
                let clock = TestClock()
                let mockGreetingService = MockGreetingService()
                Container.greetingService.register { mockGreetingService }
                Container.clock.register { AnyClock(clock) }

                let sut = GreetingView()
                try await ViewHosting.host(sut) {
                    try await sut.inspection.inspect { view in
                        try view.find(ViewType.TextField.self).setInput("   ")
                    }
                    await clock.advance(by: .milliseconds(300))

                    try await sut.inspection.inspect { view in
                        _ = try view.find(text: "Say Hello")
                    }
                }

                verify(mockGreetingService).greeting(for: .any).called(.never)
            }
        }
    }

    @Test func theScreenSaysSoWhenTheServiceFails() async throws {
        try await withMainSerialExecutor {
            try await withTestContainer {
                let clock = TestClock()
                let mockGreetingService = MockGreetingService()
                given(mockGreetingService)
                    .greeting(for: .value("Ada"))
                    .willReturn(DeferredTask<Greeting> { throw EmptyName() })
                Container.greetingService.register { mockGreetingService }
                Container.clock.register { AnyClock(clock) }

                let sut = GreetingView()
                try await ViewHosting.host(sut) {
                    try await sut.inspection.inspect { view in
                        try view.find(ViewType.TextField.self).setInput("Ada")
                    }
                    await clock.advance(by: .milliseconds(300))

                    try await sut.inspection.inspect { view in
                        _ = try view.find(text: "No Greeting")
                    }
                }
            }
        }
    }
}
