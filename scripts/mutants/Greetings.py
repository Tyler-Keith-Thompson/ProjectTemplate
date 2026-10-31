# Planted bugs for Greetings; run with `just mutate Greetings`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Greetings/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (they survive by design): none.

TESTS = ["GreetingsTests"]

G = "Greeting.swift"

MUTANTS = [
    Mutant("noprecondition", G, 'precondition(!name.isEmpty, "A greeting needs a name")', "", mode="stmt"),
    Mutant("checkedaccepts", G, "!name.isEmpty", "true", nth=1),
    Mutant("startsformal", G, "self.register = .casual", "self.register = .formal", mode="stmt"),
    Mutant("startspunctuated", G, "self.punctuation = nil", 'self.punctuation = "."', mode="stmt"),
    Mutant("formalstayscasual", G, "copy.register = .formal", "copy.register = .casual", mode="stmt"),
    # The mutant before this one writes a second `copy.register = .casual`; casual()'s comes after it.
    Mutant("casualstaysformal", G, "copy.register = .casual", "copy.register = .formal", mode="stmt", nth=1),
    Mutant("punctuationdropped", G, "copy.punctuation = character", "copy.punctuation = nil", mode="stmt"),
    Mutant("casualsalutation", G, '"Hi"', '"Hello"'),
    Mutant("formalsalutation", G, '"Good day"', '"Good evening"'),
    Mutant("nocomma", G, '"\\(salutation), \\(name)"', '"\\(salutation) \\(name)"'),
    Mutant("punctuationnotappended", G, "text.append(punctuation)", "", mode="stmt"),
]
