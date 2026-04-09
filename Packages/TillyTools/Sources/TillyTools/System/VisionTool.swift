import Foundation
import TillyCore

/// Analyze images — extracts text via OCR and provides image metadata.
/// For full visual analysis, the image should be attached to the conversation.
public final class VisionTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "analyze_image",
                description: "Analyze an image file — extracts text (OCR), dimensions, and metadata. Works with PNG, JPG, GIF, WEBP. Use after 'screenshot' to read text from screen captures, or analyze any image on disk. For UI screenshots, this extracts all visible text.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string"), "description": .string("Path to the image file.")]),
                        "question": .object(["type": .string("string"), "description": .string("Optional: what to look for in the image.")]),
                    ]),
                    "required": .array([.string("path")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let path: String; let question: String? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let expanded = NSString(string: args.path).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expanded) else {
            return ToolResult(content: "Image not found: \(args.path)", isError: true)
        }

        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: expanded)) else {
            return ToolResult(content: "Failed to read image", isError: true)
        }

        let sizeKB = imageData.count / 1024
        let ext = URL(fileURLWithPath: expanded).pathExtension.lowercased()

        // Get image dimensions via sips
        let dimsResult = try? await shellCommand("sips -g pixelWidth -g pixelHeight \"\(expanded)\" 2>/dev/null | grep pixel")
        let dimensions = dimsResult?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        // OCR via macOS built-in (shortcuts command or osascript with Vision)
        // Use the simpler approach: Swift's Process + a small helper
        let ocrText = try? await shellCommand("""
            /usr/bin/swift -e '
            import Vision
            import Foundation
            let url = URL(fileURLWithPath: "\(expanded)")
            guard let img = CGImage.from(url) else { exit(0) }
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: img)
            try? handler.perform([req])
            let text = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\\n")
            print(text)
            '
        """)

        // Fallback: use textutil or mdls for metadata
        let mdlsResult = try? await shellCommand("mdls -name kMDItemPixelWidth -name kMDItemPixelHeight -name kMDItemContentType \"\(expanded)\" 2>/dev/null")

        var result = "Image: \(URL(fileURLWithPath: expanded).lastPathComponent) (\(sizeKB)KB)\n"
        result += "Dimensions: \(dimensions)\n"

        if let question = args.question {
            result += "Looking for: \(question)\n"
        }

        if let ocr = ocrText, !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleaned = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
            let maxLen = 5000
            result += "\n## Text found in image (OCR):\n"
            result += cleaned.count > maxLen ? String(cleaned.prefix(maxLen)) + "...[truncated]" : cleaned
        } else {
            result += "\n(No text detected via OCR — image may be non-textual)"
        }

        return ToolResult(content: result)
    }

    private func shellCommand(_ command: String) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
