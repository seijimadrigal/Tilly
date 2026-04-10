import Foundation
import SwiftUI

/// Captures diagnostic logs for debugging the agent harness.
/// Thread-safe — can be called from any actor/task.
/// UI properties accessed via @MainActor.
final class DiagnosticLogger: @unchecked Sendable {
    static let shared = DiagnosticLogger()

    private let lock = NSLock()
    private var _entries: [LogEntry] = []
    private let maxEntries = 500

    // UI state — only mutated on main actor
    @MainActor var showLogViewer = false

    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let category: Category
        let message: String
        let detail: String?

        enum Category: String, Sendable {
            case tool = "TOOL"
            case llm = "LLM"
            case error = "ERROR"
            case agent = "AGENT"
            case firebase = "FIREBASE"
            case system = "SYSTEM"
        }
    }

    /// Thread-safe read access to entries
    var entries: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    /// Thread-safe log — can be called from ANY context (main actor, task group, sub-agent, etc.)
    func log(_ category: LogEntry.Category, _ message: String, detail: String? = nil) {
        let entry = LogEntry(timestamp: Date(), category: category, message: message, detail: detail)
        lock.lock()
        _entries.append(entry)
        if _entries.count > maxEntries {
            _entries.removeFirst(_entries.count - maxEntries)
        }
        lock.unlock()
        // Also print to Xcode console
        print("[\(category.rawValue)] \(message)")
    }

    // MARK: - Convenience methods (all thread-safe)

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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        let snapshot = entries  // Thread-safe copy
        var output = "# Tilly Diagnostic Log\n"
        output += "# Exported: \(Date())\n"
        output += "# Entries: \(snapshot.count)\n\n"

        for entry in snapshot {
            let time = formatter.string(from: entry.timestamp)
            output += "[\(time)] [\(entry.category.rawValue)] \(entry.message)\n"
            if let detail = entry.detail {
                output += "  → \(detail)\n"
            }
        }

        return output
    }

    func clear() {
        lock.lock()
        _entries.removeAll()
        lock.unlock()
    }
}
