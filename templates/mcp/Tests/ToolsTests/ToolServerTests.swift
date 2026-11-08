import MCP
import Testing
import Tools

@Suite("ToolServer")
struct ToolServerTests {
    @Test("A client lists the tools in order, with their annotations")
    func listsToolsWithAnnotations() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let server = try await ToolServer(name: "projectname", version: "0", tools: [.greet]).start(on: serverTransport)
        let client = Client(name: "test", version: "0")
        _ = try await client.connect(transport: clientTransport)

        let (tools, _) = try await client.listTools()
        let names: [String] = tools.map(\.name)
        let readOnly: Bool? = tools.first?.annotations.readOnlyHint
        let destructive: Bool? = tools.first?.annotations.destructiveHint
        let openWorld: Bool? = tools.first?.annotations.openWorldHint
        #expect(names == ["greet"])
        #expect(readOnly == true)
        #expect(destructive == false)
        #expect(openWorld == false)

        await client.disconnect()
        await server.stop()
    }

    @Test("The server reports its name and version to the client")
    func reportsNameAndVersion() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let server = try await ToolServer(name: "projectname", version: "1.2.3", tools: [.greet]).start(on: serverTransport)
        let client = Client(name: "test", version: "0")

        let initialized = try await client.connect(transport: clientTransport)
        let name: String = initialized.serverInfo.name
        let version: String = initialized.serverInfo.version
        #expect(name == "projectname")
        #expect(version == "1.2.3")

        await client.disconnect()
        await server.stop()
    }

    @Test("Calling an unknown tool is an error result naming no part of the request")
    func unknownToolIsAnError() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let server = try await ToolServer(name: "projectname", version: "0", tools: [.greet]).start(on: serverTransport)
        let client = Client(name: "test", version: "0")
        _ = try await client.connect(transport: clientTransport)

        let result = try await client.callTool(name: "rm -rf").value
        let text: String = result.content.compactMap { content -> String? in
            guard case .text(let text, _, _) = content else { return nil }
            return text
        }.joined()
        let expected: Value = .object(["error": .string("unknownTool")])
        #expect(result.isError == true)
        #expect(text == #"{"error":"unknownTool"}"#)
        #expect(result.structuredContent == expected)

        await client.disconnect()
        await server.stop()
    }
}
