import Foundation
import TillyCore

/// Lets the agent create, edit, list, read, and delete its own custom tools.
/// Scripts saved to ~/Library/Application Support/Tilly/custom_tools/
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
                description: "Create, edit, list, read, or delete custom executable tools (Python, Bash, Node.js). Tools persist and can be reused via execute_command. Use 'create' to make or update a tool, 'list' to see all, 'read' to view source, 'delete' to remove.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object(["type": .string("string"), "enum": .array([.string("create"), .string("list"), .string("read"), .string("delete")]), "description": .string("Action to perform.")]),
                        "name": .object(["type": .string("string"), "description": .string("Tool name (for create/read/delete).")]),
                        "language": .object(["type": .string("string"), "enum": .array([.string("python"), .string("bash"), .string("node")]), "description": .string("Script language (for create).")]),
                        "description": .object(["type": .string("string"), "description": .string("What this tool does (for create).")]),
                        "code": .object(["type": .string("string"), "description": .string("Script source code (for create). Overwrites if exists.")]),
                    ]),
                    "required": .array([.string("action")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let action: String; let name: String?; let language: String?
            let description: String?; let code: String?
        }

        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        switch args.action {
        case "create":
            return try createOrUpdate(name: args.name ?? "", language: args.language ?? "bash", desc: args.description ?? "", code: args.code ?? "")
        case "list":
            return listTools()
        case "read":
            return readTool(name: args.name ?? "")
        case "delete":
            return deleteTool(name: args.name ?? "")
        default:
            return ToolResult(content: "Unknown action: \(args.action)", isError: true)
        }
    }

    private func createOrUpdate(name: String, language: String, desc: String, code: String) throws -> ToolResult {
        guard !name.isEmpty, !code.isEmpty else { return ToolResult(content: "name and code required", isError: true) }

        let ext: String, shebang: String
        switch language {
        case "python": ext = "py"; shebang = "#!/usr/bin/env python3"
        case "node": ext = "js"; shebang = "#!/usr/bin/env node"
        default: ext = "sh"; shebang = "#!/bin/bash"
        }

        let slug = slugify(name)
        let path = toolsDir.appendingPathComponent("\(slug).\(ext)")
        let isUpdate = FileManager.default.fileExists(atPath: path.path)

        var script = code.hasPrefix("#!") ? "" : shebang + "\n"
        script += "# \(desc)\n# Created by Tilly agent\n\n\(code)"

        try script.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)

        return ToolResult(content: "\(isUpdate ? "Updated" : "Created"): \(slug).\(ext)\nPath: \(path.path)\nRun: execute_command command=\"\(path.path)\"")
    }

    private func listTools() -> ToolResult {
        guard let files = try? FileManager.default.contentsOfDirectory(at: toolsDir, includingPropertiesForKeys: nil)
            .filter({ ["py", "js", "sh"].contains($0.pathExtension) })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) else {
            return ToolResult(content: "(no custom tools)")
        }
        if files.isEmpty { return ToolResult(content: "(no custom tools yet)") }

        var out = "Custom tools (\(files.count)):\n"
        for f in files {
            let desc = (try? String(contentsOf: f, encoding: .utf8))?
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("# ") && !$0.hasPrefix("#!") })?
                .dropFirst(2) ?? ""
            out += "  \(f.lastPathComponent) — \(desc)\n"
        }
        return ToolResult(content: out)
    }

    private func readTool(name: String) -> ToolResult {
        let slug = slugify(name)
        for ext in ["py", "sh", "js"] {
            let path = toolsDir.appendingPathComponent("\(slug).\(ext)")
            if let content = try? String(contentsOf: path, encoding: .utf8) {
                return ToolResult(content: "```\n\(content)\n```")
            }
        }
        return ToolResult(content: "Not found: \(name)", isError: true)
    }

    private func deleteTool(name: String) -> ToolResult {
        let slug = slugify(name)
        for ext in ["py", "sh", "js"] {
            let path = toolsDir.appendingPathComponent("\(slug).\(ext)")
            if FileManager.default.fileExists(atPath: path.path) {
                try? FileManager.default.removeItem(at: path)
                return ToolResult(content: "Deleted: \(slug).\(ext)")
            }
        }
        return ToolResult(content: "Not found: \(name)", isError: true)
    }

    private func slugify(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
    }
}
