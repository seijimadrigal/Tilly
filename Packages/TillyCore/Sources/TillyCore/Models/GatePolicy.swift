import Foundation

/// Policy for human-in-the-loop approval gates.
/// Gates pause the agent loop and ask the user for confirmation
/// before executing potentially dangerous or expensive operations.
public struct GatePolicy: Codable, Sendable, Identifiable {
    public let id: UUID
    public let type: GateType
    public let toolPatterns: [String]
    public let argPatterns: [String]
    public let message: String

    public init(
        type: GateType,
        toolPatterns: [String],
        argPatterns: [String] = [],
        message: String
    ) {
        self.id = UUID()
        self.type = type
        self.toolPatterns = toolPatterns
        self.argPatterns = argPatterns
        self.message = message
    }

    public enum GateType: String, Codable, Sendable {
        case destructive
        case expensive
        case lowConfidence
        case external
        case custom
    }

    public static let defaults: [GatePolicy] = [
        GatePolicy(
            type: .destructive,
            toolPatterns: ["execute_command"],
            argPatterns: ["rm -rf", "rm -r /", "DROP TABLE", "DROP DATABASE", "format disk", "mkfs"],
            message: "This command could permanently delete data. Proceed?"
        ),
        GatePolicy(
            type: .destructive,
            toolPatterns: ["memory_delete"],
            argPatterns: [],
            message: "This will permanently delete a stored memory. Proceed?"
        ),
        GatePolicy(
            type: .external,
            toolPatterns: ["http_request"],
            argPatterns: ["POST", "PUT", "DELETE", "PATCH"],
            message: "This will send data to an external API. Proceed?"
        ),
    ]
}
