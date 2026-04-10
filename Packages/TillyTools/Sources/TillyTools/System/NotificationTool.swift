import Foundation
import TillyCore

/// Send macOS notifications to the user.
public final class NotificationTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "notify",
                description: "Send a macOS notification to the user. Shows in Notification Center. Use to alert when a long task completes, an error occurs, or something needs attention.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "title": .object(["type": .string("string"), "description": .string("Notification title.")]),
                        "message": .object(["type": .string("string"), "description": .string("Notification body text.")]),
                        "sound": .object(["type": .string("boolean"), "description": .string("Play sound. Default true.")]),
                    ]),
                    "required": .array([.string("title"), .string("message")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        #if os(macOS)
        struct Args: Decodable { let title: String; let message: String; let sound: Bool? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        // Use osascript for notifications (works without UNUserNotificationCenter setup)
        let soundFlag = args.sound ?? true
        let script = """
        display notification "\(args.message.replacingOccurrences(of: "\"", with: "\\\""))" \
        with title "\(args.title.replacingOccurrences(of: "\"", with: "\\\""))" \
        \(soundFlag ? "sound name \"Glass\"" : "")
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
        process.waitUntilExit()

        return ToolResult(content: "Notification sent: \(args.title)")
        #else
        return ToolResult(content: "This tool is only available on macOS.", isError: true)
        #endif
    }
}
