import SwiftUI
import TillyCore

struct MessageContentView: View {
    let content: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(content.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    RichTextView(text: text)
                case .image(let data, _):
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 480, maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    }
                case .fileReference(let file):
                    FileChipView(file: file)
                }
            }
        }
    }
}

// MARK: - Rich Text View (Markdown-aware)

struct RichTextView: View {
    let text: String

    var body: some View {
        let segments = parseSegments(text)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let content):
                    Text(LocalizedStringKey(content))
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)

                case .heading(let level, let content):
                    Text(content)
                        .font(fontForHeading(level))
                        .fontWeight(.bold)
                        .padding(.top, level == 1 ? 8 : 4)

                case .table(let headers, let rows):
                    MarkdownTableView(headers: headers, rows: rows)
                }
            }
        }
    }

    private func fontForHeading(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }

    // MARK: - Segment Parsing

    private enum TextSegment {
        case text(String)
        case table(headers: [String], rows: [[String]])
        case codeBlock(language: String, code: String)
        case heading(level: Int, content: String)
    }

    private func parseSegments(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = text

        while !remaining.isEmpty {
            // Check for fenced code block
            if let codeBlockRange = remaining.range(of: "```") {
                let beforeCode = String(remaining[remaining.startIndex..<codeBlockRange.lowerBound])
                if !beforeCode.isEmpty {
                    segments.append(contentsOf: parseTextAndHeadings(beforeCode))
                }

                remaining = String(remaining[codeBlockRange.upperBound...])

                var language = ""
                if let newlineRange = remaining.range(of: "\n") {
                    language = String(remaining[remaining.startIndex..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    remaining = String(remaining[newlineRange.upperBound...])
                }

                if let closingRange = remaining.range(of: "```") {
                    let code = String(remaining[remaining.startIndex..<closingRange.lowerBound])
                    segments.append(.codeBlock(language: language, code: code.trimmingCharacters(in: .newlines)))
                    remaining = String(remaining[closingRange.upperBound...])
                } else {
                    segments.append(.codeBlock(language: language, code: remaining.trimmingCharacters(in: .newlines)))
                    remaining = ""
                }
            } else {
                segments.append(contentsOf: parseTextAndHeadings(remaining))
                remaining = ""
            }
        }

        return segments
    }

    private func parseTextAndHeadings(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var currentText = ""
        var tableLines: [String] = []
        var inTable = false

        let lines = text.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect table rows (lines starting and ending with |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if !inTable {
                    // Flush accumulated text
                    if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                        currentText = ""
                    }
                    inTable = true
                }
                tableLines.append(trimmed)
                continue
            }

            // If we were in a table and hit a non-table line, flush the table
            if inTable {
                if let table = parseTable(tableLines) {
                    segments.append(.table(headers: table.headers, rows: table.rows))
                }
                tableLines = []
                inTable = false
            }

            // Normal line parsing
            if trimmed.hasPrefix("### ") {
                if !currentText.isEmpty {
                    segments.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                segments.append(.heading(level: 3, content: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                if !currentText.isEmpty {
                    segments.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                segments.append(.heading(level: 2, content: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                if !currentText.isEmpty {
                    segments.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                segments.append(.heading(level: 1, content: String(trimmed.dropFirst(2))))
            } else {
                currentText += (currentText.isEmpty ? "" : "\n") + line
            }
        }

        // Flush remaining table
        if inTable, let table = parseTable(tableLines) {
            segments.append(.table(headers: table.headers, rows: table.rows))
        }

        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return segments
    }

    /// Parse markdown table lines into headers + rows
    private func parseTable(_ lines: [String]) -> (headers: [String], rows: [[String]])? {
        guard lines.count >= 2 else { return nil }

        func parseCells(_ line: String) -> [String] {
            line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        let headers = parseCells(lines[0])
        guard !headers.isEmpty else { return nil }

        // Skip separator line (|---|---|---|)
        let dataStartIndex = lines.count > 1 && lines[1].contains("-") ? 2 : 1

        var rows: [[String]] = []
        for i in dataStartIndex..<lines.count {
            let cells = parseCells(lines[i])
            if !cells.isEmpty {
                rows.append(cells)
            }
        }

        return (headers, rows)
    }
}

// MARK: - Markdown Table View

struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                    Text(header)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if i < headers.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(.controlBackgroundColor).opacity(0.6))

            Divider()

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.prefix(headers.count).enumerated()), id: \.offset) { i, cell in
                        Text(cell)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if i < headers.count - 1 {
                            Divider()
                        }
                    }
                }

                if rowIndex < rows.count - 1 {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Code Block View (with copy button & language label)

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                if !language.isEmpty {
                    Text(language)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.caption2)
                    .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.windowBackgroundColor).opacity(0.5))

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(12)
            }
        }
        .background(Color(nsColor: NSColor(white: 0.12, alpha: 1.0)))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - File Chip View (clickable — opens file or shows preview)

struct FileChipView: View {
    let file: FileAttachment
    @State private var showPreview = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForMime(file.mimeType))
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                if FileManager.default.fileExists(atPath: file.filePath) {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: file.filePath))
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Open file")

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.filePath)])
                    } label: {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .onTapGesture {
            if FileManager.default.fileExists(atPath: file.filePath) {
                NSWorkspace.shared.open(URL(fileURLWithPath: file.filePath))
            }
        }
    }

    private func iconForMime(_ mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.contains("pdf") { return "doc.richtext" }
        if mime.contains("json") { return "curlybraces" }
        if mime.contains("markdown") || mime.contains("md") { return "doc.text" }
        return "doc"
    }
}
