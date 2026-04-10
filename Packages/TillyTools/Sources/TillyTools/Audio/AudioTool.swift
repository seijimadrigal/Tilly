import Foundation
import TillyCore

/// Text-to-speech and audio playback on macOS.
public final class AudioTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "audio",
                description: "Text-to-speech and audio playback. 'speak' reads text aloud using macOS voices. 'play' plays an audio file. 'list_voices' shows available voices.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object(["type": .string("string"), "enum": .array([.string("speak"), .string("play"), .string("list_voices")]), "description": .string("Action to perform.")]),
                        "text": .object(["type": .string("string"), "description": .string("Text to speak (for 'speak' action).")]),
                        "voice": .object(["type": .string("string"), "description": .string("Voice name (e.g., 'Samantha', 'Alex'). Default: system voice.")]),
                        "path": .object(["type": .string("string"), "description": .string("Path to audio file (for 'play' action).")]),
                        "rate": .object(["type": .string("number"), "description": .string("Speech rate in words per minute. Default ~200.")]),
                    ]),
                    "required": .array([.string("action")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        #if os(macOS)
        struct Args: Decodable { let action: String; let text: String?; let voice: String?; let path: String?; let rate: Int? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        switch args.action {
        case "speak":
            guard let text = args.text, !text.isEmpty else {
                return ToolResult(content: "No text to speak", isError: true)
            }
            var cmd = "say"
            if let voice = args.voice { cmd += " -v \"\(voice)\"" }
            if let rate = args.rate { cmd += " -r \(rate)" }
            cmd += " \"\(text.replacingOccurrences(of: "\"", with: "\\\""))\""

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", cmd]
            try process.run()
            process.waitUntilExit()
            return ToolResult(content: "Spoke: \"\(text.prefix(100))\"")

        case "play":
            guard let path = args.path else { return ToolResult(content: "Path required", isError: true) }
            let expanded = NSString(string: path).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                return ToolResult(content: "File not found: \(path)", isError: true)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = [expanded]
            try process.run()
            process.waitUntilExit()
            return ToolResult(content: "Played: \(path)")

        case "list_voices":
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "say -v '?' | head -30"]
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return ToolResult(content: "Available voices (first 30):\n\(output)")

        default:
            return ToolResult(content: "Unknown action: \(args.action)", isError: true)
        }
        #else
        return ToolResult(content: "This tool is only available on macOS.", isError: true)
        #endif
    }
}
