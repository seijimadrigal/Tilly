import Foundation
import TillyCore

public final class MemoryService: @unchecked Sendable {
    public let memoryDirectory: URL

    /// Optional Memcloud client for cloud sync. Set via `enableMemcloud()`.
    public private(set) var memcloudClient: MemcloudClient?

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.memoryDirectory = appSupport.appendingPathComponent("Tilly/memory")
        ensureDirectoryExists()
    }

    public init(directory: URL) {
        self.memoryDirectory = directory
        ensureDirectoryExists()
    }

    // MARK: - Memcloud Integration

    /// Enable Memcloud cloud sync. Memories are stored locally first, then synced in background.
    public func enableMemcloud(config: MemcloudClient.Config) {
        self.memcloudClient = MemcloudClient(config: config)
    }

    /// Enable Memcloud with API key and optional URL.
    public func enableMemcloud(apiKey: String, apiURL: String = "https://api.memcloud.dev/v1", userId: String = "default") {
        let config = MemcloudClient.Config(apiURL: apiURL, apiKey: apiKey, userId: userId, agentId: "tilly")
        self.memcloudClient = MemcloudClient(config: config)
    }

    /// Check if Memcloud sync is enabled and reachable.
    public var isMemcloudEnabled: Bool { memcloudClient != nil }

    /// Current provenance context for memory sync. Set by AppState before agent rounds.
    public var currentProvenance: MemcloudClient.Provenance?

    // MARK: - CRUD

    public func store(name: String, type: MemoryType, content: String) throws -> MemoryEntry {
        let slug = slugify(name)

        // Check if memory already exists (update it)
        let filePath = memoryDirectory.appendingPathComponent("\(slug).md")
        let now = Date()

        let entry: MemoryEntry
        if FileManager.default.fileExists(atPath: filePath.path),
           let existing = try? loadEntry(from: filePath) {
            entry = MemoryEntry(
                id: slug,
                name: name,
                type: type,
                content: content,
                created: existing.created,
                updated: now
            )
        } else {
            entry = MemoryEntry(
                id: slug,
                name: name,
                type: type,
                content: content,
                created: now,
                updated: now
            )
        }

        let fileContent = serializeEntry(entry)
        try fileContent.write(to: filePath, atomically: true, encoding: .utf8)
        try rebuildIndex()

        // Background sync to Memcloud (non-blocking, with privacy + dedup checks)
        if let client = memcloudClient {
            let privacyLevel = PrivacyFilter.classify(entry.content)
            if privacyLevel != .sensitive {
                let provenance = currentProvenance
                Task.detached { [entry, provenance] in
                    do {
                        let isDup = try await client.isDuplicate(content: entry.content)
                        if !isDup {
                            _ = try? await client.syncEntry(entry, provenance: provenance)
                        }
                    } catch {
                        // Dedup check failed (network issue) — sync anyway
                        _ = try? await client.syncEntry(entry, provenance: provenance)
                    }
                }
            }
            // Sensitive memories stay local-only (no cloud sync)
        }

        return entry
    }

    public func search(query: String, type: MemoryType? = nil) throws -> [MemoryEntry] {
        let entries = try list()
        let lowered = query.lowercased()

        return entries.filter { entry in
            let matchesType = type == nil || entry.type == type
            let matchesQuery = lowered.isEmpty ||
                entry.name.lowercased().contains(lowered) ||
                entry.content.lowercased().contains(lowered)
            return matchesType && matchesQuery
        }
    }

    public func list() throws -> [MemoryEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: memoryDirectory.path) else { return [] }

        let files = try fm.contentsOfDirectory(at: memoryDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "MEMORY.md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return files.compactMap { try? loadEntry(from: $0) }
    }

    public func load(name: String) throws -> MemoryEntry {
        let slug = slugify(name)
        let filePath = memoryDirectory.appendingPathComponent("\(slug).md")

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw TillyError.memoryNotFound(name)
        }

        return try loadEntry(from: filePath)
    }

    public func delete(name: String) throws {
        let slug = slugify(name)
        let filePath = memoryDirectory.appendingPathComponent("\(slug).md")

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw TillyError.memoryNotFound(name)
        }

        try FileManager.default.removeItem(at: filePath)
        try rebuildIndex()
    }

    public func loadIndex() -> String {
        let indexPath = memoryDirectory.appendingPathComponent("MEMORY.md")
        return (try? String(contentsOf: indexPath, encoding: .utf8)) ?? "(no memories stored yet)"
    }

    public func rebuildIndex() throws {
        let entries = try list()
        let indexPath = memoryDirectory.appendingPathComponent("MEMORY.md")

        if entries.isEmpty {
            try "(no memories stored yet)".write(to: indexPath, atomically: true, encoding: .utf8)
            return
        }

        let lines = entries.map(\.indexLine)
        let index = lines.joined(separator: "\n")
        try index.write(to: indexPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Frontmatter Parsing

    private func loadEntry(from url: URL) throws -> MemoryEntry {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let slug = url.deletingPathExtension().lastPathComponent

        // Parse YAML frontmatter
        guard raw.hasPrefix("---\n"),
              let endIndex = raw.range(of: "\n---\n", range: raw.index(raw.startIndex, offsetBy: 4)..<raw.endIndex) else {
            // No frontmatter - treat entire content as a simple memory
            return MemoryEntry(id: slug, name: slug, type: .reference, content: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let frontmatter = String(raw[raw.index(raw.startIndex, offsetBy: 4)..<endIndex.lowerBound])
        let body = String(raw[endIndex.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Simple YAML parsing (key: value per line)
        var meta: [String: String] = [:]
        for line in frontmatter.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                meta[parts[0].trimmingCharacters(in: .whitespaces)] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        let name = meta["name"] ?? slug
        let type = MemoryType(rawValue: meta["type"] ?? "reference") ?? .reference
        let created = parseDate(meta["created"]) ?? Date()
        let updated = parseDate(meta["updated"]) ?? Date()

        return MemoryEntry(id: slug, name: name, type: type, content: body, created: created, updated: updated)
    }

    private func serializeEntry(_ entry: MemoryEntry) -> String {
        let formatter = ISO8601DateFormatter()
        return """
        ---
        name: \(entry.name)
        type: \(entry.type.rawValue)
        created: \(formatter.string(from: entry.created))
        updated: \(formatter.string(from: entry.updated))
        ---

        \(entry.content)
        """
    }

    // MARK: - Helpers

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: memoryDirectory.path) {
            do {
                try fm.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
            } catch {
                print("[MemoryService] ERROR: Failed to create memory directory at \(memoryDirectory.path): \(error.localizedDescription)")
            }
        }
    }

    private func slugify(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let slug = text.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return String(slug.prefix(64))
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }
}
