import Foundation

// MARK: - Skill Check (test prerequisite)

public struct SkillCheck: Codable, Sendable, Equatable {
    public let check: String           // "credential", "api", "command"
    public let name: String?           // credential name (for credential check)
    public let source: String?         // "memory", "keychain", "any" (default)
    public let url: String?            // API endpoint (for api check)
    public let method: String?         // HTTP method (for api check)
    public let expectStatus: Int?      // expected HTTP status
    public let command: String?        // shell command (for command check)
    public let expectContains: String? // expected substring in output

    public init(
        check: String,
        name: String? = nil, source: String? = nil,
        url: String? = nil, method: String? = nil, expectStatus: Int? = nil,
        command: String? = nil, expectContains: String? = nil
    ) {
        self.check = check
        self.name = name; self.source = source
        self.url = url; self.method = method; self.expectStatus = expectStatus
        self.command = command; self.expectContains = expectContains
    }
}

// MARK: - Skill Entry

public struct SkillEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let trigger: String
    public let instructions: String
    public let created: Date

    // Chaining metadata
    public let dependencies: [String]  // skill IDs that must run first
    public let inputs: [String]        // named inputs (e.g., "topic", "url")
    public let outputs: [String]       // named outputs (e.g., "report_path")

    // Test prerequisites
    public let tests: [SkillCheck]

    public init(
        id: String,
        name: String,
        description: String,
        trigger: String,
        instructions: String,
        created: Date = Date(),
        dependencies: [String] = [],
        inputs: [String] = [],
        outputs: [String] = [],
        tests: [SkillCheck] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.trigger = trigger
        self.instructions = instructions
        self.created = created
        self.dependencies = dependencies
        self.inputs = inputs
        self.outputs = outputs
        self.tests = tests
    }

    // Custom decoder for backward compat (existing skills don't have new fields)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? ""
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        inputs = try container.decodeIfPresent([String].self, forKey: .inputs) ?? []
        outputs = try container.decodeIfPresent([String].self, forKey: .outputs) ?? []
        tests = try container.decodeIfPresent([SkillCheck].self, forKey: .tests) ?? []
    }

    /// One-line summary for SKILLS.md index
    public var indexLine: String {
        var line = "- **\(name)** (`\(id)`) — \(description)"
        if !inputs.isEmpty || !outputs.isEmpty {
            let io = [
                inputs.isEmpty ? nil : "in: \(inputs.joined(separator: ", "))",
                outputs.isEmpty ? nil : "out: \(outputs.joined(separator: ", "))",
            ].compactMap { $0 }.joined(separator: " → ")
            line += " [\(io)]"
        }
        return line
    }
}
