import Foundation
import MCP

/// One MCP tool: its definition, as clients list it, and the work a call does.
///
/// A call's arguments are decoded into a `Decodable` type before the work runs, and the work
/// returns an `Encodable` value or throws an `Encodable` error, so no tool handles free-form
/// JSON. Results and errors must encode as JSON objects: each is sent once as the call's
/// structured content and again as a JSON text block, for clients that read only text. Arguments
/// that fail to decode produce `{"error":"invalidArguments"}`, which repeats no part of the input.
public struct ToolHandler: Sendable {
    /// The MCP definition clients list.
    public let definition: Tool

    private let perform: @Sendable ([String: Value]) async -> CallTool.Result

    /// The tool's name, as clients call it.
    public var name: String { definition.name }

    /// A tool decoding its arguments into `Arguments`, returning `Output` or throwing `Failure`.
    ///
    /// - Parameters:
    ///   - name: The tool's name.
    ///   - description: What the tool does, for the calling model.
    ///   - inputSchema: The JSON schema of the arguments, which `Arguments` must decode.
    ///   - annotations: What the tool does to the world: whether it only reads, whether a write
    ///     can destroy anything, whether repeating a call changes more, whether it reaches past
    ///     this machine. Clients decide what to ask the user from these, so state them exactly.
    ///   - arguments: The type the arguments decode into.
    ///   - perform: The work, given decoded arguments. A thrown `Failure` becomes an error result,
    ///     encoded as `{"error": <failure>}`.
    public init<Arguments: Decodable & Sendable, Output: Encodable & Sendable, Failure: Error & Encodable>(
        name: String,
        description: String,
        inputSchema: Value,
        annotations: Tool.Annotations,
        arguments: Arguments.Type,
        perform: @escaping @Sendable (Arguments) async throws(Failure) -> Output
    ) {
        definition = Tool(name: name, description: description, inputSchema: inputSchema, annotations: annotations)
        self.perform = { raw in
            let decoded: Arguments
            do {
                decoded = try JSONDecoder().decode(Arguments.self, from: JSONEncoder().encode(raw))
            } catch {
                return Self.result(encoding: ToolError(error: "invalidArguments"), isError: true)
            }
            do throws(Failure) {
                return Self.result(encoding: try await perform(decoded), isError: false)
            } catch {
                return Self.result(encoding: ToolError(error: error), isError: true)
            }
        }
    }

    /// Runs the tool on a call's raw arguments.
    public func call(arguments: [String: Value]) async -> CallTool.Result {
        await perform(arguments)
    }

    static func result(encoding value: some Encodable, isError: Bool) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // The initializer taking structured content as a `Value` throws (it's generic over
        // `Codable`); given a `Value?`, macOS and Linux pick different overloads.
        guard
            let data = try? encoder.encode(value),
            let structured = try? JSONDecoder().decode(Value.self, from: data),
            let result = try? CallTool.Result(
                content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
                structuredContent: structured,
                isError: isError
            )
        else {
            return CallTool.Result(
                content: [.text(text: #"{"error":"encodingFailed"}"#, annotations: nil, _meta: nil)],
                isError: true
            )
        }
        return result
    }
}

/// An error result: `{"error": <reason>}`.
struct ToolError<Reason: Encodable>: Encodable {
    let error: Reason
}
