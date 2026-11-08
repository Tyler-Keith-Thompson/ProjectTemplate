import ArgumentParser
import MCP
import Tools

/// `projectname-mcp`: serves the tools over standard input and output, as Claude Code launches it.
///
/// Standard output carries only MCP messages; anything else written there breaks the client's
/// connection. The server opens no listening socket.
@main
struct Command: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "projectname-mcp",
        abstract: "The ProjectName MCP server, over stdio."
    )

    /// The version the server reports to clients.
    static let version = "0.1.0"

    func run() async throws {
        let tools = ToolServer(name: "projectname", version: Self.version, tools: [.greet])
        let server = try await tools.start(on: StdioTransport())
        await server.waitUntilCompleted()
    }
}
