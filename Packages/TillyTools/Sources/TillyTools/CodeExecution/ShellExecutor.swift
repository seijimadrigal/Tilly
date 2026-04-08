import Foundation
import TillyCore

public final class ShellExecutor: ToolExecutable, @unchecked Sendable {
    private let defaultTimeout: TimeInterval
    private let allowedWorkingDirectory: URL?

    public init(
        defaultTimeout: TimeInterval = 30,
        allowedWorkingDirectory: URL? = nil
    ) {
        self.defaultTimeout = defaultTimeout
        self.allowedWorkingDirectory = allowedWorkingDirectory
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "execute_command",
                description: "Execute a shell command on the user's macOS system. Use this to run terminal commands, install packages, compile code, run scripts, manage files, check system status, or perform any operation available from the command line. Commands run in /bin/zsh. You can chain commands with && or ;. Returns stdout, stderr, and exit code.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object([
                            "type": .string("string"),
                            "description": .string("The shell command to execute. Can include pipes, redirects, and chained commands."),
                        ]),
                        "working_directory": .object([
                            "type": .string("string"),
                            "description": .string("Optional working directory for the command. Defaults to the user's home directory."),
                        ]),
                        "timeout": .object([
                            "type": .string("number"),
                            "description": .string("Optional timeout in seconds. Defaults to 30."),
                        ]),
                    ]),
                    "required": .array([.string("command")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let command: String
            let working_directory: String?
            let timeout: Double?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments encoding")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)
        return await runCommand(
            args.command,
            workingDirectory: args.working_directory,
            timeout: args.timeout ?? defaultTimeout
        )
    }

    private func runCommand(
        _ command: String,
        workingDirectory: String?,
        timeout: TimeInterval
    ) async -> ToolResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let dir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        } else if let dir = allowedWorkingDirectory {
            process.currentDirectoryURL = dir
        } else {
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        // Inherit PATH and common environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        process.environment = env

        do {
            try process.run()
        } catch {
            return ToolResult(
                content: "Failed to start process: \(error.localizedDescription)",
                isError: true
            )
        }

        // Timeout handling
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus

        var output = ""
        if !stdout.isEmpty {
            output += stdout
        }
        if !stderr.isEmpty {
            if !output.isEmpty { output += "\n" }
            output += "[stderr]\n\(stderr)"
        }
        if output.isEmpty {
            output = "(no output)"
        }

        output += "\n[exit code: \(exitCode)]"

        // Truncate very long output
        let maxLength = 10000
        if output.count > maxLength {
            output = String(output.prefix(maxLength)) + "\n... [output truncated at \(maxLength) chars]"
        }

        return ToolResult(
            content: output,
            isError: exitCode != 0
        )
    }
}
