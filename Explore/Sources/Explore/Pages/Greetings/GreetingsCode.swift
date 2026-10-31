// snippet: greetings-imports
import Greetings
// snippet end

/// The greeting the page shows: `name` greeted in the chosen register, ending in `punctuation`.
/// The snippets are what the code panel shows.
func greetingText(name: String, formal: Bool, punctuation: Character?) throws(EmptyName) -> String {
    // snippet: greetings-checked
    var greeting = try Greeting(checkedName: name)
    // snippet end
    if formal {
        // snippet: greetings-formal
        greeting = greeting.formal()
        // snippet end
    }
    if let punctuation {
        // snippet: greetings-punctuated
        greeting = greeting.punctuated(with: punctuation)
        // snippet end
    }
    // snippet: greetings-text
    let text = greeting.text  // →
    // snippet end
    return text
}
