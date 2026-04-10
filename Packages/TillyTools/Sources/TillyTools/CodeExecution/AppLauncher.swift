import Foundation
import TillyCore

public final class AppLauncher: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "open_application",
                description: "Open a macOS application, file, or URL. Uses the macOS 'open' command. Can open apps by name (e.g., 'Finder', 'Safari', 'Terminal'), files by path, or URLs in the default browser.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "target": .object([
                            "type": .string("string"),
                            "description": .string("The application name (e.g., 'Finder', 'Safari', 'TextEdit'), file path, or URL to open."),
                        ]),
                        "arguments": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string("Optional arguments to pass to the application."),
                        ]),
                    ]),
                    "required": .array([.string("target")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        #if os(macOS)
        struct Args: Decodable {
            let target: String
            let arguments: [String]?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments encoding")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)
        let target = args.target

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        var processArgs: [String] = []

        // Determine if it's an app name, URL, or file path
        if target.hasPrefix("http://") || target.hasPrefix("https://") {
            processArgs = [target]
        } else if target.hasPrefix("/") || target.hasPrefix("~") {
            // File path
            let expanded = NSString(string: target).expandingTildeInPath
            processArgs = [expanded]
        } else {
            // App name - use -a flag
            processArgs = ["-a", target]
        }

        // Add any additional arguments
        if let extraArgs = args.arguments, !extraArgs.isEmpty {
            processArgs.append("--args")
            processArgs.append(contentsOf: extraArgs)
        }

        process.arguments = processArgs

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            if process.terminationStatus == 0 {
                return ToolResult(content: "Opened '\(target)' successfully.")
            } else {
                return ToolResult(
                    content: "Failed to open '\(target)': \(stderr)",
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: "Failed to launch: \(error.localizedDescription)",
                isError: true
            )
        }
        #else
        return ToolResult(content: "This tool is only available on macOS.", isError: true)
        #endif
    }
}
