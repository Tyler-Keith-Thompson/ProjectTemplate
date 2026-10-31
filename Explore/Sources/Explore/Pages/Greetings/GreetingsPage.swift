import ElementaryUI
import Reactivity

/// The punctuation choices, in the order the buttons show them; nil is none.
let greetingsPunctuation: [Character?] = [nil, ".", "!", "?"]

@Reactive
final class GreetingsModel {
    var name = "Ada"
    var formal = false
    var punctuation = 2
}

let greetings = GreetingsModel()

@View
struct GreetingsLab {
    var body: some View {
        let model = greetings
        let punctuation = greetingsPunctuation[model.punctuation]
        let text = try? greetingText(name: model.name, formal: model.formal, punctuation: punctuation)
        section(.class("lab"), .custom(name: "aria-label", value: "A greeting")) {
            div(.class("panel stage")) {
                if let text {
                    p(.class("greeting")) { text }
                } else {
                    p(.class("greeting empty")) { "No greeting: a greeting needs a name." }
                }
                p(.class("note")) { "Type a name, then pick the register and the punctuation." }
            }
            div(.class("side")) {
                div(.class("panel")) {
                    label(.class("field")) {
                        "Name"
                        input(.id("greetings-name"), .type(.text), .value(model.name), .custom(name: "maxlength", value: "24"))
                            .onInput { event in greetings.name = event.targetValue ?? "" }
                    }
                    div(.class("buttons")) {
                        div(.class("segmented"), .custom(name: "role", value: "group"), .custom(name: "aria-label", value: "Register")) {
                            button(.type(.button), .class(model.formal ? "" : "on")) { "Casual" }
                                .onClick { greetings.formal = false }
                            button(.type(.button), .class(model.formal ? "on" : "")) { "Formal" }
                                .onClick { greetings.formal = true }
                        }
                    }
                    div(.class("buttons")) {
                        div(.class("segmented"), .custom(name: "role", value: "group"), .custom(name: "aria-label", value: "Punctuation")) {
                            button(.type(.button), .class(model.punctuation == 0 ? "on" : "")) { "None" }
                                .onClick { greetings.punctuation = 0 }
                            button(.type(.button), .class(model.punctuation == 1 ? "on" : "")) { "." }
                                .onClick { greetings.punctuation = 1 }
                            button(.type(.button), .class(model.punctuation == 2 ? "on" : "")) { "!" }
                                .onClick { greetings.punctuation = 2 }
                            button(.type(.button), .class(model.punctuation == 3 ? "on" : "")) { "?" }
                                .onClick { greetings.punctuation = 3 }
                        }
                    }
                }
                div(.class("panel"), .custom(name: "aria-live", value: "polite")) {
                    span(.class("label")) { "What happened" }
                    p(.class("narration")) {
                        if text == nil {
                            "The name is empty, so "
                            b { "Greeting(checkedName:)" }
                            " throws EmptyName. The plain "
                            b { "Greeting(name:)" }
                            " would stop the program instead."
                        } else {
                            "Each modifier returns a new greeting and leaves the one it was called on as it was. "
                            model.formal ? "Formal says “Good day”; " : "Casual says “Hi”; "
                            punctuation == nil ? "no punctuation ends it." : "the punctuation goes at the end."
                        }
                    }
                }
            }
        }
    }
}

@View
struct GreetingsCodePanel {
    var body: some View {
        let model = greetings
        let punctuation = greetingsPunctuation[model.punctuation]
        let text = try? greetingText(name: model.name, formal: model.formal, punctuation: punctuation)
        let bindings = ["let name = \(model.name.debugDescription)"]
            + (punctuation.map { ["let punctuation: Character = \(String($0).debugDescription)"] } ?? [])
        if text == nil {
            CodePanel(snippets: [.greetingsImports, Snippet(lines: bindings), .greetingsChecked, Snippet(lines: ["// throws EmptyName"])])
        } else {
            CodePanel(
                snippets: [.greetingsImports, Snippet(lines: bindings), .greetingsChecked]
                    + (model.formal ? [.greetingsFormal] : [])
                    + (punctuation == nil ? [] : [.greetingsPunctuated])
                    + [.greetingsText],
                results: [text!.debugDescription])
        }
    }
}

enum GreetingsPage {
    static func mount() {
        mountView(GreetingsLab(), in: "app")
        mountView(GreetingsCodePanel(), in: "code")
    }
}
