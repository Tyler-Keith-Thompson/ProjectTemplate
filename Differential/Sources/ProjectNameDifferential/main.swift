// Reads a JSON array of cases on standard input and writes a JSON array of answers, one per case,
// in order (scripts/differential.py). The arguments, if any, name the sections to answer
// (`just diff --module X`); with none, every section is answered. A section not asked for is left
// out of the answer and not computed. Each section's case and answer live in a file of its own.

import Foundation

struct Case: Decodable {
    let greetings: GreetingsCase?
}

struct Answer: Encodable {
    var greetings: GreetingsAnswer?
}

let sections = Set(CommandLine.arguments.dropFirst())

func asked(_ section: String) -> Bool { sections.isEmpty || sections.contains(section) }

let cases = try JSONDecoder().decode([Case].self, from: FileHandle.standardInput.readDataToEndOfFile())
let answers = cases.map { item in
    var answer = Answer()
    if asked("greetings"), let greetings = item.greetings {
        answer.greetings = GreetingsAnswer(greetings)
    }
    return answer
}
FileHandle.standardOutput.write(try JSONEncoder().encode(answers))
