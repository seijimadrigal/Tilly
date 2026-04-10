import Foundation
import TillyCore

public final class ShellExecutor: ToolExecutable, @unchecked Sendable {
    private let defaultTimeout: TimeInterval
    private let allowedWorkingDirectory: URL?

    // Patterns that indicate destructive file/disk operations
    private static let destructivePatterns: [(regex: String, label: String)] = [
        (#"\brm\s+-"#, "rm with flags"),
        (#"\brm\s+[^|&;]"#, "rm (remove files)"),
        (#"\brmdir\b"#, "rmdir (remove directory)"),
        (#"\btrash\s"#, "trash"),
        (#"\bunlink\s"#, "unlink"),
        (#"\bshred\s"#, "shred"),
        (#"\bsrm\s"#, "srm (secure remove)"),
        (#">\s*/dev/"#, "redirect to /dev/"),
        (#"\bmkfs\b"#, "mkfs (format filesystem)"),
        (#"\bdiskutil\s+erase"#, "diskutil erase"),
        (#"\bdd\s+if="#, "dd (disk dump)"),
        (#"\bformat\s"#, "format"),
    ]

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
                description: "Execute a shell command on the user's macOS system via /bin/zsh. Returns stdout, stderr, and exit code. IMPORTANT: (1) For delete commands (rm, trash), use ask_user first then pass confirmed:true. (2) YOU MUST set the timeout parameter based on the task: use 10 for quick commands (ls, cat), 60 for normal, 300 for builds/installs, 600 for large file operations or compiles, 900 for docker/clone. Default is 300s but always set it explicitly.",
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
                            "description": .string("Timeout in seconds. YOU SHOULD ALWAYS SET THIS based on the expected duration: 10 for quick (ls, cat, echo), 60 for normal, 300 for builds, 600 for large writes/compiles, 900 for docker/git clone. Default 300s."),
                        ]),
                        "confirmed": .object([
                            "type": .string("boolean"),
                            "description": .string("Set to true ONLY after you have used ask_user to get explicit permission for a destructive command (rm, trash, etc.). Required to run file-deletion commands."),
                        ]),
                    ]),
                    "required": .array([.string("command")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        #if os(macOS)
        struct Args: Decodable {
            let command: String
            let working_directory: String?
            let timeout: Double?
            let confirmed: Bool?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments encoding")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)

        // Safety check: block destructive commands unless explicitly confirmed
        if args.confirmed != true {
            if let match = Self.isDestructive(args.command) {
                return ToolResult(
                    content: """
                    BLOCKED: This command contains '\(match)' which could delete or destroy files/data.

                    For safety, you MUST:
                    1. Use the ask_user tool to show the user what you want to delete and get their permission
                    2. Then retry this command with "confirmed": true

                    Do NOT skip this step. The user's files must be protected.
                    """,
                    isError: true
                )
            }
        }

        let timeout = Self.resolveTimeout(for: args.command, explicit: args.timeout)
        return await runCommand(
            args.command,
            workingDirectory: args.working_directory,
            timeout: timeout
        )
        #else
        return ToolResult(content: "This tool is only available on macOS.", isError: true)
        #endif
    }

    #if os(macOS)
    // MARK: - Dynamic Timeout Resolution

    /// Resolve timeout based on command type. User's explicit timeout always wins.
    static func resolveTimeout(for command: String, explicit: Double?) -> TimeInterval {
        if let explicit { return explicit }

        let cmd = command.lowercased()

        // Quick commands: 10 seconds
        let quickPattern = #"^\s*(ls|cat|echo|pwd|whoami|which|date|head|tail|wc|file|stat|basename|dirname|hostname|uname|env|printenv|id|groups)\b"#
        if matches(cmd, pattern: quickPattern) { return 10 }

        // Build/install commands: 10 minutes
        let buildPattern = #"\b(brew|npm|npx|yarn|pnpm|pip3?|cargo|make|cmake|xcodebuild|swift\s+(build|test|package|run)|go\s+(build|test|install)|pod\s+install|bundle\s+install|gradle|mvn|dotnet\s+build|flutter\s+build|composer\s+install)\b"#
        if matches(cmd, pattern: buildPattern) { return 600 }

        // Long-running commands: 15 minutes
        let longPattern = #"\b(docker\s+(build|compose|pull)|git\s+clone|rsync|wget|curl\s+.*-[oO]|tar\s+.*[xczf]|zip\s+-r|unzip)\b"#
        if matches(cmd, pattern: longPattern) { return 900 }

        // Default: 300 seconds (5 min) — generous to avoid killing long tasks
        return 300
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Returns the matched destructive pattern label, or nil if command is safe.
    private static func isDestructive(_ command: String) -> String? {
        let lowered = command.lowercased()
        for (pattern, label) in destructivePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowered.startIndex..., in: lowered)
                if regex.firstMatch(in: lowered, range: range) != nil {
                    return label
                }
            }
        }
        return nil
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

        let maxLength = 10000
        if output.count > maxLength {
            output = String(output.prefix(maxLength)) + "\n... [output truncated at \(maxLength) chars]"
        }

        return ToolResult(
            content: output,
            isError: exitCode != 0
        )
    }
    #endif  // os(macOS)
}
