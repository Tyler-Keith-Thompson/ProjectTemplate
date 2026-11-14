import Afluent
import BazelSnapshotTesting
import Clocks
import DependencyInjection
import Greetings
import GreetingService
import Mockable
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
import ViewInspector
@testable import GreetingFeature

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GreetingViewSnapshotTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func greetingViewBeforeAnythingIsTyped(colorScheme: ColorScheme) async throws {
        try await withTestContainer {
            Container.greetingService.register { MockGreetingService() }
            Container.clock.register { AnyClock(TestClock()) }

            let sut = GreetingView()
            let controller = UIHostingController(rootView: sut.transaction { $0.disablesAnimations = true })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.isHidden = false
            try await sut.inspection.inspect { view in
                _ = try view.find(ViewType.ContentUnavailableView.self)
            }

            assertBazelSnapshot(
                of: controller,
                as: .image(
                    on: .iPhone13,
                    perceptualPrecision: 0.98,
                    traits: UITraitCollection(userInterfaceStyle: UIUserInterfaceStyle(colorScheme))
                ),
                named: "\(colorScheme)"
            )
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func greetingViewShowingAGreeting(colorScheme: ColorScheme) async throws {
        try await withTestContainer {
            let clock = TestClock()
            let mockGreetingService = MockGreetingService()
            given(mockGreetingService)
                .greeting(for: .value("Ada"))
                .willReturn(DeferredTask { Greeting(name: "Ada").formal().punctuated(with: "!") })
            Container.greetingService.register { mockGreetingService }
            Container.clock.register { AnyClock(clock) }

            let sut = GreetingView()
            let controller = UIHostingController(rootView: sut.transaction { $0.disablesAnimations = true })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.isHidden = false
            try await sut.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("Ada")
            }
            await clock.advance(by: .milliseconds(300))
            try await sut.inspection.inspect { view in
                _ = try view.find(text: "Good day, Ada!")
            }

            assertBazelSnapshot(
                of: controller,
                as: .image(
                    on: .iPhone13,
                    perceptualPrecision: 0.98,
                    traits: UITraitCollection(userInterfaceStyle: UIUserInterfaceStyle(colorScheme))
                ),
                named: "\(colorScheme)"
            )
        }
    }

    @Test(arguments: [DynamicTypeSize.xSmall, .accessibility5])
    func greetingViewShowingAGreetingWithDynamicType(dynamicTypeSize: DynamicTypeSize) async throws {
        try await withTestContainer {
            let clock = TestClock()
            let mockGreetingService = MockGreetingService()
            given(mockGreetingService)
                .greeting(for: .value("Ada"))
                .willReturn(DeferredTask { Greeting(name: "Ada").formal().punctuated(with: "!") })
            Container.greetingService.register { mockGreetingService }
            Container.clock.register { AnyClock(clock) }

            let sut = GreetingView()
            let controller = UIHostingController(rootView: sut.transaction { $0.disablesAnimations = true })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.isHidden = false
            try await sut.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("Ada")
            }
            await clock.advance(by: .milliseconds(300))
            try await sut.inspection.inspect { view in
                _ = try view.find(text: "Good day, Ada!")
            }

            assertBazelSnapshot(
                of: controller,
                as: .image(
                    on: .iPhone13,
                    perceptualPrecision: 0.98,
                    traits: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
                ),
                named: "\(dynamicTypeSize)"
            )
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func greetingViewWhenTheServiceFails(colorScheme: ColorScheme) async throws {
        try await withTestContainer {
            let clock = TestClock()
            let mockGreetingService = MockGreetingService()
            given(mockGreetingService)
                .greeting(for: .value("Ada"))
                .willReturn(DeferredTask<Greeting> { throw EmptyName() })
            Container.greetingService.register { mockGreetingService }
            Container.clock.register { AnyClock(clock) }

            let sut = GreetingView()
            let controller = UIHostingController(rootView: sut.transaction { $0.disablesAnimations = true })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.isHidden = false
            try await sut.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("Ada")
            }
            await clock.advance(by: .milliseconds(300))
            try await sut.inspection.inspect { view in
                _ = try view.find(text: "No Greeting")
            }

            assertBazelSnapshot(
                of: controller,
                as: .image(
                    on: .iPhone13,
                    perceptualPrecision: 0.98,
                    traits: UITraitCollection(userInterfaceStyle: UIUserInterfaceStyle(colorScheme))
                ),
                named: "\(colorScheme)"
            )
        }
    }
}
