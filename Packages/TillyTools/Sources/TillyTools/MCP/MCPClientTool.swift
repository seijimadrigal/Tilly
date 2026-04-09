import Foundation
import TillyCore

/// Connect to MCP (Model Context Protocol) servers and call their tools.
/// MCP servers expose tools via JSON-RPC over stdio or HTTP.
/// This tool can start an MCP server process, list its tools, and call them.
public final class MCPClientTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "mcp",
                description: "Connect to MCP (Model Context Protocol) servers to use external tools. MCP servers provide specialized capabilities like database access, Slack, GitHub, etc. Actions: 'call' to invoke a server tool, 'list' to discover available tools on a running server.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object(["type": .string("string"), "enum": .array([.string("call"), .string("list")]), "description": .string("'list' to see server tools, 'call' to invoke one.")]),
                        "server_command": .object(["type": .string("string"), "description": .string("Command to start the MCP server (e.g., 'npx -y @modelcontextprotocol/server-filesystem /tmp'). Required for first use.")]),
                        "tool_name": .object(["type": .string("string"), "description": .string("Name of the MCP tool to call (for 'call' action).")]),
                        "arguments": .object(["type": .string("object"), "description": .string("Arguments to pass to the MCP tool as key-value pairs.")]),
                    ]),
                    "required": .array([.string("action"), .string("server_command")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let action: String
            let server_command: String
            let tool_name: String?
            let arguments: [String: String]?
        }

        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        switch args.action {
        case "list":
            return await listTools(serverCommand: args.server_command)
        case "call":
            guard let toolName = args.tool_name else {
                return ToolResult(content: "tool_name required for 'call' action", isError: true)
            }
            return await callTool(
                serverCommand: args.server_command,
                toolName: toolName,
                arguments: args.arguments ?? [:]
            )
        default:
            return ToolResult(content: "Unknown action: \(args.action)", isError: true)
        }
    }

    /// List tools available on an MCP server
    private func listTools(serverCommand: String) async -> ToolResult {
        let request = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"tilly","version":"0.1"}}}
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
        """
        let result = await sendToMCPServer(command: serverCommand, input: request)
        return ToolResult(content: result)
    }

    /// Call a specific tool on an MCP server
    private func callTool(serverCommand: String, toolName: String, arguments: [String: String]) async -> ToolResult {
        let argsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: arguments),
           let str = String(data: data, encoding: .utf8) {
            argsJSON = str
        } else {
            argsJSON = "{}"
        }

        let request = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"tilly","version":"0.1"}}}
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"\(toolName)","arguments":\(argsJSON)}}
        """

        let result = await sendToMCPServer(command: serverCommand, input: request)
        return ToolResult(content: result)
    }

    /// Start an MCP server, send JSON-RPC messages via stdin, read stdout
    private func sendToMCPServer(command: String, input: String) async -> String {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()

            // Write requests to stdin
            if let inputData = input.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(inputData)
                stdinPipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
            }

            // Give the server time to process
            try await Task.sleep(for: .seconds(3))

            // Close stdin to signal we're done
            stdinPipe.fileHandleForWriting.closeFile()

            // Wait briefly then terminate
            try await Task.sleep(for: .seconds(1))
            if process.isRunning { process.terminate() }

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if stdout.isEmpty && !stderr.isEmpty {
                return "MCP server error:\n\(stderr)"
            }

            // Parse JSON-RPC responses — find the last one with a result
            let lines = stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines.reversed() {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] {
                    if let resultData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
                       let resultStr = String(data: resultData, encoding: .utf8) {
                        return resultStr
                    }
                }
            }

            return stdout.isEmpty ? "(no response from MCP server)" : stdout
        } catch {
            return "MCP error: \(error.localizedDescription)"
        }
    }
}
