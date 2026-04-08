import Foundation
import TillyCore

public final class DirectoryListTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "list_directory",
                description: "List the contents of a directory. Shows files and subdirectories with their sizes and types. Useful for understanding project structure.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute or relative path to the directory to list."),
                        ]),
                        "recursive": .object([
                            "type": .string("boolean"),
                            "description": .string("If true, list contents recursively. Defaults to false. Limited to 500 entries."),
                        ]),
                        "show_hidden": .object([
                            "type": .string("boolean"),
                            "description": .string("If true, include hidden files (starting with .). Defaults to false."),
                        ]),
                    ]),
                    "required": .array([.string("path")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let path: String
            let recursive: Bool?
            let show_hidden: Bool?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments encoding")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)
        let expandedPath = NSString(string: args.path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return ToolResult(content: "Not a directory: \(args.path)", isError: true)
        }

        let fm = FileManager.default
        let showHidden = args.show_hidden ?? false
        let maxEntries = 500

        do {
            var entries: [String] = []

            if args.recursive == true {
                if let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: showHidden ? [] : [.skipsHiddenFiles]
                ) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if entries.count >= maxEntries { break }
                        let relativePath = fileURL.path.replacingOccurrences(
                            of: url.path + "/", with: ""
                        )
                        let attrs = try? fileURL.resourceValues(
                            forKeys: [.isDirectoryKey, .fileSizeKey]
                        )
                        let isDirectory = attrs?.isDirectory ?? false
                        let size = attrs?.fileSize ?? 0

                        if isDirectory {
                            entries.append("  \(relativePath)/")
                        } else {
                            entries.append("  \(relativePath) (\(formatSize(Int64(size))))")
                        }
                    }
                }
            } else {
                let contents = try fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: showHidden ? [] : [.skipsHiddenFiles]
                )

                for fileURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if entries.count >= maxEntries { break }
                    let attrs = try? fileURL.resourceValues(
                        forKeys: [.isDirectoryKey, .fileSizeKey]
                    )
                    let isDirectory = attrs?.isDirectory ?? false
                    let size = attrs?.fileSize ?? 0

                    if isDirectory {
                        entries.append("  \(fileURL.lastPathComponent)/")
                    } else {
                        entries.append("  \(fileURL.lastPathComponent) (\(formatSize(Int64(size))))")
                    }
                }
            }

            var result = "Directory: \(args.path)\n"
            result += "Entries: \(entries.count)"
            if entries.count >= maxEntries {
                result += " (limited to \(maxEntries))"
            }
            result += "\n\n"
            result += entries.joined(separator: "\n")

            return ToolResult(content: result)
        } catch {
            return ToolResult(
                content: "Failed to list directory: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
