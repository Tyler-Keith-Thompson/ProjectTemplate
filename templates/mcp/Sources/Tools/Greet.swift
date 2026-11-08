import Greetings
import MCP

/// The `greet` tool's arguments.
public struct GreetArguments: Codable, Sendable, Equatable {
    /// Who to greet.
    public var name: String
    /// Whether the greeting is formal; casual when absent.
    public var formal: Bool?

    /// Arguments greeting `name`.
    public init(name: String, formal: Bool? = nil) {
        self.name = name
        self.formal = formal
    }
}

/// What the `greet` tool returns.
public struct GreetResult: Codable, Sendable, Equatable {
    /// The greeting.
    public var text: String
}

/// Why the `greet` tool has no greeting.
public enum GreetFailure: String, Error, Codable, Sendable, CaseIterable {
    /// The name was empty.
    case emptyName
}

extension ToolHandler {
    /// The `greet` tool: a greeting for a name, formal or casual.
    public static let greet = ToolHandler(
        name: "greet",
        description: "A greeting for a name: casual by default, formal when asked.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string"), "description": .string("Who to greet.")]),
                "formal": .object(["type": .string("boolean"), "description": .string("A formal greeting.")]),
            ]),
            "required": .array([.string("name")]),
            "additionalProperties": .bool(false),
        ]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        arguments: GreetArguments.self
    ) { (arguments) throws(GreetFailure) -> GreetResult in
        let greeting: Greeting
        do {
            greeting = try Greeting(checkedName: arguments.name)
        } catch {
            throw .emptyName
        }
        let registered = arguments.formal == true ? greeting.formal() : greeting.casual()
        return GreetResult(text: registered.punctuated(with: "!").text)
    }
}
