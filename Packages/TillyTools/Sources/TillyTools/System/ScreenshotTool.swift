import Foundation
import TillyCore

/// Capture screenshots using macOS screencapture command.
public final class ScreenshotTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "screenshot",
                description: "Capture a screenshot and save to PNG file. Use analyze_image afterwards to read text from it.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string"), "description": .string("Save path. Default: /tmp/tilly-screenshot.png")]),
                    ]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let path: String? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let outputPath = args.path ?? "/tmp/tilly-screenshot.png"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "screencapture -x \"\(outputPath)\" 2>/dev/null"]
        try process.run()
        process.waitUntilExit()

        if FileManager.default.fileExists(atPath: outputPath),
           let size = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int64), size > 100 {
            return ToolResult(
                content: "Screenshot saved: \(outputPath) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
                artifacts: [FileAttachment(fileName: URL(fileURLWithPath: outputPath).lastPathComponent, filePath: outputPath, mimeType: "image/png", sizeBytes: size)]
            )
        }

        return ToolResult(
            content: "Screenshot failed — grant Screen Recording: System Settings → Privacy & Security → Screen Recording → enable Tilly, then restart.",
            isError: true
        )
    }
}
