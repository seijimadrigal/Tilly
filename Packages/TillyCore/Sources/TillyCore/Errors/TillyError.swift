import Foundation

public enum TillyError: Error, LocalizedError, Sendable {
    case httpError(statusCode: Int, message: String?)
    case sseParsingError(String)
    case apiError(String)
    case rateLimited(retryAfter: TimeInterval?)
    case overloaded
    case authenticationRequired(ProviderID)
    case invalidAPIKey(ProviderID)
    case modelNotFound(String)
    case unknownTool(String)
    case toolExecutionFailed(String)
    case sandboxViolation(String)
    case sessionNotFound(UUID)
    case encodingError(String)
    case networkError(Error)
    case timeout
    case cancelled
    case memoryNotFound(String)
    case skillNotFound(String)
    case invalidMemoryType(String)
    case skillChainFailed(String)
    case skillTestFailed(String)
    case skillCyclicDependency(String)
    case skillMissingInput(String)

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let message):
            return "HTTP \(code): \(message ?? "Unknown error")"
        case .sseParsingError(let detail):
            return "SSE parsing error: \(detail)"
        case .apiError(let message):
            return "API error: \(message)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds))s"
            }
            return "Rate limited. Please try again later."
        case .overloaded:
            return "Provider is overloaded. Please try again later."
        case .authenticationRequired(let provider):
            return "API key required for \(provider.displayName)"
        case .invalidAPIKey(let provider):
            return "Invalid API key for \(provider.displayName)"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .toolExecutionFailed(let detail):
            return "Tool execution failed: \(detail)"
        case .sandboxViolation(let detail):
            return "Sandbox violation: \(detail)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .encodingError(let detail):
            return "Encoding error: \(detail)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request cancelled"
        case .memoryNotFound(let name):
            return "Memory not found: \(name)"
        case .skillNotFound(let name):
            return "Skill not found: \(name)"
        case .invalidMemoryType(let type):
            return "Invalid memory type: \(type). Use: user, feedback, project, reference"
        case .skillChainFailed(let detail):
            return "Skill chain failed: \(detail)"
        case .skillTestFailed(let detail):
            return "Skill test failed: \(detail)"
        case .skillCyclicDependency(let detail):
            return "Cyclic dependency in skill chain: \(detail)"
        case .skillMissingInput(let detail):
            return "Missing skill input: \(detail)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .timeout, .networkError:
            return true
        default:
            return false
        }
    }
}
