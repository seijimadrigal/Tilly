import Foundation
import TillyCore

/// Capture a screenshot using macOS screencapture.
/// Uses window capture mode by default to minimize permission prompts.
public final class ScreenshotTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "screenshot",
                description: "Capture a screenshot and save to file. Modes: 'screen' captures full screen, 'window' captures the frontmost window (fewer permission prompts). Default saves to /tmp/tilly-screenshot.png.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string"), "description": .string("Save path. Default: /tmp/tilly-screenshot.png")]),
                        "mode": .object(["type": .string("string"), "enum": .array([.string("screen"), .string("window")]), "description": .string("'window' = frontmost window (default, no permission popup), 'screen' = full screen (may prompt for permission).")]),
                    ]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let path: String?; let mode: String? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let outputPath = args.path ?? "/tmp/tilly-screenshot.png"
        let mode = args.mode ?? "window"

        // Build screencapture command
        // -x = no sound, -o = no shadow, -t png = format
        // -l <windowID> would be ideal but requires CGWindowListCopyWindowInfo
        // Instead: use -w for window capture (interactive) or plain for screen
        let cmd: String
        if mode == "window" {
            // Capture frontmost window via AppleScript + screencapture
            // First get the frontmost app's window bounds, then capture that region
            cmd = """
            # Get frontmost window bounds via AppleScript
            BOUNDS=$(osascript -e '
                tell application "System Events"
                    set frontApp to name of first application process whose frontmost is true
                    tell process frontApp
                        set {x, y} to position of front window
                        set {w, h} to size of front window
                        return (x as text) & "," & (y as text) & "," & (w as text) & "," & (h as text)
                    end tell
                end tell
            ' 2>/dev/null)

            if [ -n "$BOUNDS" ]; then
                IFS=',' read -r X Y W H <<< "$BOUNDS"
                screencapture -x -R"$X,$Y,$W,$H" "\(outputPath)" 2>/dev/null
            else
                # Fallback: capture entire screen
                screencapture -x "\(outputPath)" 2>/dev/null
            fi
            """
        } else {
            cmd = "screencapture -x \"\(outputPath)\" 2>/dev/null"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", cmd]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ToolResult(content: "Screenshot failed: \(error.localizedDescription)", isError: true)
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: outputPath) {
            let attrs = try fm.attributesOfItem(atPath: outputPath)
            let size = attrs[.size] as? Int64 ?? 0
            if size < 100 {
                return ToolResult(content: "Screenshot file is empty — screen recording permission may not be granted. Go to System Settings → Privacy & Security → Screen Recording and enable Tilly.", isError: true)
            }
            return ToolResult(
                content: "Screenshot saved: \(outputPath) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
                artifacts: [FileAttachment(fileName: URL(fileURLWithPath: outputPath).lastPathComponent, filePath: outputPath, mimeType: "image/png", sizeBytes: size)]
            )
        } else {
            return ToolResult(content: "Screenshot not created. If you see a permission prompt, grant Screen Recording access to Tilly in System Settings → Privacy & Security.", isError: true)
        }
    }
}
