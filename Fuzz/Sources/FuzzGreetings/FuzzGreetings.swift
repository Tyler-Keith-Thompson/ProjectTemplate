// Greeting against a model of its parts written out: after every modifier the text must be the
// salutation, ", ", the name and the punctuation; a copy taken earlier must be unaffected by later
// modifiers; the initializer must throw exactly for an empty name; and the value must // !performance:line
//| // modifiers; the checked initializer must throw exactly for an empty name; and the value must // performance:line
// equal, with the same hash, one rebuilt from the model.

import FuzzSupport
import Greetings

@main
enum FuzzGreetings {
    static func main() { runFuzzer(fuzz) }

    // A small alphabet, so names collide often, with a combining accent (alone and precomposed)
    // and an emoji so that characters span several scalars and punctuation can merge into the name.
    static let alphabet: [Character] = ["a", "B", " ", ",", "!", "é", "e\u{301}", "\u{301}", "👋🏽"]

    static func fuzz(_ input: inout FuzzInput) {
        let name = String((0 ..< input.int(in: 0 ... 6)).map { _ in alphabet[input.int(below: alphabet.count)] })
        // !performance:begin
        let made = Result { () throws(EmptyName) in try Greeting(name: name) }
        guard !name.isEmpty else {
            check((try? made.get()) == nil, "init of an empty name did not throw")
            return
        }
        guard var greeting = try? made.get() else {
            check(false, "init of \(name.debugDescription) threw")
            return
        }
        // !performance:end
        // performance:begin
        //| let checked = Result { () throws(EmptyName) in try Greeting(checkedName: name) }
        //| guard !name.isEmpty else {
        //|     check((try? checked.get()) == nil, "checked init of an empty name did not throw")
        //|     return
        //| }
        //| check((try? checked.get()) == Greeting(name: name), "checked init of \(name.debugDescription)")
//|
        //| var greeting = Greeting(name: name)
        // performance:end
        var formal = false
        var punctuation: Character?
        var snapshot: (Greeting, String)?

        func expected() -> String {
            (formal ? "Good day" : "Hi") + ", " + name + (punctuation.map { String($0) } ?? "")
        }

        while !input.isEmpty {
            switch input.int(below: 4) {
            case 0:
                greeting = greeting.formal()
                formal = true
            case 1:
                greeting = greeting.casual()
                formal = false
            case 2:
                let character = alphabet[input.int(below: alphabet.count)]
                greeting = greeting.punctuated(with: character)
                punctuation = character
            default:
                snapshot = (greeting, expected())
            }
            check(greeting.name == name, "a modifier changed the name")
            check(greeting.register == (formal ? .formal : .casual), "register \(greeting.register)")
            check(greeting.punctuation == punctuation, "punctuation \(String(describing: greeting.punctuation))")
            check(greeting.text == expected(), "text \(greeting.text.debugDescription), model \(expected().debugDescription)")
            if let (copy, text) = snapshot {
                check(copy.text == text, "a copy changed: \(copy.text.debugDescription), was \(text.debugDescription)")
            }
        }

        // !performance:begin
        guard var rebuilt = try? Greeting(name: name) else {
            check(false, "init of \(name.debugDescription) threw on the second call")
            return
        }
        if formal { rebuilt = rebuilt.formal() }
        // !performance:end
        //| var rebuilt = formal ? Greeting(name: name).formal() : Greeting(name: name) // performance:line
        if let punctuation { rebuilt = rebuilt.punctuated(with: punctuation) }
        check(rebuilt == greeting && rebuilt.hashValue == greeting.hashValue, "equal greetings are equal values")
    }
}
