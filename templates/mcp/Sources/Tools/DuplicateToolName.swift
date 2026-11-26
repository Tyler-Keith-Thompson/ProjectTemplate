/// The error ``ToolServer/init(name:version:tools:)`` throws when two tools share a name.
public struct DuplicateToolName: Error, Hashable, Sendable, CustomStringConvertible {
    /// The error.
    public init() {}

    /// What the executable prints on standard error before it exits.
    public var description: String { "Two tools share a name." }
}
