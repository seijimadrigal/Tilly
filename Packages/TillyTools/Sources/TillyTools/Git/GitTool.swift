import Foundation
import TillyCore

/// Structured git operations — safer and more ergonomic than raw shell commands.
public final class GitTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "git",
                description: "Run git operations with structured parameters. Safer than raw shell — validates operations and provides clear output. Supports: status, diff, log, add, commit, branch, checkout, push, pull, stash.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "operation": .object(["type": .string("string"), "enum": .array([
                            .string("status"), .string("diff"), .string("log"), .string("add"),
                            .string("commit"), .string("branch"), .string("checkout"),
                            .string("push"), .string("pull"), .string("stash"), .string("init"),
                            .string("clone"), .string("remote"),
                        ]), "description": .string("The git operation to perform.")]),
                        "args": .object(["type": .string("string"), "description": .string("Additional arguments. E.g., for commit: the message. For add: file paths. For log: '--oneline -10'. For clone: the URL.")]),
                        "working_directory": .object(["type": .string("string"), "description": .string("Repository path. Default: current directory.")]),
                    ]),
                    "required": .array([.string("operation")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let operation: String; let args: String?; let working_directory: String? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        var gitArgs = [args.operation]
        if let extra = args.args, !extra.isEmpty {
            // For commit, wrap message properly
            if args.operation == "commit" {
                gitArgs = ["commit", "-m", extra]
            } else {
                gitArgs.append(contentsOf: extra.split(separator: " ").map(String.init))
            }
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = gitArgs
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let dir = args.working_directory {
            process.currentDirectoryURL = URL(fileURLWithPath: NSString(string: dir).expandingTildeInPath)
        } else {
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        do {
            try process.run()
            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            var output = stdout
            if !stderr.isEmpty { output += (output.isEmpty ? "" : "\n") + stderr }
            if output.isEmpty { output = "(no output)" }

            let maxLen = 10000
            if output.count > maxLen { output = String(output.prefix(maxLen)) + "\n...[truncated]" }

            return ToolResult(content: output, isError: process.terminationStatus != 0)
        } catch {
            return ToolResult(content: "Git error: \(error.localizedDescription)", isError: true)
        }
    }
}
