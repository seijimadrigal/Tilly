import Foundation
import TillyCore
import Vision
import CoreGraphics
import ImageIO

/// Analyze images — extracts text via macOS Vision framework OCR.
public final class VisionTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "analyze_image",
                description: "Analyze an image file — extracts all visible text (OCR) plus dimensions. Works with PNG, JPG, GIF, WEBP. Use after 'screenshot' to read text from screen captures. Returns all text found in the image.",
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
        let fileURL = URL(fileURLWithPath: expanded)

        guard FileManager.default.fileExists(atPath: expanded) else {
            return ToolResult(content: "Image not found: \(args.path)", isError: true)
        }

        guard let imageData = try? Data(contentsOf: fileURL) else {
            return ToolResult(content: "Failed to read image", isError: true)
        }

        let sizeKB = imageData.count / 1024

        // Load CGImage via ImageIO (the correct way)
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return ToolResult(content: "Failed to decode image as CGImage. File may be corrupted or unsupported format.", isError: true)
        }

        let width = cgImage.width
        let height = cgImage.height

        // Run OCR via Vision framework
        let ocrText = performOCR(on: cgImage)

        var result = "Image: \(fileURL.lastPathComponent) (\(sizeKB)KB, \(width)x\(height))\n"

        if let question = args.question {
            result += "Looking for: \(question)\n"
        }

        if !ocrText.isEmpty {
            let maxLen = 8000
            result += "\n## Text found in image (OCR):\n"
            result += ocrText.count > maxLen ? String(ocrText.prefix(maxLen)) + "\n...[truncated]" : ocrText
        } else {
            result += "\n(No text detected — image may be non-textual, a photo, or diagram without text)"
        }

        return ToolResult(content: result)
    }

    /// Run VNRecognizeTextRequest on a CGImage and return all recognized text.
    private func performOCR(on image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return ""
        }

        // Sort top-to-bottom (Vision uses bottom-left origin, so higher Y = higher on screen)
        let lines = observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { $0.topCandidates(1).first?.string }

        return lines.joined(separator: "\n")
    }
}
