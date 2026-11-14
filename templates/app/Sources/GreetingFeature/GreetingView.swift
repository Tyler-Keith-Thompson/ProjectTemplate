import Afluent
import AsyncAlgorithms
import Clocks
import DependencyInjection
import DesignSystem
import GreetingService
import os
import SwiftUI

/// The greeting screen: a name field, and the greeting for the name typed once typing pauses.
public struct GreetingView: View {
    private static let logger = Logger(subsystem: "GreetingFeature", category: "GreetingView")
    @ConstructorInjected(Container.greetingService) private var greetingService: GreetingService
    @ConstructorInjected(Container.clock) private var clock: AnyClock<Duration>
    @State private var name = ""
    @State private var names = CurrentValueSubject("")
    @State private var settledName = ""
    @State private var state = ViewState.prompt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // ViewInspector reads the view after it updates through this (its guide's "approach 2"): the one
    // hook production code carries for tests, since a SwiftUI view can't be inspected otherwise.
    let inspection = Inspection<Self>()

    /// The screen, resolving its service and clock from the current container.
    public init() { }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("Name", text: $name)
                .accessibilityLabel("Name to greet")
                .font(.bodyRegular)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(16)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : .smooth, value: state)
        }
        .onChange(of: name) { _, name in
            names.send(name)
        }
        .task {
            try? await settleNames()
        }
        .task(id: settledName) {
            await greet(settledName)
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .prompt:
            ContentUnavailableView("Say Hello", systemImage: "hand.wave", description: Text("Type a name to greet."))
        case .greeting(let text):
            Text(text)
                .font(.titleBold)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(16)
        case .failed:
            ContentUnavailableView("No Greeting", systemImage: "exclamationmark.bubble", description: Text("Try the name again."))
        }
    }

    // Asking on every keystroke would greet names half typed; 300 ms without a keystroke reads as a
    // pause.
    private func settleNames() async throws {
        for try await name in names.debounce(for: .milliseconds(300), clock: clock) {
            settledName = name
        }
    }

    private func greet(_ name: String) async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            state = .prompt
            return
        }
        do {
            let result = try await greetingService.greeting(for: name).execute()
            guard !Task.isCancelled else { return }
            state = .greeting(result.text)
        } catch {
            guard !Task.isCancelled else { return }
            Self.logger.error("Greeting failed: \(error.localizedDescription, privacy: .public)")
            state = .failed
        }
    }
}

extension GreetingView {
    /// What the screen shows: a case for each state it can be in.
    private enum ViewState: Equatable {
        case prompt
        case greeting(String)
        case failed
    }
}

extension Container {
    static let clock = Factory { AnyClock(ContinuousClock()) }
}
