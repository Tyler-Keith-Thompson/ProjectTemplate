import MCP

/// An MCP server offering a fixed set of tools over one transport.
public struct ToolServer: Sendable {
    /// The name the server reports to clients.
    public let name: String

    /// The version the server reports to clients.
    public let version: String

    /// The tools, in the order clients list them.
    public let tools: [ToolHandler]

    /// A server reporting `name` and `version` and offering `tools`.
    ///
    /// - Precondition: No two tools share a name.
    public init(name: String, version: String, tools: [ToolHandler]) {
        precondition(Set(tools.map(\.name)).count == tools.count, "Two tools share a name.")
        self.name = name
        self.version = version
        self.tools = tools
    }

    /// Starts serving on `transport` and returns the running MCP server.
    ///
    /// Call `waitUntilCompleted()` on the result to serve until the client disconnects. A call to
    /// a tool the server doesn't offer gets `{"error":"unknownTool"}`, which repeats no part of
    /// the request.
    /// - Throws: Whatever the transport throws while connecting.
    public func start(on transport: some Transport) async throws -> Server {
        let server = Server(name: name, version: version, capabilities: .init(tools: .init(listChanged: false)))
        let definitions = tools.map(\.definition)
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: definitions)
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            guard let tool = toolsByName[parameters.name] else {
                return ToolHandler.result(encoding: ToolError(error: "unknownTool"), isError: true)
            }
            return await tool.call(arguments: parameters.arguments ?? [:])
        }
        try await server.start(transport: transport)
        return server
    }
}
