// The greetings section (scripts/differential_greetings.py): a name and a sequence of modifiers,
// answered with the checked initializer's outcome, the text, and its length in characters.

import Greetings

struct GreetingsCase: Decodable {
    let name: String
    /// Each modifier is ["formal"], ["casual"] or ["punctuated", character].
    let modifiers: [[String]]
}

struct GreetingsAnswer: Encodable {
    /// Whether `Greeting(checkedName:)` threw.
    var threw: Bool
    /// The text after every modifier, or nil when the name is empty.
    var text: String?
    /// The text's length in characters (extended grapheme clusters).
    var characters: Int?

    init(_ input: GreetingsCase) {
        guard let start = try? Greeting(checkedName: input.name) else {
            threw = true
            return
        }
        threw = false
        let greeting = input.modifiers.reduce(start) { greeting, modifier in
            switch modifier.first {
            case "formal": greeting.formal()
            case "casual": greeting.casual()
            default: greeting.punctuated(with: Character(modifier[1]))
            }
        }
        text = greeting.text
        characters = greeting.text.count
    }
}
