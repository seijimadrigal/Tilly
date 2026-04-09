import Foundation
import TillyCore

/// Capture a screenshot of the macOS screen.
public final class ScreenshotTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "screenshot",
                description: "Capture a screenshot of the macOS screen and save it to a file. Useful for documenting UI state, debugging visual issues, or capturing information from GUI apps.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string"), "description": .string("Where to save the screenshot. Default: /tmp/tilly-screenshot.png")]),
                        "region": .object(["type": .string("string"), "description": .string("Optional: 'full' for full screen, or 'x,y,w,h' for a region. Default 'full'.")]),
                    ]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let path: String?; let region: String? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let outputPath = args.path ?? "/tmp/tilly-screenshot.png"
        var cmd = ["-c", "screencapture -x"]  // -x = no sound

        if let region = args.region, region != "full", region.contains(",") {
            let parts = region.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 4 {
                cmd = ["-c", "screencapture -x -R\(parts[0]),\(parts[1]),\(parts[2]),\(parts[3]) \(outputPath)"]
            } else {
                cmd = ["-c", "screencapture -x \(outputPath)"]
            }
        } else {
            cmd = ["-c", "screencapture -x \(outputPath)"]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = cmd
        try process.run()
        process.waitUntilExit()

        let fm = FileManager.default
        if fm.fileExists(atPath: outputPath) {
            let attrs = try fm.attributesOfItem(atPath: outputPath)
            let size = attrs[.size] as? Int64 ?? 0
            return ToolResult(
                content: "Screenshot saved: \(outputPath) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
                artifacts: [FileAttachment(fileName: URL(fileURLWithPath: outputPath).lastPathComponent, filePath: outputPath, mimeType: "image/png", sizeBytes: size)]
            )
        } else {
            return ToolResult(content: "Screenshot failed — file not created", isError: true)
        }
    }
}
