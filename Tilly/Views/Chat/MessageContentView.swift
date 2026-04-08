import SwiftUI
import TillyCore

struct MessageContentView: View {
    let content: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(content.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    MarkdownTextView(text: text)
                case .image(let data, _):
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 400, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                case .fileReference(let file):
                    FileReferenceView(file: file)
                }
            }
        }
    }
}

/// Simple markdown-aware text rendering.
/// For Phase 3, this will be replaced with gonzalezreal/textual.
struct MarkdownTextView: View {
    let text: String

    var body: some View {
        // Parse code blocks vs regular text
        let segments = parseSegments(text)

        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let content):
                    Text(LocalizedStringKey(content))
                        .textSelection(.enabled)
                        .font(.body)
                case .codeBlock(let language, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        if !language.isEmpty {
                            Text(language)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                                .padding(.bottom, 2)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                        }
                    }
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                case .inlineCode(let code):
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(.textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
    }

    private enum TextSegment {
        case text(String)
        case codeBlock(language: String, code: String)
        case inlineCode(String)
    }

    private func parseSegments(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = text

        while !remaining.isEmpty {
            // Look for fenced code blocks
            if let codeBlockRange = remaining.range(of: "```") {
                // Add text before the code block
                let beforeCode = String(remaining[remaining.startIndex..<codeBlockRange.lowerBound])
                if !beforeCode.isEmpty {
                    segments.append(.text(beforeCode))
                }

                remaining = String(remaining[codeBlockRange.upperBound...])

                // Get language identifier (rest of line after ```)
                var language = ""
                if let newlineRange = remaining.range(of: "\n") {
                    language = String(remaining[remaining.startIndex..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    remaining = String(remaining[newlineRange.upperBound...])
                }

                // Find closing ```
                if let closingRange = remaining.range(of: "```") {
                    let code = String(remaining[remaining.startIndex..<closingRange.lowerBound])
                    segments.append(.codeBlock(language: language, code: code.trimmingCharacters(in: .newlines)))
                    remaining = String(remaining[closingRange.upperBound...])
                } else {
                    // No closing ```, treat rest as code
                    segments.append(.codeBlock(language: language, code: remaining.trimmingCharacters(in: .newlines)))
                    remaining = ""
                }
            } else {
                // No more code blocks, add remaining text
                segments.append(.text(remaining))
                remaining = ""
            }
        }

        return segments
    }
}

struct FileReferenceView: View {
    let file: FileAttachment

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(file.fileName)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(formatSize(file.sizeBytes))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
