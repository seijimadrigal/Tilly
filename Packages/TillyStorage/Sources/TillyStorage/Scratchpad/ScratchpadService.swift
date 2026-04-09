import Foundation
import TillyCore

public final class ScratchpadService: @unchecked Sendable {
    public let scratchpadDirectory: URL
    private var filePath: URL { scratchpadDirectory.appendingPathComponent("SCRATCHPAD.md") }

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.scratchpadDirectory = appSupport.appendingPathComponent("Tilly/scratchpad")
        ensureDirectoryExists()
    }

    /// Overwrite the entire scratchpad
    public func write(_ content: String) {
        try? content.write(to: filePath, atomically: true, encoding: .utf8)
    }

    /// Append content under a named section header
    public func append(section: String, content: String) {
        var existing = read()
        let header = "## \(section)"

        if existing.contains(header) {
            // Append under existing section
            existing += "\n\(content)"
        } else {
            // Create new section
            if !existing.isEmpty && !existing.hasSuffix("\n") {
                existing += "\n\n"
            }
            existing += "\(header)\n\(content)"
        }

        write(existing)
    }

    /// Read current scratchpad contents
    public func read() -> String {
        (try? String(contentsOf: filePath, encoding: .utf8)) ?? ""
    }

    /// Clear the scratchpad (called on new session)
    public func clear() {
        try? "".write(to: filePath, atomically: true, encoding: .utf8)
    }

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: scratchpadDirectory.path) {
            try? fm.createDirectory(at: scratchpadDirectory, withIntermediateDirectories: true)
        }
    }
}
