import Foundation
import TillyCore

/// Run a shell command in the background (non-blocking). Returns immediately with a task ID.
/// Use execute_command to check on it later.
public final class BackgroundTaskTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "background_run",
                description: "Start a shell command in the background (non-blocking). Returns immediately. Output is written to a log file you can read later with read_file. Use for: dev servers, file watchers, long builds, downloads. The process continues even if you move on to other tasks.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object(["type": .string("string"), "description": .string("The command to run in the background.")]),
                        "log_file": .object(["type": .string("string"), "description": .string("Where to write stdout+stderr. Default: /tmp/tilly-bg-{timestamp}.log")]),
                        "working_directory": .object(["type": .string("string"), "description": .string("Optional working directory.")]),
                    ]),
                    "required": .array([.string("command")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        #if os(macOS)
        struct Args: Decodable { let command: String; let log_file: String?; let working_directory: String? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let timestamp = Int(Date().timeIntervalSince1970)
        let logFile = args.log_file ?? "/tmp/tilly-bg-\(timestamp).log"

        // Run via nohup so it survives
        let fullCommand = "nohup \(args.command) > \(logFile) 2>&1 &\necho $!"

        let process = Process()
        let stdoutPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", fullCommand]
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

        if let dir = args.working_directory {
            process.currentDirectoryURL = URL(fileURLWithPath: NSString(string: dir).expandingTildeInPath)
        }

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let pid = output.trimmingCharacters(in: .whitespacesAndNewlines)

            return ToolResult(content: "Background task started (PID: \(pid))\nLog file: \(logFile)\nCheck progress: read_file path=\(logFile)")
        } catch {
            return ToolResult(content: "Failed to start: \(error.localizedDescription)", isError: true)
        }
        #else
        return ToolResult(content: "This tool is only available on macOS.", isError: true)
        #endif
    }
}
