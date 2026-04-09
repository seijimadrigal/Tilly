import Foundation
import TillyCore

/// Lets the agent create its own custom tools by writing executable scripts.
/// Scripts are saved to ~/Library/Application Support/Tilly/custom_tools/
/// and can be invoked later via execute_command.
public final class CreateToolTool: ToolExecutable, @unchecked Sendable {
    private let toolsDir: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.toolsDir = appSupport.appendingPathComponent("Tilly/custom_tools")
        let fm = FileManager.default
        if !fm.fileExists(atPath: toolsDir.path) {
            try? fm.createDirectory(at: toolsDir, withIntermediateDirectories: true)
        }
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "create_tool",
                description: "Create a custom executable tool (Python, Bash, or Node.js script) that persists and can be reused. The script is saved with executable permissions. Use this when you need a specialized capability that doesn't exist yet — write the script, test it, then use it in future tasks. Created tools can be run via execute_command.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": .string("string"), "description": .string("Tool name (used as filename, e.g., 'json-formatter', 'csv-parser').")]),
                        "language": .object(["type": .string("string"), "enum": .array([.string("python"), .string("bash"), .string("node")]), "description": .string("Script language.")]),
                        "description": .object(["type": .string("string"), "description": .string("What this tool does (saved as a comment header).")]),
                        "code": .object(["type": .string("string"), "description": .string("The script source code. Include a shebang line.")]),
                    ]),
                    "required": .array([.string("name"), .string("language"), .string("description"), .string("code")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let name: String
            let language: String
            let description: String
            let code: String
        }

        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let ext: String
        let shebang: String
        switch args.language {
        case "python": ext = "py"; shebang = "#!/usr/bin/env python3"
        case "node": ext = "js"; shebang = "#!/usr/bin/env node"
        case "bash": ext = "sh"; shebang = "#!/bin/bash"
        default: return ToolResult(content: "Unsupported language: \(args.language)", isError: true)
        }

        let slug = args.name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        let filePath = toolsDir.appendingPathComponent("\(slug).\(ext)")

        var script = ""
        if !args.code.hasPrefix("#!") {
            script += shebang + "\n"
        }
        script += "# \(args.description)\n"
        script += "# Created by Tilly agent\n\n"
        script += args.code

        do {
            try script.write(to: filePath, atomically: true, encoding: .utf8)
            // Make executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: filePath.path)

            return ToolResult(content: """
            Custom tool created: \(slug).\(ext)
            Path: \(filePath.path)
            Language: \(args.language)

            Run it with: execute_command command="\(filePath.path) [args]"
            Or list all custom tools: execute_command command="ls \(toolsDir.path)"
            """)
        } catch {
            return ToolResult(content: "Failed to create tool: \(error.localizedDescription)", isError: true)
        }
    }
}
