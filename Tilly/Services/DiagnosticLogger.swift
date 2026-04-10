import Foundation
import SwiftUI

/// Captures diagnostic logs for debugging the agent harness.
/// Tracks: tool calls, LLM requests, errors, agent rounds, timing.
/// Accessible via hidden UI (Cmd+Shift+L on Mac).
@MainActor
@Observable
final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    var entries: [LogEntry] = []
    var showLogViewer = false

    private let maxEntries = 500
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: Category
        let message: String
        let detail: String?

        enum Category: String {
            case tool = "TOOL"
            case llm = "LLM"
            case error = "ERROR"
            case agent = "AGENT"
            case firebase = "FIREBASE"
            case system = "SYSTEM"
        }
    }

    func log(_ category: LogEntry.Category, _ message: String, detail: String? = nil) {
        let entry = LogEntry(timestamp: Date(), category: category, message: message, detail: detail)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        // Also print to console for Xcode debugging
        print("[\(category.rawValue)] \(message)")
    }

    // MARK: - Convenience methods

    func toolCall(name: String, args: String, duration: TimeInterval? = nil, resultSize: Int? = nil) {
        var msg = "Called: \(name)"
        if let duration { msg += " (\(String(format: "%.1f", duration))s)" }
        if let resultSize { msg += " → \(resultSize) chars" }
        let argPreview = args.count > 200 ? String(args.prefix(200)) + "..." : args
        log(.tool, msg, detail: argPreview)
    }

    func llmRequest(model: String, messageCount: Int, toolCount: Int) {
        log(.llm, "Request: \(model), \(messageCount) msgs, \(toolCount) tools")
    }

    func llmResponse(model: String, tokens: Int?, latency: Int?, finishReason: String?) {
        var msg = "Response: \(model)"
        if let tokens { msg += ", \(tokens) tokens" }
        if let latency { msg += ", \(latency)ms" }
        if let reason = finishReason { msg += " [\(reason)]" }
        log(.llm, msg)
    }

    func agentRound(_ round: Int, maxRounds: Int) {
        log(.agent, "Round \(round)/\(maxRounds)")
    }

    func error(_ message: String, detail: String? = nil) {
        log(.error, message, detail: detail)
    }

    // MARK: - Export

    func exportLog() -> String {
        var output = "# Tilly Diagnostic Log\n"
        output += "# Exported: \(Date())\n"
        output += "# Entries: \(entries.count)\n\n"

        for entry in entries {
            let time = dateFormatter.string(from: entry.timestamp)
            output += "[\(time)] [\(entry.category.rawValue)] \(entry.message)\n"
            if let detail = entry.detail {
                output += "  → \(detail)\n"
            }
        }

        return output
    }

    func clear() {
        entries.removeAll()
    }
}
