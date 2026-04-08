import Foundation
import TillyCore

public final class SkillService: @unchecked Sendable {
    public let skillsDirectory: URL

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.skillsDirectory = appSupport.appendingPathComponent("Tilly/skills")
        ensureDirectoryExists()
    }

    public init(directory: URL) {
        self.skillsDirectory = directory
        ensureDirectoryExists()
    }

    // MARK: - CRUD

    public func create(
        name: String,
        description: String,
        trigger: String,
        instructions: String
    ) throws -> SkillEntry {
        let slug = slugify(name)
        let skillDir = skillsDirectory.appendingPathComponent(slug)
        let skillFile = skillDir.appendingPathComponent("SKILL.md")

        // Create skill directory
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let entry = SkillEntry(
            id: slug,
            name: name,
            description: description,
            trigger: trigger,
            instructions: instructions
        )

        let content = serializeEntry(entry)
        try content.write(to: skillFile, atomically: true, encoding: .utf8)
        try rebuildIndex()

        return entry
    }

    public func list() throws -> [SkillEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillsDirectory.path) else { return [] }

        let contents = try fm.contentsOfDirectory(
            at: skillsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        return contents.compactMap { dir -> SkillEntry? in
            let skillFile = dir.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { return nil }
            return try? loadEntry(from: skillFile, slug: dir.lastPathComponent)
        }.sorted { $0.name < $1.name }
    }

    public func load(name: String) throws -> SkillEntry {
        let slug = slugify(name)
        let skillFile = skillsDirectory
            .appendingPathComponent(slug)
            .appendingPathComponent("SKILL.md")

        guard FileManager.default.fileExists(atPath: skillFile.path) else {
            // Try searching by name
            let allSkills = try list()
            if let match = allSkills.first(where: {
                $0.name.lowercased() == name.lowercased() || $0.id == name.lowercased()
            }) {
                return match
            }
            throw TillyError.skillNotFound(name)
        }

        return try loadEntry(from: skillFile, slug: slug)
    }

    public func delete(name: String) throws {
        let slug = slugify(name)
        let skillDir = skillsDirectory.appendingPathComponent(slug)

        guard FileManager.default.fileExists(atPath: skillDir.path) else {
            throw TillyError.skillNotFound(name)
        }

        try FileManager.default.removeItem(at: skillDir)
        try rebuildIndex()
    }

    public func loadIndex() -> String {
        let indexPath = skillsDirectory.appendingPathComponent("SKILLS.md")
        return (try? String(contentsOf: indexPath, encoding: .utf8)) ?? "(no skills saved yet)"
    }

    public func rebuildIndex() throws {
        let entries = try list()
        let indexPath = skillsDirectory.appendingPathComponent("SKILLS.md")

        if entries.isEmpty {
            try "(no skills saved yet)".write(to: indexPath, atomically: true, encoding: .utf8)
            return
        }

        let lines = entries.map(\.indexLine)
        let index = lines.joined(separator: "\n")
        try index.write(to: indexPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Frontmatter Parsing

    private func loadEntry(from url: URL, slug: String) throws -> SkillEntry {
        let raw = try String(contentsOf: url, encoding: .utf8)

        guard raw.hasPrefix("---\n"),
              let endIndex = raw.range(of: "\n---\n", range: raw.index(raw.startIndex, offsetBy: 4)..<raw.endIndex) else {
            return SkillEntry(id: slug, name: slug, description: "", trigger: "", instructions: raw)
        }

        let frontmatter = String(raw[raw.index(raw.startIndex, offsetBy: 4)..<endIndex.lowerBound])
        let body = String(raw[endIndex.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        var meta: [String: String] = [:]
        for line in frontmatter.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                meta[parts[0].trimmingCharacters(in: .whitespaces)] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        return SkillEntry(
            id: slug,
            name: meta["name"] ?? slug,
            description: meta["description"] ?? "",
            trigger: meta["trigger"] ?? "",
            instructions: body,
            created: parseDate(meta["created"]) ?? Date()
        )
    }

    private func serializeEntry(_ entry: SkillEntry) -> String {
        let formatter = ISO8601DateFormatter()
        return """
        ---
        name: \(entry.name)
        description: \(entry.description)
        trigger: \(entry.trigger)
        created: \(formatter.string(from: entry.created))
        ---

        \(entry.instructions)
        """
    }

    // MARK: - Helpers

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: skillsDirectory.path) {
            try? fm.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
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
        return ISO8601DateFormatter().date(from: string)
    }
}
