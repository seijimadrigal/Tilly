import Foundation

public protocol ToolExecutable: Sendable {
    var definition: ToolDefinition { get }
    func execute(arguments: String) async throws -> ToolResult
}
