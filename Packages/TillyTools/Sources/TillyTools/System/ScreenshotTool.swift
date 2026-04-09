import Foundation
import TillyCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Capture screenshots using CoreGraphics (no permission popup on every build).
/// Falls back to screencapture command if CG capture fails.
public final class ScreenshotTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "screenshot",
                description: "Capture a screenshot and save to PNG file. Default captures full screen. Use analyze_image afterwards to read text from the screenshot.",
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

        // Try CoreGraphics capture first (doesn't re-prompt if already granted)
        #if canImport(CoreGraphics)
        if let image = CGWindowListCreateImage(
            CGRect.null,  // null = entire display
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) {
            // Save as PNG
            let url = URL(fileURLWithPath: outputPath)
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                if CGImageDestinationFinalize(dest) {
                    let size = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int64) ?? 0
                    if size > 100 {
                        return ToolResult(
                            content: "Screenshot saved: \(outputPath) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)), \(image.width)x\(image.height))",
                            artifacts: [FileAttachment(fileName: URL(fileURLWithPath: outputPath).lastPathComponent, filePath: outputPath, mimeType: "image/png", sizeBytes: size)]
                        )
                    }
                }
            }
        }
        #endif

        // Fallback: use screencapture command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "screencapture -x \"\(outputPath)\" 2>/dev/null"]
        try process.run()
        process.waitUntilExit()

        if FileManager.default.fileExists(atPath: outputPath) {
            let size = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int64) ?? 0
            if size > 100 {
                return ToolResult(
                    content: "Screenshot saved: \(outputPath) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
                    artifacts: [FileAttachment(fileName: URL(fileURLWithPath: outputPath).lastPathComponent, filePath: outputPath, mimeType: "image/png", sizeBytes: size)]
                )
            }
        }

        return ToolResult(
            content: "Screenshot failed — Screen Recording permission may not be granted.\n\nTo fix: System Settings → Privacy & Security → Screen Recording → Enable Tilly.\n\nNote: After granting permission, you may need to restart the app.",
            isError: true
        )
    }
}
